
variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR"
}

variable "public_subnets" {
  type        = list(any)
  description = "Set of public subnet CIDR's"
}

variable "private_subnets" {
  type        = list(any)
  description = "Set of private subnet CIDR's"
}
