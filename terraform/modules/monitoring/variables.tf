# Monitoring Module Variables

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "cloud_provider" {
  description = "Cloud provider (aws, azure, gcp)"
  type        = string
  validation {
    condition     = contains(["aws", "azure", "gcp"], var.cloud_provider)
    error_message = "Cloud provider must be one of: aws, azure, gcp."
  }
}

variable "cluster_name" {
  description = "Kubernetes cluster name"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for monitoring"
  type        = string
  default     = "monitoring"
}

variable "prometheus_retention_days" {
  description = "Prometheus data retention in days"
  type        = number
  default     = 15
  validation {
    condition     = var.prometheus_retention_days >= 1 && var.prometheus_retention_days <= 365
    error_message = "Prometheus retention must be between 1 and 365 days."
  }
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.grafana_admin_password) >= 8
    error_message = "Grafana admin password must be at least 8 characters long."
  }
}

variable "alert_manager_config" {
  description = "AlertManager configuration"
  type = object({
    slack_webhook_url = optional(string)
    email_smtp_host   = optional(string)
    email_smtp_port   = optional(number)
    email_from        = optional(string)
    email_to          = optional(list(string))
  })
  default = {}
}

variable "enable_ingress" {
  description = "Enable ingress for Grafana"
  type        = bool
  default     = false
}

variable "domain" {
  description = "Domain for ingress (required if enable_ingress is true)"
  type        = string
  default     = ""
}

# AWS-specific variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

# Azure-specific variables
variable "resource_group_name" {
  description = "Azure resource group name"
  type        = string
  default     = ""
}

variable "location" {
  description = "Azure location"
  type        = string
  default     = "East US"
}

# GCP-specific variables
variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
  default     = ""
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

# Monitoring configuration
variable "enable_node_exporter" {
  description = "Enable Node Exporter for system metrics"
  type        = bool
  default     = true
}

variable "enable_kube_state_metrics" {
  description = "Enable kube-state-metrics for Kubernetes metrics"
  type        = bool
  default     = true
}

variable "enable_blackbox_exporter" {
  description = "Enable Blackbox Exporter for endpoint monitoring"
  type        = bool
  default     = true
}

variable "storage_class" {
  description = "Storage class for persistent volumes"
  type        = string
  default     = "standard"
}

variable "monitoring_resources" {
  description = "Resource limits for monitoring components"
  type = object({
    prometheus = object({
      cpu_request    = string
      memory_request = string
      cpu_limit      = string
      memory_limit   = string
    })
    grafana = object({
      cpu_request    = string
      memory_request = string
      cpu_limit      = string
      memory_limit   = string
    })
    alertmanager = object({
      cpu_request    = string
      memory_request = string
      cpu_limit      = string
      memory_limit   = string
    })
  })
  default = {
    prometheus = {
      cpu_request    = "500m"
      memory_request = "2Gi"
      cpu_limit      = "1000m"
      memory_limit   = "4Gi"
    }
    grafana = {
      cpu_request    = "250m"
      memory_request = "512Mi"
      cpu_limit      = "500m"
      memory_limit   = "1Gi"
    }
    alertmanager = {
      cpu_request    = "100m"
      memory_request = "256Mi"
      cpu_limit      = "200m"
      memory_limit   = "512Mi"
    }
  }
}

variable "retention_policy" {
  description = "Data retention policy configuration"
  type = object({
    prometheus_retention = string
    grafana_retention    = string
    logs_retention       = number
  })
  default = {
    prometheus_retention = "15d"
    grafana_retention    = "30d"
    logs_retention       = 30
  }
}

variable "backup_config" {
  description = "Backup configuration for monitoring data"
  type = object({
    enabled           = bool
    schedule          = string
    retention_days    = number
    storage_location  = string
  })
  default = {
    enabled          = false
    schedule         = "0 2 * * *"  # Daily at 2 AM
    retention_days   = 30
    storage_location = ""
  }
} 