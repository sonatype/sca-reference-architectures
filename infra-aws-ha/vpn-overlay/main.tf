terraform {
  # >= 1.9 for the cross-variable reference in cloudconnexa_application_domain's
  # validation block (it checks var.ssl_enabled).
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    cloudconnexa = {
      source  = "OpenVPN/cloudconnexa"
      version = "~> 1.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "cloudconnexa" {
  base_url = var.cloudconnexa_base_url
}
