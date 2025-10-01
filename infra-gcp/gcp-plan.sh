#!/bin/bash
set -euo pipefail

# GCP Plan script for Nexus IQ Server Infrastructure
# This script runs terraform plan with proper validation and formatting

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
PLAN_FILE="$SCRIPT_DIR/tfplan"
LOG_FILE="$SCRIPT_DIR/plan.log"
DETAILED_OUTPUT=false
SAVE_PLAN=true
VALIDATE_ONLY=false

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
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
        print_error "terraform.tfvars not found. Please run './deploy.sh' first to create it."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        print_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    print_status "Prerequisites check completed"
}

# Function to validate configuration
validate_configuration() {
    print_status "Validating Terraform configuration..."
    
    cd "$TERRAFORM_DIR"
    
    # Initialize Terraform
    print_status "Initializing Terraform..."
    if ! terraform init -input=false > "$LOG_FILE" 2>&1; then
        print_error "Terraform initialization failed. Check $LOG_FILE for details."
        cat "$LOG_FILE"
        exit 1
    fi
    
    # Validate configuration
    print_status "Running configuration validation..."
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
    
    print_status "Configuration validation completed"
}

# Function to run terraform plan
run_terraform_plan() {
    print_status "Running Terraform plan..."
    
    cd "$TERRAFORM_DIR"
    
    local plan_args=()
    
    # Add var file
    plan_args+=("-var-file=$TFVARS_FILE")
    
    # Add output file if saving plan
    if [[ "$SAVE_PLAN" == "true" ]]; then
        plan_args+=("-out=$PLAN_FILE")
        print_status "Plan will be saved to: $PLAN_FILE"
    fi
    
    # Add detailed exitcode
    plan_args+=("-detailed-exitcode")
    
    # Run the plan
    local exit_code=0
    terraform plan "${plan_args[@]}" 2>&1 | tee -a "$LOG_FILE" || exit_code=$?
    
    # Handle terraform plan exit codes
    case $exit_code in
        0)
            print_status "✅ No changes needed - infrastructure matches configuration"
            ;;
        1)
            print_error "❌ Terraform plan failed"
            exit 1
            ;;
        2)
            print_status "📋 Changes detected - see plan above"
            ;;
        *)
            print_error "❌ Unexpected exit code: $exit_code"
            exit 1
            ;;
    esac
    
    return $exit_code
}

# Function to show plan summary
show_plan_summary() {
    if [[ ! -f "$PLAN_FILE" ]]; then
        print_warning "No plan file found to summarize"
        return 0
    fi
    
    print_status "Plan Summary"
    print_status "============"
    
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
        print_status "📊 Planned Changes:"
        echo "$plan_summary" | sort | uniq -c | sort -rn | while read -r count action_resource; do
            local action=$(echo "$action_resource" | cut -d: -f1)
            local resource_type=$(echo "$action_resource" | cut -d: -f2 | cut -d. -f1)
            
            case "$action" in
                *create*)
                    print_status "  + $count $resource_type resources to be created"
                    ;;
                *update*)
                    print_status "  ~ $count $resource_type resources to be updated"
                    ;;
                *delete*)
                    print_status "  - $count $resource_type resources to be deleted"
                    ;;
                *replace*)
                    print_warning "  ± $count $resource_type resources to be replaced"
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
        print_status "📦 Resource Types in Plan:"
        echo "$resource_types" | while read -r count type; do
            print_status "  $count x $type"
        done
        echo ""
    fi
    
    # Show estimated costs (if available)
    if command -v infracost &> /dev/null; then
        print_status "💰 Cost Estimation:"
        if infracost breakdown --path "$TERRAFORM_DIR" --format table 2>/dev/null; then
            echo ""
        else
            print_warning "Could not generate cost estimate"
        fi
    else
        print_debug "Install 'infracost' for cost estimation"
    fi
    
    # Show security analysis (if available)
    if command -v tfsec &> /dev/null; then
        print_status "🔒 Security Analysis:"
        if tfsec "$TERRAFORM_DIR" --format table --soft-fail 2>/dev/null; then
            echo ""
        else
            print_warning "Security analysis completed with findings"
        fi
    else
        print_debug "Install 'tfsec' for security analysis"
    fi
}

# Function to show detailed plan output
show_detailed_output() {
    if [[ ! -f "$PLAN_FILE" ]]; then
        print_warning "No plan file found for detailed output"
        return 0
    fi
    
    print_status "Detailed Plan Output"
    print_status "===================="
    
    cd "$TERRAFORM_DIR"
    
    # Show human-readable plan
    terraform show "$PLAN_FILE" 2>/dev/null || print_warning "Could not show detailed plan"
}

# Function to validate plan against best practices
validate_plan() {
    if [[ ! -f "$PLAN_FILE" ]]; then
        print_warning "No plan file found for validation"
        return 0
    fi
    
    print_status "Validating plan against best practices..."
    
    cd "$TERRAFORM_DIR"
    
    # Check for common issues
    local issues_found=false
    
    # Check for resources without labels/tags
    if terraform show -json "$PLAN_FILE" 2>/dev/null | jq -r '.planned_values.root_module.resources[]? | select(.values.labels == null and .values.tags == null) | .address' | head -5 | grep -q .; then
        print_warning "⚠️  Some resources may be missing labels/tags"
        issues_found=true
    fi
    
    # Check for hardcoded values
    if grep -r "TODO\|FIXME\|CHANGEME" "$TERRAFORM_DIR"/*.tf 2>/dev/null | head -3; then
        print_warning "⚠️  Found TODO/FIXME/CHANGEME comments in configuration"
        issues_found=true
    fi
    
    # Check for deletion protection on critical resources
    if terraform show -json "$PLAN_FILE" 2>/dev/null | jq -r '.planned_values.root_module.resources[]? | select(.type == "google_sql_database_instance" and .values.deletion_protection != true) | .address' | head -3 | grep -q .; then
        print_warning "⚠️  Database instances may not have deletion protection enabled"
        issues_found=true
    fi
    
    if [[ "$issues_found" == "false" ]]; then
        print_status "✅ Plan validation completed - no issues found"
    else
        print_warning "⚠️  Plan validation found potential issues (see above)"
    fi
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Run Terraform plan for Nexus IQ Server GCP infrastructure

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
    - Requires terraform.tfvars file (run ./deploy.sh first)
    - Plan is saved to tfplan file by default
    - Use './gcp-apply.sh' to apply the saved plan
    - Logs are written to plan.log
EOF
}

# Main function
main() {
    # Initialize log file
    echo "=== Nexus IQ Server GCP Plan - $(date) ===" > "$LOG_FILE"
    
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
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Check prerequisites
    check_prerequisites
    
    # Validate configuration
    validate_configuration
    
    if [[ "$VALIDATE_ONLY" == "true" ]]; then
        print_status "✅ Configuration validation completed successfully"
        exit 0
    fi
    
    # Run terraform plan
    local plan_exit_code=0
    run_terraform_plan || plan_exit_code=$?
    
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
    print_status "📋 Next Steps:"
    if [[ "$SAVE_PLAN" == "true" ]]; then
        print_status "   - Review the plan above"
        print_status "   - Run './gcp-apply.sh' to apply the saved plan"
        print_status "   - Or run './deploy.sh' for full deployment"
    else
        print_status "   - Review the plan above"
        print_status "   - Run './deploy.sh' to deploy the infrastructure"
    fi
    print_status "   - Check plan.log for detailed logs"
    echo ""
    
    # Exit with terraform plan's exit code
    exit $plan_exit_code
}

# Run main function
main "$@"