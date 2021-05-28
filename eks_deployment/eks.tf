module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  cluster_name    = local.component_name
  cluster_version = "1.17"
  subnets         = aws_subnet.private_subnets.*.id
  vpc_id          = aws_vpc.main.id

  workers_group_defaults = {
  	root_volume_type = "gp2"
  }

  node_groups = {
    eks_nodes = {
      desired_capacity = 3
      max_capacity     = 3
      min_capaicty     = 3

      instance_type = "t2.small"
    }
  }

  manage_aws_auth = false

}
