######################
##### Provider #####
######################
provider "aws" {
  region = "us-east-1"
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  component_name = "my_eks_infra"
}

######################
##### Resources #####
######################
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  tags = {
    Name                                            = "${local.component_name}-vpc"
    "kubernetes.io/cluster/${local.component_name}" = "shared"
  }
}

resource "aws_subnet" "public_subnets" {
  count                   = length(var.public_subnets)
  vpc_id                  = aws_vpc.main.id
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  cidr_block              = var.public_subnets[count.index]

  tags = {
    Name                                            = "${local.component_name}-public-subnet"
    "kubernetes.io/cluster/${local.component_name}" = "shared"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.main.id
  availability_zone = data.aws_availability_zones.available.names[count.index]
  cidr_block        = var.private_subnets[count.index]

  tags = {
    Name                                            = "${local.component_name}-private-subnet"
    "kubernetes.io/cluster/${local.component_name}" = "shared"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.component_name}-igw"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${local.component_name}-public-rt"
  }
}

resource "aws_route_table_association" "public_rt_ass" {
  count = length(var.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_eip" "eip" {
  vpc      = true
}

resource "aws_nat_gateway" "natgw" {
  allocation_id = aws_eip.eip.id
  subnet_id     = aws_subnet.public_subnets[0].id

  tags = {
    Name = "${local.component_name}-natgw"
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.natgw.id
  }

  tags = {
    Name = "${local.component_name}-private-rt"
  }
}

resource "aws_route_table_association" "private_rt_ass" {
  count = length(var.private_subnets)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_rt.id
}

####################
##### Outputs #####
####################
output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value = aws_subnet.public_subnets.*.id
}

output "private_subnet_id" {
  value = aws_subnet.private_subnets.*.id
}
