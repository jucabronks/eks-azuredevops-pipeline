# Logging Module for Multicloud Centralized Logging
# Supports AWS CloudWatch Logs, Azure Log Analytics, GCP Cloud Logging

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
  description = "Kubernetes namespace for logging"
  type        = string
  default     = "logging"
}

variable "log_retention_days" {
  description = "Log retention period in days"
  type        = number
  default     = 30
}

variable "elasticsearch_replicas" {
  description = "Number of Elasticsearch replicas"
  type        = number
  default     = 1
}

variable "kibana_admin_password" {
  description = "Kibana admin password"
  type        = string
  sensitive   = true
}

# AWS CloudWatch Logs Configuration
resource "aws_cloudwatch_log_group" "application_logs" {
  count             = var.cloud_provider == "aws" ? 1 : 0
  name              = "/aws/eks/${var.cluster_name}/application-logs"
  retention_in_days = var.log_retention_days

  tags = {
    Environment = var.environment
    Cluster     = var.cluster_name
  }
}

resource "aws_cloudwatch_log_group" "system_logs" {
  count             = var.cloud_provider == "aws" ? 1 : 0
  name              = "/aws/eks/${var.cluster_name}/system-logs"
  retention_in_days = var.log_retention_days

  tags = {
    Environment = var.environment
    Cluster     = var.cluster_name
  }
}

resource "aws_cloudwatch_log_group" "audit_logs" {
  count             = var.cloud_provider == "aws" ? 1 : 0
  name              = "/aws/eks/${var.cluster_name}/audit-logs"
  retention_in_days = 90  # Longer retention for audit logs

  tags = {
    Environment = var.environment
    Cluster     = var.cluster_name
  }
}

# AWS IAM Role for Fluent Bit
resource "aws_iam_role" "fluent_bit" {
  count = var.cloud_provider == "aws" ? 1 : 0
  name  = "${var.cluster_name}-fluent-bit-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current[0].account_id}:oidc-provider/${replace(data.aws_eks_cluster.cluster[0].identity[0].oidc[0].issuer, "https://", "")}"
        }
        Condition = {
          StringEquals = {
            "${replace(data.aws_eks_cluster.cluster[0].identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:${var.namespace}:fluent-bit"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "fluent_bit" {
  count = var.cloud_provider == "aws" ? 1 : 0
  name  = "${var.cluster_name}-fluent-bit-policy"
  role  = aws_iam_role.fluent_bit[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          aws_cloudwatch_log_group.application_logs[0].arn,
          aws_cloudwatch_log_group.system_logs[0].arn,
          aws_cloudwatch_log_group.audit_logs[0].arn
        ]
      }
    ]
  })
}

data "aws_caller_identity" "current" {
  count = var.cloud_provider == "aws" ? 1 : 0
}

data "aws_eks_cluster" "cluster" {
  count = var.cloud_provider == "aws" ? 1 : 0
  name  = var.cluster_name
}

# Azure Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.cloud_provider == "azure" ? 1 : 0
  name                = "${var.cluster_name}-logs-${var.environment}"
  location            = data.azurerm_resource_group.main[0].location
  resource_group_name = data.azurerm_resource_group.main[0].name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = {
    Environment = var.environment
    Cluster     = var.cluster_name
  }
}

data "azurerm_resource_group" "main" {
  count = var.cloud_provider == "azure" ? 1 : 0
  name  = var.resource_group_name
}

# GCP Cloud Logging Configuration
resource "google_logging_project_sink" "application_logs" {
  count   = var.cloud_provider == "gcp" ? 1 : 0
  name    = "${var.cluster_name}-application-logs"
  project = var.gcp_project_id

  destination = "storage.googleapis.com/${google_storage_bucket.logs[0].name}"

  filter = "resource.type=\"k8s_container\" AND resource.labels.cluster_name=\"${var.cluster_name}\""

  unique_writer_identity = true
}

resource "google_storage_bucket" "logs" {
  count   = var.cloud_provider == "gcp" ? 1 : 0
  name    = "${var.cluster_name}-logs-${var.environment}"
  project = var.gcp_project_id
  location = var.gcp_region

  lifecycle_rule {
    condition {
      age = var.log_retention_days
    }
    action {
      type = "Delete"
    }
  }
}

# Kubernetes Namespace for Logging
resource "kubernetes_namespace" "logging" {
  metadata {
    name = var.namespace
    labels = {
      name        = var.namespace
      environment = var.environment
    }
  }
}

# Service Account for Fluent Bit
resource "kubernetes_service_account" "fluent_bit" {
  metadata {
    name      = "fluent-bit"
    namespace = var.namespace
    annotations = var.cloud_provider == "aws" ? {
      "eks.amazonaws.com/role-arn" = aws_iam_role.fluent_bit[0].arn
    } : {}
  }

  depends_on = [kubernetes_namespace.logging]
}

# Fluent Bit Configuration
resource "kubernetes_config_map" "fluent_bit_config" {
  metadata {
    name      = "fluent-bit-config"
    namespace = var.namespace
  }

  data = {
    "fluent-bit.conf" = templatefile("${path.module}/templates/fluent-bit.conf.tpl", {
      cloud_provider = var.cloud_provider
      cluster_name   = var.cluster_name
      environment    = var.environment
      aws_region     = var.aws_region
      log_group      = var.cloud_provider == "aws" ? aws_cloudwatch_log_group.application_logs[0].name : ""
      workspace_id   = var.cloud_provider == "azure" ? azurerm_log_analytics_workspace.main[0].workspace_id : ""
      gcp_project    = var.gcp_project_id
    })
  }

  depends_on = [kubernetes_namespace.logging]
}

# Fluent Bit DaemonSet
resource "kubernetes_daemon_set" "fluent_bit" {
  metadata {
    name      = "fluent-bit"
    namespace = var.namespace
  }

  spec {
    selector {
      match_labels = {
        name = "fluent-bit"
      }
    }

    template {
      metadata {
        labels = {
          name = "fluent-bit"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.fluent_bit.metadata[0].name

        containers {
          name  = "fluent-bit"
          image = "fluent/fluent-bit:2.1"

          volume_mounts {
            name       = "fluent-bit-config"
            mount_path = "/fluent-bit/etc/"
          }

          volume_mounts {
            name       = "varlog"
            mount_path = "/var/log"
            read_only  = true
          }

          volume_mounts {
            name       = "varlibdockercontainers"
            mount_path = "/var/lib/docker/containers"
            read_only  = true
          }

          resources {
            limits = {
              memory = "500Mi"
              cpu    = "500m"
            }
            requests = {
              memory = "200Mi"
              cpu    = "100m"
            }
          }
        }

        volumes {
          name = "fluent-bit-config"
          config_map {
            name = kubernetes_config_map.fluent_bit_config.metadata[0].name
          }
        }

        volumes {
          name = "varlog"
          host_path {
            path = "/var/log"
          }
        }

        volumes {
          name = "varlibdockercontainers"
          host_path {
            path = "/var/lib/docker/containers"
          }
        }

        tolerations {
          key    = "node-role.kubernetes.io/master"
          effect = "NoSchedule"
        }
      }
    }
  }

  depends_on = [kubernetes_config_map.fluent_bit_config]
}

# Elasticsearch Cluster (for centralized logging)
resource "helm_release" "elasticsearch" {
  count      = var.enable_elasticsearch ? 1 : 0
  name       = "elasticsearch"
  repository = "https://helm.elastic.co"
  chart      = "elasticsearch"
  namespace  = var.namespace
  create_namespace = false

  set {
    name  = "replicas"
    value = var.elasticsearch_replicas
  }

  set {
    name  = "minimumMasterNodes"
    value = var.elasticsearch_replicas > 1 ? 2 : 1
  }

  set {
    name  = "resources.requests.memory"
    value = "2Gi"
  }

  set {
    name  = "resources.limits.memory"
    value = "4Gi"
  }

  set {
    name  = "volumeClaimTemplate.resources.requests.storage"
    value = "50Gi"
  }

  depends_on = [kubernetes_namespace.logging]
}

# Kibana (for log visualization)
resource "helm_release" "kibana" {
  count      = var.enable_elasticsearch ? 1 : 0
  name       = "kibana"
  repository = "https://helm.elastic.co"
  chart      = "kibana"
  namespace  = var.namespace
  create_namespace = false

  set {
    name  = "elasticsearchHosts"
    value = "http://elasticsearch-master:9200"
  }

  set {
    name  = "resources.requests.memory"
    value = "1Gi"
  }

  set {
    name  = "resources.limits.memory"
    value = "2Gi"
  }

  depends_on = [helm_release.elasticsearch]
}

# Log Aggregation Service
resource "kubernetes_service" "log_aggregator" {
  count = var.enable_elasticsearch ? 1 : 0

  metadata {
    name      = "log-aggregator"
    namespace = var.namespace
  }

  spec {
    selector = {
      app = "log-aggregator"
    }

    port {
      port        = 8080
      target_port = 8080
    }

    type = "ClusterIP"
  }

  depends_on = [helm_release.elasticsearch]
}

# Outputs
output "cloudwatch_log_groups" {
  description = "AWS CloudWatch log group names"
  value = var.cloud_provider == "aws" ? {
    application = aws_cloudwatch_log_group.application_logs[0].name
    system      = aws_cloudwatch_log_group.system_logs[0].name
    audit       = aws_cloudwatch_log_group.audit_logs[0].name
  } : null
}

output "log_analytics_workspace_id" {
  description = "Azure Log Analytics workspace ID"
  value       = var.cloud_provider == "azure" ? azurerm_log_analytics_workspace.main[0].workspace_id : null
}

output "gcp_log_sink" {
  description = "GCP Cloud Logging sink name"
  value       = var.cloud_provider == "gcp" ? google_logging_project_sink.application_logs[0].name : null
}

output "elasticsearch_url" {
  description = "Elasticsearch access URL"
  value       = var.enable_elasticsearch ? "http://elasticsearch-master:9200" : null
}

output "kibana_url" {
  description = "Kibana access URL"
  value       = var.enable_elasticsearch ? "http://kibana-kibana:5601" : null
} 