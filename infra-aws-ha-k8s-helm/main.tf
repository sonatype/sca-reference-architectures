terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_caller_identity" "current" {}

resource "aws_vpc" "iq_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name    = "${var.cluster_name}-vpc"
    Project = "nexus-iq-server-ha"
    Environment = var.environment
  }
}

resource "aws_internet_gateway" "iq_igw" {
  vpc_id = aws_vpc.iq_vpc.id

  tags = {
    Name    = "${var.cluster_name}-igw"
    Project = "nexus-iq-server-ha"
    Environment = var.environment
  }
}

resource "aws_subnet" "public" {
  count = 2

  availability_zone       = data.aws_availability_zones.available.names[count.index]
  cidr_block              = "10.0.${count.index + 1}.0/24"
  map_public_ip_on_launch = true
  vpc_id                  = aws_vpc.iq_vpc.id

  tags = {
    Name    = "${var.cluster_name}-public-${count.index + 1}"
    Project = "nexus-iq-server-ha"
    Environment = var.environment
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "private" {
  count = 2

  availability_zone = data.aws_availability_zones.available.names[count.index]
  cidr_block        = "10.0.${count.index + 10}.0/24"
  vpc_id            = aws_vpc.iq_vpc.id

  tags = {
    Name    = "${var.cluster_name}-private-${count.index + 1}"
    Project = "nexus-iq-server-ha"
    Environment = var.environment
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "database" {
  count = 2

  availability_zone = data.aws_availability_zones.available.names[count.index]
  cidr_block        = "10.0.${count.index + 20}.0/24"
  vpc_id            = aws_vpc.iq_vpc.id

  tags = {
    Name    = "${var.cluster_name}-db-${count.index + 1}"
    Project = "nexus-iq-server-ha"
    Environment = var.environment
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.iq_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.iq_igw.id
  }

  tags = {
    Name    = "${var.cluster_name}-public"
    Project = "nexus-iq-server-ha"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "public" {
  count = 2

  route_table_id = aws_route_table.public.id
  subnet_id      = aws_subnet.public[count.index].id
}

resource "aws_eip" "nat" {
  count = 2

  domain = "vpc"
  depends_on = [aws_internet_gateway.iq_igw]

  tags = {
    Name    = "${var.cluster_name}-nat-${count.index + 1}"
    Project = "nexus-iq-server-ha"
    Environment = var.environment
  }
}

resource "aws_nat_gateway" "nat" {
  count = 2

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name    = "${var.cluster_name}-nat-${count.index + 1}"
    Project = "nexus-iq-server-ha"
    Environment = var.environment
  }

  depends_on = [aws_internet_gateway.iq_igw]
}

resource "aws_route_table" "private" {
  count = 2

  vpc_id = aws_vpc.iq_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat[count.index].id
  }

  tags = {
    Name    = "${var.cluster_name}-private-${count.index + 1}"
    Project = "nexus-iq-server-ha"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "private" {
  count = 2

  route_table_id = aws_route_table.private[count.index].id
  subnet_id      = aws_subnet.private[count.index].id
}

resource "aws_route_table_association" "database" {
  count = 2

  route_table_id = aws_vpc.iq_vpc.default_route_table_id
  subnet_id      = aws_subnet.database[count.index].id
}