data "aws_eks_cluster" "cluster" {
  name = module.my-cluster.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.my-cluster.cluster_id
}

data "aws_caller_identity" "current" {}

variable "admin_users" {
  type = list
}

variable "dev_users" {
  type = list
}

locals {

  admin_users = [
    for user in var.admin_users:
    {
      userarn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${user}"
      username = user
      groups = ["system:masters"]
    }
  ]

  dev_users = [
    for user in var.dev_users:
    {
      userarn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${user}"
      username = user
      groups = []
    }
  ]
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
  version                = "~> 1.9"
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
    token                  = data.aws_eks_cluster_auth.cluster.token
    load_config_file       = false
  }
  version = "~> 1.2"
}

module "my-cluster" {
  source          = "terraform-aws-modules/eks/aws"
  version          = "15.1.0"
  cluster_name    = "kag-eks-cluster"
  cluster_version = "1.16"
  subnets         = module.vpc.private_subnets
  vpc_id          = module.vpc.vpc_id

  workers_group_defaults = {
  	root_volume_type = "gp2"
  }

  worker_groups = [
    {
      instance_type = "t2.small"
      asg_desired_capacity = 3
      asg_max_size  = 3
      asg_min_size  = 3
    }
  ]

  map_users = concat(local.admin_users, local.dev_users)
}
