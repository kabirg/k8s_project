cluster_name = "kag-eks-cluster"
vpc_name = "kag-test-vpc"
vpc_cidr = "10.0.0.0/16"
public_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnets = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

admin_users = ["kabir-admin", "kabir"]
dev_users = ["kabir-dev"]

release_name = "nginx-ingress"
chart_name = "nginx-ingress"
chart_repo = "https://helm.nginx.com/stable"
chart_version = "0.5.2"
domain = "kabirg-eks-demo.click"
subdomains = ["sample", "api"]
ingress_gateway_annotations = {
  "controller.service.httpPort.targetPort"                                                                    = "http",
  "controller.service.httpsPort.targetPort"                                                                   = "http",
  "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-backend-protocol"        = "http",
  "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-ssl-ports"               = "https",
  "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-connection-idle-timeout" = "60",
  "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"                    = "elb"
}

namespaces = ["sample-apps"]
