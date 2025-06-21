# Monitoring Module for Multicloud Observability
# Supports AWS CloudWatch, Azure Monitor, GCP Cloud Monitoring

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
  description = "Kubernetes namespace for monitoring"
  type        = string
  default     = "monitoring"
}

variable "prometheus_retention_days" {
  description = "Prometheus data retention in days"
  type        = number
  default     = 15
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
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

# AWS CloudWatch Configuration
resource "aws_cloudwatch_log_group" "application_logs" {
  count             = var.cloud_provider == "aws" ? 1 : 0
  name              = "/aws/eks/${var.cluster_name}/application-logs"
  retention_in_days = 30

  tags = {
    Environment = var.environment
    Cluster     = var.cluster_name
  }
}

resource "aws_cloudwatch_dashboard" "main" {
  count           = var.cloud_provider == "aws" ? 1 : 0
  dashboard_name  = "${var.cluster_name}-dashboard"
  dashboard_body  = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/EKS", "cluster_failed_node_count", "ClusterName", var.cluster_name],
            [".", "cluster_node_count", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current[0].name
          title  = "EKS Cluster Metrics"
        }
      }
    ]
  })
}

data "aws_region" "current" {
  count = var.cloud_provider == "aws" ? 1 : 0
}

# Azure Monitor Configuration
resource "azurerm_application_insights" "main" {
  count               = var.cloud_provider == "azure" ? 1 : 0
  name                = "${var.cluster_name}-app-insights"
  location            = data.azurerm_resource_group.main[0].location
  resource_group_name = data.azurerm_resource_group.main[0].name
  application_type    = "web"

  tags = {
    Environment = var.environment
    Cluster     = var.cluster_name
  }
}

data "azurerm_resource_group" "main" {
  count = var.cloud_provider == "azure" ? 1 : 0
  name  = var.resource_group_name
}

# GCP Cloud Monitoring Configuration
resource "google_monitoring_workspace" "main" {
  count   = var.cloud_provider == "gcp" ? 1 : 0
  project = var.gcp_project_id
  display_name = "${var.cluster_name} Monitoring Workspace"
}

# Kubernetes Namespace for Monitoring
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = var.namespace
    labels = {
      name        = var.namespace
      environment = var.environment
    }
  }
}

# Prometheus Operator with Helm
resource "helm_release" "prometheus_operator" {
  name       = "prometheus-operator"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = var.namespace
  create_namespace = false

  set {
    name  = "prometheus.prometheusSpec.retention"
    value = "${var.prometheus_retention_days}d"
  }

  set {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }

  set {
    name  = "grafana.persistence.enabled"
    value = "true"
  }

  set {
    name  = "grafana.persistence.size"
    value = "10Gi"
  }

  set {
    name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage"
    value = "50Gi"
  }

  # Cloud-specific configurations
  dynamic "set" {
    for_each = var.cloud_provider == "aws" ? [1] : []
    content {
      name  = "prometheus.prometheusSpec.additionalScrapeConfigs"
      value = yamlencode([
        {
          job_name = "aws-cloudwatch"
          static_configs = [
            {
              targets = ["localhost:9090"]
            }
          ]
        }
      ])
    }
  }

  depends_on = [kubernetes_namespace.monitoring]
}

# Custom Application Monitoring
resource "kubernetes_config_map" "custom_monitoring" {
  metadata {
    name      = "custom-monitoring-config"
    namespace = var.namespace
  }

  data = {
    "application-metrics.yaml" = yamlencode({
      apiVersion = "v1"
      kind       = "ServiceMonitor"
      metadata = {
        name      = "application-metrics"
        namespace = var.namespace
      }
      spec = {
        selector = {
          matchLabels = {
            app = "application"
          }
        }
        endpoints = [
          {
            port = "metrics"
            path = "/metrics"
          }
        ]
      }
    })
  }

  depends_on = [kubernetes_namespace.monitoring]
}

# Alert Rules
resource "kubernetes_config_map" "alert_rules" {
  metadata {
    name      = "alert-rules"
    namespace = var.namespace
  }

  data = {
    "application-alerts.yaml" = yamlencode({
      apiVersion = "monitoring.coreos.com/v1"
      kind       = "PrometheusRule"
      metadata = {
        name      = "application-alerts"
        namespace = var.namespace
      }
      spec = {
        groups = [
          {
            name = "application"
            rules = [
              {
                alert = "HighCPUUsage"
                expr  = "100 - (avg by(instance) (irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100) > 80"
                for   = "5m"
                labels = {
                  severity = "warning"
                }
                annotations = {
                  summary     = "High CPU usage detected"
                  description = "CPU usage is above 80% for more than 5 minutes"
                }
              },
              {
                alert = "HighMemoryUsage"
                expr  = "(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 85"
                for   = "5m"
                labels = {
                  severity = "warning"
                }
                annotations = {
                  summary     = "High memory usage detected"
                  description = "Memory usage is above 85% for more than 5 minutes"
                }
              },
              {
                alert = "PodRestarting"
                expr  = "increase(kube_pod_container_status_restarts_total[15m]) > 0"
                for   = "1m"
                labels = {
                  severity = "critical"
                }
                annotations = {
                  summary     = "Pod is restarting frequently"
                  description = "Pod {{ $labels.pod }} in namespace {{ $labels.namespace }} is restarting"
                }
              }
            ]
          }
        ]
      }
    })
  }

  depends_on = [kubernetes_namespace.monitoring]
}

# Service for Grafana
resource "kubernetes_service" "grafana" {
  metadata {
    name      = "grafana-service"
    namespace = var.namespace
  }

  spec {
    selector = {
      app = "grafana"
    }

    port {
      port        = 80
      target_port = 3000
    }

    type = "ClusterIP"
  }

  depends_on = [helm_release.prometheus_operator]
}

# Ingress for Grafana (if enabled)
resource "kubernetes_ingress_v1" "grafana" {
  count = var.enable_ingress ? 1 : 0

  metadata {
    name      = "grafana-ingress"
    namespace = var.namespace
    annotations = {
      "kubernetes.io/ingress.class" = "nginx"
      "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
    }
  }

  spec {
    rule {
      host = "grafana.${var.domain}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "grafana-service"
              port {
                number = 80
              }
            }
          }
        }
      }
    }

    tls {
      hosts       = ["grafana.${var.domain}"]
      secret_name = "grafana-tls"
    }
  }

  depends_on = [kubernetes_service.grafana]
}

# Outputs
output "grafana_url" {
  description = "Grafana access URL"
  value       = var.enable_ingress ? "https://grafana.${var.domain}" : "http://localhost:3000"
}

output "prometheus_url" {
  description = "Prometheus access URL"
  value       = "http://localhost:9090"
}

output "alertmanager_url" {
  description = "AlertManager access URL"
  value       = "http://localhost:9093"
}

output "cloudwatch_log_group" {
  description = "AWS CloudWatch log group name"
  value       = var.cloud_provider == "aws" ? aws_cloudwatch_log_group.application_logs[0].name : null
}

output "application_insights_key" {
  description = "Azure Application Insights instrumentation key"
  value       = var.cloud_provider == "azure" ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
} 