# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.iq_vpc.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.iq_vpc.cidr_block
}

output "public_subnets" {
  description = "List of IDs of the public subnets"
  value       = aws_subnet.public_subnets[*].id
}

output "private_subnets" {
  description = "List of IDs of the private subnets"
  value       = aws_subnet.private_subnets[*].id
}

output "database_subnets" {
  description = "List of IDs of the database subnets"
  value       = aws_subnet.db_subnets[*].id
}

# ECS Outputs
output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.iq_cluster.name
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.iq_cluster.arn
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.iq_service.name
}

output "ecs_service_arn" {
  description = "ARN of the ECS service"
  value       = aws_ecs_service.iq_service.id
}

output "ecs_task_definition_arn" {
  description = "ARN of the ECS task definition"
  value       = aws_ecs_task_definition.iq_task.arn
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task role"
  value       = aws_iam_role.ecs_task_role.arn
}

output "ecs_execution_role_arn" {
  description = "ARN of the ECS execution role"
  value       = aws_iam_role.ecs_execution_role.arn
}

output "service_discovery_namespace" {
  description = "Service discovery namespace for internal communication"
  value       = aws_service_discovery_private_dns_namespace.iq_namespace.name
}

# Database Outputs
output "aurora_cluster_endpoint" {
  description = "Aurora cluster endpoint"
  value       = aws_rds_cluster.iq_aurora_cluster.endpoint
}

output "aurora_cluster_reader_endpoint" {
  description = "Aurora cluster reader endpoint"
  value       = aws_rds_cluster.iq_aurora_cluster.reader_endpoint
}

output "aurora_cluster_id" {
  description = "Aurora cluster identifier"
  value       = aws_rds_cluster.iq_aurora_cluster.cluster_identifier
}

output "aurora_cluster_port" {
  description = "Aurora cluster port"
  value       = aws_rds_cluster.iq_aurora_cluster.port
}

output "aurora_cluster_database_name" {
  description = "Aurora cluster database name"
  value       = aws_rds_cluster.iq_aurora_cluster.database_name
}

output "aurora_cluster_master_username" {
  description = "Aurora cluster master username"
  value       = aws_rds_cluster.iq_aurora_cluster.master_username
  sensitive   = true
}

output "aurora_security_group_id" {
  description = "Security group ID for Aurora cluster"
  value       = aws_security_group.aurora.id
}

# Load Balancer Outputs
output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer"
  value       = aws_lb.iq_alb.dns_name
}

output "alb_zone_id" {
  description = "The zone ID of the Application Load Balancer"
  value       = aws_lb.iq_alb.zone_id
}

output "alb_arn" {
  description = "The ARN of the Application Load Balancer"
  value       = aws_lb.iq_alb.arn
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.iq_tg.arn
}

# Application URLs
output "application_url" {
  description = "URL to access Nexus IQ Server"
  value = var.ssl_certificate_arn != "" ? "https://${aws_lb.iq_alb.dns_name}" : "http://${aws_lb.iq_alb.dns_name}"
}

# EFS Outputs
output "efs_id" {
  description = "EFS file system ID"
  value       = aws_efs_file_system.iq_efs.id
}

output "efs_dns_name" {
  description = "EFS DNS name"
  value       = aws_efs_file_system.iq_efs.dns_name
}

output "efs_access_point_id" {
  description = "EFS access point ID for IQ Server data"
  value       = aws_efs_access_point.iq_access_point.id
}

output "efs_logs_access_point_id" {
  description = "EFS access point ID for IQ Server logs"
  value       = aws_efs_access_point.iq_logs_access_point.id
}

# Security Outputs
output "db_credentials_secret_arn" {
  description = "ARN of the Secrets Manager secret containing database credentials"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

# Service Discovery Outputs
output "service_discovery_service" {
  description = "Service discovery service for IQ Server instances"
  value       = aws_service_discovery_service.iq_service.name
}

# Monitoring Outputs
output "cloudwatch_log_groups" {
  description = "CloudWatch log groups"
  value = {
    ecs_tasks = aws_cloudwatch_log_group.iq_logs.name
    aurora    = "/aws/rds/cluster/${aws_rds_cluster.iq_aurora_cluster.cluster_identifier}/postgresql"
  }
}

# WAF Outputs (DISABLED)
# output "waf_web_acl_arn" {
#   description = "ARN of the WAF Web ACL"
#   value       = aws_wafv2_web_acl.iq_waf.arn
# }

# Backup Outputs
output "backup_vault_name" {
  description = "Name of the backup vault for EFS"
  value       = aws_backup_vault.iq_efs_backup_vault.name
}

# ECS Cluster Information
output "ecs_cluster_info" {
  description = "ECS cluster information and management commands"
  value = {
    cluster_name    = aws_ecs_cluster.iq_cluster.name
    service_name    = aws_ecs_service.iq_service.name
    task_definition = aws_ecs_task_definition.iq_task.family
    log_group       = aws_cloudwatch_log_group.iq_logs.name
  }
}

# Architecture Summary
output "architecture_summary" {
  description = "High-level summary of the deployed architecture"
  value = {
    deployment_type = "High Availability"
    compute_platform = "Amazon ECS Fargate"
    database_type = "Aurora PostgreSQL Cluster"
    storage_type = "Amazon EFS"
    load_balancer = "Application Load Balancer"
    ssl_enabled = var.ssl_certificate_arn != ""
    waf_enabled = true
    backup_enabled = true
    monitoring_enabled = var.enable_container_insights
    availability_zones = length(data.aws_availability_zones.available.names)
    iq_server_tasks = var.iq_desired_count
    aurora_instances = var.aurora_instances
    auto_scaling = {
      min_tasks = var.iq_min_count
      desired_tasks = var.iq_desired_count
      max_tasks = var.iq_max_count
      cpu_target = var.iq_cpu_target_value
      memory_target = var.iq_memory_target_value
    }
    service_discovery_enabled = true
  }
}