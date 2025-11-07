
resource "aws_db_subnet_group" "iq_db_subnet_group" {
  name       = "ref-arch-iq-db-subnet-group"
  subnet_ids = aws_subnet.db_subnets[*].id

  tags = {
    Name        = "ref-arch-iq-db-subnet-group"
  }
}


resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "ref-arch-iq-db-credentials"
  description             = "Database credentials for Nexus IQ Server"
  recovery_window_in_days = 7

  tags = {
    Name        = "ref-arch-iq-db-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
  })
}


resource "aws_db_instance" "iq_db" {
  identifier     = "ref-arch-iq-database"
  engine         = "postgres"
  engine_version = var.postgres_version
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.iq_db_subnet_group.name

  backup_retention_period = var.db_backup_retention_period
  backup_window          = var.db_backup_window
  maintenance_window     = var.db_maintenance_window

  skip_final_snapshot = var.db_skip_final_snapshot
  deletion_protection = var.db_deletion_protection

  performance_insights_enabled = true
  monitoring_interval         = 60
  monitoring_role_arn        = aws_iam_role.rds_enhanced_monitoring.arn

  auto_minor_version_upgrade = true

  tags = {
    Name        = "ref-arch-iq-database"
  }
}


resource "aws_iam_role" "rds_enhanced_monitoring" {
  name = "ref-arch-rds-enhanced-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "ref-arch-rds-enhanced-monitoring"
  }
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}