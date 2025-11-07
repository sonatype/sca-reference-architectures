#!/bin/bash

# Nexus IQ Server GCP HA Infrastructure - Terraform Destroy Script
# This script safely destroys the GCP HA infrastructure

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR"
TFVARS_FILE="$SCRIPT_DIR/terraform.tfvars"
LOG_FILE="$SCRIPT_DIR/destroy.log"
DRY_RUN=false
PRESERVE_STATE=false

# Function to print colored output with logging
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

# Legacy function aliases for compatibility
log() {
    print_status "$*"
}

error() {
    print_error "$*"
}

warning() {
    print_warning "$*"
}

success() {
    print_status "$*"
}

# Global variables
AUTO_APPROVE=false
FORCE_DESTROY=false
BACKUP_DIR=""
SKIP_BACKUP=false

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely destroy Nexus IQ Server HA infrastructure on Google Cloud Platform

OPTIONS:
    -h, --help              Show this help message
    -f, --force             Force destroy (disable deletion protection)
    -d, --dry-run           Show destroy plan only (no actual destruction)
    -y, --yes               Skip confirmation prompts
    --no-backup             Skip data backup before destruction
    --preserve-state        Keep Terraform state and plan files
    -v, --verbose           Enable verbose logging

EXAMPLES:
    # Show what would be destroyed (recommended first step)
    $0 --dry-run
    
    # Standard destruction with confirmation
    $0
    
    # Force destroy everything (dangerous!)
    $0 --force --yes
    
    # Destroy without data backup
    $0 --no-backup

PREREQUISITES:
    • terraform (>= 1.0)
    • gcloud CLI with active authentication
    • jq and gsutil tools
    • Existing HA Terraform state

DESTRUCTION PHASES:
    1. Comprehensive backup of critical HA data
    2. Generate and validate destruction plan
    3. Staged HA resource destruction (20-35 minutes)
       - Scale down autoscaler and instance groups
       - Destroy load balancer and networking
       - Destroy database with connection cleanup
       - Destroy storage and persistent resources
       - Clean up remaining infrastructure
    4. Verification and cleanup
    5. Final summary and manual cleanup instructions

WARNING:
    This will permanently delete ALL HA infrastructure and data!
    
    HA Resources to be destroyed:
    • Managed instance groups (2-6+ instances)
    • Regional autoscaler and load balancers
    • Cloud SQL regional database with read replicas
    • Regional persistent disks and file storage
    • VPC networking and firewall rules
    • Monitoring, logging, and alerting
    • Service accounts and IAM bindings
    • All backup buckets and stored data

NOTES:
    - Creates comprehensive backup of critical data by default
    - Uses staged destruction to avoid GCP dependency issues
    - Logs all operations to destroy.log
    - Verifies destruction completion with GCP API calls
    - Some resources may require manual cleanup (service networking)
    - Protected resources (databases, KMS keys) preserved unless --force used
EOF
}

# Function to create backup directory
create_backup_dir() {
    if [ "$SKIP_BACKUP" = false ]; then
        BACKUP_DIR="pre-destroy-backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        log "Created backup directory: $BACKUP_DIR"
    fi
}

# Function to backup critical data
backup_critical_data() {
    if [[ "$SKIP_BACKUP" == "true" ]]; then
        print_warning "Data backup skipped by user request"
        return 0
    fi
    
    print_status "Creating comprehensive backup of critical HA data..."
    
    cd "$TERRAFORM_DIR"
    
    # Initialize Terraform to get state
    if ! terraform init -input=false >> "$LOG_FILE" 2>&1; then
        print_warning "Could not initialize Terraform for backup. Skipping data backup."
        return 0
    fi
    
    # Get current outputs for backup information
    local project_id backup_bucket config_bucket
    project_id=$(terraform output -raw project_id 2>/dev/null || echo "")
    backup_bucket=$(terraform output -raw backup_bucket_name 2>/dev/null || echo "")
    
    print_status "Project ID: $project_id"
    
    # Create comprehensive backup
    if [[ -n "$project_id" ]]; then
        print_status "Creating final backup of HA application data..."
        local backup_dir="./pre-destroy-backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup_dir"
        
        # Export current Terraform state
        if terraform state pull > "$backup_dir/terraform.tfstate" 2>/dev/null; then
            print_status "Terraform state backed up to: $backup_dir/terraform.tfstate"
        fi
        
        # Export state as JSON for easier reading
        if terraform show -json > "$backup_dir/terraform-state.json" 2>/dev/null; then
            print_status "Current state exported to: $backup_dir/terraform-state.json"
        fi
        
        # Copy configuration files
        cp "$TFVARS_FILE" "$backup_dir/" 2>/dev/null || true
        cp "$SCRIPT_DIR"/*.tf "$backup_dir/" 2>/dev/null || true
        
        # Backup any plan files
        if ls tfplan-ha-* 1> /dev/null 2>&1; then
            cp tfplan-ha-* "$BACKUP_DIR/" 2>/dev/null || true
        fi
        
        # Try to backup from any existing backup buckets
        if [[ -n "$backup_bucket" ]] && gsutil ls "gs://$backup_bucket" &> /dev/null; then
            print_status "Downloading recent backups from bucket..."
            if gsutil -m cp -r "gs://$backup_bucket/*" "$backup_dir/" >> "$LOG_FILE" 2>&1; then
                print_status "HA backup data saved to: $backup_dir"
            else
                print_warning "Could not download backup data. It may not exist yet."
            fi
        fi
        
        # Update backup directory reference
        BACKUP_DIR="$backup_dir"
        
        print_status "Critical HA data backup completed"
    else
        print_warning "Could not determine project information for backup"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check required tools
    local required_tools=("terraform" "gcloud" "jq" "gsutil")
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        print_error "Please install the missing tools and try again."
        exit 1
    fi
    
    # Check Terraform version
    local tf_version=$(terraform version -json | jq -r '.terraform_version')
    local tf_major=$(echo "$tf_version" | cut -d. -f1)
    local tf_minor=$(echo "$tf_version" | cut -d. -f2)
    
    if [[ $tf_major -lt 1 ]] || [[ $tf_major -eq 1 && $tf_minor -lt 0 ]]; then
        print_error "Terraform version 1.0 or higher is required. Found: $tf_version"
        exit 1
    fi
    
    # Check if terraform.tfvars exists
    if [[ ! -f "$TFVARS_FILE" ]]; then
        print_error "terraform.tfvars not found. Nothing to destroy or wrong directory."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        print_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    success "Prerequisites check passed (Terraform $tf_version)"
}

# Function to validate terraform state
validate_state() {
    log "Validating Terraform state..."
    
    if [ ! -f "terraform.tfstate" ]; then
        warning "No terraform.tfstate found"
        log "This might mean:"
        echo "  • Infrastructure was never deployed"
        echo "  • State file was moved or deleted"
        echo "  • You're in the wrong directory"
        echo
        read -p "Continue anyway? (yes/no): " -r response
        case "$response" in
            [yY][eE][sS]|[yY]) ;;
            *) exit 0 ;;
        esac
    fi
    
    # Check if there are any resources to destroy
    if terraform show -json 2>/dev/null | jq -e '.values.root_module.resources | length > 0' >/dev/null 2>&1; then
        success "Found resources to destroy"
    else
        warning "No resources found in state"
        log "Nothing to destroy"
        exit 0
    fi
}

# Function to check what will be destroyed and generate destroy plan
show_destroy_plan() {
    print_status "🔍 Generating HA destruction plan..."
    
    cd "$TERRAFORM_DIR"
    
    # Initialize Terraform
    if ! terraform init -input=false >> "$LOG_FILE" 2>&1; then
        print_error "Terraform initialization failed. Check $LOG_FILE for details."
        exit 1
    fi
    
    # Show current HA infrastructure state
    print_status "Current HA infrastructure state:"
    local total_resources
    total_resources=$(terraform state list 2>/dev/null | wc -l || echo "0")
    print_status "Total resources in state: $total_resources"
    
    if [[ $total_resources -gt 0 ]]; then
        print_status "HA Resource types found:"
        terraform state list 2>/dev/null | grep -o '^[^.]*' | sort | uniq -c | while read count type; do
            print_status "  $count x $type"
        done
    fi
    
    # Create destroy plan
    if [[ "$DRY_RUN" != "true" ]]; then
        if ! terraform plan -destroy -var-file="$TFVARS_FILE" -out=destroy-plan >> "$LOG_FILE" 2>&1; then
            print_error "Failed to create destroy plan. Check $LOG_FILE for details."
            exit 1
        fi
        
        # Show destroy plan summary
        print_status "📋 Resources to be destroyed:"
        if terraform show -no-color destroy-plan | grep -E "will be destroyed|Destroy complete" | head -15; then
            echo ""
        else
            print_warning "Could not parse destroy plan details"
        fi
    fi
}

# Function to handle protected HA resources
handle_protected_resources() {
    print_status "🔒 Checking for protected HA resources..."
    
    cd "$TERRAFORM_DIR"
    
    # List HA resources that might need special handling
    local protected_resources=(
        "google_sql_database_instance"
        "google_storage_bucket"
        "google_kms_crypto_key"
        "google_compute_region_instance_group_manager"
        "google_compute_region_autoscaler"
    )
    
    local found_protected=false
    for resource in "${protected_resources[@]}"; do
        if terraform state list | grep -q "$resource"; then
            print_warning "Found protected HA resource type: $resource"
            found_protected=true
        fi
    done
    
    if [[ "$found_protected" == "true" ]]; then
        print_warning "HA resources have deletion protection enabled"
        if [[ "$FORCE_DESTROY" != "true" ]]; then
            print_warning "Use --force to automatically disable protection"
        fi
    fi
    
    # Check for deletion protection in configuration
    if terraform show -json 2>/dev/null | jq -r '.values.root_module.resources[]? | select(.values.deletion_protection == true) | .address' | head -5; then
        print_warning "Some HA resources have deletion protection enabled"
        if [[ "$FORCE_DESTROY" != "true" ]]; then
            print_warning "Use --force to override deletion protection"
        fi
    fi
}

# Function to show enhanced destruction summary
show_destruction_summary() {
    print_status "🗑️ HA Infrastructure Destruction Summary"
    print_status "======================================="
    echo
    
    print_error "⚠️ This will PERMANENTLY DELETE the following HA resources:"
    echo
    
    # Try to get detailed resource information from terraform
    if terraform show -json 2>/dev/null | jq -r '.values.root_module.resources[]? | "  • \(.type): \(.values.name // .address)"' 2>/dev/null | head -25; then
        echo
        local total_resources
        total_resources=$(terraform show -json 2>/dev/null | jq '.values.root_module.resources | length' 2>/dev/null || echo "0")
        if [[ "$total_resources" -gt 25 ]]; then
            print_status "  ... and $(($total_resources - 25)) more resources"
            echo
        fi
    else
        echo "  • All Nexus IQ HA infrastructure resources"
        echo "  • Compute Engine managed instance groups (2-6+ instances)"
        echo "  • Regional autoscaler and load balancers"
        echo "  • Cloud SQL regional database with read replicas"
        echo "  • Regional persistent disks and file storage"
        echo "  • Monitoring, logging, and alerting configuration"
        echo "  • Service accounts and IAM bindings"
        echo "  • VPC networking and firewall rules"
        echo
    fi
    
    print_error "💀 CRITICAL DATA LOSS WARNING (HA DEPLOYMENT):"
    echo "  • ALL database data will be permanently lost"
    echo "  • ALL files on persistent disks will be permanently lost"
    echo "  • ALL Nexus IQ Server HA configuration and data will be lost"
    echo "  • ALL backup data stored in GCP buckets will be lost"
    echo "  • This action CANNOT be undone"
    echo "  • HA setup and autoscaling configuration will be destroyed"
    echo
    
    if [[ "$SKIP_BACKUP" == "false" ]] && [[ -n "$BACKUP_DIR" ]]; then
        print_status "💾 Backup Information:"
        echo "  • State backup: $BACKUP_DIR/terraform.tfstate"
        echo "  • Configuration backup: $BACKUP_DIR/terraform.tfvars"
        echo "  • State JSON: $BACKUP_DIR/terraform-state.json"
        if [[ -d "$BACKUP_DIR" ]]; then
            local backup_size
            backup_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1 || echo "Unknown")
            echo "  • Backup size: $backup_size"
        fi
        echo
    fi
}

# Function to disable deletion protection if force is enabled
handle_deletion_protection() {
    if [ "$FORCE_DESTROY" = true ]; then
        warning "Force destroy enabled - attempting to disable deletion protection..."
        
        # Try to modify the database deletion protection setting
        if [ -f "terraform.tfvars" ]; then
            if grep -q "db_deletion_protection.*=.*true" terraform.tfvars; then
                log "Temporarily disabling database deletion protection..."
                sed -i.bak 's/db_deletion_protection.*=.*true/db_deletion_protection = false/' terraform.tfvars
                success "Database deletion protection disabled"
            fi
        fi
    else
        # Check if deletion protection is enabled
        if grep -q "db_deletion_protection.*=.*true" terraform.tfvars 2>/dev/null; then
            warning "Database deletion protection is enabled"
            warning "The destroy may fail. Options:"
            echo "  1. Use --force to automatically disable protection"
            echo "  2. Manually set db_deletion_protection = false in terraform.tfvars"
            echo "  3. Continue and handle the error manually"
            echo
        fi
    fi
}

# Function to get user confirmation
get_user_confirmation() {
    if [ "$AUTO_APPROVE" = true ]; then
        log "Auto-approve enabled, skipping confirmation"
        return 0
    fi
    
    echo
    warning "FINAL CONFIRMATION"
    echo "This will permanently destroy ALL Nexus IQ HA infrastructure."
    echo "All data will be lost and cannot be recovered."
    echo
    echo -n "Type 'yes' to confirm destruction: "
    read -r response
    
    case "$response" in
        yes)
            return 0
            ;;
        *)
            log "Destruction cancelled by user"
            exit 0
            ;;
    esac
}

# Function to perform safe HA destroy with enhanced staging
perform_destroy() {
    print_status "🔥 Starting HA infrastructure destruction..."
    
    cd "$TERRAFORM_DIR"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "Dry run mode - no actual destruction will occur"
        print_status "HA destroy plan has been generated and saved"
        return 0
    fi
    
    # Handle deletion protection if force destroy is enabled
    if [[ "$FORCE_DESTROY" == "true" ]]; then
        print_warning "Force destroy enabled - attempting to disable deletion protection..."
        
        # Create a temporary tfvars file with deletion protection disabled
        local temp_tfvars="/tmp/destroy-$(date +%s).tfvars"
        cp "$TFVARS_FILE" "$temp_tfvars"
        echo "" >> "$temp_tfvars"
        echo "# Temporary overrides for HA destruction" >> "$temp_tfvars"
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
    
    # Perform staged HA destroy with proper ordering
    print_status "Destroying HA infrastructure in stages... This may take 20-35 minutes."
    
    # Stage 1: Scale down autoscaler and destroy instances first
    print_status "Stage 1: Scaling down HA cluster and destroying application instances..."
    terraform destroy -target=google_compute_region_autoscaler.iq_autoscaler \
                     -target=google_compute_region_instance_group_manager.iq_mig \
                     -auto-approve -var-file="$TFVARS_FILE" >> "$LOG_FILE" 2>&1 || print_warning "Some autoscaler/MIG resources may not have been destroyed cleanly"
    
    # Stage 2: Destroy load balancer and networking components
    print_status "Stage 2: Destroying load balancer and networking components..."
    terraform destroy -target=google_compute_global_forwarding_rule.iq_forwarding_rule \
                     -target=google_compute_target_http_proxy.iq_target_proxy \
                     -target=google_compute_url_map.iq_url_map \
                     -target=google_compute_backend_service.iq_backend_service \
                     -target=google_compute_health_check.iq_health_check \
                     -auto-approve -var-file="$TFVARS_FILE" >> "$LOG_FILE" 2>&1 || print_warning "Some load balancer resources may not have been destroyed cleanly"
    
    # Stage 3: Destroy database resources with enhanced cleanup
    print_status "Stage 3: Destroying HA database and related services..."
    
    # First, try to close any active database connections
    local db_instance_name
    db_instance_name=$(terraform output -raw database_connection_name 2>/dev/null | cut -d: -f1 || echo "")
    if [[ -n "$db_instance_name" ]]; then
        print_status "Attempting to close database connections..."
        local project_id
        project_id=$(grep gcp_project_id terraform.tfvars | cut -d'"' -f2 2>/dev/null || echo "")
        if [[ -n "$project_id" ]]; then
            gcloud sql operations list --instance="$db_instance_name" --limit=1 --project="$project_id" --format="value(name)" 2>/dev/null | head -1 || true
        fi
    fi
    
    # Destroy database resources in specific order
    # Note: Database user often cannot be dropped due to dependent objects
    # Remove it from state instead to allow database instance deletion
    if terraform state list 2>/dev/null | grep -q "google_sql_user.iq_ha_db_user"; then
        print_status "Removing database user from Terraform state (has dependent objects)..."
        terraform state rm google_sql_user.iq_ha_db_user >> "$LOG_FILE" 2>&1 || print_warning "Database user removal from state failed"
    fi
    
    # Destroy read replica first if it exists
    if terraform state list 2>/dev/null | grep -q "google_sql_database_instance.iq_ha_db_replica"; then
        print_status "Destroying database read replica..."
        terraform destroy -target=google_sql_database_instance.iq_ha_db_replica \
                         -auto-approve -var-file="$TFVARS_FILE" >> "$LOG_FILE" 2>&1 || print_warning "Database replica destruction may have failed"
        sleep 30
    fi
    
    # Destroy database and related resources
    terraform destroy -target=google_sql_database.iq_ha_database \
                     -target=google_sql_ssl_cert.iq_ha_client_cert \
                     -auto-approve -var-file="$TFVARS_FILE" >> "$LOG_FILE" 2>&1 || print_warning "Database resources destruction may have failed"
    
    # Wait for database operations to complete
    print_status "Waiting for database operations to complete..."
    sleep 45
    
    # Finally destroy the database instance
    terraform destroy -target=google_sql_database_instance.iq_ha_db \
                     -auto-approve -var-file="$TFVARS_FILE" >> "$LOG_FILE" 2>&1 || print_warning "Database instance destruction may have failed"
    
    # Stage 4: Destroy storage and other persistent resources
    print_status "Stage 4: Destroying storage and persistent resources..."
    
    # Destroy Filestore instance if it exists
    if terraform state list 2>/dev/null | grep -q "google_filestore_instance.iq_ha_filestore"; then
        print_status "Destroying Cloud Filestore instance..."
        terraform destroy -target=google_filestore_instance.iq_ha_filestore \
                         -auto-approve -var-file="$TFVARS_FILE" >> "$LOG_FILE" 2>&1 || print_warning "Filestore destruction may have failed"
        sleep 30
    fi
    
    # Destroy storage buckets if they exist (legacy single-instance only)
    if terraform state list 2>/dev/null | grep -q "google_storage_bucket"; then
        terraform destroy -target=google_storage_bucket.iq_backup_bucket \
                         -target=google_storage_bucket.iq_config_bucket \
                         -auto-approve -var-file="$TFVARS_FILE" >> "$LOG_FILE" 2>&1 || print_warning "Some storage resources may not have been destroyed cleanly"
    fi
    
    # Stage 5: Handle service networking connection (remove from state)
    print_status "Stage 5: Removing service networking connection from Terraform state..."
    print_warning "Service networking connection will be abandoned due to GCP dependency issues"
    terraform state rm google_service_networking_connection.private_vpc_connection >> "$LOG_FILE" 2>&1 || print_warning "Service networking connection may not exist in state"
    
    # Wait longer for GCP to fully clean up all dependencies
    print_status "Waiting for GCP to fully clean up HA dependencies..."
    sleep 60
    
    # Stage 6: Destroy everything else
    print_status "Stage 6: Destroying remaining HA infrastructure..."
    if ! terraform destroy -auto-approve -var-file="$TFVARS_FILE" >> "$LOG_FILE" 2>&1; then
        print_error "Terraform destroy failed. Check $LOG_FILE for details."
        print_error "Some HA resources may still exist and require manual cleanup."
        
        # Try to identify what's still there
        print_status "Checking remaining HA resources..."
        terraform state list >> "$LOG_FILE" 2>&1 || true
        
        exit 1
    fi
    
    print_status "✅ HA infrastructure destruction completed successfully"
}

# Function to cleanup local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove plan files
    if ls tfplan-ha-* 1> /dev/null 2>&1; then
        rm -f tfplan-ha-*
        success "Removed plan files"
    fi
    
    # Remove terraform lock file if it exists
    if [ -f ".terraform.lock.hcl" ]; then
        warning "Keeping .terraform.lock.hcl (contains provider versions)"
    fi
    
    # Restore original tfvars if we modified it
    if [ -f "terraform.tfvars.bak" ]; then
        mv terraform.tfvars.bak terraform.tfvars
        log "Restored original terraform.tfvars"
    fi
}

# Function to verify HA destruction
verify_destruction() {
    print_status "🔍 Verifying HA infrastructure destruction..."
    
    cd "$TERRAFORM_DIR"
    
    # Check if any resources remain in Terraform state
    local remaining_resources
    remaining_resources=$(terraform state list 2>/dev/null | wc -l || echo "0")
    
    if [[ "$remaining_resources" -gt 0 ]]; then
        print_warning "$remaining_resources HA resources remain in Terraform state"
        print_status "Remaining resources:"
        terraform state list 2>/dev/null | head -10 || true
        if [[ "$remaining_resources" -gt 10 ]]; then
            print_status "... and $(($remaining_resources - 10)) more"
        fi
    else
        print_status "✅ All HA resources successfully removed from Terraform state"
    fi
    
    # Verify with GCP (if project info is available)
    local project_id
    project_id=$(grep "^gcp_project_id[[:space:]]*=" "$TFVARS_FILE" | cut -d'"' -f2 2>/dev/null || echo "")
    
    if [[ -n "$project_id" ]]; then
        print_status "Checking for remaining GCP resources in project: $project_id"
        
        # Check for HA-specific resource types
        local resource_checks=(
            "instances:gcloud compute instances list"
            "instance-groups:gcloud compute instance-groups managed list"
            "autoscalers:gcloud compute autoscalers list"
            "sql-instances:gcloud sql instances list"
            "buckets:gsutil ls -p"
            "addresses:gcloud compute addresses list"
            "health-checks:gcloud compute health-checks list"
        )
        
        for check_info in "${resource_checks[@]}"; do
            local resource_name="${check_info%%:*}"
            local command="${check_info##*:}"
            
            local count
            case $resource_name in
                "buckets")
                    count=$(${command} "$project_id" 2>/dev/null | wc -l || echo "0")
                    ;;
                *)
                    count=$(${command} --project="$project_id" --format="value(name)" 2>/dev/null | wc -l || echo "0")
                    ;;
            esac
            
            if [[ "$count" -gt 0 ]]; then
                print_warning "$count $resource_name still exist in project"
            else
                print_debug "✓ No $resource_name found"
            fi
        done
    fi
    
    print_status "HA destruction verification completed"
}

# Function to show enhanced final summary
show_final_summary() {
    success "🎉 HA Infrastructure destruction completed!"
    echo
    
    print_status "🗑️ What was destroyed:"
    echo "  • Nexus IQ Server HA cluster infrastructure"
    echo "  • All Compute Engine managed instance groups (2-6+ instances)"
    echo "  • Regional autoscaler and load balancing components"
    echo "  • Cloud SQL regional database with read replicas"
    echo "  • Regional persistent disks and file storage"
    echo "  • Monitoring, logging, and alerting configuration"
    echo "  • VPC networking, firewall rules, and service accounts"
    echo "  • All backup buckets and stored data"
    echo
    
    if [[ "$SKIP_BACKUP" == "false" ]] && [[ -n "$BACKUP_DIR" ]] && [[ -d "$BACKUP_DIR" ]]; then
        print_status "💾 Backup Information:"
        echo "  • State backup: $BACKUP_DIR/terraform.tfstate"
        echo "  • Configuration backup: $BACKUP_DIR/terraform.tfvars"
        echo "  • State JSON: $BACKUP_DIR/terraform-state.json"
        local backup_size
        backup_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1 || echo "Unknown")
        echo "  • Total backup size: $backup_size"
        echo
        print_status "📋 To restore HA infrastructure (if needed):"
        echo "  1. Copy $BACKUP_DIR/terraform.tfstate to terraform.tfstate"
        echo "  2. Run './gcp-ha-plan.sh' to verify restoration plan"
        echo "  3. Run './gcp-ha-apply.sh' to restore HA infrastructure"
        echo "  4. Restore application data from backups"
        echo
    fi
    
    print_status "✅ Verification Steps:"
    echo "  • Check GCP Console to confirm all HA resources are deleted"
    echo "  • Verify GCP billing to ensure no ongoing charges"
    echo "  • Clean up any remaining DNS entries if custom domains were used"
    echo "  • Review any service networking connections in VPC console"
    echo "  • Store backups in a secure location for future reference"
    echo
    
    print_warning "⚠️ MANUAL CLEANUP REQUIRED:"
    print_warning "   Service Networking Connection may still exist in GCP"
    print_warning "   This resource was abandoned to avoid destroy failures"
    print_warning "   To clean up manually, run:"
    echo ""
    print_warning "   gcloud services vpc-peerings delete \\"
    print_warning "     --network=nexus-iq-ha-vpc \\"
    print_warning "     --service=servicenetworking.googleapis.com \\"
    print_warning "     --project=$project_id"
    echo ""
    print_warning "   Or delete via GCP Console: VPC Networks > Private Service Connection"
    echo ""
    
    print_status "📁 Log file: $LOG_FILE"
    echo
    
    success "✅ High Availability infrastructure destruction completed successfully!"
}

# Function to handle cleanup on exit
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        error "Destruction failed with exit code $exit_code"
        if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ] && [ "$SKIP_BACKUP" = false ]; then
            log "Backup directory preserved: $BACKUP_DIR"
        fi
        
        # Restore original tfvars if we modified it
        if [ -f "terraform.tfvars.bak" ]; then
            mv terraform.tfvars.bak terraform.tfvars
            log "Restored original terraform.tfvars"
        fi
    fi
}

# Main function
main() {
    # Initialize log file
    echo "=== Nexus IQ Server GCP HA Destruction - $(date) ===" > "$LOG_FILE"
    
    print_status "🔥 Starting Nexus IQ Server GCP HA infrastructure destruction..."
    echo
    
    # Change to script directory
    cd "$(dirname "$0")"
    
    # Set up cleanup handler
    trap cleanup EXIT
    
    # Show warning about HA destruction
    echo ""
    print_error "⚠️  DANGER: This will permanently destroy ALL Nexus IQ HA infrastructure!"
    print_error "⚠️  This action cannot be undone!"
    print_error "⚠️  HA deployments contain multiple instances and critical data!"
    echo ""
    
    if [[ "$FORCE_DESTROY" == "true" ]]; then
        print_error "🔥 FORCE MODE ENABLED - Will destroy ALL protected HA resources!"
        echo ""
    fi
    
    # Get initial confirmation unless skipped
    if [[ "$AUTO_APPROVE" != "true" && "$DRY_RUN" != "true" ]]; then
        echo "Please type 'destroy' to confirm HA destruction: "
        read -r confirmation
        if [[ "$confirmation" != "destroy" ]]; then
            print_status "HA destruction cancelled by user"
            exit 0
        fi
        echo ""
    fi
    
    create_backup_dir
    backup_critical_data
    check_prerequisites
    validate_state
    show_destroy_plan
    handle_protected_resources
    show_destruction_summary
    
    # Final confirmation for actual destroy
    if [[ "$DRY_RUN" != "true" && "$AUTO_APPROVE" != "true" ]]; then
        echo ""
        print_warning "🚨 FINAL CONFIRMATION FOR HA DESTRUCTION 🚨"
        print_warning "This will permanently delete the ENTIRE HA cluster shown above."
        print_warning "All data across multiple instances will be lost and cannot be recovered."
        echo ""
        read -p "Type 'YES' to confirm HA destruction: " -r
        if [[ ! $REPLY =~ ^YES$ ]]; then
            print_status "HA destruction cancelled by user"
            exit 0
        fi
        echo ""
    fi
    
    # Perform the HA destruction
    perform_destroy
    
    # Verify destruction completed
    verify_destruction
    
    # Cleanup terraform files
    cleanup_local_files
    
    # Show summary
    if [[ "$DRY_RUN" != "true" ]]; then
        show_final_summary
    else
        print_status "HA dry run completed. Review the destroy plan above."
        print_status "Run without --dry-run to actually destroy the HA infrastructure."
    fi
    
    print_status "✅ HA Script completed successfully"
}

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
            AUTO_APPROVE=true
            shift
            ;;
        --no-backup)
            SKIP_BACKUP=true
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

# Run main function
main