# The IQ Server license. Terraform reads the file named by iq_license_file and keeps it in
# Secret Manager, and the instance writes it to a file that config.yml names as licenseFile,
# so IQ Server installs it on its first start. iq-post-deploy.sh installs it again only as a
# fallback. The service account's project-wide secretAccessor grant covers it.

variable "iq_license_file" {
  description = "Path to the IQ Server license file (.lic). Terraform reads it on every plan, so keep the file where this path points"
  type        = string

  validation {
    condition     = !can(regex("CHANGE_ME", var.iq_license_file)) && try(fileexists(var.iq_license_file), false)
    error_message = "iq_license_file must be the path to your IQ Server license file, not a CHANGE_ME placeholder, and the file must exist. Set it in terraform.tfvars."
  }
}

resource "google_secret_manager_secret" "iq_license" {
  secret_id = "${local.app_name}-iq-license"
  project   = var.gcp_project_id

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "iq_license" {
  secret      = google_secret_manager_secret.iq_license.id
  secret_data = sensitive(filebase64(var.iq_license_file))
}

output "iq_license_file" {
  description = "The IQ Server license file, read by iq-post-deploy.sh if IQ Server has no license yet"
  value       = abspath(var.iq_license_file)
}
