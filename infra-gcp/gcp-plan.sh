#!/bin/bash

# Nexus IQ Server GCP Infrastructure Planning Script
# This script plans the Terraform deployment with proper authentication

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TFVARS_FILE="${SCRIPT_DIR}/terraform.tfvars"

# Functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ✗${NC} $1"
    exit 1
}

print_banner() {
    echo ""
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}  Nexus IQ Server GCP Infrastructure Plan${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo ""
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install Google Cloud SDK."
    fi
    
    # Check if terraform is installed
    if ! command -v terraform &> /dev/null; then
        error "Terraform is not installed. Please install Terraform >= 1.0"
    fi
    
    # Check if authenticated with gcloud
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null 2>&1; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login'"
    fi
    
    success "Prerequisites check passed"
}

check_project() {
    log "Checking GCP project configuration..."
    
    # Get current project
    CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
    
    if [[ -z "$CURRENT_PROJECT" ]]; then
        error "No GCP project is set. Please run 'gcloud config set project YOUR_PROJECT_ID'"
    fi
    
    # Verify project exists and is accessible
    if ! gcloud projects describe "$CURRENT_PROJECT" > /dev/null 2>&1; then
        error "Cannot access project '$CURRENT_PROJECT'. Please check your permissions."
    fi
    
    success "Using GCP project: $CURRENT_PROJECT"
}

check_terraform_config() {
    log "Checking Terraform configuration..."
    
    if [[ ! -f "$TFVARS_FILE" ]]; then
        warning "terraform.tfvars not found. Please run './deploy.sh' first to create configuration template."
        exit 1
    fi
    
    success "Terraform configuration found"
}

terraform_init() {
    log "Initializing Terraform..."
    
    cd "$SCRIPT_DIR"
    terraform init -upgrade
    
    success "Terraform initialized"
}

terraform_validate() {
    log "Validating Terraform configuration..."
    
    cd "$SCRIPT_DIR"
    terraform validate
    
    success "Terraform configuration is valid"
}

terraform_plan() {
    log "Running Terraform plan..."
    
    cd "$SCRIPT_DIR"
    
    # Run terraform plan with detailed output
    terraform plan \
        -var-file="$TFVARS_FILE" \
        -out=tfplan \
        -detailed-exitcode
    
    PLAN_EXIT_CODE=$?
    
    case $PLAN_EXIT_CODE in
        0)
            success "No changes required - infrastructure is up-to-date"
            ;;
        1)
            error "Terraform plan failed"
            ;;
        2)
            success "Plan completed - changes detected"
            show_plan_summary
            ;;
    esac
}

show_plan_summary() {
    echo ""
    echo -e "${BLUE}Plan Summary:${NC}"
    echo ""
    
    cd "$SCRIPT_DIR"
    
    # Show a summary of changes
    terraform show -json tfplan | jq -r '
        .planned_values.root_module.resources[] |
        select(.type) |
        "\(.type).\(.name) - \(.values.name // .values.id // "unnamed")"
    ' 2>/dev/null | sort | uniq | while read -r resource; do
        echo -e "  ${GREEN}+${NC} $resource"
    done
    
    echo ""
    echo -e "${YELLOW}To apply these changes, run:${NC}"
    echo -e "  ${BLUE}terraform apply tfplan${NC}"
    echo -e "or"
    echo -e "  ${BLUE}./gcp-apply.sh${NC}"
    echo ""
}

show_cost_estimate() {
    log "Estimating costs..."
    
    echo ""
    echo -e "${YELLOW}Estimated Monthly Costs (approximate):${NC}"
    echo ""
    
    # Read configuration to estimate costs
    cd "$SCRIPT_DIR"
    
    if [[ -f "$TFVARS_FILE" ]]; then
        DEPLOYMENT_MODE=$(grep iq_deployment_mode "$TFVARS_FILE" | cut -d'"' -f2 2>/dev/null || echo "single")
        DB_TIER=$(grep db_instance_tier "$TFVARS_FILE" | cut -d'"' -f2 2>/dev/null || echo "db-custom-2-4096")
        FILESTORE_CAPACITY=$(grep filestore_capacity_gb "$TFVARS_FILE" | cut -d' ' -f3 2>/dev/null || echo "1024")
        
        echo -e "${BLUE}Core Services:${NC}"
        echo -e "  • Cloud Run (2 vCPU, 4GB): ~\$30-50/month"
        
        if [[ "$DEPLOYMENT_MODE" == "ha" ]]; then
            echo -e "  • Cloud Run (HA mode): ~\$60-100/month"
        fi
        
        case "$DB_TIER" in
            "db-custom-2-4096")
                echo -e "  • Cloud SQL (2 vCPU, 4GB): ~\$70-90/month"
                ;;
            "db-custom-4-8192")
                echo -e "  • Cloud SQL (4 vCPU, 8GB): ~\$140-180/month"
                ;;
            *)
                echo -e "  • Cloud SQL: ~\$70-180/month (depends on tier)"
                ;;
        esac
        
        FILESTORE_COST=$((FILESTORE_CAPACITY * 20 / 100))  # Approximate $0.20/GB/month
        echo -e "  • Cloud Filestore (${FILESTORE_CAPACITY}GB): ~\$${FILESTORE_COST}/month"
        
        echo -e "  • Load Balancer: ~\$20-30/month"
        echo -e "  • Networking & Storage: ~\$10-20/month"
        echo ""
        echo -e "${YELLOW}Total Estimated: \$200-400/month${NC}"
        echo -e "${BLUE}Note: Actual costs depend on usage, region, and configuration${NC}"
    fi
    
    echo ""
}

main() {
    print_banner
    
    check_prerequisites
    check_project
    check_terraform_config
    terraform_init
    terraform_validate
    terraform_plan
    show_cost_estimate
    
    echo ""
    echo -e "${GREEN}Planning completed successfully!${NC}"
    echo ""
}

# Run main function
main "$@"