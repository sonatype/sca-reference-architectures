terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  # Base for the Name tags on the network resources below. Those tags read
  # "ref-arch-iq-ha-*" while cluster_name defaults to "ref-arch-iq-ha-cluster", so
  # the trailing "-cluster" comes off. That keeps the tags unchanged for anyone who
  # leaves cluster_name alone, while a per-deployment cluster_name still reaches
  # them, which is what lets two deployments be told apart in the console.
  network_name = trimsuffix(var.cluster_name, "-cluster")
}


resource "aws_vpc" "iq_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.common_tags, {
    Name = "${local.network_name}-vpc"
  })
}


resource "aws_internet_gateway" "iq_igw" {
  vpc_id = aws_vpc.iq_vpc.id

  tags = merge(var.common_tags, {
    Name = "${local.network_name}-igw"
  })
}


resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.iq_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  map_public_ip_on_launch = true

  tags = merge(var.common_tags, {
    Name = "${local.network_name}-public-subnet-${count.index + 1}"
    Type = "Public"
  })
}


resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.iq_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(var.common_tags, {
    Name = "${local.network_name}-private-subnet-${count.index + 1}"
    Type = "Private"
  })
}


resource "aws_subnet" "db_subnets" {
  count             = length(var.db_subnet_cidrs)
  vpc_id            = aws_vpc.iq_vpc.id
  cidr_block        = var.db_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(var.common_tags, {
    Name = "${local.network_name}-db-subnet-${count.index + 1}"
    Type = "Database"
  })
}


resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.iq_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.iq_igw.id
  }

  tags = merge(var.common_tags, {
    Name = "${local.network_name}-public-route-table"
  })
}


resource "aws_route_table_association" "public_rta" {
  count          = length(aws_subnet.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}


resource "aws_eip" "nat_eip" {
  count  = var.enable_nat_gateway ? length(aws_subnet.public_subnets) : 0
  domain = "vpc"

  tags = merge(var.common_tags, {
    Name = "${local.network_name}-nat-eip-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.iq_igw]
}

resource "aws_nat_gateway" "nat_gw" {
  count         = var.enable_nat_gateway ? length(aws_subnet.public_subnets) : 0
  allocation_id = aws_eip.nat_eip[count.index].id
  subnet_id     = aws_subnet.public_subnets[count.index].id

  tags = merge(var.common_tags, {
    Name = "${local.network_name}-nat-gateway-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.iq_igw]
}


resource "aws_route_table" "private_rt" {
  count  = var.enable_nat_gateway ? length(aws_subnet.private_subnets) : 1
  vpc_id = aws_vpc.iq_vpc.id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = var.enable_nat_gateway ? aws_nat_gateway.nat_gw[count.index % length(aws_nat_gateway.nat_gw)].id : null
    }
  }

  tags = merge(var.common_tags, {
    Name = "${local.network_name}-private-route-table-${count.index + 1}"
  })
}


resource "aws_route_table_association" "private_rta" {
  count          = length(aws_subnet.private_subnets)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = var.enable_nat_gateway ? aws_route_table.private_rt[count.index % length(aws_route_table.private_rt)].id : aws_route_table.private_rt[0].id
}


resource "aws_route_table" "db_rt" {
  vpc_id = aws_vpc.iq_vpc.id

  tags = merge(var.common_tags, {
    Name = "${local.network_name}-db-route-table"
  })
}


resource "aws_route_table_association" "db_rta" {
  count          = length(aws_subnet.db_subnets)
  subnet_id      = aws_subnet.db_subnets[count.index].id
  route_table_id = aws_route_table.db_rt.id
}