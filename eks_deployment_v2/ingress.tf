
variable "release_name" {
  type = string
}

variable "chart_name" {
  type = string
}

variable "chart_repo" {
  type = string
}

variable "chart_version" {
  type = string
}

variable "ingress_gateway_annotations" {
  type = map(string)
  description = "Ingress Gateway Annotations Required by EKS."
}

variable "domain" {
  type = string
  default = "demo-domain.guru"
}

# Create the Route53 Hosted Zone
# Src: https://www.grailbox.com/2020/04/how-to-set-up-a-domain-in-amazon-route-53-with-terraform/
resource "aws_route53_zone" "my-domain" {
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

# The ACM cert will return a CNAME info which we create here. ACM will ping this to verify we own the domain.
# Once this is successfully created, ACM will finish creating the cert.
resource "aws_route53_record" "domain_cert_dns_validation" {

  # .domain_validation_options returns does not return a map or set of strings (in which case a simple for_each could be used)
  # Instead it returns set(object):
      # {
      #   domain_name = xx
      #   resource_record_name = xx
      #   resource_record_type = xx
      #   resource_record_value = xx
      # }
  # We must convert this into a set(strings) or a map (of any type) to iterate over it, hence we use the "for_each = {for x in x: xxx => x}" trick to convert to a map.
  # Src: https://www.sheldonhull.com/blog/how-to-iterate-through-a-list-of-objects-with-terraforms-for-each-function/
  # Src: https://github.com/hashicorp/terraform/issues/23354
  # Src: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/guides/version-3-upgrade#resource-aws_acm_certificate
  # Src: https://www.concurrency.com/blog/july-2019/conditionals-and-for-in-terraform
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
  zone_id = aws_route53_zone.my-domain.id
  ttl     = 60
}

# This will validate that the cert is done creating (which isn't instantaneous)
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
  zone_id = aws_route53_zone.my-domain.id

  alias {
    name = data.kubernetes_service.ingress_gateway.load_balancer_ingress.0.hostname
    zone_id = data.aws_elb_hosted_zone_id.elb_zone_id.id
    evaluate_target_health = true
  }
}
