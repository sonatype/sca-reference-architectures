#!/bin/bash
set -euo pipefail

# GCP Apply script for Nexus IQ Server Infrastructure
# This script applies a saved Terraform plan

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR"
PLAN_FILE="$SCRIPT_DIR/tfplan"
LOG_FILE="$SCRIPT_DIR/apply.log"
AUTO_APPROVE=false
SHOW_PROGRESS=true
SKIP_PLAN_CHECK=false

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
    local required_tools=("terraform" "gcloud" "jq")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            print_error "$tool is not installed. Please install it and try again."
            exit 1
        fi
    done
    
    # Check if plan file exists
    if [[ ! -f "$PLAN_FILE" ]]; then
        print_error "Plan file not found: $PLAN_FILE"
        print_error "Please run './gcp-plan.sh' first to create a plan"
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        print_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    print_status "Prerequisites check completed"
}

# Function to validate plan file
validate_plan_file() {
    print_status "Validating plan file..."
    
    cd "$TERRAFORM_DIR"
    
    # Check if plan file is readable
    if ! terraform show "$PLAN_FILE" &> /dev/null; then
        print_error "Plan file is invalid or corrupted"
        print_error "Please run './gcp-plan.sh' to create a new plan"
        exit 1
    fi
    
    # Check plan age
    local plan_age_seconds
    plan_age_seconds=$(($(date +%s) - $(stat -f %m "$PLAN_FILE" 2>/dev/null || stat -c %Y "$PLAN_FILE" 2>/dev/null || echo 0)))
    local plan_age_hours=$((plan_age_seconds / 3600))
    
    if [[ $plan_age_hours -gt 24 ]]; then
        print_warning "Plan file is $plan_age_hours hours old"
        print_warning "Consider running './gcp-plan.sh' to create a fresh plan"
        
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

# Function to show plan summary before apply
show_plan_summary() {
    print_status "Plan Summary Before Apply"
    print_status "========================="
    
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
        [[ $create_count -gt 0 ]] && print_status "  + $create_count resources to create"
        [[ $update_count -gt 0 ]] && print_status "  ~ $update_count resources to update"
        [[ $delete_count -gt 0 ]] && print_status "  - $delete_count resources to delete"
        [[ $replace_count -gt 0 ]] && print_warning "  ± $replace_count resources to replace"
        echo ""
    fi
}

# Function to get user confirmation
get_user_confirmation() {
    if [[ "$AUTO_APPROVE" == "true" ]]; then
        print_status "Auto-approve enabled, skipping confirmation"
        return 0
    fi
    
    echo ""
    print_warning "🚀 This will apply the changes shown above to your GCP infrastructure"
    print_warning "⚠️  Make sure you have reviewed the plan carefully"
    echo ""
    
    read -p "Do you want to proceed with applying these changes? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_status "Apply cancelled by user"
        exit 0
    fi
    
    echo ""
}

# Function to apply the terraform plan
apply_terraform_plan() {
    print_status "Applying Terraform plan..."
    print_status "This may take 10-20 minutes depending on the resources being created"
    echo ""
    
    cd "$TERRAFORM_DIR"
    
    # Create a timestamped backup of the plan
    local backup_plan="$PLAN_FILE.backup.$(date +%Y%m%d-%H%M%S)"
    cp "$PLAN_FILE" "$backup_plan"
    print_debug "Plan backed up to: $backup_plan"
    
    # Apply the plan with progress tracking
    local start_time
    start_time=$(date +%s)
    
    if [[ "$SHOW_PROGRESS" == "true" ]]; then
        # Apply with progress monitoring
        if ! terraform apply "$PLAN_FILE" 2>&1 | tee -a "$LOG_FILE" | while IFS= read -r line; do
            echo "$line"
            # Show progress indicators
            if [[ "$line" =~ ^[[:space:]]*[a-z_]+\.[a-z_]+.*: ]]; then
                print_debug "Processing: $(echo "$line" | sed 's/:.*//' | xargs)"
            fi
        done; then
            print_error "Terraform apply failed. Check $LOG_FILE for details."
            return 1
        fi
    else
        # Simple apply without progress monitoring
        if ! terraform apply "$PLAN_FILE" >> "$LOG_FILE" 2>&1; then
            print_error "Terraform apply failed. Check $LOG_FILE for details."
            return 1
        fi
    fi
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    
    print_status "✅ Terraform apply completed successfully in ${minutes}m ${seconds}s"
}

# Function to show deployment outputs
show_deployment_outputs() {
    print_status "Deployment Outputs"
    print_status "=================="
    
    cd "$TERRAFORM_DIR"
    
    # Get and display key outputs
    local outputs
    if outputs=$(terraform output -json 2>/dev/null); then
        echo ""
        print_status "🌐 Access Information:"
        
        # Nexus IQ URL
        local nexus_url
        nexus_url=$(echo "$outputs" | jq -r '.nexus_iq_url.value // "Not available"' 2>/dev/null)
        print_status "   Nexus IQ Server: $nexus_url"
        
        # Load Balancer IP
        local lb_ip
        lb_ip=$(echo "$outputs" | jq -r '.load_balancer_ip.value // "Not available"' 2>/dev/null)
        print_status "   Load Balancer IP: $lb_ip"
        
        # Project and Region
        local project_id region
        project_id=$(echo "$outputs" | jq -r '.project_id.value // "Not available"' 2>/dev/null)
        region=$(echo "$outputs" | jq -r '.region.value // "Not available"' 2>/dev/null)
        print_status "   GCP Project: $project_id"
        print_status "   Region: $region"
        
        echo ""
        print_status "🗄️ Database Information:"
        local db_name db_connection
        db_name=$(echo "$outputs" | jq -r '.database_instance_name.value // "Not available"' 2>/dev/null)
        db_connection=$(echo "$outputs" | jq -r '.database_connection_name.value // "Not available"' 2>/dev/null)
        print_status "   Database Instance: $db_name"
        print_status "   Connection Name: $db_connection"
        
        echo ""
        print_status "💾 Storage Information:"
        local filestore_name backup_bucket
        filestore_name=$(echo "$outputs" | jq -r '.filestore_instance_name.value // "Not available"' 2>/dev/null)
        backup_bucket=$(echo "$outputs" | jq -r '.backup_bucket_name.value // "Not available"' 2>/dev/null)
        print_status "   Filestore Instance: $filestore_name"
        print_status "   Backup Bucket: $backup_bucket"
        
        echo ""
        print_status "📊 Monitoring:"
        local dashboard_url
        dashboard_url=$(echo "$outputs" | jq -r '.monitoring_dashboard_url.value // "Not available"' 2>/dev/null)
        print_status "   Dashboard: $dashboard_url"
        
        # HA outputs if enabled
        local ha_url
        ha_url=$(echo "$outputs" | jq -r '.nexus_iq_ha_url.value // null' 2>/dev/null)
        if [[ "$ha_url" != "null" && -n "$ha_url" ]]; then
            echo ""
            print_status "🏠 High Availability:"
            print_status "   Nexus IQ HA Server: $ha_url"
        fi
        
    else
        print_warning "Could not retrieve deployment outputs"
    fi
}

# Function to perform post-apply verification
verify_deployment() {
    print_status "Verifying deployment..."
    
    cd "$TERRAFORM_DIR"
    
    # Check if key resources exist in state
    local key_resources=(
        "google_cloud_run_service.iq_service"
        "google_sql_database_instance.iq_db"
        "google_compute_global_address.iq_lb_ip"
    )
    
    local missing_resources=()
    for resource in "${key_resources[@]}"; do
        if ! terraform state show "$resource" &> /dev/null; then
            missing_resources+=("$resource")
        fi
    done
    
    if [[ ${#missing_resources[@]} -eq 0 ]]; then
        print_status "✅ All key resources are present in Terraform state"
    else
        print_warning "⚠️  Some key resources are missing from state:"
        for resource in "${missing_resources[@]}"; do
            print_warning "   - $resource"
        done
    fi
    
    # Basic connectivity test (if possible)
    local nexus_url
    if nexus_url=$(terraform output -raw nexus_iq_url 2>/dev/null) && [[ -n "$nexus_url" ]]; then
        print_status "Testing connectivity to Nexus IQ Server..."
        if curl -f -s --max-time 30 "$nexus_url" &> /dev/null; then
            print_status "✅ Nexus IQ Server is responding"
        else
            print_warning "⚠️  Nexus IQ Server is not yet responding (this is normal during initial deployment)"
            print_warning "   It may take 5-10 minutes for the service to fully start"
        fi
    fi
    
    print_status "Deployment verification completed"
}

# Function to show post-deployment steps
show_next_steps() {
    echo ""
    print_status "✅ Deployment Completed Successfully"
    echo ""
    print_status "🎯 Next Steps"
    print_status "━━━━━━━━━━━━"
    print_status "1. Access IQ Server (wait 5-10 minutes for initialization)"
    print_status "2. Default credentials: admin / admin123"
    print_status "3. Monitor deployment health"
    echo ""
    print_warning "⚠️  Important Security Notes"
    print_warning "━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_warning "• Change default admin password immediately"
    print_warning "• Review firewall rules"
    print_warning "• Set up monitoring and alerting"
    echo ""
    print_status "📖 Resources:"
    print_status "   - GCP Console: https://console.cloud.google.com"
    print_status "   - Nexus IQ Documentation: https://help.sonatype.com/iqserver"
    print_status "   - Apply logs: $LOG_FILE"
    echo ""
}

# Function to cleanup plan file
cleanup_plan_file() {
    if [[ -f "$PLAN_FILE" ]]; then
        print_status "Cleaning up plan file..."
        rm -f "$PLAN_FILE"
        print_debug "Plan file removed: $PLAN_FILE"
    fi
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Apply a saved Terraform plan for Nexus IQ Server GCP infrastructure

OPTIONS:
    -h, --help              Show this help message
    -y, --auto-approve      Skip confirmation prompt
    -q, --quiet             Minimize output (no progress indicators)
    --skip-plan-check       Skip plan age validation
    --keep-plan             Don't delete plan file after apply
    -v, --verbose           Enable verbose logging

EXAMPLES:
    # Standard apply with confirmation
    $0
    
    # Auto-approve (for automation)
    $0 --auto-approve
    
    # Quiet apply
    $0 --quiet --auto-approve
    
    # Keep plan file after apply
    $0 --keep-plan

NOTES:
    - Requires a plan file created by './gcp-plan.sh'
    - Plan file is automatically deleted after successful apply
    - Logs all operations to apply.log
    - Performs basic verification after deployment
EOF
}

# Main function
main() {
    # Initialize log file
    echo "=== Nexus IQ Server GCP Apply - $(date) ===" > "$LOG_FILE"
    
    local keep_plan=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
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
                keep_plan=true
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
    
    # Validate plan file
    validate_plan_file
    
    # Show plan summary
    show_plan_summary
    
    # Get user confirmation
    get_user_confirmation
    
    # Apply the plan
    if ! apply_terraform_plan; then
        print_error "Apply failed. Check $LOG_FILE for details."
        exit 1
    fi
    
    # Show deployment outputs
    show_deployment_outputs
    
    # Verify deployment
    verify_deployment
    
    # Show next steps
    show_next_steps
    
    # Cleanup plan file unless requested to keep it
    if [[ "$keep_plan" != "true" ]]; then
        cleanup_plan_file
    fi
    
    print_status "Apply completed successfully!"
}

# Run main function
main "$@"