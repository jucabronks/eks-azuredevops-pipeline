# ML/AI Module for DevOps Automation
# Anomaly Detection, Predictive Scaling, Intelligent Monitoring

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

# Variables
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "cloud_provider" {
  description = "Cloud provider (aws, azure, gcp)"
  type        = string
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
  description = "Enable anomaly detection"
  type        = bool
  default     = true
}

variable "enable_predictive_scaling" {
  description = "Enable predictive scaling"
  type        = bool
  default     = true
}

variable "enable_intelligent_monitoring" {
  description = "Enable intelligent monitoring"
  type        = bool
  default     = true
}

variable "enable_cost_optimization" {
  description = "Enable cost optimization"
  type        = bool
  default     = true
}

variable "enable_intelligent_rollback" {
  description = "Enable intelligent rollback"
  type        = bool
  default     = true
}

# AWS SageMaker Configuration
resource "aws_sagemaker_domain" "ml_domain" {
  count = var.cloud_provider == "aws" ? 1 : 0
  domain_name = "${var.cluster_name}-ml-domain"
  auth_mode   = "IAM"
  vpc_id      = var.vpc_id
  subnet_ids  = var.private_subnet_ids

  default_user_settings {
    execution_role = aws_iam_role.sagemaker_execution[0].arn

    jupyter_server_app_settings {
      default_resource_spec {
        instance_type       = "ml.t3.medium"
        sagemaker_image_arn = "arn:aws:sagemaker:${var.aws_region}:474416919596:image/sagemaker-data-science-38"
      }
    }
  }

  tags = {
    Environment = var.environment
    Cluster     = var.cluster_name
  }
}

resource "aws_iam_role" "sagemaker_execution" {
  count = var.cloud_provider == "aws" ? 1 : 0
  name  = "${var.cluster_name}-sagemaker-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sagemaker_full_access" {
  count      = var.cloud_provider == "aws" ? 1 : 0
  role       = aws_iam_role.sagemaker_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

# Azure Machine Learning Workspace
resource "azurerm_machine_learning_workspace" "ml_workspace" {
  count               = var.cloud_provider == "azure" ? 1 : 0
  name                = "${var.cluster_name}-ml-workspace"
  location            = data.azurerm_resource_group.main[0].location
  resource_group_name = data.azurerm_resource_group.main[0].name
  application_insights_id = azurerm_application_insights.ml_insights[0].id
  key_vault_id        = azurerm_key_vault.ml_keyvault[0].id
  storage_account_id  = azurerm_storage_account.ml_storage[0].id

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Environment = var.environment
    Cluster     = var.cluster_name
  }
}

resource "azurerm_application_insights" "ml_insights" {
  count               = var.cloud_provider == "azure" ? 1 : 0
  name                = "${var.cluster_name}-ml-insights"
  location            = data.azurerm_resource_group.main[0].location
  resource_group_name = data.azurerm_resource_group.main[0].name
  application_type    = "web"
}

resource "azurerm_key_vault" "ml_keyvault" {
  count               = var.cloud_provider == "azure" ? 1 : 0
  name                = "${var.cluster_name}-ml-kv"
  location            = data.azurerm_resource_group.main[0].location
  resource_group_name = data.azurerm_resource_group.main[0].name
  tenant_id           = data.azurerm_client_config.current[0].tenant_id
  sku_name            = "standard"
}

resource "azurerm_storage_account" "ml_storage" {
  count               = var.cloud_provider == "azure" ? 1 : 0
  name                = "${var.cluster_name}mlstorage"
  location            = data.azurerm_resource_group.main[0].location
  resource_group_name = data.azurerm_resource_group.main[0].name
  account_tier        = "Standard"
  account_replication_type = "LRS"
}

data "azurerm_resource_group" "main" {
  count = var.cloud_provider == "azure" ? 1 : 0
  name  = var.resource_group_name
}

data "azurerm_client_config" "current" {
  count = var.cloud_provider == "azure" ? 1 : 0
}

# GCP AI Platform
resource "google_ai_platform_dataset" "ml_dataset" {
  count   = var.cloud_provider == "gcp" ? 1 : 0
  name    = "${var.cluster_name}-ml-dataset"
  project = var.gcp_project_id
  region  = var.gcp_region
  display_name = "ML Dataset for ${var.cluster_name}"
}

resource "google_ai_platform_model" "ml_model" {
  count   = var.cloud_provider == "gcp" ? 1 : 0
  name    = "${var.cluster_name}-ml-model"
  project = var.gcp_project_id
  region  = var.gcp_region
  description = "ML model for ${var.cluster_name}"

  default_version {
    name = "v1"
  }
}

# Kubernetes Namespace for ML/AI
resource "kubernetes_namespace" "ml_ai" {
  metadata {
    name = var.namespace
    labels = {
      name        = var.namespace
      environment = var.environment
    }
  }
}

# Intelligent Rollback Service
resource "kubernetes_deployment" "intelligent_rollback" {
  count = var.enable_intelligent_rollback ? 1 : 0

  metadata {
    name      = "intelligent-rollback"
    namespace = var.namespace
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "intelligent-rollback"
      }
    }

    template {
      metadata {
        labels = {
          app = "intelligent-rollback"
        }
      }

      spec {
        container {
          name  = "intelligent-rollback"
          image = "ml-ai/intelligent-rollback:latest"

          port {
            container_port = 8080
          }

          env {
            name  = "KUBERNETES_API"
            value = "https://kubernetes.default.svc"
          }

          env {
            name  = "PROMETHEUS_URL"
            value = "http://prometheus-operated:9090"
          }

          env {
            name  = "ALERTMANAGER_URL"
            value = "http://alertmanager-operated:9093"
          }

          env {
            name  = "CLOUD_PROVIDER"
            value = var.cloud_provider
          }

          env {
            name  = "ROLLBACK_THRESHOLD"
            value = "0.8"
          }

          env {
            name  = "HEALTH_CHECK_TIMEOUT"
            value = "300"
          }

          env {
            name  = "ERROR_THRESHOLD"
            value = "5"
          }

          resources {
            limits = {
              cpu    = "1000m"
              memory = "2Gi"
            }
            requests = {
              cpu    = "500m"
              memory = "1Gi"
            }
          }

          # Health checks
          liveness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/ready"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 5
            timeout_seconds       = 3
            failure_threshold     = 3
          }
        }

        service_account_name = kubernetes_service_account.ml_ai.metadata[0].name
      }
    }
  }

  depends_on = [kubernetes_namespace.ml_ai]
}

# Intelligent Rollback Service
resource "kubernetes_service" "intelligent_rollback" {
  count = var.enable_intelligent_rollback ? 1 : 0

  metadata {
    name      = "intelligent-rollback"
    namespace = var.namespace
  }

  spec {
    selector = {
      app = "intelligent-rollback"
    }

    port {
      port        = 8080
      target_port = 8080
    }

    type = "ClusterIP"
  }

  depends_on = [kubernetes_namespace.ml_ai]
}

# Rollback Webhook
resource "kubernetes_manifest" "rollback_webhook" {
  count = var.enable_intelligent_rollback ? 1 : 0

  manifest = {
    api_version = "admissionregistration.k8s.io/v1"
    kind       = "ValidatingWebhookConfiguration"
    metadata = {
      name = "intelligent-rollback-webhook"
    }
    webhooks = [
      {
        name = "rollback.kubernetes.io"
        client_config = {
          service = {
            namespace = var.namespace
            name     = "intelligent-rollback"
            path     = "/validate"
            port     = 8080
          }
        }
        rules = [
          {
            api_groups   = ["apps"]
            api_versions = ["v1"]
            operations  = ["UPDATE"]
            resources   = ["deployments"]
          }
        ]
        admission_review_versions = ["v1"]
        side_effects             = "None"
        timeout_seconds          = 5
      }
    ]
  }

  depends_on = [kubernetes_service.intelligent_rollback]
}

# Anomaly Detection Service
resource "kubernetes_deployment" "anomaly_detector" {
  count = var.enable_anomaly_detection ? 1 : 0

  metadata {
    name      = "anomaly-detector"
    namespace = var.namespace
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "anomaly-detector"
      }
    }

    template {
      metadata {
        labels = {
          app = "anomaly-detector"
        }
      }

      spec {
        container {
          name  = "anomaly-detector"
          image = "ml-ai/anomaly-detector:latest"

          port {
            container_port = 8080
          }

          env {
            name  = "PROMETHEUS_URL"
            value = "http://prometheus-operated:9090"
          }

          env {
            name  = "ALERTMANAGER_URL"
            value = "http://alertmanager-operated:9093"
          }

          env {
            name  = "CLOUD_PROVIDER"
            value = var.cloud_provider
          }

          resources {
            limits = {
              cpu    = "1000m"
              memory = "2Gi"
            }
            requests = {
              cpu    = "500m"
              memory = "1Gi"
            }
          }
        }

        service_account_name = kubernetes_service_account.ml_ai.metadata[0].name
      }
    }
  }

  depends_on = [kubernetes_namespace.ml_ai]
}

# Predictive Scaling Service
resource "kubernetes_deployment" "predictive_scaler" {
  count = var.enable_predictive_scaling ? 1 : 0

  metadata {
    name      = "predictive-scaler"
    namespace = var.namespace
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "predictive-scaler"
      }
    }

    template {
      metadata {
        labels = {
          app = "predictive-scaler"
        }
      }

      spec {
        container {
          name  = "predictive-scaler"
          image = "ml-ai/predictive-scaler:latest"

          port {
            container_port = 8080
          }

          env {
            name  = "KUBERNETES_API"
            value = "https://kubernetes.default.svc"
          }

          env {
            name  = "METRICS_SERVER"
            value = "http://metrics-server:4443"
          }

          env {
            name  = "CLOUD_PROVIDER"
            value = var.cloud_provider
          }

          resources {
            limits = {
              cpu    = "1000m"
              memory = "2Gi"
            }
            requests = {
              cpu    = "500m"
              memory = "1Gi"
            }
          }
        }

        service_account_name = kubernetes_service_account.ml_ai.metadata[0].name
      }
    }
  }

  depends_on = [kubernetes_namespace.ml_ai]
}

# Intelligent Monitoring Service
resource "kubernetes_deployment" "intelligent_monitor" {
  count = var.enable_intelligent_monitoring ? 1 : 0

  metadata {
    name      = "intelligent-monitor"
    namespace = var.namespace
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "intelligent-monitor"
      }
    }

    template {
      metadata {
        labels = {
          app = "intelligent-monitor"
        }
      }

      spec {
        container {
          name  = "intelligent-monitor"
          image = "ml-ai/intelligent-monitor:latest"

          port {
            container_port = 8080
          }

          env {
            name  = "ELASTICSEARCH_URL"
            value = "http://elasticsearch-master:9200"
          }

          env {
            name  = "JAEGER_URL"
            value = "http://jaeger-query:16686"
          }

          env {
            name  = "GRAFANA_URL"
            value = "http://grafana:3000"
          }

          resources {
            limits = {
              cpu    = "1000m"
              memory = "2Gi"
            }
            requests = {
              cpu    = "500m"
              memory = "1Gi"
            }
          }
        }

        service_account_name = kubernetes_service_account.ml_ai.metadata[0].name
      }
    }
  }

  depends_on = [kubernetes_namespace.ml_ai]
}

# Cost Optimization Service
resource "kubernetes_deployment" "cost_optimizer" {
  count = var.enable_cost_optimization ? 1 : 0

  metadata {
    name      = "cost-optimizer"
    namespace = var.namespace
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "cost-optimizer"
      }
    }

    template {
      metadata {
        labels = {
          app = "cost-optimizer"
        }
      }

      spec {
        container {
          name  = "cost-optimizer"
          image = "ml-ai/cost-optimizer:latest"

          port {
            container_port = 8080
          }

          env {
            name  = "CLOUD_PROVIDER"
            value = var.cloud_provider
          }

          env {
            name  = "AWS_REGION"
            value = var.aws_region
          }

          env {
            name  = "AZURE_SUBSCRIPTION_ID"
            value = var.azure_subscription_id
          }

          env {
            name  = "GCP_PROJECT_ID"
            value = var.gcp_project_id
          }

          resources {
            limits = {
              cpu    = "500m"
              memory = "1Gi"
            }
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
          }
        }

        service_account_name = kubernetes_service_account.ml_ai.metadata[0].name
      }
    }
  }

  depends_on = [kubernetes_namespace.ml_ai]
}

# Service Account for ML/AI
resource "kubernetes_service_account" "ml_ai" {
  metadata {
    name      = "ml-ai-sa"
    namespace = var.namespace
  }

  depends_on = [kubernetes_namespace.ml_ai]
}

# RBAC for ML/AI
resource "kubernetes_cluster_role" "ml_ai" {
  metadata {
    name = "ml-ai-role"
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "services", "endpoints", "nodes"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets"]
    verbs      = ["get", "list", "watch", "update", "patch"]
  }

  rule {
    api_groups = ["autoscaling"]
    resources  = ["horizontalpodautoscalers"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["get", "list", "watch", "create"]
  }

  # Additional permissions for rollback
  rule {
    api_groups = ["apps"]
    resources  = ["deployments/rollback"]
    verbs      = ["create", "patch"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/log"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_cluster_role_binding" "ml_ai" {
  metadata {
    name = "ml-ai-role-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.ml_ai.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.ml_ai.metadata[0].name
    namespace = var.namespace
  }
}

# ML/AI Dashboard Service
resource "kubernetes_service" "ml_ai_dashboard" {
  metadata {
    name      = "ml-ai-dashboard"
    namespace = var.namespace
  }

  spec {
    selector = {
      app = "ml-ai-dashboard"
    }

    port {
      port        = 8080
      target_port = 8080
    }

    type = "ClusterIP"
  }

  depends_on = [kubernetes_namespace.ml_ai]
}

# ML/AI Dashboard Deployment
resource "kubernetes_deployment" "ml_ai_dashboard" {
  metadata {
    name      = "ml-ai-dashboard"
    namespace = var.namespace
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "ml-ai-dashboard"
      }
    }

    template {
      metadata {
        labels = {
          app = "ml-ai-dashboard"
        }
      }

      spec {
        container {
          name  = "ml-ai-dashboard"
          image = "ml-ai/dashboard:latest"

          port {
            container_port = 8080
          }

          env {
            name  = "ANOMALY_DETECTOR_URL"
            value = "http://anomaly-detector:8080"
          }

          env {
            name  = "PREDICTIVE_SCALER_URL"
            value = "http://predictive-scaler:8080"
          }

          env {
            name  = "INTELLIGENT_MONITOR_URL"
            value = "http://intelligent-monitor:8080"
          }

          env {
            name  = "COST_OPTIMIZER_URL"
            value = "http://cost-optimizer:8080"
          }

          env {
            name  = "INTELLIGENT_ROLLBACK_URL"
            value = "http://intelligent-rollback:8080"
          }

          resources {
            limits = {
              cpu    = "500m"
              memory = "1Gi"
            }
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.ml_ai]
}

# Outputs
output "sagemaker_domain_id" {
  description = "AWS SageMaker domain ID"
  value       = var.cloud_provider == "aws" ? aws_sagemaker_domain.ml_domain[0].id : null
}

output "ml_workspace_id" {
  description = "Azure ML workspace ID"
  value       = var.cloud_provider == "azure" ? azurerm_machine_learning_workspace.ml_workspace[0].id : null
}

output "ml_dataset_id" {
  description = "GCP AI Platform dataset ID"
  value       = var.cloud_provider == "gcp" ? google_ai_platform_dataset.ml_dataset[0].id : null
}

output "ml_ai_dashboard_url" {
  description = "ML/AI Dashboard access URL"
  value       = "http://ml-ai-dashboard:8080"
}

output "intelligent_rollback_url" {
  description = "Intelligent Rollback service URL"
  value       = var.enable_intelligent_rollback ? "http://intelligent-rollback:8080" : null
} 