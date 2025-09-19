#!/bin/bash

# Terraform Apply Script with MFA Support
# This script uses aws-vault to handle AWS MFA authentication and runs terraform apply

set -e  # Exit on any error

echo "🔐 Using aws-vault to authenticate with MFA..."
echo "🚀 Running terraform apply with aws-vault..."

# Use aws-vault to execute terraform apply with proper MFA authentication
aws-vault exec admin@iq-sandbox -- terraform apply -auto-approve

echo "✅ Terraform apply completed!"