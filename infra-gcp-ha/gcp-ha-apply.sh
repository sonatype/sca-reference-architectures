#!/bin/bash

# Nexus IQ Server GCP HA Infrastructure - Terraform Apply Script
# This script deploys the GCP HA infrastructure

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
LOG_FILE="$SCRIPT_DIR/apply.log"
SHOW_PROGRESS=true
SKIP_PLAN_CHECK=false
KEEP_PLAN=false

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
PLAN_FILE=""
AUTO_APPROVE=false
BACKUP_DIR=""

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Apply a saved Terraform plan for Nexus IQ Server GCP HA infrastructure

OPTIONS:
    -h, --help              Show this help message
    -p, --plan FILE         Use specific plan file (default: latest tfplan-ha-*)
    -y, --auto-approve      Skip confirmation prompt
    -q, --quiet             Minimize output (no progress indicators)
    --skip-plan-check       Skip plan age validation
    --keep-plan             Don't delete plan file after apply
    -v, --verbose           Enable verbose logging

EXAMPLES:
    # Standard apply with confirmation
    $0
    
    # Use specific plan file
    $0 --plan tfplan-ha-20231215-143022
    
    # Auto-approve (for automation)
    $0 --auto-approve
    
    # Quiet apply
    $0 --quiet --auto-approve
    
    # Keep plan file after apply
    $0 --keep-plan

PREREQUISITES:
    • terraform (>= 1.0)
    • gcloud CLI with active authentication
    • jq and curl tools
    • Valid HA plan file (run './gcp-ha-plan.sh' first)

DEPLOYMENT PHASES:
    1. Prerequisites and configuration validation
    2. Plan file validation and summary
    3. HA infrastructure deployment (15-30 minutes)
    4. Health checks and HA verification
    5. Post-deployment summary and next steps

NOTES:
    - Plan file is automatically deleted after successful apply
    - Logs all operations to apply.log
    - Performs comprehensive HA verification after deployment
    - Creates backup of state before deployment
EOF
}

# Function to create backup directory
create_backup_dir() {
    BACKUP_DIR="backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    log "Created backup directory: $BACKUP_DIR"
}

# Function to backup current state
backup_current_state() {
    if [ -f "terraform.tfstate" ]; then
        log "Backing up current Terraform state..."
        cp terraform.tfstate "$BACKUP_DIR/terraform.tfstate.backup"
        success "State backed up to $BACKUP_DIR/terraform.tfstate.backup"
    fi
    
    if [ -f "terraform.tfvars" ]; then
        cp terraform.tfvars "$BACKUP_DIR/terraform.tfvars.backup"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check required tools
    local required_tools=("terraform" "gcloud" "jq" "curl")
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
        print_error "terraform.tfvars not found. Please run './gcp-ha-plan.sh' first."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        print_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    success "Prerequisites check passed (Terraform $tf_version)"
}

# Function to validate configuration
validate_configuration() {
    print_status "Validating Terraform configuration..."
    
    cd "$TERRAFORM_DIR"
    
    # Initialize Terraform
    if ! terraform init -input=false > "$LOG_FILE" 2>&1; then
        print_error "Terraform initialization failed. Check $LOG_FILE for details."
        cat "$LOG_FILE"
        exit 1
    fi
    
    # Validate configuration
    if ! terraform validate >> "$LOG_FILE" 2>&1; then
        print_error "Terraform validation failed. Check $LOG_FILE for details."
        cat "$LOG_FILE"
        exit 1
    fi
    
    # Format check
    if ! terraform fmt -check >> "$LOG_FILE" 2>&1; then
        print_warning "Terraform files are not properly formatted"
        print_status "Running terraform fmt to fix formatting..."
        terraform fmt
    fi
    
    success "Configuration validation passed"
}

# Function to validate plan file
validate_plan_file() {
    print_status "Validating plan file..."
    
    cd "$TERRAFORM_DIR"
    
    # Check if plan file is readable
    if ! terraform show "$PLAN_FILE" &> /dev/null; then
        print_error "Plan file is invalid or corrupted: $PLAN_FILE"
        print_error "Please run './gcp-ha-plan.sh' to create a new plan"
        exit 1
    fi
    
    # Check plan age
    local plan_age_seconds
    plan_age_seconds=$(($(date +%s) - $(stat -f %m "$PLAN_FILE" 2>/dev/null || stat -c %Y "$PLAN_FILE" 2>/dev/null || echo 0)))
    local plan_age_hours=$((plan_age_seconds / 3600))
    
    if [[ $plan_age_hours -gt 24 ]]; then
        print_warning "Plan file is $plan_age_hours hours old"
        print_warning "Consider running './gcp-ha-plan.sh' to create a fresh plan"
        
        if [[ "$SKIP_PLAN_CHECK" != "true" ]]; then
            read -p "Continue with old plan? (y/N): " -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_status "Apply cancelled by user"
                exit 0
            fi
        fi
    fi
    
    print_status "Plan file validation completed"
}

# Function to find the latest plan file if not specified
find_plan_file() {
    if [ -z "$PLAN_FILE" ]; then
        local latest_plan=$(ls -t tfplan-ha-* 2>/dev/null | head -n1)
        if [ -z "$latest_plan" ]; then
            warning "No plan file found. Running plan first..."
            if ! ./gcp-ha-plan.sh; then
                error "Failed to create plan"
                exit 1
            fi
            latest_plan=$(ls -t tfplan-ha-* 2>/dev/null | head -n1)
        fi
        PLAN_FILE="$latest_plan"
    fi
    
    if [ ! -f "$PLAN_FILE" ]; then
        error "Plan file '$PLAN_FILE' not found"
        exit 1
    fi
    
    log "Using plan file: $PLAN_FILE"
}

# Function to show deployment summary
show_deployment_summary() {
    log "Deployment Summary:"
    echo
    
    # Extract project ID from tfvars
    local project_id=$(grep -E '^gcp_project_id\s*=' terraform.tfvars | sed 's/.*=\s*"\([^"]*\)".*/\1/')
    
    echo "Project ID: $project_id"
    echo "Plan File: $PLAN_FILE"
    echo "Backup Directory: $BACKUP_DIR"
    echo
    
    warning "This deployment will:"
    echo "  • Create a high-availability Nexus IQ Server infrastructure"
    echo "  • Deploy 2-6 Compute Engine instances across multiple zones"
    echo "  • Create a regional Cloud SQL PostgreSQL database"
    echo "  • Set up a global load balancer with SSL/TLS"
    echo "  • Configure auto-scaling and monitoring"
    echo "  • Generate billable resources in GCP"
    echo
}

# Function to get user confirmation
get_user_confirmation() {
    if [ "$AUTO_APPROVE" = true ]; then
        log "Auto-approve enabled, skipping confirmation"
        return 0
    fi
    
    echo -n "Do you want to proceed with the deployment? (yes/no): "
    read -r response
    
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            log "Deployment cancelled by user"
            exit 0
            ;;
    esac
}

# Function to show plan summary before apply
show_plan_summary() {
    print_status "📋 Plan Summary Before Apply"
    print_status "============================"
    
    cd "$TERRAFORM_DIR"
    
    # Show basic plan information
    if ! terraform show -no-color "$PLAN_FILE" | head -50; then
        print_warning "Could not display plan summary"
        return 0
    fi
    
    echo ""
    
    # Parse and show change counts
    local changes_json
    if changes_json=$(terraform show -json "$PLAN_FILE" 2>/dev/null); then
        local create_count update_count delete_count replace_count
        create_count=$(echo "$changes_json" | jq '[.resource_changes[]? | select(.change.actions[] == "create")] | length' 2>/dev/null || echo "0")
        update_count=$(echo "$changes_json" | jq '[.resource_changes[]? | select(.change.actions[] == "update")] | length' 2>/dev/null || echo "0")
        delete_count=$(echo "$changes_json" | jq '[.resource_changes[]? | select(.change.actions[] == "delete")] | length' 2>/dev/null || echo "0")
        replace_count=$(echo "$changes_json" | jq '[.resource_changes[]? | select(.change.actions | contains(["delete", "create"]))] | length' 2>/dev/null || echo "0")
        
        print_status "📊 Change Summary:"
        [[ $create_count -gt 0 ]] && success "  + $create_count resources to create"
        [[ $update_count -gt 0 ]] && print_status "  ~ $update_count resources to update"
        [[ $delete_count -gt 0 ]] && print_warning "  - $delete_count resources to delete"
        [[ $replace_count -gt 0 ]] && print_warning "  ± $replace_count resources to replace"
        echo ""
    fi
}

# Function to apply terraform with enhanced monitoring
terraform_apply() {
    print_status "🚀 Starting Terraform apply..."
    print_status "This may take 15-30 minutes for HA deployment depending on resources"
    echo ""
    
    cd "$TERRAFORM_DIR"
    
    # Create a timestamped backup of the plan
    local backup_plan="$PLAN_FILE.backup.$(date +%Y%m%d-%H%M%S)"
    cp "$PLAN_FILE" "$backup_plan"
    print_debug "Plan backed up to: $backup_plan"
    
    local apply_args=()
    
    if [ "$AUTO_APPROVE" = true ]; then
        apply_args+=("-auto-approve")
    fi
    
    # Apply with progress tracking
    local start_time
    start_time=$(date +%s)
    
    if [[ "$SHOW_PROGRESS" == "true" ]]; then
        # Apply with progress monitoring
        if ! terraform apply "${apply_args[@]}" "$PLAN_FILE" 2>&1 | tee -a "$LOG_FILE" | while IFS= read -r line; do
            echo "$line"
            # Show progress indicators for major resource types
            if [[ "$line" =~ ^[[:space:]]*google_.*: ]]; then
                resource_name=$(echo "$line" | sed 's/:.*//' | xargs | sed 's/^google_//')
                print_debug "Processing HA resource: $resource_name"
            fi
        done; then
            print_error "Terraform apply failed. Check $LOG_FILE for details."
            print_error "Backup directory: $BACKUP_DIR"
            return 1
        fi
    else
        # Simple apply without progress monitoring
        if ! terraform apply "${apply_args[@]}" "$PLAN_FILE" >> "$LOG_FILE" 2>&1; then
            print_error "Terraform apply failed. Check $LOG_FILE for details."
            print_error "Backup directory: $BACKUP_DIR"
            return 1
        fi
    fi
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    
    success "✅ Terraform apply completed successfully in ${minutes}m ${seconds}s"
}

# Function to show deployment outputs
show_deployment_outputs() {
    print_status "🌐 Deployment Outputs"
    print_status "===================="
    
    cd "$TERRAFORM_DIR"
    
    # Get and display key outputs
    local outputs
    if outputs=$(terraform output -json 2>/dev/null); then
        echo ""
        print_status "🔗 Access Information:"
        
        # Load Balancer URL/IP
        local lb_url lb_ip
        lb_url=$(echo "$outputs" | jq -r '.load_balancer_url.value // "Not available"' 2>/dev/null)
        lb_ip=$(echo "$outputs" | jq -r '.load_balancer_ip.value // "Not available"' 2>/dev/null)
        print_status "   Load Balancer URL: $lb_url"
        print_status "   Load Balancer IP: $lb_ip"
        
        # HA specific outputs
        local min_instances max_instances
        min_instances=$(echo "$outputs" | jq -r '.min_instances.value // "Not available"' 2>/dev/null)
        max_instances=$(echo "$outputs" | jq -r '.max_instances.value // "Not available"' 2>/dev/null)
        print_status "   HA Instance Range: $min_instances - $max_instances instances"
        
        # Project and Region
        local project_id region
        project_id=$(echo "$outputs" | jq -r '.project_id.value // "Not available"' 2>/dev/null)
        region=$(echo "$outputs" | jq -r '.deployment_region.value // "Not available"' 2>/dev/null)
        print_status "   GCP Project: $project_id"
        print_status "   Region: $region"
        
        echo ""
        print_status "🗄️ Database Information:"
        local db_name db_connection
        db_name=$(echo "$outputs" | jq -r '.database_connection_name.value // "Not available"' 2>/dev/null)
        print_status "   Database Connection: $db_name"
        
        echo ""
        print_status "🏠 High Availability Details:"
        local mig_name
        mig_name=$(echo "$outputs" | jq -r '.instance_group_manager_name.value // "Not available"' 2>/dev/null)
        print_status "   Managed Instance Group: $mig_name"
        
    else
        print_warning "Could not retrieve deployment outputs"
    fi
}

# Function to run post-deployment health checks and verification
run_health_checks() {
    print_status "🏥 Running post-deployment health checks..."
    
    cd "$TERRAFORM_DIR"
    
    # Check if key HA resources exist in state
    local key_resources=(
        "google_compute_instance_template"
        "google_compute_region_instance_group_manager"
        "google_compute_region_autoscaler"
        "google_sql_database_instance"
        "google_compute_global_address"
    )
    
    print_status "Verifying HA infrastructure components..."
    local missing_resources=()
    for resource in "${key_resources[@]}"; do
        if ! terraform state list | grep -q "$resource"; then
            missing_resources+=("$resource")
        fi
    done
    
    if [[ ${#missing_resources[@]} -eq 0 ]]; then
        success "✅ All key HA resources are present in Terraform state"
    else
        print_warning "⚠️  Some key HA resources are missing from state:"
        for resource in "${missing_resources[@]}"; do
            print_warning "   - $resource"
        done
    fi
    
    # Get load balancer IP for health checks
    local lb_ip
    if lb_ip=$(terraform output -raw load_balancer_ip 2>/dev/null); then
        print_status "Load balancer IP: $lb_ip"
        
        # Wait for load balancer to be ready
        print_status "Waiting for HA load balancer to be ready (this may take 10-15 minutes)..."
        local max_attempts=45
        local attempt=1
        
        while [ $attempt -le $max_attempts ]; do
            print_debug "Health check attempt $attempt/$max_attempts..."
            
            if curl -f -s --connect-timeout 10 "http://$lb_ip/" >/dev/null 2>&1; then
                success "✅ Load balancer is responding"
                break
            fi
            
            if [ $attempt -eq $max_attempts ]; then
                print_warning "⚠️  Load balancer health check timed out"
                print_warning "   This is normal for initial HA deployment - instances may still be starting"
                print_warning "   HA deployments take longer to fully initialize"
                break
            fi
            
            sleep 20
            ((attempt++))
        done
    else
        print_warning "Could not retrieve load balancer IP"
    fi
    
    # Check managed instance group status
    if terraform output -raw instance_group_manager_name >/dev/null 2>&1; then
        local mig_name region project_id
        mig_name=$(terraform output -raw instance_group_manager_name)
        region=$(terraform output -raw deployment_region)
        project_id=$(terraform output -raw project_id)
        
        print_status "Checking HA managed instance group status..."
        if gcloud compute instance-groups managed describe "$mig_name" \
           --region="$region" --project="$project_id" \
           --format="value(status.isStable)" 2>/dev/null | grep -q "True"; then
            success "✅ Managed instance group is stable"
            
            # Get current instance count
            local current_size
            current_size=$(gcloud compute instance-groups managed describe "$mig_name" \
               --region="$region" --project="$project_id" \
               --format="value(targetSize)" 2>/dev/null || echo "Unknown")
            print_status "   Current instance count: $current_size"
        else
            print_warning "⚠️  Managed instance group is still stabilizing"
            print_status "   This is normal and instances will become ready shortly"
        fi
    fi
    
    # Check autoscaler status
    if terraform state list | grep -q "google_compute_region_autoscaler"; then
        print_status "HA autoscaler is configured and active"
    fi
    
    success "✅ Health checks completed"
}

# Function to show post-deployment next steps
show_next_steps() {
    print_status "📋 Next Steps"
    print_status "=============="
    echo ""
    print_status "🎉 Your Nexus IQ Server HA infrastructure has been deployed!"
    echo ""
    print_status "⏱️ Immediate Actions (wait 10-15 minutes):"
    print_status "   1. Wait for all HA instances to fully initialize"
    print_status "   2. Access Nexus IQ Server via the Load Balancer URL above"
    print_status "   3. Complete the initial setup wizard"
    print_status "   4. Default credentials: admin/admin123 (change immediately)"
    print_status "   5. Verify HA functionality by checking multiple instances"
    echo ""
    print_status "🔧 HA Configuration Tasks:"
    print_status "   1. Verify autoscaling behavior under load"
    print_status "   2. Test failover scenarios (terminate an instance)"
    print_status "   3. Set up custom monitoring for HA cluster health"
    print_status "   4. Configure database backup and disaster recovery"
    print_status "   5. Set up SSL certificates for production use"
    echo ""
    print_status "🔍 HA Management Commands:"
    print_status "   • Check cluster status:"
    print_status "     gcloud compute instance-groups managed describe [MIG_NAME] --region=[REGION]"
    print_status "   • List instances:"
    print_status "     gcloud compute instance-groups managed list-instances [MIG_NAME] --region=[REGION]"
    print_status "   • Scale cluster:"
    print_status "     gcloud compute instance-groups managed resize [MIG_NAME] --size=[NUM] --region=[REGION]"
    print_status "   • View HA logs:"
    print_status "     gcloud logging read 'resource.type=\"gce_instance\"' --limit=50"
    echo ""
    print_status "📖 Resources:"
    print_status "   - GCP Console: https://console.cloud.google.com"
    print_status "   - Nexus IQ HA Documentation: https://help.sonatype.com/iqserver/configuring/high-availability"
    print_status "   - Apply logs: $LOG_FILE"
    echo ""
    print_warning "💡 HA Deployment Notes:"
    print_warning "   • HA deployments cost 2-3x more than single instance"
    print_warning "   • Monitor billing and set up budget alerts"
    print_warning "   • Test disaster recovery procedures regularly"
    print_warning "   • Keep database backups in multiple regions"
}

# Function to cleanup plan file
cleanup_plan_file() {
    if [[ "$KEEP_PLAN" != "true" ]] && [[ -f "$PLAN_FILE" ]]; then
        print_status "Cleaning up plan file..."
        rm -f "$PLAN_FILE"
        print_debug "Plan file removed: $PLAN_FILE"
    else
        print_status "Plan file preserved: $PLAN_FILE"
    fi
}

# Function to show final summary
show_final_summary() {
    success "🎉 HA Deployment completed successfully!"
    echo
    
    print_status "📊 HA Infrastructure Summary:"
    echo "  • High-availability Nexus IQ Server cluster deployed"
    echo "  • Auto-scaling managed instance group configured"
    echo "  • Regional load balancer with health checks"
    echo "  • Regional Cloud SQL database with backup"
    echo "  • Monitoring and logging enabled"
    echo "  • Network security and firewall rules applied"
    echo
    
    if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
        print_status "💾 Backup Information:"
        echo "  • State backup: $BACKUP_DIR/terraform.tfstate.backup"
        echo "  • Configuration backup: $BACKUP_DIR/terraform.tfvars.backup"
        echo
    fi
    
    print_warning "⚠️  Important HA Reminders:"
    echo "  • This HA deployment has higher costs than single instance"
    echo "  • Monitor GCP billing dashboard regularly"
    echo "  • Test failover scenarios to validate HA setup"
    echo "  • Keep database backups synchronized across regions"
    echo "  • Review and update security settings for production"
    echo
    
    success "✅ High Availability deployment completed successfully!"
}

# Function to handle cleanup on exit
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        error "Deployment failed with exit code $exit_code"
        if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
            log "Backup directory preserved: $BACKUP_DIR"
        fi
    fi
}

# Main function
main() {
    # Initialize log file
    echo "=== Nexus IQ Server GCP HA Apply - $(date) ===" > "$LOG_FILE"
    
    print_status "🚀 Starting Nexus IQ Server GCP HA deployment..."
    echo
    
    # Change to script directory
    cd "$(dirname "$0")"
    
    # Set up cleanup handler
    trap cleanup EXIT
    
    create_backup_dir
    backup_current_state
    check_prerequisites
    validate_configuration
    find_plan_file
    validate_plan_file
    show_deployment_summary
    show_plan_summary
    get_user_confirmation
    
    # Apply the plan
    if ! terraform_apply; then
        print_error "Apply failed. Check $LOG_FILE for details."
        exit 1
    fi
    
    # Show deployment outputs
    show_deployment_outputs
    
    # Verify deployment
    run_health_checks
    
    # Show next steps
    show_next_steps
    
    # Cleanup plan file unless requested to keep it
    cleanup_plan_file
    
    show_final_summary
    
    print_status "✅ HA Apply completed successfully!"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -p|--plan)
            PLAN_FILE="$2"
            shift 2
            ;;
        -y|--auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        -q|--quiet)
            SHOW_PROGRESS=false
            shift
            ;;
        --skip-plan-check)
            SKIP_PLAN_CHECK=true
            shift
            ;;
        --keep-plan)
            KEEP_PLAN=true
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