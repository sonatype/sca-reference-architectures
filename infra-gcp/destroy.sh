#!/bin/bash

# Nexus IQ Server GCP Infrastructure Destruction Script
# This script safely destroys the complete infrastructure for Nexus IQ Server on GCP

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
LOG_FILE="${SCRIPT_DIR}/destruction.log"

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
    echo -e "${RED}=================================================${NC}"
    echo -e "${RED}  Nexus IQ Server GCP Infrastructure Destruction${NC}"
    echo -e "${RED}=================================================${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  WARNING: This will permanently delete all resources!${NC}"
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
    
    # Check if terraform state exists
    if [[ ! -f "${SCRIPT_DIR}/terraform.tfstate" ]]; then
        warning "No terraform.tfstate found. Nothing to destroy."
        exit 0
    fi
    
    success "Prerequisites check passed"
}

show_resources_to_destroy() {
    log "Analyzing resources to be destroyed..."
    
    cd "$SCRIPT_DIR"
    
    # Get current resources from state
    CLOUD_RUN_SERVICE=$(terraform output -raw cloud_run_service_name 2>/dev/null || echo "Unknown")
    DATABASE_INSTANCE=$(terraform output -raw database_instance_name 2>/dev/null || echo "Unknown")
    FILESTORE_INSTANCE=$(terraform output -raw filestore_instance_name 2>/dev/null || echo "Unknown")
    BACKUP_BUCKET=$(terraform output -raw backup_bucket_name 2>/dev/null || echo "Unknown")
    LOAD_BALANCER_IP=$(terraform output -raw load_balancer_ip 2>/dev/null || echo "Unknown")
    
    echo ""
    echo -e "${RED}Resources that will be PERMANENTLY DELETED:${NC}"
    echo ""
    echo -e "${YELLOW}Compute Resources:${NC}"
    echo -e "  • Cloud Run Service: ${RED}$CLOUD_RUN_SERVICE${NC}"
    echo -e "  • Load Balancer IP: ${RED}$LOAD_BALANCER_IP${NC}"
    echo ""
    echo -e "${YELLOW}Data Storage (⚠️  DATA WILL BE LOST):${NC}"
    echo -e "  • Cloud SQL Database: ${RED}$DATABASE_INSTANCE${NC}"
    echo -e "  • Cloud Filestore: ${RED}$FILESTORE_INSTANCE${NC}"
    echo -e "  • Backup Storage Bucket: ${RED}$BACKUP_BUCKET${NC}"
    echo ""
    echo -e "${YELLOW}Network Resources:${NC}"
    echo -e "  • VPC Network and Subnets"
    echo -e "  • Firewall Rules"
    echo -e "  • VPC Connector"
    echo ""
    echo -e "${YELLOW}Security Resources:${NC}"
    echo -e "  • Service Accounts and IAM Bindings"
    echo -e "  • Secret Manager Secrets"
    echo -e "  • Cloud Armor Policies (if enabled)"
    echo ""
    echo -e "${YELLOW}Monitoring Resources:${NC}"
    echo -e "  • Monitoring Dashboards"
    echo -e "  • Alert Policies"
    echo -e "  • Uptime Checks"
    echo ""
}

backup_important_data() {
    log "Offering to backup important data..."
    
    echo -e "${YELLOW}Before destroying resources, would you like to create backups?${NC}"
    echo ""
    echo -e "${BLUE}Available backup options:${NC}"
    echo "1. Create database backup (recommended)"
    echo "2. Export monitoring dashboards"
    echo "3. Download application logs"
    echo "4. Skip backups"
    echo ""
    
    read -p "Enter your choice (1-4): " -n 1 -r
    echo ""
    
    case $REPLY in
        1)
            create_database_backup
            ;;
        2)
            export_monitoring_config
            ;;
        3)
            download_logs
            ;;
        4)
            log "Skipping backups as requested"
            ;;
        *)
            warning "Invalid choice. Skipping backups."
            ;;
    esac
}

create_database_backup() {
    log "Creating database backup..."
    
    cd "$SCRIPT_DIR"
    DATABASE_INSTANCE=$(terraform output -raw database_instance_name 2>/dev/null)
    
    if [[ -n "$DATABASE_INSTANCE" && "$DATABASE_INSTANCE" != "Unknown" ]]; then
        BACKUP_NAME="nexus-iq-backup-$(date +%Y%m%d-%H%M%S)"
        
        log "Creating backup: $BACKUP_NAME"
        gcloud sql backups create --instance="$DATABASE_INSTANCE" --description="Pre-destruction backup created by destroy script"
        
        success "Database backup created: $BACKUP_NAME"
    else
        warning "Could not determine database instance name for backup"
    fi
}

export_monitoring_config() {
    log "Exporting monitoring configuration..."
    
    BACKUP_DIR="${SCRIPT_DIR}/monitoring-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # Export dashboard config
    cd "$SCRIPT_DIR"
    terraform output -json > "${BACKUP_DIR}/terraform-outputs.json"
    
    success "Monitoring configuration exported to: $BACKUP_DIR"
}

download_logs() {
    log "Downloading recent application logs..."
    
    cd "$SCRIPT_DIR"
    CLOUD_RUN_SERVICE=$(terraform output -raw cloud_run_service_name 2>/dev/null)
    REGION=$(terraform output -raw region 2>/dev/null)
    
    if [[ -n "$CLOUD_RUN_SERVICE" && "$CLOUD_RUN_SERVICE" != "Unknown" ]]; then
        LOG_FILE_NAME="nexus-iq-logs-$(date +%Y%m%d-%H%M%S).txt"
        
        log "Downloading logs to: $LOG_FILE_NAME"
        gcloud run services logs read "$CLOUD_RUN_SERVICE" --region="$REGION" --limit=1000 > "$LOG_FILE_NAME"
        
        success "Logs downloaded to: $LOG_FILE_NAME"
    else
        warning "Could not determine Cloud Run service name for log download"
    fi
}

disable_deletion_protection() {
    log "Checking and disabling deletion protection..."
    
    cd "$SCRIPT_DIR"
    
    # Check if database has deletion protection enabled
    DATABASE_INSTANCE=$(terraform output -raw database_instance_name 2>/dev/null)
    
    if [[ -n "$DATABASE_INSTANCE" && "$DATABASE_INSTANCE" != "Unknown" ]]; then
        log "Checking deletion protection for database: $DATABASE_INSTANCE"
        
        # Check current deletion protection status
        PROTECTION_STATUS=$(gcloud sql instances describe "$DATABASE_INSTANCE" --format="value(settings.deletionProtectionEnabled)" 2>/dev/null || echo "false")
        
        if [[ "$PROTECTION_STATUS" == "True" ]]; then
            warning "Database has deletion protection enabled. Disabling..."
            gcloud sql instances patch "$DATABASE_INSTANCE" --no-deletion-protection
            success "Deletion protection disabled for database"
            
            # Wait a moment for the change to propagate
            sleep 5
        else
            log "Database deletion protection already disabled"
        fi
    fi
}

cleanup_secrets() {
    log "Cleaning up Secret Manager secrets..."
    
    cd "$SCRIPT_DIR"
    
    # Get secret names from terraform output if available
    DB_CRED_SECRET=$(terraform output -raw db_credentials_secret_name 2>/dev/null || echo "")
    DB_PASS_SECRET=$(terraform output -raw db_password_secret_name 2>/dev/null || echo "")
    
    # Clean up secrets with force delete to avoid recovery period
    for secret in "$DB_CRED_SECRET" "$DB_PASS_SECRET"; do
        if [[ -n "$secret" && "$secret" != "Unknown" ]]; then
            log "Force deleting secret: $secret"
            gcloud secrets delete "$secret" --quiet || warning "Could not delete secret: $secret"
        fi
    done
}

terraform_destroy() {
    log "Running Terraform destroy..."
    
    cd "$SCRIPT_DIR"
    
    # Use auto-approve flag for non-interactive destruction
    terraform destroy -var-file="$TFVARS_FILE" -auto-approve
    
    success "Terraform destroy completed"
}

final_cleanup() {
    log "Performing final cleanup..."
    
    # Remove terraform files
    cd "$SCRIPT_DIR"
    
    if [[ -f "terraform.tfstate.backup" ]]; then
        log "Removing terraform state backup"
        rm -f terraform.tfstate.backup
    fi
    
    if [[ -f "tfplan" ]]; then
        log "Removing terraform plan file"
        rm -f tfplan
    fi
    
    if [[ -f "outputs.json" ]]; then
        log "Removing outputs file"
        rm -f outputs.json
    fi
    
    success "Final cleanup completed"
}

confirm_destruction() {
    echo ""
    echo -e "${RED}⚠️  FINAL CONFIRMATION REQUIRED ⚠️${NC}"
    echo ""
    echo -e "${RED}This action will PERMANENTLY DELETE all resources and data.${NC}"
    echo -e "${RED}This action CANNOT BE UNDONE.${NC}"
    echo ""
    echo -e "Type ${YELLOW}'DESTROY'${NC} to confirm destruction: "
    read -r confirmation
    
    if [[ "$confirmation" != "DESTROY" ]]; then
        log "Destruction cancelled - confirmation not provided"
        echo -e "${GREEN}Destruction cancelled.${NC}"
        exit 0
    fi
    
    echo ""
    echo -e "${YELLOW}Final confirmation: Are you absolutely sure? (yes/no): ${NC}"
    read -r final_confirmation
    
    if [[ "$final_confirmation" != "yes" ]]; then
        log "Destruction cancelled - final confirmation not provided"
        echo -e "${GREEN}Destruction cancelled.${NC}"
        exit 0
    fi
    
    log "User confirmed destruction"
}

cleanup_on_error() {
    error "Destruction failed. Check $LOG_FILE for details."
}

main() {
    # Set up error handling
    trap cleanup_on_error ERR
    
    print_banner
    
    # Create log file
    touch "$LOG_FILE"
    log "Starting destruction at $(date)"
    
    # Run destruction steps
    check_prerequisites
    show_resources_to_destroy
    backup_important_data
    confirm_destruction
    
    log "Beginning infrastructure destruction..."
    
    disable_deletion_protection
    cleanup_secrets
    terraform_destroy
    final_cleanup
    
    echo ""
    echo -e "${GREEN}=================================================${NC}"
    echo -e "${GREEN}  Infrastructure Destruction Completed${NC}"
    echo -e "${GREEN}=================================================${NC}"
    echo ""
    echo -e "${GREEN}All resources have been successfully destroyed.${NC}"
    echo ""
    echo -e "${BLUE}Summary:${NC}"
    echo -e "  • All GCP resources deleted"
    echo -e "  • Terraform state cleaned up"
    echo -e "  • Secrets permanently removed"
    echo ""
    echo -e "${YELLOW}Note: Some resources may take a few minutes to fully disappear from the GCP console.${NC}"
    echo ""
    
    log "Destruction completed successfully at $(date)"
}

# Run main function
main "$@"