# =============================================================================
# AWS INFRASTRUCTURE - PROJETO VM
# =============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "projeto-vm-terraform-state"
    key            = "aws/dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

# =============================================================================
# PROVIDERS
# =============================================================================

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "DevOps Team"
    }
  }
}

# =============================================================================
# VARIABLES
# =============================================================================

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "projeto-vm"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "instance_count" {
  description = "Number of EC2 instances"
  type        = number
  default     = 2
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}

# =============================================================================
# DATA SOURCES
# =============================================================================

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# =============================================================================
# NETWORK MODULE
# =============================================================================

module "network" {
  source = "../modules/network"

  cloud_provider = "aws"
  project_name   = var.project_name
  environment    = var.environment
  vpc_cidr       = var.vpc_cidr

  subnets = {
    public-1 = {
      cidr_block = "10.0.1.0/24"
      az         = data.aws_availability_zones.available.names[0]
      public     = true
    }
    private-1 = {
      cidr_block = "10.0.2.0/24"
      az         = data.aws_availability_zones.available.names[0]
      public     = false
    }
    public-2 = {
      cidr_block = "10.0.3.0/24"
      az         = data.aws_availability_zones.available.names[1]
      public     = true
    }
    private-2 = {
      cidr_block = "10.0.4.0/24"
      az         = data.aws_availability_zones.available.names[1]
      public     = false
    }
  }

  tags = var.tags
}

# =============================================================================
# COMPUTE MODULE
# =============================================================================

module "compute" {
  source = "../modules/compute"

  cloud_provider = "aws"
  project_name   = var.project_name
  environment    = var.environment
  vpc_id         = module.network.vpc_id
  subnet_ids     = module.network.subnet_ids

  instance_type  = var.instance_type
  instance_count = var.instance_count

  user_data = templatefile("${path.module}/user_data.sh", {
    project_name = var.project_name
    environment  = var.environment
  })

  tags = var.tags
}

# =============================================================================
# DATABASE MODULE (RDS)
# =============================================================================

module "database" {
  source = "../modules/database"

  cloud_provider = "aws"
  project_name   = var.project_name
  environment    = var.environment
  vpc_id         = module.network.vpc_id
  subnet_ids     = module.network.private_subnet_ids

  engine         = "postgres"
  engine_version = "14.10"
  instance_class = "db.t3.micro"
  allocated_storage = 20

  database_name = "projetovm"
  username      = "admin"
  password      = var.db_password

  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"

  tags = var.tags
}

# =============================================================================
# LOAD BALANCER MODULE
# =============================================================================

module "load_balancer" {
  source = "../modules/load_balancer"

  cloud_provider = "aws"
  project_name   = var.project_name
  environment    = var.environment
  vpc_id         = module.network.vpc_id
  subnet_ids     = module.network.public_subnet_ids

  target_instance_ids = module.compute.instance_ids
  target_instance_ips = module.compute.instance_private_ips

  health_check_path = "/health"
  health_check_port = 80

  tags = var.tags
}

# =============================================================================
# MONITORING MODULE
# =============================================================================

module "monitoring" {
  source = "../modules/monitoring"

  cloud_provider = "aws"
  project_name   = var.project_name
  environment    = var.environment

  log_group_name = "/aws/ec2/${var.project_name}-${var.environment}"
  retention_days = 30

  alarm_email = var.alarm_email

  tags = var.tags
}

# =============================================================================
# OUTPUTS
# =============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = module.network.vpc_id
}

output "subnet_ids" {
  description = "Subnet IDs"
  value       = module.network.subnet_ids
}

output "instance_ids" {
  description = "EC2 instance IDs"
  value       = module.compute.instance_ids
}

output "instance_public_ips" {
  description = "EC2 instance public IPs"
  value       = module.compute.instance_public_ips
}

output "load_balancer_dns" {
  description = "Load balancer DNS name"
  value       = module.load_balancer.dns_name
}

output "database_endpoint" {
  description = "RDS endpoint"
  value       = module.database.endpoint
  sensitive   = true
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group"
  value       = module.monitoring.log_group_name
} 