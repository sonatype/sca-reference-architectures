#!/bin/bash

# Nexus IQ Server GCP Infrastructure Apply Script
# This script applies Terraform changes with proper authentication

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
LOG_FILE="${SCRIPT_DIR}/apply.log"

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
    echo -e "${BLUE}  Nexus IQ Server GCP Infrastructure Apply${NC}"
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

check_plan_file() {
    log "Checking for existing plan file..."
    
    cd "$SCRIPT_DIR"
    
    if [[ ! -f "tfplan" ]]; then
        warning "No plan file found. Running plan first..."
        ./gcp-plan.sh
        
        if [[ ! -f "tfplan" ]]; then
            error "Plan file could not be created. Please check the plan output."
        fi
    else
        # Check if plan file is recent (less than 1 hour old)
        if [[ $(find tfplan -mmin +60 2>/dev/null) ]]; then
            warning "Plan file is older than 1 hour. Consider running './gcp-plan.sh' for fresh plan."
            echo ""
            read -p "Continue with existing plan? (y/N): " -n 1 -r
            echo ""
            
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log "User chose to update plan"
                ./gcp-plan.sh
            fi
        fi
    fi
    
    success "Plan file verified"
}

show_plan_summary() {
    log "Showing plan summary..."
    
    cd "$SCRIPT_DIR"
    
    echo ""
    echo -e "${BLUE}Changes to be applied:${NC}"
    echo ""
    
    # Show terraform plan output in a more readable format
    terraform show tfplan | head -50
    
    echo ""
    if [[ $(terraform show tfplan | wc -l) -gt 50 ]]; then
        echo -e "${YELLOW}... (output truncated, full plan saved to tfplan)${NC}"
        echo ""
    fi
}

confirm_apply() {
    echo ""
    echo -e "${YELLOW}Ready to apply infrastructure changes.${NC}"
    echo -e "${YELLOW}This will create/modify resources in GCP.${NC}"
    echo ""
    
    read -p "Continue with apply? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Apply cancelled by user"
        exit 0
    fi
    
    log "User confirmed apply"
}

terraform_apply() {
    log "Applying Terraform changes..."
    
    cd "$SCRIPT_DIR"
    
    # Apply the plan with detailed output
    terraform apply tfplan
    
    success "Terraform apply completed successfully"
}

show_outputs() {
    log "Retrieving deployment information..."
    
    cd "$SCRIPT_DIR"
    
    # Save outputs to file
    terraform output -json > outputs.json
    
    # Get key outputs
    APPLICATION_URL=$(terraform output -raw application_url 2>/dev/null || echo "Not available")
    CLOUD_RUN_SERVICE=$(terraform output -raw cloud_run_service_name 2>/dev/null || echo "Not available")
    DATABASE_INSTANCE=$(terraform output -raw database_instance_name 2>/dev/null || echo "Not available")
    MONITORING_URL=$(terraform output -raw monitoring_dashboard_url 2>/dev/null || echo "Not available")
    REGION=$(terraform output -raw region 2>/dev/null || echo "Not available")
    
    echo ""
    echo -e "${GREEN}=================================================${NC}"
    echo -e "${GREEN}  Apply Completed Successfully!${NC}"
    echo -e "${GREEN}=================================================${NC}"
    echo ""
    echo -e "${BLUE}Application Access:${NC}"
    echo -e "  URL: ${GREEN}$APPLICATION_URL${NC}"
    echo -e "  Default credentials: ${YELLOW}admin / admin123${NC}"
    echo ""
    echo -e "${BLUE}Key Resources:${NC}"
    echo -e "  Cloud Run Service: ${GREEN}$CLOUD_RUN_SERVICE${NC}"
    echo -e "  Database Instance: ${GREEN}$DATABASE_INSTANCE${NC}"
    echo -e "  Region: ${GREEN}$REGION${NC}"
    echo ""
    echo -e "${BLUE}Monitoring & Management:${NC}"
    echo -e "  Dashboard: ${GREEN}$MONITORING_URL${NC}"
    echo -e "  View logs: ${BLUE}gcloud run services logs tail $CLOUD_RUN_SERVICE --region=$REGION${NC}"
    echo -e "  Service status: ${BLUE}gcloud run services describe $CLOUD_RUN_SERVICE --region=$REGION${NC}"
    echo ""
    echo -e "${BLUE}All outputs: ${BLUE}terraform output${NC}"
    echo ""
    echo -e "${YELLOW}Note: It may take 5-10 minutes for the service to be fully ready.${NC}"
    echo ""
}

verify_deployment() {
    log "Verifying deployment..."
    
    cd "$SCRIPT_DIR"
    
    CLOUD_RUN_SERVICE=$(terraform output -raw cloud_run_service_name 2>/dev/null)
    REGION=$(terraform output -raw region 2>/dev/null)
    
    if [[ -n "$CLOUD_RUN_SERVICE" && "$CLOUD_RUN_SERVICE" != "Not available" ]]; then
        log "Checking Cloud Run service status..."
        
        # Check service status
        SERVICE_STATUS=$(gcloud run services describe "$CLOUD_RUN_SERVICE" --region="$REGION" --format="value(status.conditions[0].status)" 2>/dev/null || echo "Unknown")
        
        if [[ "$SERVICE_STATUS" == "True" ]]; then
            success "Cloud Run service is ready"
        else
            warning "Cloud Run service may still be starting up"
        fi
    fi
    
    # Check database status
    DATABASE_INSTANCE=$(terraform output -raw database_instance_name 2>/dev/null)
    
    if [[ -n "$DATABASE_INSTANCE" && "$DATABASE_INSTANCE" != "Not available" ]]; then
        log "Checking database status..."
        
        DB_STATUS=$(gcloud sql instances describe "$DATABASE_INSTANCE" --format="value(state)" 2>/dev/null || echo "Unknown")
        
        if [[ "$DB_STATUS" == "RUNNABLE" ]]; then
            success "Database is ready"
        else
            warning "Database may still be starting up"
        fi
    fi
}

cleanup_files() {
    log "Cleaning up temporary files..."
    
    cd "$SCRIPT_DIR"
    
    # Remove plan file after successful apply
    if [[ -f "tfplan" ]]; then
        rm -f tfplan
        log "Removed plan file"
    fi
}

cleanup_on_error() {
    error "Apply failed. Check $LOG_FILE for details."
    echo ""
    echo -e "${YELLOW}Troubleshooting tips:${NC}"
    echo -e "  • Check the error output above"
    echo -e "  • Verify your GCP permissions"
    echo -e "  • Run '${BLUE}./gcp-plan.sh${NC}' to check for issues"
    echo -e "  • Check quota limits in your GCP project"
    echo ""
}

main() {
    # Set up error handling
    trap cleanup_on_error ERR
    
    print_banner
    
    # Create log file
    touch "$LOG_FILE"
    log "Starting apply at $(date)"
    
    # Run apply steps
    check_prerequisites
    check_plan_file
    show_plan_summary
    confirm_apply
    terraform_apply
    show_outputs
    verify_deployment
    cleanup_files
    
    log "Apply completed successfully at $(date)"
}

# Run main function
main "$@"