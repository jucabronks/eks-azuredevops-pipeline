#!/bin/bash

# =============================================================================
# DEPLOY SCRIPT - PROJETO VM
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 <cloud_provider> <environment> [options]"
    echo ""
    echo "Arguments:"
    echo "  cloud_provider    Cloud provider (aws, azure, gcp)"
    echo "  environment       Environment (dev, staging, prod)"
    echo ""
    echo "Options:"
    echo "  --plan-only       Only run terraform plan, don't apply"
    echo "  --destroy         Destroy infrastructure"
    echo "  --force           Skip confirmation prompts"
    echo "  --help            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 aws dev"
    echo "  $0 azure staging --plan-only"
    echo "  $0 gcp prod --destroy"
}

# Function to validate arguments
validate_args() {
    local cloud_provider=$1
    local environment=$2
    
    # Validate cloud provider
    case $cloud_provider in
        aws|azure|gcp)
            ;;
        *)
            print_error "Invalid cloud provider: $cloud_provider"
            print_error "Valid options: aws, azure, gcp"
            exit 1
            ;;
    esac
    
    # Validate environment
    case $environment in
        dev|staging|prod)
            ;;
        *)
            print_error "Invalid environment: $environment"
            print_error "Valid options: dev, staging, prod"
            exit 1
            ;;
    esac
}

# Function to check prerequisites
check_prerequisites() {
    local cloud_provider=$1
    
    print_status "Checking prerequisites..."
    
    # Check if Terraform is installed
    if ! command -v terraform >/dev/null 2>&1; then
        print_error "Terraform is not installed"
        exit 1
    fi
    
    # Check cloud provider CLI
    case $cloud_provider in
        aws)
            if ! command -v aws >/dev/null 2>&1; then
                print_error "AWS CLI is not installed"
                exit 1
            fi
            ;;
        azure)
            if ! command -v az >/dev/null 2>&1; then
                print_error "Azure CLI is not installed"
                exit 1
            fi
            ;;
        gcp)
            if ! command -v gcloud >/dev/null 2>&1; then
                print_error "Google Cloud SDK is not installed"
                exit 1
            fi
            ;;
    esac
    
    print_success "Prerequisites check passed"
}

# Function to configure cloud provider
configure_cloud_provider() {
    local cloud_provider=$1
    
    print_status "Configuring $cloud_provider..."
    
    case $cloud_provider in
        aws)
            # Check AWS credentials
            if ! aws sts get-caller-identity >/dev/null 2>&1; then
                print_warning "AWS credentials not configured"
                print_status "Please run: aws configure"
                exit 1
            fi
            print_success "AWS credentials configured"
            ;;
        azure)
            # Check Azure login
            if ! az account show >/dev/null 2>&1; then
                print_warning "Azure not logged in"
                print_status "Please run: az login"
                exit 1
            fi
            print_success "Azure logged in"
            ;;
        gcp)
            # Check GCP auth
            if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
                print_warning "GCP not authenticated"
                print_status "Please run: gcloud auth login"
                exit 1
            fi
            print_success "GCP authenticated"
            ;;
    esac
}

# Function to load environment variables
load_env_vars() {
    local environment=$1
    
    print_status "Loading environment variables..."
    
    # Load .env file if it exists
    if [ -f ".env" ]; then
        export $(cat .env | grep -v '^#' | xargs)
        print_success "Loaded .env file"
    fi
    
    # Set environment-specific variables
    export TF_VAR_environment=$environment
    export TF_VAR_project_name="projeto-vm"
    
    print_success "Environment variables loaded"
}

# Function to run Terraform commands
run_terraform() {
    local cloud_provider=$1
    local environment=$2
    local action=$3
    local plan_only=$4
    local force=$5
    
    local terraform_dir="terraform/$cloud_provider"
    local var_file="environments/${environment}.tfvars"
    
    print_status "Running Terraform in $terraform_dir..."
    
    # Change to Terraform directory
    cd "$terraform_dir"
    
    # Initialize Terraform
    print_status "Initializing Terraform..."
    terraform init
    
    # Format and validate
    print_status "Formatting Terraform code..."
    terraform fmt -recursive
    
    print_status "Validating Terraform code..."
    terraform validate
    
    case $action in
        deploy)
            if [ "$plan_only" = "true" ]; then
                print_status "Running Terraform plan..."
                terraform plan -var-file="$var_file" -out=tfplan
                print_success "Plan completed. Review the plan above."
            else
                print_status "Running Terraform plan..."
                terraform plan -var-file="$var_file" -out=tfplan
                
                if [ "$force" != "true" ]; then
                    echo ""
                    read -p "Do you want to apply this plan? (y/N): " -n 1 -r
                    echo ""
                    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                        print_warning "Deployment cancelled"
                        exit 0
                    fi
                fi
                
                print_status "Applying Terraform plan..."
                terraform apply -auto-approve tfplan
                print_success "Deployment completed successfully!"
            fi
            ;;
        destroy)
            if [ "$force" != "true" ]; then
                echo ""
                print_warning "This will DESTROY all infrastructure in $environment environment!"
                read -p "Are you sure you want to continue? (y/N): " -n 1 -r
                echo ""
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    print_warning "Destruction cancelled"
                    exit 0
                fi
            fi
            
            print_status "Destroying infrastructure..."
            terraform destroy -var-file="$var_file" -auto-approve
            print_success "Infrastructure destroyed successfully!"
            ;;
    esac
    
    # Return to original directory
    cd - > /dev/null
}

# Function to run post-deployment tests
run_tests() {
    local cloud_provider=$1
    local environment=$2
    
    print_status "Running post-deployment tests..."
    
    # Get outputs from Terraform
    cd "terraform/$cloud_provider"
    
    # Wait for instances to be ready
    print_status "Waiting for instances to be ready..."
    sleep 30
    
    # Test endpoints if available
    if command -v curl >/dev/null 2>&1; then
        # Get load balancer DNS or instance IPs
        local endpoint=""
        
        case $cloud_provider in
            aws)
                endpoint=$(terraform output -raw load_balancer_dns 2>/dev/null || echo "")
                ;;
            azure)
                endpoint=$(terraform output -raw load_balancer_ip 2>/dev/null || echo "")
                ;;
            gcp)
                endpoint=$(terraform output -raw load_balancer_ip 2>/dev/null || echo "")
                ;;
        esac
        
        if [ -n "$endpoint" ]; then
            print_status "Testing endpoint: $endpoint"
            
            # Test health endpoint
            if curl -f -s "http://$endpoint/health" >/dev/null 2>&1; then
                print_success "Health check passed"
            else
                print_warning "Health check failed"
            fi
            
            # Test main endpoint
            if curl -f -s "http://$endpoint/" >/dev/null 2>&1; then
                print_success "Main endpoint test passed"
            else
                print_warning "Main endpoint test failed"
            fi
        else
            print_warning "No endpoint found for testing"
        fi
    else
        print_warning "curl not available, skipping endpoint tests"
    fi
    
    cd - > /dev/null
}

# Function to show deployment summary
show_summary() {
    local cloud_provider=$1
    local environment=$2
    local action=$3
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  DEPLOYMENT SUMMARY${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Cloud Provider: $cloud_provider"
    echo "Environment: $environment"
    echo "Action: $action"
    echo "Timestamp: $(date)"
    echo ""
    
    if [ "$action" = "deploy" ]; then
        echo -e "${BLUE}Next steps:${NC}"
        echo "1. Monitor the deployment in your cloud console"
        echo "2. Check application logs"
        echo "3. Run integration tests"
        echo "4. Update monitoring dashboards"
    fi
    
    echo ""
    echo -e "${YELLOW}For more information, see the documentation${NC}"
}

# Main execution
main() {
    # Parse arguments
    local cloud_provider=""
    local environment=""
    local plan_only=false
    local destroy=false
    local force=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --plan-only)
                plan_only=true
                shift
                ;;
            --destroy)
                destroy=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            -*)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                if [ -z "$cloud_provider" ]; then
                    cloud_provider=$1
                elif [ -z "$environment" ]; then
                    environment=$1
                else
                    print_error "Too many arguments"
                    show_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Check required arguments
    if [ -z "$cloud_provider" ] || [ -z "$environment" ]; then
        print_error "Missing required arguments"
        show_usage
        exit 1
    fi
    
    # Validate arguments
    validate_args "$cloud_provider" "$environment"
    
    # Determine action
    local action="deploy"
    if [ "$destroy" = "true" ]; then
        action="destroy"
    fi
    
    # Show deployment info
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  PROJETO VM - DEPLOYMENT${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "Cloud Provider: $cloud_provider"
    echo "Environment: $environment"
    echo "Action: $action"
    if [ "$plan_only" = "true" ]; then
        echo "Mode: Plan only"
    fi
    if [ "$force" = "true" ]; then
        echo "Mode: Force (no confirmation)"
    fi
    echo ""
    
    # Check prerequisites
    check_prerequisites "$cloud_provider"
    
    # Configure cloud provider
    configure_cloud_provider "$cloud_provider"
    
    # Load environment variables
    load_env_vars "$environment"
    
    # Run Terraform
    run_terraform "$cloud_provider" "$environment" "$action" "$plan_only" "$force"
    
    # Run tests if deploying
    if [ "$action" = "deploy" ] && [ "$plan_only" != "true" ]; then
        run_tests "$cloud_provider" "$environment"
    fi
    
    # Show summary
    show_summary "$cloud_provider" "$environment" "$action"
}

# Run main function
main "$@" 