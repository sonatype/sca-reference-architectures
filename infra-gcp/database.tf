# Cloud SQL PostgreSQL Database Instance (Single-instance)
resource "google_sql_database_instance" "iq_db" {
  name             = "nexus-iq-db-${random_string.suffix.result}"
  database_version = var.postgres_version
  region           = var.gcp_region
  project          = var.gcp_project_id

  settings {
    tier                  = var.db_instance_tier
    availability_type     = var.db_availability_type
    disk_type             = "PD_SSD"
    disk_size             = var.db_disk_size
    disk_autoresize       = true
    disk_autoresize_limit = var.db_max_disk_size

    user_labels = {
      environment = var.environment
      component   = "nexus-iq-database"
    }

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
      private_network = google_compute_network.iq_vpc.id
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

  depends_on = [
    google_service_networking_connection.private_vpc_connection,
    google_project_service.required_apis
  ]
}

# Cloud SQL Database
resource "google_sql_database" "iq_database" {
  name     = var.db_name
  instance = google_sql_database_instance.iq_db.name
  project  = var.gcp_project_id
}

# Cloud SQL User
resource "google_sql_user" "iq_db_user" {
  name     = var.db_username
  instance = google_sql_database_instance.iq_db.name
  password = var.db_password
  project  = var.gcp_project_id
}

# Secret Manager for database credentials
resource "google_secret_manager_secret" "db_credentials" {
  secret_id = "nexus-iq-db-credentials"
  project   = var.gcp_project_id

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "db_credentials" {
  secret = google_secret_manager_secret.db_credentials.id
  secret_data = jsonencode({
    username = var.db_username
    password = var.db_password
    host     = google_sql_database_instance.iq_db.private_ip_address
    port     = 5432
    database = var.db_name
  })
}



# SSL Certificate for Cloud SQL
resource "google_sql_ssl_cert" "iq_client_cert" {
  common_name = "nexus-iq-client-cert"
  instance    = google_sql_database_instance.iq_db.name
  project     = var.gcp_project_id
}

