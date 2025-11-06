resource "aws_efs_file_system" "iq_efs" {
  creation_token   = "${var.cluster_name}-efs"
  performance_mode = "generalPurpose"
  throughput_mode  = "provisioned"
  provisioned_throughput_in_mibps = var.efs_provisioned_throughput

  encrypted  = true
  kms_key_id = aws_kms_key.efs_kms_key.arn

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }

  tags = {
    Name        = "${var.cluster_name}-efs"
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }
}

resource "aws_kms_key" "efs_kms_key" {
  description             = "KMS key for ${var.cluster_name} EFS encryption"
  deletion_window_in_days = 7

  tags = {
    Name        = "${var.cluster_name}-efs-kms-key"
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }
}

resource "aws_kms_alias" "efs_kms_key_alias" {
  name          = "alias/${var.cluster_name}-efs-key"
  target_key_id = aws_kms_key.efs_kms_key.key_id
}

resource "aws_efs_mount_target" "iq_efs_mount_target" {
  count = length(aws_subnet.private)

  file_system_id  = aws_efs_file_system.iq_efs.id
  subnet_id       = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_security_group" "efs" {
  name_prefix = "${var.cluster_name}-efs"
  vpc_id      = aws_vpc.iq_vpc.id

  ingress {
    description = "NFS from private subnets (EKS nodes)"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [for subnet in aws_subnet.private : subnet.cidr_block]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.cluster_name}-efs"
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }
}

resource "aws_efs_access_point" "iq_data" {
  file_system_id = aws_efs_file_system.iq_efs.id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/nexus-iq-data"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "0755"
    }
  }

  tags = {
    Name        = "${var.cluster_name}-iq-data-access-point"
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }
}

resource "aws_efs_access_point" "iq_logs" {
  file_system_id = aws_efs_file_system.iq_efs.id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/nexus-iq-logs"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "0755"
    }
  }

  tags = {
    Name        = "${var.cluster_name}-iq-logs-access-point"
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }
}

resource "aws_efs_backup_policy" "iq_efs_backup" {
  file_system_id = aws_efs_file_system.iq_efs.id

  backup_policy {
    status = "ENABLED"
  }
}

resource "aws_ssm_parameter" "efs_id" {
  name  = "/${var.cluster_name}/efs/id"
  type  = "String"
  value = aws_efs_file_system.iq_efs.id

  tags = {
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }
}

resource "aws_ssm_parameter" "efs_data_access_point" {
  name  = "/${var.cluster_name}/efs/data-access-point"
  type  = "String"
  value = aws_efs_access_point.iq_data.id

  tags = {
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }
}

resource "aws_ssm_parameter" "efs_logs_access_point" {
  name  = "/${var.cluster_name}/efs/logs-access-point"
  type  = "String"
  value = aws_efs_access_point.iq_logs.id

  tags = {
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }
}