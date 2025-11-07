
resource "aws_db_subnet_group" "iq_db_subnet_group" {
  name       = "${var.cluster_name}-db-subnet-group"
  subnet_ids = aws_subnet.db_subnets[*].id

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-db-subnet-group"
  })
}


resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.cluster_name}-db-credentials"
  description             = "Database credentials for Nexus IQ Server HA"
  recovery_window_in_days = 7

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-db-credentials"
  })
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
  })
}


resource "aws_kms_key" "aurora" {
  description             = "KMS key for Aurora cluster encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-aurora-kms-key"
  })
}

resource "aws_kms_alias" "aurora" {
  name          = "alias/${var.cluster_name}-aurora"
  target_key_id = aws_kms_key.aurora.key_id
}


resource "aws_rds_cluster" "iq_aurora_cluster" {
  cluster_identifier      = "${var.cluster_name}-aurora-cluster"
  engine                 = "aurora-postgresql"
  engine_version         = var.aurora_engine_version
  database_name          = var.db_name
  master_username        = var.db_username
  master_password        = var.db_password


  vpc_security_group_ids = [aws_security_group.aurora.id]
  db_subnet_group_name   = aws_db_subnet_group.iq_db_subnet_group.name


  backup_retention_period = var.db_backup_retention_period
  preferred_backup_window = var.db_backup_window
  preferred_maintenance_window = var.db_maintenance_window


  storage_encrypted   = true
  kms_key_id         = aws_kms_key.aurora.arn
  deletion_protection = var.db_deletion_protection
  skip_final_snapshot = var.db_skip_final_snapshot
  final_snapshot_identifier = var.db_skip_final_snapshot ? null : "${var.cluster_name}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"


  availability_zones = slice(data.aws_availability_zones.available.names, 0, min(length(data.aws_availability_zones.available.names), 3))


  enabled_cloudwatch_logs_exports = ["postgresql"]




  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.iq_aurora_cluster_pg.name

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-aurora-cluster"
  })




}


resource "aws_rds_cluster_instance" "iq_aurora_instances" {
  count              = var.aurora_instances
  identifier         = "${var.cluster_name}-aurora-instance-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.iq_aurora_cluster.id
  instance_class     = var.aurora_instance_class
  engine             = aws_rds_cluster.iq_aurora_cluster.engine
  engine_version     = aws_rds_cluster.iq_aurora_cluster.engine_version


  performance_insights_enabled = true
  monitoring_interval         = 60
  monitoring_role_arn        = aws_iam_role.aurora_enhanced_monitoring.arn


  auto_minor_version_upgrade = true


  db_parameter_group_name = aws_db_parameter_group.iq_aurora_instance_pg.name


  availability_zone = data.aws_availability_zones.available.names[count.index % length(data.aws_availability_zones.available.names)]

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-aurora-instance-${count.index + 1}"
  })




}


resource "aws_iam_role" "aurora_enhanced_monitoring" {
  name = "${var.cluster_name}-aurora-enhanced-monitoring"

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

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-aurora-enhanced-monitoring"
  })
}

resource "aws_iam_role_policy_attachment" "aurora_enhanced_monitoring" {
  role       = aws_iam_role.aurora_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}












resource "aws_rds_cluster_parameter_group" "iq_aurora_cluster_pg" {
  family      = "aurora-postgresql15"
  name        = "${var.cluster_name}-aurora-cluster-pg"
  description = "Aurora cluster parameter group for IQ Server HA"


  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }

  parameter {
    name  = "log_statement"
    value = "all"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }


  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-aurora-cluster-pg"
  })
}

resource "aws_db_parameter_group" "iq_aurora_instance_pg" {
  family = "aurora-postgresql15"
  name   = "${var.cluster_name}-aurora-instance-pg"


  parameter {
    name  = "log_rotation_size"
    value = "102400"
  }

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-aurora-instance-pg"
  })
}

