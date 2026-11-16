# Provisioned performance is sent only on Hyperdisk Balanced, and only when both values are set.
locals {
  db_disk_provisioned = var.db_disk_type == "HYPERDISK_BALANCED" && var.db_disk_provisioned_iops != null && var.db_disk_provisioned_throughput != null
}

# Cloud SQL PostgreSQL Database Instance (Regional HA)
resource "google_sql_database_instance" "iq_ha_db" {
  name             = "${local.app_name}-db-${random_string.suffix.result}"
  database_version = var.postgres_version
  region           = var.gcp_region
  project          = var.gcp_project_id

  settings {
    tier                  = var.db_instance_tier
    edition               = var.db_edition
    availability_type     = var.db_availability_type # REGIONAL for HA
    disk_type             = var.db_disk_type
    disk_size             = var.db_disk_size
    disk_autoresize       = true
    disk_autoresize_limit = var.db_max_disk_size

    # Cloud SQL accepts provisioned IOPS and throughput only on Hyperdisk Balanced, and only
    # together, so both are sent or neither is.
    data_disk_provisioned_iops       = local.db_disk_provisioned ? var.db_disk_provisioned_iops : null
    data_disk_provisioned_throughput = local.db_disk_provisioned ? var.db_disk_provisioned_throughput : null

    user_labels = merge(var.common_tags, {
      component = "nexus-iq-ha-database"
    })

    database_flags {
      name  = "max_connections"
      value = var.db_max_connections
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.db_backup_start_time
      location                       = var.gcp_region
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = var.db_transaction_log_retention_days
      backup_retention_settings {
        retained_backups = var.db_backup_retention_count
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.db_maintenance_window_day
      hour         = var.db_maintenance_window_hour
      update_track = "stable"
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.iq_ha_vpc.id
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
    }
  }

  deletion_protection = var.db_deletion_protection

  lifecycle {
    precondition {
      condition     = length(regexall("^db-custom-N4-", var.db_instance_tier)) == 0 || var.db_disk_type == "HYPERDISK_BALANCED"
      error_message = "The N4 tiers (db-custom-N4-*) take only HYPERDISK_BALANCED storage, so db_disk_type must be HYPERDISK_BALANCED."
    }
    precondition {
      condition     = length(regexall("^db-(custom-[0-9]|f1-|g1-)", var.db_instance_tier)) == 0 || var.db_disk_type != "HYPERDISK_BALANCED"
      error_message = "The classic db-custom-*, db-f1-micro and db-g1-small tiers take PD_SSD or PD_HDD, so set db_disk_type to PD_SSD."
    }
    precondition {
      condition     = (var.db_disk_provisioned_iops == null) == (var.db_disk_provisioned_throughput == null)
      error_message = "Cloud SQL takes provisioned IOPS and throughput together, so set both db_disk_provisioned_iops and db_disk_provisioned_throughput, or leave both null."
    }
    precondition {
      condition     = coalesce(var.db_disk_provisioned_throughput, 140) >= max(140, coalesce(var.db_disk_provisioned_iops, 3000) / 256) && coalesce(var.db_disk_provisioned_throughput, 140) <= min(2400, coalesce(var.db_disk_provisioned_iops, 3000) / 4)
      error_message = "Hyperdisk Balanced takes a throughput from the larger of 140 and IOPS / 256, up to the smaller of 2400 and IOPS / 4, in MiB/s."
    }
  }

  depends_on = [
    google_service_networking_connection.private_vpc_connection,
    google_project_service.required_apis
  ]
}

# Cloud SQL Database
resource "google_sql_database" "iq_ha_database" {
  name     = var.db_name
  instance = google_sql_database_instance.iq_ha_db.name
  project  = var.gcp_project_id
}

# Cloud SQL User
resource "google_sql_user" "iq_ha_db_user" {
  name     = var.db_username
  instance = google_sql_database_instance.iq_ha_db.name
  password = var.db_password
  project  = var.gcp_project_id
}

# Secret Manager for database credentials
resource "google_secret_manager_secret" "db_credentials" {
  secret_id = "${local.app_name}-db-credentials-${random_string.suffix.result}"
  project   = var.gcp_project_id

  replication {
    auto {}
  }

  labels = merge(var.common_tags, {
    component = "nexus-iq-ha-database-secrets"
  })

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "db_credentials" {
  secret = google_secret_manager_secret.db_credentials.id
  secret_data = jsonencode({
    username = var.db_username
    password = var.db_password
    host     = google_sql_database_instance.iq_ha_db.private_ip_address
    port     = 5432
    database = var.db_name
  })
}

# Store just the password for easier access in startup script
resource "google_secret_manager_secret" "db_password" {
  secret_id = "${local.app_name}-db-password-${random_string.suffix.result}"
  project   = var.gcp_project_id

  replication {
    auto {}
  }

  labels = merge(var.common_tags, {
    component = "nexus-iq-ha-database-password"
  })

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = var.db_password
}

# SSL Certificate for Cloud SQL
resource "google_sql_ssl_cert" "iq_ha_client_cert" {
  common_name = "${local.app_name}-client-cert"
  instance    = google_sql_database_instance.iq_ha_db.name
  project     = var.gcp_project_id
}