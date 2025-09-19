# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.iq_vpc.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.iq_vpc.cidr_block
}

# Subnet Outputs
output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public_subnets[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private_subnets[*].id
}

output "db_subnet_ids" {
  description = "IDs of the database subnets"
  value       = aws_subnet.db_subnets[*].id
}

# Load Balancer Outputs
output "load_balancer_dns_name" {
  description = "DNS name of the load balancer"
  value       = aws_lb.iq_alb.dns_name
}

output "load_balancer_zone_id" {
  description = "Zone ID of the load balancer"
  value       = aws_lb.iq_alb.zone_id
}

output "load_balancer_arn" {
  description = "ARN of the load balancer"
  value       = aws_lb.iq_alb.arn
}

# ECS Outputs
output "ecs_cluster_id" {
  description = "ID of the ECS cluster"
  value       = aws_ecs_cluster.iq_cluster.id
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.iq_cluster.arn
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.iq_service.name
}

output "ecs_task_definition_arn" {
  description = "ARN of the ECS task definition"
  value       = aws_ecs_task_definition.iq_task.arn
}

# Database Outputs
output "db_instance_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.iq_db.endpoint
  sensitive   = true
}

output "db_instance_id" {
  description = "RDS instance ID"
  value       = aws_db_instance.iq_db.id
}

output "db_instance_port" {
  description = "RDS instance port"
  value       = aws_db_instance.iq_db.port
}

# Security Group Outputs
output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "ecs_security_group_id" {
  description = "ID of the ECS tasks security group"
  value       = aws_security_group.ecs_tasks.id
}

output "rds_security_group_id" {
  description = "ID of the RDS security group"
  value       = aws_security_group.rds.id
}

# IAM Outputs
output "ecs_execution_role_arn" {
  description = "ARN of the ECS execution role"
  value       = aws_iam_role.ecs_execution_role.arn
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task role"
  value       = aws_iam_role.ecs_task_role.arn
}

# CloudWatch Outputs
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.iq_logs.name
}

# EFS Outputs
output "efs_file_system_id" {
  description = "ID of the EFS file system"
  value       = aws_efs_file_system.iq_efs.id
}

output "efs_dns_name" {
  description = "DNS name of the EFS file system"
  value       = aws_efs_file_system.iq_efs.dns_name
}

# Application URL
output "application_url" {
  description = "URL to access Nexus IQ Server"
  value       = "http://${aws_lb.iq_alb.dns_name}"
}


# Secrets Manager
output "db_credentials_secret_arn" {
  description = "ARN of the database credentials secret"
  value       = aws_secretsmanager_secret.db_credentials.arn
  sensitive   = true
}