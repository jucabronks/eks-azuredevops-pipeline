#!/bin/bash

# =============================================================================
# SETUP SCRIPT - PROJETO VM
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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install package
install_package() {
    local package=$1
    if ! command_exists $package; then
        print_status "Installing $package..."
        case "$(uname -s)" in
            Linux*)
                if command_exists apt-get; then
                    sudo apt-get update && sudo apt-get install -y $package
                elif command_exists yum; then
                    sudo yum install -y $package
                elif command_exists dnf; then
                    sudo dnf install -y $package
                else
                    print_error "Package manager not found. Please install $package manually."
                    return 1
                fi
                ;;
            Darwin*)
                if command_exists brew; then
                    brew install $package
                else
                    print_error "Homebrew not found. Please install $package manually."
                    return 1
                fi
                ;;
            MINGW*|MSYS*|CYGWIN*)
                print_error "Windows detected. Please install $package manually."
                return 1
                ;;
        esac
    else
        print_success "$package is already installed"
    fi
}

# Function to check and install Terraform
setup_terraform() {
    print_status "Setting up Terraform..."
    
    if ! command_exists terraform; then
        print_status "Installing Terraform..."
        
        # Download and install Terraform
        local tf_version="1.5.0"
        local os=$(uname -s | tr '[:upper:]' '[:lower:]')
        local arch=$(uname -m)
        
        if [ "$arch" = "x86_64" ]; then
            arch="amd64"
        elif [ "$arch" = "aarch64" ]; then
            arch="arm64"
        fi
        
        local tf_url="https://releases.hashicorp.com/terraform/${tf_version}/terraform_${tf_version}_${os}_${arch}.zip"
        local tf_zip="terraform.zip"
        
        curl -L -o $tf_zip $tf_url
        unzip $tf_zip
        sudo mv terraform /usr/local/bin/
        rm $tf_zip
        
        print_success "Terraform ${tf_version} installed successfully"
    else
        local current_version=$(terraform version -json | jq -r '.terraform_version')
        print_success "Terraform ${current_version} is already installed"
    fi
}

# Function to setup cloud providers
setup_cloud_providers() {
    print_status "Setting up cloud providers..."
    
    # AWS CLI
    if ! command_exists aws; then
        print_status "Installing AWS CLI..."
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip awscliv2.zip
        sudo ./aws/install
        rm -rf aws awscliv2.zip
        print_success "AWS CLI installed successfully"
    else
        print_success "AWS CLI is already installed"
    fi
    
    # Azure CLI
    if ! command_exists az; then
        print_status "Installing Azure CLI..."
        curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
        print_success "Azure CLI installed successfully"
    else
        print_success "Azure CLI is already installed"
    fi
    
    # Google Cloud SDK
    if ! command_exists gcloud; then
        print_status "Installing Google Cloud SDK..."
        curl https://sdk.cloud.google.com | bash
        exec -l $SHELL
        print_success "Google Cloud SDK installed successfully"
    else
        print_success "Google Cloud SDK is already installed"
    fi
}

# Function to setup development tools
setup_dev_tools() {
    print_status "Setting up development tools..."
    
    # Install essential packages
    local packages=("git" "curl" "wget" "jq" "unzip" "docker" "docker-compose" "kubectl")
    
    for package in "${packages[@]}"; do
        install_package $package
    done
    
    # Setup Docker
    if command_exists docker; then
        sudo usermod -aG docker $USER
        sudo systemctl enable docker
        sudo systemctl start docker
        print_success "Docker configured successfully"
    fi
}

# Function to setup project structure
setup_project_structure() {
    print_status "Setting up project structure..."
    
    # Create directories if they don't exist
    local directories=(
        "terraform/aws"
        "terraform/azure"
        "terraform/gcp"
        "terraform/modules"
        "kubernetes"
        "scripts"
        "docs"
        "environments"
        ".github/workflows"
    )
    
    for dir in "${directories[@]}"; do
        mkdir -p "$dir"
        print_status "Created directory: $dir"
    done
    
    # Create environment files
    if [ ! -f "environments/dev.tfvars" ]; then
        cat > environments/dev.tfvars << 'EOF'
# Development Environment Variables
environment = "dev"
instance_type = "t3.micro"
instance_count = 2
vpc_cidr = "10.0.0.0/16"

# Tags
tags = {
  Environment = "dev"
  Project     = "projeto-vm"
  Owner       = "DevOps Team"
  CostCenter  = "IT"
}
EOF
        print_success "Created environments/dev.tfvars"
    fi
    
    if [ ! -f "environments/staging.tfvars" ]; then
        cat > environments/staging.tfvars << 'EOF'
# Staging Environment Variables
environment = "staging"
instance_type = "t3.small"
instance_count = 3
vpc_cidr = "10.1.0.0/16"

# Tags
tags = {
  Environment = "staging"
  Project     = "projeto-vm"
  Owner       = "DevOps Team"
  CostCenter  = "IT"
}
EOF
        print_success "Created environments/staging.tfvars"
    fi
    
    if [ ! -f "environments/prod.tfvars" ]; then
        cat > environments/prod.tfvars << 'EOF'
# Production Environment Variables
environment = "prod"
instance_type = "t3.medium"
instance_count = 4
vpc_cidr = "10.2.0.0/16"

# Tags
tags = {
  Environment = "production"
  Project     = "projeto-vm"
  Owner       = "DevOps Team"
  CostCenter  = "IT"
}
EOF
        print_success "Created environments/prod.tfvars"
    fi
}

# Function to setup Git hooks
setup_git_hooks() {
    print_status "Setting up Git hooks..."
    
    if [ -d ".git" ]; then
        # Create pre-commit hook
        cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash

# Pre-commit hook for Terraform validation
echo "Running pre-commit checks..."

# Check for Terraform files
if git diff --cached --name-only | grep -E '\.tf$|\.tfvars$'; then
    echo "Terraform files detected, running validation..."
    
    # Find all Terraform directories
    for dir in terraform/*/; do
        if [ -d "$dir" ]; then
            echo "Validating $dir..."
            cd "$dir"
            terraform fmt -check -recursive
            terraform init -backend=false
            terraform validate
            cd - > /dev/null
        fi
    done
fi

echo "Pre-commit checks completed."
EOF
        
        chmod +x .git/hooks/pre-commit
        print_success "Git hooks configured successfully"
    else
        print_warning "Git repository not found. Skipping Git hooks setup."
    fi
}

# Function to setup environment variables
setup_env_vars() {
    print_status "Setting up environment variables..."
    
    if [ ! -f ".env" ]; then
        if [ -f "env.example" ]; then
            cp env.example .env
            print_warning "Please edit .env file with your actual credentials"
        else
            print_error "env.example not found. Please create .env file manually."
        fi
    else
        print_success ".env file already exists"
    fi
}

# Function to validate setup
validate_setup() {
    print_status "Validating setup..."
    
    local errors=0
    
    # Check required tools
    local tools=("terraform" "aws" "az" "gcloud" "git" "docker")
    
    for tool in "${tools[@]}"; do
        if command_exists $tool; then
            print_success "$tool is available"
        else
            print_error "$tool is not available"
            ((errors++))
        fi
    done
    
    # Check project structure
    local required_dirs=("terraform" "scripts" "environments" ".github/workflows")
    
    for dir in "${required_dirs[@]}"; do
        if [ -d "$dir" ]; then
            print_success "Directory $dir exists"
        else
            print_error "Directory $dir is missing"
            ((errors++))
        fi
    done
    
    if [ $errors -eq 0 ]; then
        print_success "Setup validation completed successfully!"
    else
        print_error "Setup validation failed with $errors errors"
        return 1
    fi
}

# Function to display next steps
show_next_steps() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  SETUP COMPLETED SUCCESSFULLY!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. Edit .env file with your cloud provider credentials"
    echo "2. Configure your cloud providers:"
    echo "   - AWS: aws configure"
    echo "   - Azure: az login"
    echo "   - GCP: gcloud auth login"
    echo "3. Initialize Terraform backends:"
    echo "   - cd terraform/aws && terraform init"
    echo "   - cd terraform/azure && terraform init"
    echo "   - cd terraform/gcp && terraform init"
    echo "4. Test deployment:"
    echo "   - ./scripts/deploy.sh aws dev"
    echo ""
    echo -e "${YELLOW}For more information, see the README.md file${NC}"
}

# Main execution
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  PROJETO VM - SETUP SCRIPT${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        print_error "Please do not run this script as root"
        exit 1
    fi
    
    # Update system packages
    print_status "Updating system packages..."
    if command_exists apt-get; then
        sudo apt-get update
    fi
    
    # Setup components
    setup_terraform
    setup_cloud_providers
    setup_dev_tools
    setup_project_structure
    setup_git_hooks
    setup_env_vars
    
    # Validate setup
    validate_setup
    
    # Show next steps
    show_next_steps
}

# Run main function
main "$@" 