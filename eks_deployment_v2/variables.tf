# VPC Variables
variable "cluster_name" {
  type = string
}

variable "vpc_name" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "public_subnets" {
  type = list(string)
}

variable "private_subnets" {
  type = list(string)
}


# EKS Cluster Variables
variable "admin_users" {
  type = list
}

variable "dev_users" {
  type = list
}


# Ingress Variables
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

variable "subdomains" {
  type = list(string)
}

# Namespace Variables
variable "namespaces" {
  type        = list(string)
}
