# The IQ Server license. Terraform reads the file named by iq_license_file and keeps it
# in Secrets Manager, and every task writes it to a file that config.yml names as
# licenseFile, so IQ Server installs it on its first start. An unlicensed IQ Server runs
# one node only, so without it every task after the first would stop and restart until
# the license was installed. iq-post-deploy.sh installs it again only as a fallback.

variable "iq_license_file" {
  description = "Path to the IQ Server license file (.lic). Terraform reads it on every plan, so keep the file where this path points"
  type        = string

  validation {
    condition     = !can(regex("CHANGE_ME", var.iq_license_file)) && try(fileexists(var.iq_license_file), false)
    error_message = "iq_license_file must be the path to your IQ Server license file, not a CHANGE_ME placeholder, and the file must exist. Set it in terraform.tfvars."
  }
}

resource "aws_secretsmanager_secret" "iq_license" {
  name                    = "${var.cluster_name}-iq-license"
  description             = "Nexus IQ Server license, base64 encoded"
  recovery_window_in_days = 0

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-iq-license"
  })
}

resource "aws_secretsmanager_secret_version" "iq_license" {
  secret_id     = aws_secretsmanager_secret.iq_license.id
  secret_string = sensitive(filebase64(var.iq_license_file))
}

output "iq_license_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the IQ Server license, force-deleted by tf-destroy.sh"
  value       = aws_secretsmanager_secret.iq_license.arn
}

output "iq_license_file" {
  description = "The IQ Server license file, read by iq-post-deploy.sh if IQ Server has no license yet"
  value       = abspath(var.iq_license_file)
}
