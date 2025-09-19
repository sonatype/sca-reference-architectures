#!/bin/bash

# Nexus IQ Server GCP Infrastructure Deployment Script
# This script deploys the complete infrastructure for Nexus IQ Server on GCP

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
LOG_FILE="${SCRIPT_DIR}/deployment.log"

# Functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✓${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ✗${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

print_banner() {
    echo ""
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}  Nexus IQ Server GCP Infrastructure Deployment${NC}"
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
    
    # Check terraform version
    TERRAFORM_VERSION=$(terraform version -json | jq -r '.terraform_version')
    if ! terraform version -json | jq -r '.terraform_version' | grep -E '^1\.[0-9]+\.[0-9]+$' > /dev/null; then
        error "Terraform version 1.0 or higher is required. Current version: $TERRAFORM_VERSION"
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

check_apis() {
    log "Checking required GCP APIs..."
    
    REQUIRED_APIS=(
        "compute.googleapis.com"
        "run.googleapis.com"
        "sqladmin.googleapis.com"
        "file.googleapis.com"
        "secretmanager.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "iam.googleapis.com"
    )
    
    for api in "${REQUIRED_APIS[@]}"; do
        if gcloud services list --enabled --filter="name:$api" --format="value(name)" | grep -q "$api"; then
            success "API enabled: $api"
        else
            warning "API not enabled: $api"
            log "Enabling API: $api"
            gcloud services enable "$api"
            success "API enabled: $api"
        fi
    done
}

check_terraform_config() {
    log "Checking Terraform configuration..."
    
    if [[ ! -f "$TFVARS_FILE" ]]; then
        warning "terraform.tfvars not found. Creating template..."
        cat > "$TFVARS_FILE" << 'EOF'
# GCP Configuration
gcp_project_id = "your-project-id"
gcp_region     = "us-central1"
gcp_zone       = "us-central1-a"

# Environment
environment = "dev"

# Deployment Mode: "single" or "ha"
iq_deployment_mode = "single"

# Database Configuration
db_password = "ChangeMe123!"  # Please change this!

# Networking
vpc_connector_cidr = "10.0.4.0/28"

# Optional: Domain and SSL
# domain_name = "nexus-iq.example.com"
# ssl_certificate_name = "nexus-iq-ssl-cert"

# Optional: Monitoring
# alert_email_addresses = ["admin@example.com"]

# Security
enable_cloud_armor = true
rate_limit_threshold = 100

# Storage
storage_force_destroy = false  # Set to true for testing environments only
EOF
        error "Please edit $TFVARS_FILE with your configuration before running this script again."
    fi
    
    # Validate required variables
    if ! grep -q "gcp_project_id" "$TFVARS_FILE" || grep -q "your-project-id" "$TFVARS_FILE"; then
        error "Please set gcp_project_id in $TFVARS_FILE"
    fi
    
    if grep -q "ChangeMe123!" "$TFVARS_FILE"; then
        error "Please change the default database password in $TFVARS_FILE"
    fi
    
    success "Terraform configuration validated"
}

terraform_init() {
    log "Initializing Terraform..."
    
    cd "$SCRIPT_DIR"
    terraform init
    
    success "Terraform initialized"
}

terraform_plan() {
    log "Planning Terraform deployment..."
    
    cd "$SCRIPT_DIR"
    terraform plan -var-file="$TFVARS_FILE" -out=tfplan
    
    success "Terraform plan completed"
}

terraform_apply() {
    log "Applying Terraform configuration..."
    
    cd "$SCRIPT_DIR"
    terraform apply tfplan
    
    success "Infrastructure deployed successfully"
}

show_outputs() {
    log "Retrieving deployment information..."
    
    cd "$SCRIPT_DIR"
    terraform output -json > outputs.json
    
    APPLICATION_URL=$(terraform output -raw application_url 2>/dev/null || echo "Not available")
    CLOUD_RUN_SERVICE=$(terraform output -raw cloud_run_service_name 2>/dev/null || echo "Not available")
    DATABASE_INSTANCE=$(terraform output -raw database_instance_name 2>/dev/null || echo "Not available")
    MONITORING_URL=$(terraform output -raw monitoring_dashboard_url 2>/dev/null || echo "Not available")
    
    echo ""
    echo -e "${GREEN}=================================================${NC}"
    echo -e "${GREEN}  Deployment Completed Successfully!${NC}"
    echo -e "${GREEN}=================================================${NC}"
    echo ""
    echo -e "${BLUE}Application Access:${NC}"
    echo -e "  URL: ${GREEN}$APPLICATION_URL${NC}"
    echo -e "  Default credentials: ${YELLOW}admin / admin123${NC}"
    echo ""
    echo -e "${BLUE}Key Resources:${NC}"
    echo -e "  Cloud Run Service: ${GREEN}$CLOUD_RUN_SERVICE${NC}"
    echo -e "  Database Instance: ${GREEN}$DATABASE_INSTANCE${NC}"
    echo ""
    echo -e "${BLUE}Monitoring:${NC}"
    echo -e "  Dashboard: ${GREEN}$MONITORING_URL${NC}"
    echo ""
    echo -e "${BLUE}Management:${NC}"
    echo -e "  View logs: ${BLUE}gcloud run services logs tail $CLOUD_RUN_SERVICE --region=\$(terraform output -raw region)${NC}"
    echo -e "  Full outputs: ${BLUE}terraform output${NC}"
    echo ""
    echo -e "${YELLOW}Note: It may take 5-10 minutes for the service to be fully ready.${NC}"
    echo ""
}

cleanup_on_error() {
    error "Deployment failed. Check $LOG_FILE for details."
}

main() {
    # Set up error handling
    trap cleanup_on_error ERR
    
    print_banner
    
    # Create log file
    touch "$LOG_FILE"
    log "Starting deployment at $(date)"
    
    # Run deployment steps
    check_prerequisites
    check_project
    check_apis
    check_terraform_config
    terraform_init
    terraform_plan
    
    # Confirm deployment
    echo ""
    echo -e "${YELLOW}Ready to deploy infrastructure. This will create resources in GCP.${NC}"
    read -p "Continue with deployment? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deployment cancelled by user"
        exit 0
    fi
    
    terraform_apply
    show_outputs
    
    log "Deployment completed successfully at $(date)"
}

# Run main function
main "$@"