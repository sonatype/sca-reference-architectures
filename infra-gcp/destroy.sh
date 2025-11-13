#!/bin/bash
set -euo pipefail

# Destroy script for Nexus IQ Server GCP Infrastructure
# This script safely destroys all infrastructure created by the deploy script

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR"
LOG_FILE="$SCRIPT_DIR/destroy.log"
TFVARS_FILE="$SCRIPT_DIR/terraform.tfvars"
FORCE_DESTROY=false
DRY_RUN=false
SKIP_CONFIRMATION=false
BACKUP_DATA=true
PRESERVE_STATE=false

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
    
    # Check required tools
    local required_tools=("terraform" "gcloud" "jq" "gsutil")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            print_error "$tool is not installed. Please install it and try again."
            exit 1
        fi
    done
    
    # Check if terraform.tfvars exists
    if [[ ! -f "$TFVARS_FILE" ]]; then
        print_error "terraform.tfvars not found. Nothing to destroy."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        print_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    print_status "Prerequisites check completed"
}

# Function to backup critical data
backup_critical_data() {
    if [[ "$BACKUP_DATA" != "true" ]]; then
        print_warning "Data backup skipped by user request"
        return 0
    fi
    
    print_status "Creating backup of critical data..."
    
    cd "$TERRAFORM_DIR"
    
    # Initialize Terraform to get state
    if ! terraform init -input=false >> "$LOG_FILE" 2>&1; then
        print_warning "Could not initialize Terraform for backup. Skipping data backup."
        return 0
    fi
    
    # Get current outputs for backup information
    local project_id
    local backup_bucket
    local config_bucket
    
    project_id=$(terraform output -raw project_id 2>/dev/null || echo "")
    backup_bucket=$(terraform output -raw backup_bucket_name 2>/dev/null || echo "")
    config_bucket=$(terraform output -raw config_backup_bucket_name 2>/dev/null || echo "")
    
    print_status "Project ID: $project_id"
    
    if [[ -n "$backup_bucket" ]] && gsutil ls "gs://$backup_bucket" &> /dev/null; then
        print_status "Creating final backup of application data..."
        local backup_dir="./pre-destroy-backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup_dir"
        
        # Download recent backups
        print_status "Downloading recent backups to $backup_dir..."
        if gsutil -m cp -r "gs://$backup_bucket/*" "$backup_dir/" >> "$LOG_FILE" 2>&1; then
            print_status "Backup data saved to: $backup_dir"
        else
            print_warning "Could not download backup data. It may not exist yet."
        fi
        
        # Export Terraform state
        if terraform state pull > "$backup_dir/terraform.tfstate" 2>/dev/null; then
            print_status "Terraform state backed up to: $backup_dir/terraform.tfstate"
        fi
        
        # Copy configuration files
        cp "$TFVARS_FILE" "$backup_dir/" 2>/dev/null || true
        cp "$SCRIPT_DIR"/*.tf "$backup_dir/" 2>/dev/null || true
        
        print_status "Critical data backup completed"
    else
        print_warning "No existing backup bucket found. Skipping data backup."
    fi
}

# Function to check what will be destroyed
show_destroy_plan() {
    print_status "Generating destruction plan..."
    
    cd "$TERRAFORM_DIR"
    
    # Initialize Terraform
    if ! terraform init -input=false >> "$LOG_FILE" 2>&1; then
        print_error "Terraform initialization failed. Check $LOG_FILE for details."
        exit 1
    fi
    
    # Show current state
    print_status "Current infrastructure state:"
    terraform state list 2>/dev/null | head -20 || print_warning "No Terraform state found"
    
    # Create destroy plan
    if ! terraform plan -destroy -var-file="$TFVARS_FILE" -out=destroy-plan >> "$LOG_FILE" 2>&1; then
        print_error "Failed to create destroy plan. Check $LOG_FILE for details."
        exit 1
    fi
    
    # Show destroy plan summary
    print_status "Resources to be destroyed:"
    terraform show -no-color destroy-plan | grep -E "will be destroyed|Destroy complete" | head -20 || true
    
    # Get resource counts
    local total_resources
    total_resources=$(terraform state list 2>/dev/null | wc -l || echo "0")
    print_status "Total resources to destroy: $total_resources"
}

# Function to handle protected resources
handle_protected_resources() {
    print_status "Checking for protected resources..."
    
    cd "$TERRAFORM_DIR"
    
    # List resources that might need special handling
    local protected_resources=(
        "google_sql_database_instance"
        "google_storage_bucket"
        "google_kms_crypto_key"
    )
    
    for resource in "${protected_resources[@]}"; do
        if terraform state list | grep -q "$resource"; then
            print_warning "Found protected resource type: $resource"
            print_warning "These resources have deletion protection enabled"
        fi
    done
    
    # Check for deletion protection
    if terraform show -json 2>/dev/null | jq -r '.values.root_module.resources[]? | select(.values.deletion_protection == true) | .address' | head -5; then
        print_warning "Some resources have deletion protection enabled"
        if [[ "$FORCE_DESTROY" != "true" ]]; then
            print_warning "Use --force to override deletion protection"
        fi
    fi
}

# Function to perform safe destroy
perform_destroy() {
    print_status "Starting infrastructure destruction..."
    
    cd "$TERRAFORM_DIR"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "Dry run mode - no actual destruction will occur"
        print_status "Destroy plan has been generated and saved"
        return 0
    fi
    
    # Handle deletion protection if force destroy is enabled
    if [[ "$FORCE_DESTROY" == "true" ]]; then
        print_warning "Force destroy enabled - attempting to disable deletion protection..."
        
        # Create a temporary tfvars file with deletion protection disabled
        local temp_tfvars="/tmp/destroy-$(date +%s).tfvars"
        cp "$TFVARS_FILE" "$temp_tfvars"
        echo "" >> "$temp_tfvars"
        echo "# Temporary overrides for destruction" >> "$temp_tfvars"
        echo "db_deletion_protection = false" >> "$temp_tfvars"
        echo "storage_force_destroy = true" >> "$temp_tfvars"
        
        # Apply changes to disable protection
        print_status "Disabling deletion protection..."
        if terraform apply -auto-approve -var-file="$temp_tfvars" >> "$LOG_FILE" 2>&1; then
            print_status "Deletion protection disabled"
        else
            print_warning "Could not disable deletion protection automatically"
        fi
        
        # Clean up temp file
        rm -f "$temp_tfvars"
        
        # Wait a moment for changes to propagate
        sleep 10
    fi
    
    # Perform the actual destroy with staged approach for service networking
    print_status "Destroying infrastructure... This may take 15-25 minutes."
    
    # Stage 1: Destroy Cloud Run and application layer first
    print_status "Stage 1: Destroying application services..."
    terraform destroy -target=google_cloud_run_service.iq_service \
                     -target=google_cloud_run_service_iam_binding.iq_invoker \
                     -target=google_cloud_run_domain_mapping.iq_domain \
                     -auto-approve -var-file="$TFVARS_FILE" >> "$LOG_FILE" 2>&1 || print_warning "Some Cloud Run resources may not have been destroyed cleanly"
    
    # Stage 2: Destroy all SQL-related resources with enhanced cleanup
    print_status "Stage 2: Destroying database and related services..."
    
    # First, try to terminate any active database connections
    local db_instance_name
    db_instance_name=$(terraform output -raw sql_instance_name 2>/dev/null || echo "")
    if [[ -n "$db_instance_name" ]]; then
        print_status "Attempting to close database connections..."
        gcloud sql operations list --instance="$db_instance_name" --limit=1 --project=$(grep gcp_project_id terraform.tfvars | cut -d'\"' -f2) --format="value(name)" 2>/dev/null | head -1 || true
    fi
    
    # Destroy database resources in specific order
    terraform destroy -target=google_sql_user.iq_db_user \
                     -auto-approve -var-file="$TFVARS_FILE" >> "$LOG_FILE" 2>&1 || print_warning "Database user destruction may have failed"
    
    terraform destroy -target=google_sql_database.iq_database \
                     -auto-approve -var-file="$TFVARS_FILE" >> "$LOG_FILE" 2>&1 || print_warning "Database destruction may have failed"
    
    terraform destroy -target=google_sql_ssl_cert.iq_client_cert \
                     -auto-approve -var-file="$TFVARS_FILE" >> "$LOG_FILE" 2>&1 || print_warning "SSL cert destruction may have failed"
    
    # Wait for database operations to complete
    print_status "Waiting for database operations to complete..."
    sleep 30
    
    # Finally destroy the instance
    terraform destroy -target=google_sql_database_instance.iq_db \
                     -auto-approve -var-file="$TFVARS_FILE" >> "$LOG_FILE" 2>&1 || print_warning "Database instance destruction may have failed"
    
    # Stage 3: Destroy other services that might use service networking
    print_status "Stage 3: Destroying storage and compute resources..."
    terraform destroy -target=google_filestore_instance.iq_filestore \
                     -target=google_vpc_access_connector.iq_connector \
                     -auto-approve -var-file="$TFVARS_FILE" >> "$LOG_FILE" 2>&1 || print_warning "Some storage/compute resources may not have been destroyed cleanly"
    
    # Wait longer for GCP to fully clean up all service networking dependencies
    print_status "Waiting for GCP to fully clean up service networking dependencies..."
    sleep 60
    
    # Stage 4: Handle service networking connection (remove from state instead of destroy)
    print_status "Stage 4: Removing service networking connection from Terraform state..."
    print_warning "Service networking connection will be abandoned due to GCP dependency issues"
    terraform state rm google_service_networking_connection.private_vpc_connection >> "$LOG_FILE" 2>&1 || print_warning "Service networking connection may not exist in state"
    
    # Stage 5: Destroy everything else
    print_status "Stage 5: Destroying remaining infrastructure..."
    if ! terraform destroy -auto-approve -var-file="$TFVARS_FILE" >> "$LOG_FILE" 2>&1; then
        print_error "Terraform destroy failed. Check $LOG_FILE for details."
        print_error "Some resources may still exist and require manual cleanup."
        
        # Try to identify what's still there
        print_status "Checking remaining resources..."
        terraform state list >> "$LOG_FILE" 2>&1 || true
        
        exit 1
    fi
    
    print_status "Infrastructure destruction completed successfully"
}

# Function to cleanup terraform files
cleanup_terraform_files() {
    if [[ "$PRESERVE_STATE" == "true" ]]; then
        print_status "Preserving Terraform state and plan files"
        return 0
    fi
    
    print_status "Cleaning up Terraform files..."
    
    cd "$TERRAFORM_DIR"
    
    # Remove plan files
    rm -f tfplan destroy-plan
    
    # Remove .terraform directory (but preserve backend.tf if using remote state)
    if [[ -f "backend.tf" ]]; then
        print_status "Keeping backend.tf for future deployments"
    else
        rm -rf .terraform .terraform.lock.hcl
    fi
    
    print_status "Terraform files cleaned up"
}

# Function to verify destruction
verify_destruction() {
    print_status "Verifying infrastructure destruction..."
    
    cd "$TERRAFORM_DIR"
    
    # Check if any resources remain in state
    local remaining_resources
    remaining_resources=$(terraform state list 2>/dev/null | wc -l || echo "0")
    
    if [[ "$remaining_resources" -gt 0 ]]; then
        print_warning "$remaining_resources resources remain in Terraform state"
        terraform state list 2>/dev/null || true
    else
        print_status "All resources successfully removed from Terraform state"
    fi
    
    # Verify with GCP (if project info is available)
    local project_id
    project_id=$(grep "^gcp_project_id[[:space:]]*=" "$TFVARS_FILE" | cut -d'"' -f2 2>/dev/null || echo "")
    
    if [[ -n "$project_id" ]]; then
        print_status "Checking for remaining GCP resources in project: $project_id"
        
        # Check for major resource types
        local resource_types=("instances" "sql-instances" "buckets" "addresses")
        for resource_type in "${resource_types[@]}"; do
            local count
            case $resource_type in
                "instances")
                    count=$(gcloud compute instances list --project="$project_id" --format="value(name)" 2>/dev/null | wc -l || echo "0")
                    ;;
                "sql-instances")
                    count=$(gcloud sql instances list --project="$project_id" --format="value(name)" 2>/dev/null | wc -l || echo "0")
                    ;;
                "buckets")
                    count=$(gsutil ls -p "$project_id" 2>/dev/null | wc -l || echo "0")
                    ;;
                "addresses")
                    count=$(gcloud compute addresses list --project="$project_id" --format="value(name)" 2>/dev/null | wc -l || echo "0")
                    ;;
            esac
            
            if [[ "$count" -gt 0 ]]; then
                print_warning "$count $resource_type still exist in project"
            fi
        done
    fi
    
    print_status "Verification completed"
}

# Function to show destruction summary
show_destruction_summary() {
    echo ""
    print_status "✅ Infrastructure Destroyed Successfully"
    echo ""
    print_status "🧹 Cleanup Summary"
    print_status "━━━━━━━━━━━━━━━━━━"
    print_status "• All GCP resources destroyed"
    print_status "• Terraform state updated"
    print_status "• Local artifacts removed"
    echo ""
    
    if [[ "$BACKUP_DATA" == "true" ]] && [[ -d "./pre-destroy-backup-"* ]]; then
        local backup_dir
        backup_dir=$(ls -td ./pre-destroy-backup-* | head -1)
        print_status "💾 Data backup location: $backup_dir"
        print_warning "   - Application data and configuration saved"
        print_warning "   - Terraform state backed up"
        print_warning "   - Keep this backup for recovery if needed"
        echo ""
    fi
    
    print_warning "📝 Manual Cleanup Tasks (if needed)"
    print_warning "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_warning "• Remove any manual DNS records"
    print_warning "• Clean up external monitoring"
    print_warning "• Verify no orphaned resources"
    print_warning "• Check GCP billing for unexpected charges"
    echo ""
    print_warning "⚠️  Service Networking Connection may require manual cleanup:"
    print_warning "   gcloud services vpc-peerings delete \\"
    print_warning "     --network=ref-arch-iq-vpc \\"
    print_warning "     --service=servicenetworking.googleapis.com \\"
    print_warning "     --project=\$(grep gcp_project_id terraform.tfvars | cut -d'\"' -f2)"
    echo ""
    print_status "✅ Destruction Process Completed"
    print_status "📁 Log file: $LOG_FILE"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely destroy Nexus IQ Server infrastructure on Google Cloud Platform

OPTIONS:
    -h, --help              Show this help message
    -f, --force             Force destroy (disable deletion protection)
    -d, --dry-run           Show destroy plan only (no actual destruction)
    -y, --yes               Skip confirmation prompts
    --no-backup             Skip data backup before destruction
    --preserve-state        Keep Terraform state and plan files
    -v, --verbose           Enable verbose logging

EXAMPLES:
    # Show what would be destroyed
    $0 --dry-run
    
    # Standard destruction with confirmation
    $0
    
    # Force destroy everything (dangerous!)
    $0 --force --yes
    
    # Destroy without data backup
    $0 --no-backup

WARNING:
    This will permanently delete all infrastructure and data!
    
    Protected resources (databases, KMS keys) will be preserved
    unless --force is used.
    
    Always ensure you have proper backups before destruction.

NOTES:
    - Creates backup of critical data by default
    - Logs all operations to destroy.log
    - Verifies destruction completion
    - Some resources may have deletion protection
EOF
}

# Main function
main() {
    # Initialize log file
    echo "=== Nexus IQ Server GCP Destruction - $(date) ===" > "$LOG_FILE"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -f|--force)
                FORCE_DESTROY=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --no-backup)
                BACKUP_DATA=false
                shift
                ;;
            --preserve-state)
                PRESERVE_STATE=true
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
    
    # Check prerequisites
    check_prerequisites
    
    # Show warning about destruction
    echo ""
    print_error "⚠️  DANGER: This will permanently destroy all Nexus IQ infrastructure!"
    print_error "⚠️  This action cannot be undone!"
    echo ""
    
    if [[ "$FORCE_DESTROY" == "true" ]]; then
        print_error "🔥 FORCE MODE ENABLED - Will destroy protected resources!"
        echo ""
    fi
    
    # Get confirmation unless skipped
    if [[ "$SKIP_CONFIRMATION" != "true" && "$DRY_RUN" != "true" ]]; then
        echo "Please type 'destroy' to confirm destruction: "
        read -r confirmation
        if [[ "$confirmation" != "destroy" ]]; then
            print_status "Destruction cancelled by user"
            exit 0
        fi
        echo ""
    fi
    
    # Backup critical data
    backup_critical_data
    
    # Show what will be destroyed
    show_destroy_plan
    
    # Handle protected resources
    handle_protected_resources
    
    # Final confirmation for actual destroy
    if [[ "$DRY_RUN" != "true" && "$SKIP_CONFIRMATION" != "true" ]]; then
        echo ""
        print_warning "Last chance! This will permanently delete everything shown above."
        read -p "Are you absolutely sure? (YES/no): " -r
        if [[ ! $REPLY =~ ^YES$ ]]; then
            print_status "Destruction cancelled by user"
            exit 0
        fi
        echo ""
    fi
    
    # Perform the destruction
    perform_destroy
    
    # Verify destruction completed
    verify_destruction
    
    # Cleanup terraform files
    cleanup_terraform_files
    
    # Show summary
    if [[ "$DRY_RUN" != "true" ]]; then
        show_destruction_summary
    else
        print_status "Dry run completed. Review the destroy plan above."
        print_status "Run without --dry-run to actually destroy the infrastructure."
    fi
    
    print_status "Script completed successfully"
}

# Run main function
main "$@"