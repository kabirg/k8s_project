# Use this to create a new Hosted Zone from a pre-existing domain
# resource "aws_route53_zone" "my-domain" {
#   name = var.domain
# }

# Use this to import an existing hosted zone (ideally from a domain registered in ACM)
# This makes validation much quicker and painless than using an external registrar where you have to update the NS's
data "aws_route53_zone" "base_domain" {
  name = var.domain
}

# Create an ACM-issued certificate for the domain
# Set create_before_destroy to true so that cert renewal doesn't destroy cert (and HTTP requests)
resource "aws_acm_certificate" "cert" {
  domain_name       = var.domain
  validation_method = "DNS"

  tags = {
    Name = var.domain
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Create a CNAME record using the value returned by ACM
resource "aws_route53_record" "domain_cert_dns_validation" {

  # 'for_each' requires a set(string) or map(any). But domain_validation_options returns set(any):
    # {
    #   domain_name = xx
    #   resource_record_name = xx
    #   resource_record_type = xx
    #   resource_record_value = xx
    # }

  # To iterate over this, we'll convert it to map(any) using the "for_each = {for x in x: xxx => x}" trick.
  # Src: https://www.sheldonhull.com/blog/how-to-iterate-through-a-list-of-objects-with-terraforms-for-each-function/
  # Src: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/guides/version-3-upgrade#resource-aws_acm_certificate
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options: dvo.domain_name => {
      name = dvo.resource_record_name
      type = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  name = each.value.name
  type = each.value.type
  records = [each.value.record]
  zone_id = data.aws_route53_zone.base_domain.id
  ttl     = 60
}

# Wait for the cert to be issued
resource "aws_acm_certificate_validation" "eks_domain_cert_validation" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.domain_cert_dns_validation : record.fqdn]
}

# Create the NGINX Ingress
resource "helm_release" "ingress_gateway" {
  name       = var.release_name
  chart      = var.chart_name
  repository = var.chart_repo
  version    = var.chart_version

  dynamic "set" {
    for_each = var.ingress_gateway_annotations
    content {
      name = set.key
      value = set.value
      type = "string"
    }
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-ssl-cert"
    value = aws_acm_certificate.cert.id
  }

  depends_on = [
    module.my-cluster
  ]
}

# Create an Alias record for our new load balancer / ingress
data "kubernetes_service" "ingress_gateway" {
  metadata {
    name = join("-", [helm_release.ingress_gateway.chart, helm_release.ingress_gateway.name])
  }

  depends_on = [module.my-cluster]
}

data "aws_elb_hosted_zone_id" "elb_zone_id" {}
resource "aws_route53_record" "eks_domain" {
  name    = var.domain
  type    = "A"
  zone_id = data.aws_route53_zone.base_domain.id

  alias {
    name = data.kubernetes_service.ingress_gateway.load_balancer_ingress.0.hostname
    zone_id = data.aws_elb_hosted_zone_id.elb_zone_id.id
    evaluate_target_health = true
  }
}

# Create CNAMES for Subdomains
resource "aws_route53_record" "deployment_subdomains" {
  for_each = toset(var.subdomains)

  zone_id = data.aws_route53_zone.base_domain.zone_id
  # the domain, which is also the value of 'name' of the A record now.
  name    = "${each.key}.${aws_route53_record.eks_domain.fqdn}"
  type    = "CNAME"
  ttl     = "5"
  records = [data.kubernetes_service.ingress_gateway.load_balancer_ingress.0.hostname]
}
