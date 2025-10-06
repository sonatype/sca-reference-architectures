# EKS Cluster Outputs
output "cluster_id" {
  description = "EKS cluster ID"
  value       = module.eks.cluster_id
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = module.eks.cluster_arn
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane"
  value       = module.eks.cluster_security_group_id
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster for the OpenID Connect identity provider"
  value       = module.eks.cluster_oidc_issuer_url
}

output "cluster_version" {
  description = "The Kubernetes version for the cluster"
  value       = module.eks.cluster_version
}

# AWS Region Output
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC where the cluster and associated resources are created"
  value       = aws_vpc.iq_vpc.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.iq_vpc.cidr_block
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = aws_subnet.private[*].id
}

output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = aws_subnet.public[*].id
}

output "database_subnets" {
  description = "List of IDs of database subnets"
  value       = aws_subnet.database[*].id
}

# RDS Outputs
output "rds_cluster_endpoint" {
  description = "Aurora cluster endpoint"
  value       = aws_rds_cluster.iq_cluster.endpoint
  sensitive   = true
}

output "rds_cluster_reader_endpoint" {
  description = "Aurora cluster reader endpoint"
  value       = aws_rds_cluster.iq_cluster.reader_endpoint
  sensitive   = true
}

output "rds_cluster_port" {
  description = "Aurora cluster port"
  value       = aws_rds_cluster.iq_cluster.port
}

output "rds_cluster_database_name" {
  description = "Aurora cluster database name"
  value       = aws_rds_cluster.iq_cluster.database_name
}

output "rds_cluster_master_username" {
  description = "Aurora cluster master username"
  value       = aws_rds_cluster.iq_cluster.master_username
  sensitive   = true
}

# EFS Outputs
output "efs_id" {
  description = "ID of the EFS file system"
  value       = aws_efs_file_system.iq_efs.id
}

output "efs_dns_name" {
  description = "DNS name of the EFS file system"
  value       = aws_efs_file_system.iq_efs.dns_name
}

output "efs_data_access_point_id" {
  description = "ID of the EFS access point for Nexus IQ data"
  value       = aws_efs_access_point.iq_data.id
}

output "efs_logs_access_point_id" {
  description = "ID of the EFS access point for Nexus IQ logs"
  value       = aws_efs_access_point.iq_logs.id
}

# Security Group Outputs
output "eks_nodes_security_group_id" {
  description = "Security group ID for EKS nodes"
  value       = aws_security_group.eks_nodes.id
}

output "rds_security_group_id" {
  description = "Security group ID for RDS"
  value       = aws_security_group.rds.id
}

output "efs_security_group_id" {
  description = "Security group ID for EFS"
  value       = aws_security_group.efs.id
}

output "alb_security_group_id" {
  description = "Security group ID for ALB"
  value       = aws_security_group.alb.id
}

# Parameter Store Keys
output "ssm_parameter_db_host_key" {
  description = "SSM parameter key for database host"
  value       = aws_ssm_parameter.db_host.name
}

output "ssm_parameter_db_username_key" {
  description = "SSM parameter key for database username"
  value       = aws_ssm_parameter.db_username.name
}

output "ssm_parameter_db_password_key" {
  description = "SSM parameter key for database password"
  value       = aws_ssm_parameter.db_password.name
}

output "ssm_parameter_efs_id_key" {
  description = "SSM parameter key for EFS ID"
  value       = aws_ssm_parameter.efs_id.name
}

# Kubernetes Configuration Command
output "kubectl_config_command" {
  description = "Command to configure kubectl for this EKS cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

# Helm Installation Instructions
output "helm_installation_command" {
  description = "Command to install Nexus IQ Server using Helm"
  value       = "./helm-install.sh"
}