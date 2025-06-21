# =============================================================================
# TERRAFORM VERSIONS - PROJETO VM
# =============================================================================

terraform {
  required_version = ">= 1.12.2"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.45"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.95"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.25"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    template = {
      source  = "hashicorp/template"
      version = "~> 2.3"
    }
  }
} 