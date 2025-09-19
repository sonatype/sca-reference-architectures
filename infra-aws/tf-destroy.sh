#!/bin/bash

# Terraform Destroy Script with MFA Support
# This script uses aws-vault to handle AWS MFA authentication and runs terraform destroy

set -e  # Exit on any error

echo "🔐 Using aws-vault to authenticate with MFA..."

echo "🗑️  Cleaning up secrets manager secrets..."

# Force delete the database credentials secret to avoid retention period issues
aws-vault exec admin@iq-sandbox -- aws secretsmanager delete-secret \
  --secret-id "ref-arch-iq-db-credentials" \
  --force-delete-without-recovery \
  --region us-east-1 || echo "⚠️  Secret may not exist or already deleted"

echo "💥 Running terraform destroy with aws-vault..."

# Use aws-vault to execute terraform destroy with proper MFA authentication
aws-vault exec admin@iq-sandbox -- terraform destroy -auto-approve

echo "✅ Terraform destroy completed!"
