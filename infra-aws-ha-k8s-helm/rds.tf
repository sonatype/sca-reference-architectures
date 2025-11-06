resource "aws_db_subnet_group" "iq_db_subnet_group" {
  name       = "${var.cluster_name}-db-subnet-group"
  subnet_ids = aws_subnet.database[*].id

  tags = {
    Name        = "${var.cluster_name}-db-subnet-group"
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }
}

resource "aws_rds_cluster" "iq_cluster" {
  cluster_identifier      = "${var.cluster_name}-aurora-cluster"
  engine                  = "aurora-postgresql"
  engine_version          = var.aurora_engine_version
  availability_zones      = slice(data.aws_availability_zones.available.names, 0, 2)
  database_name           = var.database_name
  master_username         = var.database_username
  master_password         = var.database_password
  backup_retention_period = var.backup_retention_period
  preferred_backup_window = "03:00-04:00"
  preferred_maintenance_window = "Sun:04:00-Sun:05:00"
  db_subnet_group_name    = aws_db_subnet_group.iq_db_subnet_group.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  storage_encrypted       = true
  kms_key_id             = aws_kms_key.iq_kms_key.arn
  skip_final_snapshot    = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.cluster_name}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  deletion_protection    = var.deletion_protection

  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = {
    Name        = "${var.cluster_name}-aurora-cluster"
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }
}

resource "aws_rds_cluster_instance" "iq_cluster_instances" {
  count              = var.aurora_instance_count
  identifier         = "${var.cluster_name}-aurora-${count.index}"
  cluster_identifier = aws_rds_cluster.iq_cluster.id
  instance_class     = var.aurora_instance_class
  engine             = aws_rds_cluster.iq_cluster.engine
  engine_version     = aws_rds_cluster.iq_cluster.engine_version

  performance_insights_enabled = true
  monitoring_interval         = 60
  monitoring_role_arn        = aws_iam_role.rds_enhanced_monitoring.arn

  tags = {
    Name        = "${var.cluster_name}-aurora-${count.index}"
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }
}

resource "aws_kms_key" "iq_kms_key" {
  description             = "KMS key for ${var.cluster_name} RDS encryption"
  deletion_window_in_days = 7

  tags = {
    Name        = "${var.cluster_name}-kms-key"
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }
}

resource "aws_kms_alias" "iq_kms_key_alias" {
  name          = "alias/${var.cluster_name}-rds-key"
  target_key_id = aws_kms_key.iq_kms_key.key_id
}

resource "aws_security_group" "rds" {
  name_prefix = "${var.cluster_name}-rds"
  vpc_id      = aws_vpc.iq_vpc.id

  ingress {
    description     = "PostgreSQL from EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.cluster_name}-rds"
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }
}

resource "aws_iam_role" "rds_enhanced_monitoring" {
  name = "${var.cluster_name}-rds-enhanced-monitoring"

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
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name                           = "${var.cluster_name}-db-credentials"
  description                    = "Database credentials for ${var.cluster_name}"
  recovery_window_in_days        = 0
  force_overwrite_replica_secret = true

  tags = {
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.database_username
    password = var.database_password
  })
}

resource "aws_ssm_parameter" "db_host" {
  name  = "/${var.cluster_name}/database/host"
  type  = "String"
  value = aws_rds_cluster.iq_cluster.endpoint

  tags = {
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }
}

resource "aws_ssm_parameter" "db_port" {
  name  = "/${var.cluster_name}/database/port"
  type  = "String"
  value = "5432"

  tags = {
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }
}

resource "aws_ssm_parameter" "db_name" {
  name  = "/${var.cluster_name}/database/name"
  type  = "String"
  value = var.database_name

  tags = {
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }
}

resource "aws_ssm_parameter" "db_username" {
  name  = "/${var.cluster_name}/database/username"
  type  = "SecureString"
  value = var.database_username

  tags = {
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }
}

resource "aws_ssm_parameter" "db_password" {
  name  = "/${var.cluster_name}/database/password"
  type  = "SecureString"
  value = var.database_password

  tags = {
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }
}