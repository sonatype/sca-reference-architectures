# Cloud SQL PostgreSQL Database Instance
resource "google_sql_database_instance" "iq_db" {
  name             = "ref-arch-iq-database-${random_string.suffix.result}"
  database_version = "POSTGRES_${var.postgres_version}"
  region           = var.gcp_region

  settings {
    tier                        = var.db_instance_tier
    deletion_protection_enabled = var.db_deletion_protection
    availability_type           = var.iq_deployment_mode == "ha" ? "REGIONAL" : "ZONAL"
    disk_type                   = "PD_SSD"
    disk_size                   = var.db_allocated_storage
    disk_autoresize             = true
    disk_autoresize_limit       = var.db_max_allocated_storage

    backup_configuration {
      enabled = true
      start_time = var.db_backup_start_time
      location = var.gcp_region
      point_in_time_recovery_enabled = true
      backup_retention_settings {
        retained_backups = var.db_backup_retention_days
        retention_unit   = "COUNT"
      }
      transaction_log_retention_days = 7
    }

    maintenance_window {
      day  = 7  # Sunday
      hour = 4  # 4 AM
    }

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = google_compute_network.iq_vpc.id
      enable_private_path_for_google_cloud_services = true
    }

    database_flags {
      name  = "log_checkpoints"
      value = "on"
    }
    
    database_flags {
      name  = "log_connections"
      value = "on"
    }
    
    database_flags {
      name  = "log_disconnections"
      value = "on"
    }
    
    database_flags {
      name  = "log_lock_waits"
      value = "on"
    }

    insights_config {
      query_insights_enabled  = true
      record_application_tags = true
      record_client_address   = true
    }
  }

  depends_on = [
    google_service_networking_connection.private_vpc_connection,
    google_project_service.required_apis
  ]

  deletion_protection = var.db_deletion_protection
}

# Create the database
resource "google_sql_database" "iq_database" {
  name     = var.db_name
  instance = google_sql_database_instance.iq_db.name
}

# Create database user
resource "google_sql_user" "iq_user" {
  name     = var.db_username
  instance = google_sql_database_instance.iq_db.name
  password = var.db_password
}

# Create secrets for database credentials
resource "google_secret_manager_secret" "db_credentials" {
  secret_id = "ref-arch-iq-db-credentials"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "db_credentials" {
  secret      = google_secret_manager_secret.db_credentials.id
  secret_data = var.db_username
}

resource "google_secret_manager_secret" "db_password" {
  secret_id = "ref-arch-iq-db-password"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = var.db_password
}

# Read replica for HA deployment (optional)
resource "google_sql_database_instance" "iq_db_replica" {
  count            = var.iq_deployment_mode == "ha" && var.enable_read_replica ? 1 : 0
  name             = "ref-arch-iq-database-replica-${random_string.suffix.result}"
  database_version = "POSTGRES_${var.postgres_version}"
  region           = var.gcp_region_secondary

  replica_configuration {
    master_instance_name = google_sql_database_instance.iq_db.name
  }

  settings {
    tier              = var.db_instance_tier
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = google_compute_network.iq_vpc.id
      enable_private_path_for_google_cloud_services = true
    }

    insights_config {
      query_insights_enabled  = true
      record_application_tags = true
      record_client_address   = true
    }
  }

  depends_on = [
    google_sql_database_instance.iq_db
  ]

  deletion_protection = var.db_deletion_protection
}