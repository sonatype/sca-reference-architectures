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

# VPC Configuration
resource "aws_vpc" "iq_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "ref-arch-iq-vpc"
    Project     = "nexus-iq-server"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "iq_igw" {
  vpc_id = aws_vpc.iq_vpc.id

  tags = {
    Name        = "ref-arch-iq-igw"
  }
}

# Public Subnets
resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.iq_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  map_public_ip_on_launch = true

  tags = {
    Name        = "ref-arch-public-subnet-${count.index + 1}"
    Type        = "Public"
  }
}

# Private Subnets for ECS tasks
resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.iq_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name        = "ref-arch-private-subnet-${count.index + 1}"
    Type        = "Private"
  }
}

# Database Subnets
resource "aws_subnet" "db_subnets" {
  count             = length(var.db_subnet_cidrs)
  vpc_id            = aws_vpc.iq_vpc.id
  cidr_block        = var.db_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name        = "ref-arch-db-subnet-${count.index + 1}"
    Type        = "Database"
  }
}

# Route Table for Public Subnets
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.iq_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.iq_igw.id
  }

  tags = {
    Name        = "ref-arch-public-route-table"
  }
}

# Route Table Associations for Public Subnets
resource "aws_route_table_association" "public_rta" {
  count          = length(aws_subnet.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

# NAT Gateway for private subnet internet access
resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name        = "ref-arch-nat-eip"
  }
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnets[0].id

  tags = {
    Name        = "ref-arch-nat-gateway"
  }

  depends_on = [aws_internet_gateway.iq_igw]
}

# Route Table for Private Subnets
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.iq_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }

  tags = {
    Name        = "ref-arch-private-route-table"
  }
}

# Route Table Associations for Private Subnets
resource "aws_route_table_association" "private_rta" {
  count          = length(aws_subnet.private_subnets)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_rt.id
}

# Route Table for Database Subnets
resource "aws_route_table" "db_rt" {
  vpc_id = aws_vpc.iq_vpc.id

  tags = {
    Name        = "ref-arch-db-route-table"
  }
}

# Route Table Associations for Database Subnets
resource "aws_route_table_association" "db_rta" {
  count          = length(aws_subnet.db_subnets)
  subnet_id      = aws_subnet.db_subnets[count.index].id
  route_table_id = aws_route_table.db_rt.id
}