#!/bin/bash

# Terraform destroy script for Nexus IQ Server HA on AKS
# Usage: ./tf-destroy.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${RED}⚠️  Nexus IQ Server HA on AKS - Terraform Destroy${NC}"
echo "======================================================="
echo ""

if [[ ! -f "main.tf" ]]; then
    echo -e "${RED}❌ Error: main.tf not found in current directory${NC}"
    exit 1
fi

echo -e "${BLUE}🗑️  Destroying infrastructure...${NC}"

terraform destroy -auto-approve

echo ""
echo -e "${GREEN}✅ Infrastructure destroyed successfully${NC}"
