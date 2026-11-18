# The IQ Server license. Terraform checks that the file named by iq_license_file exists,
# and helm-install.sh builds the nexus-iq-license Kubernetes Secret from it, which the
# chart mounts so every IQ Server pod installs the license on its first start. An
# unlicensed IQ Server runs one node only, so without it every pod after the first would
# stop and restart until the license was installed. iq-post-deploy.sh installs it again
# only as a fallback.

variable "iq_license_file" {
  description = "Path to the IQ Server license file (.lic). helm-install.sh reads it, so keep the file where this path points"
  type        = string

  validation {
    condition     = !can(regex("CHANGE_ME", var.iq_license_file)) && try(fileexists(var.iq_license_file), false)
    error_message = "iq_license_file must be the path to your IQ Server license file, not a CHANGE_ME placeholder, and the file must exist. Set it in terraform.tfvars."
  }
}

output "iq_license_file" {
  description = "The IQ Server license file, read by helm-install.sh into the nexus-iq-license secret"
  value       = abspath(var.iq_license_file)
}
