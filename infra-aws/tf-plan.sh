#!/bin/bash

# Terraform Plan Script with MFA Support
# This script uses aws-vault to handle AWS MFA authentication and runs terraform plan

set -e  # Exit on any error

echo "🔐 Using aws-vault to authenticate with MFA..."
echo "📋 Running terraform plan with aws-vault..."

# Use aws-vault to execute terraform plan with proper MFA authentication
aws-vault exec admin@iq-sandbox -- terraform plan

echo "✅ Terraform plan completed!"