# EFS File System for shared storage across IQ Server pods
resource "aws_efs_file_system" "iq_efs" {
  creation_token   = "${var.cluster_name}-efs"
  encrypted        = true
  kms_key_id      = aws_kms_key.efs.arn

  performance_mode = "generalPurpose"
  throughput_mode  = var.efs_throughput_mode

  # Only set provisioned throughput if mode is provisioned
  provisioned_throughput_in_mibps = var.efs_throughput_mode == "provisioned" ? var.efs_provisioned_throughput_in_mibps : null

  # Lifecycle policy to transition files to IA storage
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-efs"
  })
}

# KMS Key for EFS encryption
resource "aws_kms_key" "efs" {
  description             = "KMS key for EFS encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-efs-kms-key"
  })
}

resource "aws_kms_alias" "efs" {
  name          = "alias/${var.cluster_name}-efs"
  target_key_id = aws_kms_key.efs.key_id
}

# EFS Mount Targets (one per private subnet for HA)
resource "aws_efs_mount_target" "iq_efs_mt" {
  count           = length(aws_subnet.private_subnets)
  file_system_id  = aws_efs_file_system.iq_efs.id
  subnet_id       = aws_subnet.private_subnets[count.index].id
  security_groups = [aws_security_group.efs.id]
}

# EFS Access Point for IQ Server with proper POSIX permissions
resource "aws_efs_access_point" "iq_access_point" {
  file_system_id = aws_efs_file_system.iq_efs.id

  posix_user {
    uid = 1000  # IQ Server container user ID (official image)
    gid = 1000  # IQ Server container group ID (official image)
  }

  root_directory {
    path = "/nexus-iq-data"
    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "0755"
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-efs-access-point"
  })
}

# Additional access point for logs (used by Fluentd)
resource "aws_efs_access_point" "iq_logs_access_point" {
  file_system_id = aws_efs_file_system.iq_efs.id

  posix_user {
    uid = 1000  # IQ Server container user ID (official image)
    gid = 1000  # IQ Server container group ID (official image)
  }

  root_directory {
    path = "/nexus-iq-logs"
    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "0755"
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-efs-logs-access-point"
  })
}

# EFS Backup Policy
resource "aws_efs_backup_policy" "iq_efs_backup" {
  file_system_id = aws_efs_file_system.iq_efs.id

  backup_policy {
    status = "ENABLED"
  }
}

# EFS Backup Vault for more control
resource "aws_backup_vault" "iq_efs_backup_vault" {
  name        = "${var.cluster_name}-efs-backup-vault"
  kms_key_arn = aws_kms_key.efs_backup.arn

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-efs-backup-vault"
  })
}

# KMS Key for EFS backup encryption
resource "aws_kms_key" "efs_backup" {
  description             = "KMS key for EFS backup encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-efs-backup-kms-key"
  })
}

resource "aws_kms_alias" "efs_backup" {
  name          = "alias/${var.cluster_name}-efs-backup"
  target_key_id = aws_kms_key.efs_backup.key_id
}

# IAM Role for EFS backup
resource "aws_iam_role" "efs_backup_role" {
  name = "${var.cluster_name}-efs-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-efs-backup-role"
  })
}

resource "aws_iam_role_policy_attachment" "efs_backup_policy" {
  role       = aws_iam_role.efs_backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

# EFS Backup Plan
resource "aws_backup_plan" "iq_efs_backup_plan" {
  name = "${var.cluster_name}-efs-backup-plan"

  rule {
    rule_name         = "daily_backups"
    target_vault_name = aws_backup_vault.iq_efs_backup_vault.name
    schedule          = "cron(0 2 ? * * *)"  # Daily at 2 AM

    recovery_point_tags = merge(var.common_tags, {
      BackupType = "Daily"
    })

    lifecycle {
      cold_storage_after = 30
      delete_after       = 120  # Keep for 4 months
    }
  }

  rule {
    rule_name         = "weekly_backups"
    target_vault_name = aws_backup_vault.iq_efs_backup_vault.name
    schedule          = "cron(0 3 ? * SUN *)"  # Weekly on Sunday at 3 AM

    recovery_point_tags = merge(var.common_tags, {
      BackupType = "Weekly"
    })

    lifecycle {
      cold_storage_after = 30
      delete_after       = 365  # Keep for 1 year
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-efs-backup-plan"
  })
}

# EFS Backup Selection
resource "aws_backup_selection" "iq_efs_backup_selection" {
  iam_role_arn = aws_iam_role.efs_backup_role.arn
  name         = "${var.cluster_name}-efs-backup-selection"
  plan_id      = aws_backup_plan.iq_efs_backup_plan.id

  resources = [
    aws_efs_file_system.iq_efs.arn
  ]
}