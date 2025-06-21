# ML/AI Module Variables

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
  description = "Kubernetes namespace for ML/AI components"
  type        = string
  default     = "ml-ai"
}

variable "enable_anomaly_detection" {
  description = "Enable anomaly detection service"
  type        = bool
  default     = true
}

variable "enable_predictive_scaling" {
  description = "Enable predictive scaling service"
  type        = bool
  default     = true
}

variable "enable_intelligent_monitoring" {
  description = "Enable intelligent monitoring service"
  type        = bool
  default     = true
}

variable "enable_cost_optimization" {
  description = "Enable cost optimization service"
  type        = bool
  default     = true
}

# AWS-specific variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "vpc_id" {
  description = "VPC ID for SageMaker domain"
  type        = string
  default     = ""
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for SageMaker domain"
  type        = list(string)
  default     = []
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

variable "azure_subscription_id" {
  description = "Azure subscription ID"
  type        = string
  default     = ""
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

# ML/AI Configuration
variable "ml_model_config" {
  description = "ML model configuration"
  type = object({
    algorithm = string
    version   = string
    parameters = map(string)
  })
  default = {
    algorithm = "isolation_forest"
    version   = "1.0"
    parameters = {
      contamination = "0.1"
      random_state  = "42"
    }
  }
}

variable "anomaly_detection_config" {
  description = "Anomaly detection configuration"
  type = object({
    sensitivity = number
    window_size = string
    threshold   = number
  })
  default = {
    sensitivity = 0.8
    window_size = "5m"
    threshold   = 0.7
  }
  validation {
    condition     = var.anomaly_detection_config.sensitivity >= 0 && var.anomaly_detection_config.sensitivity <= 1
    error_message = "Sensitivity must be between 0 and 1."
  }
}

variable "predictive_scaling_config" {
  description = "Predictive scaling configuration"
  type = object({
    prediction_horizon = string
    min_replicas      = number
    max_replicas      = number
    scale_up_threshold = number
    scale_down_threshold = number
  })
  default = {
    prediction_horizon = "30m"
    min_replicas      = 1
    max_replicas      = 10
    scale_up_threshold = 0.7
    scale_down_threshold = 0.3
  }
}

variable "intelligent_monitoring_config" {
  description = "Intelligent monitoring configuration"
  type = object({
    log_analysis_enabled = bool
    trace_analysis_enabled = bool
    performance_analysis_enabled = bool
    alert_correlation_enabled = bool
  })
  default = {
    log_analysis_enabled = true
    trace_analysis_enabled = true
    performance_analysis_enabled = true
    alert_correlation_enabled = true
  }
}

variable "cost_optimization_config" {
  description = "Cost optimization configuration"
  type = object({
    auto_scaling_enabled = bool
    spot_instances_enabled = bool
    resource_rightsizing_enabled = bool
    idle_resource_cleanup_enabled = bool
    budget_alerts_enabled = bool
  })
  default = {
    auto_scaling_enabled = true
    spot_instances_enabled = true
    resource_rightsizing_enabled = true
    idle_resource_cleanup_enabled = true
    budget_alerts_enabled = true
  }
}

variable "ml_resources" {
  description = "Resource limits for ML/AI components"
  type = object({
    anomaly_detector = object({
      cpu_request    = string
      memory_request = string
      cpu_limit      = string
      memory_limit   = string
    })
    predictive_scaler = object({
      cpu_request    = string
      memory_request = string
      cpu_limit      = string
      memory_limit   = string
    })
    intelligent_monitor = object({
      cpu_request    = string
      memory_request = string
      cpu_limit      = string
      memory_limit   = string
    })
    cost_optimizer = object({
      cpu_request    = string
      memory_request = string
      cpu_limit      = string
      memory_limit   = string
    })
    dashboard = object({
      cpu_request    = string
      memory_request = string
      cpu_limit      = string
      memory_limit   = string
    })
  })
  default = {
    anomaly_detector = {
      cpu_request    = "500m"
      memory_request = "1Gi"
      cpu_limit      = "1000m"
      memory_limit   = "2Gi"
    }
    predictive_scaler = {
      cpu_request    = "500m"
      memory_request = "1Gi"
      cpu_limit      = "1000m"
      memory_limit   = "2Gi"
    }
    intelligent_monitor = {
      cpu_request    = "500m"
      memory_request = "1Gi"
      cpu_limit      = "1000m"
      memory_limit   = "2Gi"
    }
    cost_optimizer = {
      cpu_request    = "250m"
      memory_request = "512Mi"
      cpu_limit      = "500m"
      memory_limit   = "1Gi"
    }
    dashboard = {
      cpu_request    = "250m"
      memory_request = "512Mi"
      cpu_limit      = "500m"
      memory_limit   = "1Gi"
    }
  }
}

variable "data_retention" {
  description = "Data retention configuration for ML/AI"
  type = object({
    training_data_retention = string
    model_artifacts_retention = string
    predictions_retention = string
    logs_retention = string
  })
  default = {
    training_data_retention = "90d"
    model_artifacts_retention = "365d"
    predictions_retention = "30d"
    logs_retention = "60d"
  }
}

variable "model_training_config" {
  description = "Model training configuration"
  type = object({
    auto_retrain_enabled = bool
    retrain_interval = string
    model_evaluation_threshold = number
    feature_store_enabled = bool
  })
  default = {
    auto_retrain_enabled = true
    retrain_interval = "7d"
    model_evaluation_threshold = 0.8
    feature_store_enabled = true
  }
}

variable "security_config" {
  description = "Security configuration for ML/AI"
  type = object({
    encryption_enabled = bool
    network_isolation_enabled = bool
    audit_logging_enabled = bool
    data_governance_enabled = bool
  })
  default = {
    encryption_enabled = true
    network_isolation_enabled = true
    audit_logging_enabled = true
    data_governance_enabled = true
  }
}

variable "monitoring_endpoints" {
  description = "Monitoring endpoints configuration"
  type = object({
    prometheus_url = string
    grafana_url = string
    elasticsearch_url = string
    jaeger_url = string
  })
  default = {
    prometheus_url = "http://prometheus-operated:9090"
    grafana_url = "http://grafana:3000"
    elasticsearch_url = "http://elasticsearch-master:9200"
    jaeger_url = "http://jaeger-query:16686"
  }
} 