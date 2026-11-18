# The IQ Server license. Terraform reads the file named by iq_license_file and keeps it
# in Key Vault and as a Container App secret, and the container writes it to a file that
# config.yml names as licenseFile, so IQ Server installs it on its first start.
# iq-post-deploy.sh installs it again only as a fallback.

variable "iq_license_file" {
  description = "Path to the IQ Server license file (.lic). Terraform reads it on every plan, so keep the file where this path points"
  type        = string

  validation {
    condition     = !can(regex("CHANGE_ME", var.iq_license_file)) && try(fileexists(var.iq_license_file), false)
    error_message = "iq_license_file must be the path to your IQ Server license file, not a CHANGE_ME placeholder, and the file must exist. Set it in terraform.tfvars."
  }
}

locals {
  iq_license_b64 = sensitive(filebase64(var.iq_license_file))
}

resource "azurerm_key_vault_secret" "iq_license" {
  name         = "iq-license"
  value        = local.iq_license_b64
  content_type = "base64"
  key_vault_id = azurerm_key_vault.iq_kv.id

  depends_on = [azurerm_key_vault_access_policy.current_user]

  tags = merge(var.common_tags, {
    Name = "iq-license"
  })
}

output "iq_license_file" {
  description = "The IQ Server license file, read by iq-post-deploy.sh if IQ Server has no license yet"
  value       = abspath(var.iq_license_file)
}
