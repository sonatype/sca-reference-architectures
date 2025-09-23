#!/bin/bash
set -euo pipefail

# Deploy script for Nexus IQ Server GCP Infrastructure
# This script creates all the required infrastructure for Nexus IQ Server on GCP

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR"
LOG_FILE="$SCRIPT_DIR/deploy.log"
TFVARS_FILE="$SCRIPT_DIR/terraform.tfvars"
STATE_BUCKET=""
DRY_RUN=false
FORCE_DESTROY=false
SKIP_VALIDATION=false

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

print_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1" | tee -a "$LOG_FILE"
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if running on supported OS
    if [[ "$OSTYPE" != "linux-gnu"* ]] && [[ "$OSTYPE" != "darwin"* ]]; then
        print_error "This script only supports Linux and macOS"
        exit 1
    fi
    
    # Check required tools
    local required_tools=("terraform" "gcloud" "jq" "curl")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            print_error "$tool is not installed. Please install it and try again."
            exit 1
        fi
    done
    
    # Check Terraform version
    local tf_version=$(terraform version -json | jq -r '.terraform_version')
    local tf_major=$(echo "$tf_version" | cut -d. -f1)
    local tf_minor=$(echo "$tf_version" | cut -d. -f2)
    
    if [[ $tf_major -lt 1 ]] || [[ $tf_major -eq 1 && $tf_minor -lt 0 ]]; then
        print_error "Terraform version 1.0 or higher is required. Found: $tf_version"
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        print_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    print_status "Prerequisites check completed successfully"
}

# Function to validate GCP project and permissions
validate_gcp_project() {
    local project_id="$1"
    
    print_status "Validating GCP project: $project_id"
    
    # Check if project exists and user has access
    if ! gcloud projects describe "$project_id" &> /dev/null; then
        print_error "Cannot access project '$project_id'. Please check project ID and permissions."
        exit 1
    fi
    
    # Check required APIs are enabled or user has permission to enable them
    local required_apis=(
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
    
    print_status "Checking required GCP APIs..."
    for api in "${required_apis[@]}"; do
        if ! gcloud services list --enabled --project="$project_id" --filter="name:$api" --format="value(name)" | grep -q "$api"; then
            print_warning "API $api is not enabled. It will be enabled during deployment."
        fi
    done
    
    print_status "GCP project validation completed"
}

# Function to create terraform.tfvars file if it doesn't exist
create_tfvars_template() {
    if [[ ! -f "$TFVARS_FILE" ]]; then
        print_status "Creating terraform.tfvars template..."
        cat > "$TFVARS_FILE" << 'EOF'
# GCP Configuration
gcp_project_id = "your-gcp-project-id"
gcp_region     = "us-central1"
environment    = "dev"

# Database Configuration
db_password = "change-me-secure-password"

# Network Configuration (optional - defaults will be used if not specified)
# vpc_cidr              = "10.100.0.0/16"
# public_subnet_cidr    = "10.100.1.0/24"
# private_subnet_cidr   = "10.100.10.0/24"
# db_subnet_cidr        = "10.100.20.0/24"


# SSL/TLS Configuration
enable_ssl = true
# domain_name = "nexus-iq.example.com"

# Security Configuration
enable_cloud_armor = true
# blocked_countries = ["CN", "RU"]
# ssh_source_ranges = ["YOUR_IP/32"]

# Monitoring Configuration
enable_monitoring_alerts = true
# alert_email_addresses = ["admin@example.com"]
# slack_webhook_url = "https://hooks.slack.com/services/..."

# Storage Configuration
backup_retention_days = 30
log_retention_days = 30

# Scaling Configuration
iq_desired_count = "1"
iq_cpu_limit = "2000m"
iq_memory_limit = "4Gi"
EOF
        print_warning "Created terraform.tfvars template. Please edit it with your configuration before proceeding."
        print_warning "At minimum, set 'gcp_project_id' and 'db_password' values."
        exit 0
    fi
}

# Function to validate terraform.tfvars
validate_tfvars() {
    print_status "Validating terraform.tfvars configuration..."
    
    # Check required variables
    local required_vars=("gcp_project_id" "db_password")
    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}[[:space:]]*=" "$TFVARS_FILE"; then
            print_error "Required variable '$var' not found in terraform.tfvars"
            exit 1
        fi
        
        local value=$(grep "^${var}[[:space:]]*=" "$TFVARS_FILE" | cut -d'"' -f2)
        if [[ -z "$value" ]] || [[ "$value" == "your-gcp-project-id" ]] || [[ "$value" == "change-me-secure-password" ]]; then
            print_error "Please set a proper value for '$var' in terraform.tfvars"
            exit 1
        fi
    done
    
    # Validate password strength
    local db_password=$(grep "^db_password[[:space:]]*=" "$TFVARS_FILE" | cut -d'"' -f2)
    if [[ ${#db_password} -lt 12 ]]; then
        print_error "Database password must be at least 12 characters long"
        exit 1
    fi
    
    print_status "terraform.tfvars validation completed"
}

# Function to setup Terraform backend
setup_terraform_backend() {
    local project_id="$1"
    
    if [[ -n "$STATE_BUCKET" ]]; then
        print_status "Setting up Terraform backend with bucket: $STATE_BUCKET"
        
        # Check if bucket exists
        if ! gsutil ls "gs://$STATE_BUCKET" &> /dev/null; then
            print_status "Creating Terraform state bucket: $STATE_BUCKET"
            gsutil mb -p "$project_id" "gs://$STATE_BUCKET"
            gsutil versioning set on "gs://$STATE_BUCKET"
        fi
        
        # Create backend configuration
        cat > "$TERRAFORM_DIR/backend.tf" << EOF
terraform {
  backend "gcs" {
    bucket = "$STATE_BUCKET"
    prefix = "terraform/state"
  }
}
EOF
        print_status "Terraform backend configured"
    else
        print_warning "No state bucket specified. Using local state (not recommended for production)"
    fi
}

# Function to run terraform plan
run_terraform_plan() {
    print_status "Running Terraform plan..."
    
    cd "$TERRAFORM_DIR"
    
    # Initialize Terraform
    print_status "Initializing Terraform..."
    if ! terraform init -input=false >> "$LOG_FILE" 2>&1; then
        print_error "Terraform initialization failed. Check $LOG_FILE for details."
        exit 1
    fi
    
    # Validate configuration
    print_status "Validating Terraform configuration..."
    if ! terraform validate >> "$LOG_FILE" 2>&1; then
        print_error "Terraform validation failed. Check $LOG_FILE for details."
        exit 1
    fi
    
    # Run plan
    print_status "Creating execution plan..."
    if ! terraform plan -var-file="$TFVARS_FILE" -out=tfplan >> "$LOG_FILE" 2>&1; then
        print_error "Terraform plan failed. Check $LOG_FILE for details."
        exit 1
    fi
    
    # Show plan summary
    print_status "Terraform plan completed successfully"
    terraform show -no-color tfplan | grep -E "Plan:|will be created|will be updated|will be destroyed" | head -20
}

# Function to run terraform apply
run_terraform_apply() {
    print_status "Applying Terraform configuration..."
    
    cd "$TERRAFORM_DIR"
    
    # Apply the plan
    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "Dry run mode - skipping actual deployment"
        return 0
    fi
    
    if ! terraform apply -auto-approve tfplan >> "$LOG_FILE" 2>&1; then
        print_error "Terraform apply failed. Check $LOG_FILE for details."
        print_error "You may need to run 'terraform destroy' to clean up partial deployment."
        exit 1
    fi
    
    print_status "Infrastructure deployment completed successfully"
}

# Function to display deployment summary
show_deployment_summary() {
    print_status "Deployment Summary"
    print_status "=================="
    
    cd "$TERRAFORM_DIR"
    
    # Get outputs
    local nexus_url=$(terraform output -raw nexus_iq_url 2>/dev/null || echo "Not available")
    local load_balancer_ip=$(terraform output -raw load_balancer_ip 2>/dev/null || echo "Not available")
    local project_id=$(terraform output -raw project_id 2>/dev/null || echo "Not available")
    
    echo ""
    print_status "🎉 Nexus IQ Server infrastructure has been deployed successfully!"
    echo ""
    print_status "📋 Access Information:"
    print_status "   Nexus IQ URL: $nexus_url"
    print_status "   Load Balancer IP: $load_balancer_ip"
    print_status "   GCP Project: $project_id"
    echo ""
    print_status "📊 You can view resources in the GCP Console:"
    print_status "   https://console.cloud.google.com/home/dashboard?project=$project_id"
    echo ""
    print_status "📈 Monitoring Dashboard:"
    local dashboard_url=$(terraform output -raw monitoring_dashboard_url 2>/dev/null || echo "Not available")
    print_status "   $dashboard_url"
    echo ""
    print_status "🔒 Security:"
    print_status "   - Cloud Armor protection is enabled"
    print_status "   - All data is encrypted at rest and in transit"
    print_status "   - Network access is restricted to necessary ports"
    echo ""
    print_warning "📝 Next Steps:"
    print_warning "   1. Configure DNS if using custom domains"
    print_warning "   2. Complete Nexus IQ Server initial setup via web interface"
    print_warning "   3. Review and customize monitoring alerts"
    print_warning "   4. Set up backup and disaster recovery procedures"
    echo ""
    print_status "📁 Log file: $LOG_FILE"
}

# Function to cleanup on failure
cleanup_on_failure() {
    print_error "Deployment failed. Cleaning up..."
    
    if [[ "$FORCE_DESTROY" == "true" ]]; then
        print_warning "Force destroy enabled. Running terraform destroy..."
        cd "$TERRAFORM_DIR"
        terraform destroy -auto-approve -var-file="$TFVARS_FILE" >> "$LOG_FILE" 2>&1 || true
    else
        print_warning "Run './destroy.sh' to clean up resources if needed"
    fi
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Nexus IQ Server infrastructure on Google Cloud Platform

OPTIONS:
    -h, --help              Show this help message
    -p, --project PROJECT   GCP Project ID (overrides terraform.tfvars)
    -s, --state-bucket BUCKET  GCS bucket for Terraform state
    -d, --dry-run              Run terraform plan only (no deployment)
    -f, --force-destroy        Auto-destroy on failure (dangerous!)
    --skip-validation          Skip prerequisites validation
    -v, --verbose              Enable verbose logging

EXAMPLES:
    # Create terraform.tfvars template
    $0
    
    # Deploy with default configuration
    $0 --project my-gcp-project
    
    
    # Dry run (plan only)
    $0 --project my-gcp-project --dry-run
    
    # Deploy with remote state
    $0 --project my-gcp-project --state-bucket my-terraform-state-bucket

NOTES:
    - First run creates terraform.tfvars template
    - Requires gcloud CLI and Terraform >= 1.0
    - Logs are written to deploy.log
    - Run './destroy.sh' to clean up resources
EOF
}

# Main function
main() {
    # Initialize log file
    echo "=== Nexus IQ Server GCP Deployment - $(date) ===" > "$LOG_FILE"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -p|--project)
                GCP_PROJECT_ID="$2"
                shift 2
                ;;
            -s|--state-bucket)
                STATE_BUCKET="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force-destroy)
                FORCE_DESTROY=true
                shift
                ;;
            --skip-validation)
                SKIP_VALIDATION=true
                shift
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Create tfvars template if it doesn't exist
    create_tfvars_template
    
    # Validate tfvars
    if [[ "$SKIP_VALIDATION" != "true" ]]; then
        validate_tfvars
    fi
    
    # Get project ID from tfvars if not provided via CLI
    if [[ -z "${GCP_PROJECT_ID:-}" ]]; then
        GCP_PROJECT_ID=$(grep "^gcp_project_id[[:space:]]*=" "$TFVARS_FILE" | cut -d'"' -f2)
    fi
    
    
    # Check prerequisites
    if [[ "$SKIP_VALIDATION" != "true" ]]; then
        check_prerequisites
        validate_gcp_project "$GCP_PROJECT_ID"
    fi
    
    # Setup error handling
    trap cleanup_on_failure ERR
    
    # Setup Terraform backend
    setup_terraform_backend "$GCP_PROJECT_ID"
    
    # Run deployment
    run_terraform_plan
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Confirm deployment
        echo ""
        print_warning "This will create infrastructure in GCP project: $GCP_PROJECT_ID"
        echo ""
        read -p "Do you want to proceed with deployment? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            print_status "Deployment cancelled by user"
            exit 0
        fi
        
        run_terraform_apply
        show_deployment_summary
    else
        print_status "Dry run completed. Review the plan above."
        print_status "Run without --dry-run to deploy the infrastructure."
    fi
    
    print_status "Script completed successfully"
}

# Run main function
main "$@"