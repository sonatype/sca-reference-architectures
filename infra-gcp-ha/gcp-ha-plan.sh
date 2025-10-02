#!/bin/bash

# Nexus IQ Server GCP HA Infrastructure - Terraform Plan Script  
# This script validates and plans the GCP HA deployment

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
PLAN_FILE="$SCRIPT_DIR/tfplan-ha-$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$SCRIPT_DIR/plan.log"
DETAILED_OUTPUT=false
SAVE_PLAN=true
VALIDATE_ONLY=false

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

print_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $*"
}

# Function to check if required tools are installed
check_prerequisites() {
    log "Checking prerequisites..."
    
    local missing_tools=()
    
    if ! command -v terraform &> /dev/null; then
        missing_tools+=("terraform")
    fi
    
    if ! command -v gcloud &> /dev/null; then
        missing_tools+=("gcloud")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        error "Missing required tools: ${missing_tools[*]}"
        error "Please install the missing tools and try again."
        exit 1
    fi
    
    # Check Terraform version
    local tf_version=$(terraform version -json | jq -r '.terraform_version')
    local tf_major=$(echo "$tf_version" | cut -d. -f1)
    local tf_minor=$(echo "$tf_version" | cut -d. -f2)
    
    if [[ $tf_major -lt 1 ]] || [[ $tf_major -eq 1 && $tf_minor -lt 0 ]]; then
        error "Terraform version 1.0 or higher is required. Found: $tf_version"
        exit 1
    fi
    
    success "All prerequisites are installed (Terraform $tf_version)"
}

# Function to check GCP authentication
check_gcp_auth() {
    log "Checking GCP authentication..."
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error "No active GCP authentication found"
        error "Please run 'gcloud auth login' or 'gcloud auth application-default login'"
        exit 1
    fi
    
    local active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
    success "Authenticated as: $active_account"
}

# Function to validate terraform.tfvars
validate_tfvars() {
    log "Validating terraform.tfvars..."
    
    if [ ! -f "terraform.tfvars" ]; then
        warning "terraform.tfvars not found"
        if [ -f "terraform.tfvars.example" ]; then
            warning "Copy terraform.tfvars.example to terraform.tfvars and customize it"
            warning "cp terraform.tfvars.example terraform.tfvars"
        fi
        error "Please create terraform.tfvars before proceeding"
        exit 1
    fi
    
    # Check for required variables
    local required_vars=("gcp_project_id" "db_password")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if ! grep -q "^$var\s*=" terraform.tfvars; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -ne 0 ]; then
        error "Missing required variables in terraform.tfvars: ${missing_vars[*]}"
        exit 1
    fi
    
    # Check for default/insecure values
    if grep -q 'db_password.*=.*"your-secure-database-password"' terraform.tfvars; then
        error "Please change the default database password in terraform.tfvars"
        exit 1
    fi
    
    if grep -q 'gcp_project_id.*=.*"your-gcp-project-id"' terraform.tfvars; then
        error "Please set your actual GCP project ID in terraform.tfvars"
        exit 1
    fi
    
    success "terraform.tfvars validation passed"
}

# Function to check GCP project and permissions
check_gcp_project() {
    log "Checking GCP project and permissions..."
    
    # Extract project ID with simple and reliable method
    local project_id
    project_id=$(grep -E '^gcp_project_id\s*=' terraform.tfvars | head -1 | cut -d'"' -f2 2>/dev/null)
    
    print_debug "Raw line from tfvars: $(grep -E '^gcp_project_id\s*=' terraform.tfvars | head -1)"
    print_debug "Extracted project ID: '$project_id'"
    
    if [ -z "$project_id" ]; then
        error "Could not extract project ID from terraform.tfvars"
        error "Please ensure terraform.tfvars contains: gcp_project_id = \"your-project-id\""
        exit 1
    fi
    
    if [ -z "$project_id" ]; then
        error "Project ID is empty in terraform.tfvars"
        exit 1
    fi
    
    # Set the project with error handling
    print_debug "Setting active GCP project to: $project_id"
    if ! gcloud config set project "$project_id" 2>/dev/null; then
        warning "Could not set active project, but continuing..."
    fi
    
    # Check if project exists and is accessible
    print_debug "Verifying project access..."
    if gcloud projects describe "$project_id" --format="value(projectId)" >/dev/null 2>&1; then
        success "GCP project '$project_id' is accessible"
    else
        error "Cannot access project '$project_id'"
        error "Please check that:"
        error "  1. The project exists"
        error "  2. You have access to the project"
        error "  3. Your GCP authentication is working"
        error "  4. The project ID is correct in terraform.tfvars"
        exit 1
    fi
    
    # Check required APIs (will be enabled by Terraform, but good to warn)
    log "Checking required GCP APIs..."
    local required_apis=(
        "compute.googleapis.com"
        "sqladmin.googleapis.com" 
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "servicenetworking.googleapis.com"
        "file.googleapis.com"
    )
    
    print_debug "Checking API status..."
    local disabled_apis=()
    for api in "${required_apis[@]}"; do
        print_debug "Checking API: $api"
        if ! gcloud services list --enabled --filter="name:$api" --format="value(name)" --project="$project_id" 2>/dev/null | grep -q "$api"; then
            disabled_apis+=("$api")
        fi
    done
    
    if [ ${#disabled_apis[@]} -ne 0 ]; then
        warning "The following APIs are not enabled: ${disabled_apis[*]}"
        warning "Terraform will enable them automatically during apply"
    else
        success "All required APIs are enabled"
    fi
}

# Function to initialize Terraform
terraform_init() {
    log "Initializing Terraform..."
    
    cd "$TERRAFORM_DIR"
    
    if ! terraform init -input=false > "$LOG_FILE" 2>&1; then
        error "Terraform initialization failed. Check $LOG_FILE for details."
        cat "$LOG_FILE"
        exit 1
    fi
    
    success "Terraform initialized successfully"
}

# Function to validate Terraform configuration
terraform_validate() {
    log "Validating Terraform configuration..."
    
    cd "$TERRAFORM_DIR"
    
    if ! terraform validate >> "$LOG_FILE" 2>&1; then
        error "Terraform validation failed. Check $LOG_FILE for details."
        cat "$LOG_FILE"
        exit 1
    fi
    
    # Format check
    if ! terraform fmt -check >> "$LOG_FILE" 2>&1; then
        warning "Terraform files are not properly formatted"
        log "Running terraform fmt to fix formatting..."
        terraform fmt
    fi
    
    success "Terraform configuration is valid"
}

# Function to run terraform plan
terraform_plan() {
    log "Running Terraform plan..."
    
    cd "$TERRAFORM_DIR"
    
    local plan_args=()
    
    # Add var file
    plan_args+=("-var-file=$TFVARS_FILE")
    
    # Add output file if saving plan
    if [[ "$SAVE_PLAN" == "true" ]]; then
        plan_args+=("-out=$PLAN_FILE")
        log "Plan will be saved to: $PLAN_FILE"
    fi
    
    # Add detailed exitcode
    plan_args+=("-detailed-exitcode")
    
    # Run the plan
    local exit_code=0
    terraform plan "${plan_args[@]}" 2>&1 | tee -a "$LOG_FILE" || exit_code=$?
    
    # Handle terraform plan exit codes
    case $exit_code in
        0)
            success "✅ No changes needed - infrastructure matches configuration"
            ;;
        1)
            error "❌ Terraform plan failed"
            exit 1
            ;;
        2)
            success "📋 Changes detected - see plan above"
            ;;
        *)
            error "❌ Unexpected exit code: $exit_code"
            exit 1
            ;;
    esac
    
    return $exit_code
}

# Function to show plan summary
show_plan_summary() {
    if [[ ! -f "$PLAN_FILE" ]]; then
        warning "No plan file found to summarize"
        return 0
    fi
    
    log "📊 Plan Summary"
    log "==============="
    
    cd "$TERRAFORM_DIR"
    
    # Get plan summary
    local plan_summary
    plan_summary=$(terraform show -json "$PLAN_FILE" 2>/dev/null | jq -r '
        .resource_changes[] | 
        select(.change.actions[] | . != "no-op") |
        "\(.change.actions | join(",")): \(.address)"
    ' 2>/dev/null || echo "Could not parse plan summary")
    
    if [[ -n "$plan_summary" ]]; then
        echo ""
        log "📋 Planned Changes:"
        echo "$plan_summary" | sort | uniq -c | sort -rn | while read -r count action_resource; do
            local action=$(echo "$action_resource" | cut -d: -f1)
            local resource_type=$(echo "$action_resource" | cut -d: -f2 | cut -d. -f1)
            
            case "$action" in
                *create*)
                    success "  + $count $resource_type resources to be created"
                    ;;
                *update*)
                    log "  ~ $count $resource_type resources to be updated"
                    ;;
                *delete*)
                    warning "  - $count $resource_type resources to be deleted"
                    ;;
                *replace*)
                    warning "  ± $count $resource_type resources to be replaced"
                    ;;
            esac
        done
        echo ""
    fi
    
    # Show resource types
    local resource_types
    resource_types=$(terraform show -json "$PLAN_FILE" 2>/dev/null | jq -r '
        .planned_values.root_module.resources[]?.type
    ' 2>/dev/null | sort | uniq -c | sort -rn || echo "")
    
    if [[ -n "$resource_types" ]]; then
        log "📦 Resource Types in Plan:"
        echo "$resource_types" | while read -r count type; do
            log "  $count x $type"
        done
        echo ""
    fi
}

# Function to show detailed plan output
show_detailed_output() {
    if [[ ! -f "$PLAN_FILE" ]]; then
        warning "No plan file found for detailed output"
        return 0
    fi
    
    log "📄 Detailed Plan Output"
    log "======================"
    
    cd "$TERRAFORM_DIR"
    
    # Show human-readable plan
    terraform show "$PLAN_FILE" 2>/dev/null || warning "Could not show detailed plan"
}

# Function to validate plan against best practices
validate_plan() {
    if [[ ! -f "$PLAN_FILE" ]]; then
        warning "No plan file found for validation"
        return 0
    fi
    
    log "🔍 Validating plan against best practices..."
    
    cd "$TERRAFORM_DIR"
    
    # Check for common issues
    local issues_found=false
    
    # Check for resources without labels/tags
    if terraform show -json "$PLAN_FILE" 2>/dev/null | jq -r '.planned_values.root_module.resources[]? | select(.values.labels == null and .values.tags == null) | .address' | head -5 | grep -q .; then
        warning "⚠️  Some resources may be missing labels/tags"
        issues_found=true
    fi
    
    # Check for hardcoded values
    if grep -r "TODO\|FIXME\|CHANGEME" "$TERRAFORM_DIR"/*.tf 2>/dev/null | head -3; then
        warning "⚠️  Found TODO/FIXME/CHANGEME comments in configuration"
        issues_found=true
    fi
    
    # Check for deletion protection on critical resources (databases)
    if terraform show -json "$PLAN_FILE" 2>/dev/null | jq -r '.planned_values.root_module.resources[]? | select(.type == "google_sql_database_instance" and .values.deletion_protection != true) | .address' | head -3 | grep -q .; then
        warning "⚠️  Database instances may not have deletion protection enabled"
        issues_found=true
    fi
    
    if [[ "$issues_found" == "false" ]]; then
        success "✅ Plan validation completed - no issues found"
    else
        warning "⚠️  Plan validation found potential issues (see above)"
    fi
}

# Function to estimate costs
estimate_costs() {
    log "💰 Cost Estimation"
    log "=================="
    
    # Check for infracost tool
    if command -v infracost &> /dev/null; then
        log "Running cost estimation with infracost..."
        if infracost breakdown --path "$TERRAFORM_DIR" --format table 2>/dev/null; then
            echo ""
        else
            warning "Could not generate detailed cost estimate"
        fi
    else
        log "Install 'infracost' for detailed cost estimation"
        echo ""
    fi
    
    warning "This HA deployment will create billable resources:"
    echo "  • Compute Engine instances (2-6 instances for HA cluster)"
    echo "  • Cloud SQL regional instance + read replicas for HA"
    echo "  • Regional persistent disks with replication"
    echo "  • Global load balancer with SSL certificates"
    echo "  • Cloud NAT gateway with external IP"
    echo "  • Monitoring, logging, and alerting services"
    echo "  • Secret Manager for credential storage"
    echo
    warning "HA configuration typically costs 2-3x more than single instance"
    warning "Use 'gcloud billing projects describe PROJECT_ID' to check billing"
    echo
}

# Function to run security analysis
run_security_analysis() {
    log "🔒 Security Analysis"
    log "==================="
    
    if command -v tfsec &> /dev/null; then
        log "Running security analysis with tfsec..."
        if tfsec "$TERRAFORM_DIR" --format table --soft-fail 2>/dev/null; then
            echo ""
        else
            warning "Security analysis completed with findings"
        fi
    else
        log "Install 'tfsec' for security analysis"
        echo ""
    fi
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Run Terraform plan for Nexus IQ Server GCP HA infrastructure

OPTIONS:
    -h, --help              Show this help message
    -d, --detailed          Show detailed plan output
    -n, --no-save          Don't save plan to file
    -v, --validate-only    Only validate configuration (no plan)
    --verbose              Enable verbose logging

EXAMPLES:
    # Standard plan
    $0
    
    # Detailed plan output
    $0 --detailed
    
    # Validate configuration only
    $0 --validate-only
    
    # Plan without saving to file
    $0 --no-save

NOTES:
    - Requires terraform.tfvars file with required variables
    - Plan is saved to timestamped tfplan-ha file by default
    - Use './gcp-ha-apply.sh' to apply the saved plan
    - Logs are written to plan.log
EOF
}

# Main function
main() {
    # Initialize log file
    echo "=== Nexus IQ Server GCP HA Plan - $(date) ===" > "$LOG_FILE"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -d|--detailed)
                DETAILED_OUTPUT=true
                shift
                ;;
            -n|--no-save)
                SAVE_PLAN=false
                PLAN_FILE="$SCRIPT_DIR/tfplan-ha-temp"
                shift
                ;;
            -v|--validate-only)
                VALIDATE_ONLY=true
                shift
                ;;
            --verbose)
                set -x
                shift
                ;;
            *)
                error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    log "Starting Nexus IQ Server GCP HA infrastructure planning..."
    echo
    
    # Change to script directory
    cd "$(dirname "$0")"
    
    check_prerequisites
    check_gcp_auth
    validate_tfvars
    check_gcp_project
    terraform_init
    terraform_validate
    
    if [[ "$VALIDATE_ONLY" == "true" ]]; then
        success "✅ Configuration validation completed successfully"
        exit 0
    fi
    
    estimate_costs
    run_security_analysis
    
    # Run terraform plan
    local plan_exit_code=0
    terraform_plan || plan_exit_code=$?
    
    # Show plan summary
    show_plan_summary
    
    # Validate plan
    validate_plan
    
    # Show detailed output if requested
    if [[ "$DETAILED_OUTPUT" == "true" ]]; then
        show_detailed_output
    fi
    
    # Show next steps
    echo ""
    log "📋 Next Steps:"
    if [[ "$SAVE_PLAN" == "true" ]]; then
        success "   - Review the plan above"
        success "   - Run './gcp-ha-apply.sh' to apply the saved plan"
        success "   - Or run 'terraform apply \"$PLAN_FILE\"' to apply directly"
    else
        success "   - Review the plan above"
        success "   - Run this script again without --no-save to save plan"
        success "   - Run './gcp-ha-apply.sh' for deployment"
    fi
    success "   - Check plan.log for detailed logs"
    echo ""
    
    # Final status
    if [[ $plan_exit_code -eq 0 ]]; then
        success "✅ Planning completed successfully - no changes needed!"
    elif [[ $plan_exit_code -eq 2 ]]; then
        success "✅ Planning completed successfully - changes detected!"
    fi
    
    warning "Remember: This will create billable HA resources in GCP"
    
    # Exit with terraform plan's exit code
    exit $plan_exit_code
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_usage
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac