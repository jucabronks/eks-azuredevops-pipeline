# Distributed Tracing Module for Multicloud Environments
# Supports Jaeger, OpenTelemetry, and cloud-native tracing

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
  description = "Kubernetes namespace for tracing"
  type        = string
  default     = "tracing"
}

variable "tracing_backend" {
  description = "Tracing backend (jaeger, zipkin, otel)"
  type        = string
  default     = "jaeger"
  validation {
    condition     = contains(["jaeger", "zipkin", "otel"], var.tracing_backend)
    error_message = "Tracing backend must be one of: jaeger, zipkin, otel."
  }
}

variable "storage_backend" {
  description = "Storage backend for traces (memory, elasticsearch, cassandra)"
  type        = string
  default     = "elasticsearch"
  validation {
    condition     = contains(["memory", "elasticsearch", "cassandra"], var.storage_backend)
    error_message = "Storage backend must be one of: memory, elasticsearch, cassandra."
  }
}

variable "jaeger_replicas" {
  description = "Number of Jaeger replicas"
  type        = number
  default     = 1
}

variable "enable_ingress" {
  description = "Enable ingress for tracing UI"
  type        = bool
  default     = false
}

variable "domain" {
  description = "Domain for ingress"
  type        = string
  default     = ""
}

# AWS X-Ray Configuration
resource "aws_xray_group" "application" {
  count = var.cloud_provider == "aws" ? 1 : 0
  group_name = "${var.cluster_name}-${var.environment}"
  filter_expression = "service(\"${var.cluster_name}\")"

  tags = {
    Environment = var.environment
    Cluster     = var.cluster_name
  }
}

# Azure Application Insights for Tracing
resource "azurerm_application_insights" "tracing" {
  count               = var.cloud_provider == "azure" ? 1 : 0
  name                = "${var.cluster_name}-tracing-${var.environment}"
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

# GCP Cloud Trace Configuration
resource "google_project_service" "cloudtrace" {
  count   = var.cloud_provider == "gcp" ? 1 : 0
  project = var.gcp_project_id
  service = "cloudtrace.googleapis.com"

  disable_dependent_services = true
  disable_on_destroy         = false
}

# Kubernetes Namespace for Tracing
resource "kubernetes_namespace" "tracing" {
  metadata {
    name = var.namespace
    labels = {
      name        = var.namespace
      environment = var.environment
    }
  }
}

# Jaeger Operator
resource "helm_release" "jaeger_operator" {
  count      = var.tracing_backend == "jaeger" ? 1 : 0
  name       = "jaeger-operator"
  repository = "https://jaegertracing.github.io/helm-charts"
  chart      = "jaeger-operator"
  namespace  = var.namespace
  create_namespace = false

  set {
    name  = "rbac.create"
    value = "true"
  }

  set {
    name  = "clusterRole.create"
    value = "true"
  }

  depends_on = [kubernetes_namespace.tracing]
}

# Jaeger Instance
resource "kubernetes_manifest" "jaeger_instance" {
  count = var.tracing_backend == "jaeger" ? 1 : 0

  manifest = {
    apiVersion = "jaegertracing.io/v1"
    kind       = "Jaeger"
    metadata = {
      name      = "jaeger"
      namespace = var.namespace
    }
    spec = {
      strategy = "allInOne"
      storage = {
        type = var.storage_backend
        options = var.storage_backend == "elasticsearch" ? {
          es = {
            server-urls = "http://elasticsearch-master:9200"
          }
        } : {}
      }
      ingress = var.enable_ingress ? {
        enabled = true
        hosts   = ["jaeger.${var.domain}"]
        annotations = {
          "kubernetes.io/ingress.class" = "nginx"
          "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
        }
        tls = [
          {
            secretName = "jaeger-tls"
            hosts      = ["jaeger.${var.domain}"]
          }
        ]
      } : {
        enabled = false
      }
    }
  }

  depends_on = [helm_release.jaeger_operator]
}

# OpenTelemetry Collector
resource "helm_release" "opentelemetry_collector" {
  count      = var.tracing_backend == "otel" ? 1 : 0
  name       = "opentelemetry-collector"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  namespace  = var.namespace
  create_namespace = false

  set {
    name  = "mode"
    value = "daemonset"
  }

  set {
    name  = "config"
    value = yamlencode({
      receivers = {
        otlp = {
          protocols = {
            grpc = {}
            http = {}
          }
        }
        jaeger = {
          protocols = {
            grpc = {}
            thrift_http = {}
          }
        }
        zipkin = {}
      }
      processors = {
        batch = {}
        resource = {
          attributes = [
            {
              key   = "environment"
              value = var.environment
            },
            {
              key   = "cluster_name"
              value = var.cluster_name
            }
          ]
        }
      }
      exporters = {
        otlp = {
          endpoint = "jaeger-collector:14250"
          tls = {
            insecure = true
          }
        }
        %{ if cloud_provider == "aws" }
        xray = {
          region = var.aws_region
        }
        %{ endif }
        %{ if cloud_provider == "azure" }
        azuremonitor = {
          connection_string = azurerm_application_insights.tracing[0].connection_string
        }
        %{ endif }
        %{ if cloud_provider == "gcp" }
        googlecloud = {
          project_id = var.gcp_project_id
        }
        %{ endif }
      }
      service = {
        pipelines = {
          traces = {
            receivers  = ["otlp", "jaeger", "zipkin"]
            processors = ["batch", "resource"]
            exporters  = ["otlp"]
          }
        }
      }
    })
  }

  depends_on = [kubernetes_namespace.tracing]
}

# Service for Tracing UI
resource "kubernetes_service" "tracing_ui" {
  count = var.tracing_backend == "jaeger" ? 1 : 0

  metadata {
    name      = "jaeger-query"
    namespace = var.namespace
  }

  spec {
    selector = {
      app = "jaeger"
      component = "query"
    }

    port {
      port        = 16686
      target_port = 16686
    }

    type = "ClusterIP"
  }

  depends_on = [kubernetes_manifest.jaeger_instance]
}

# ConfigMap for Application Tracing Configuration
resource "kubernetes_config_map" "tracing_config" {
  metadata {
    name      = "tracing-config"
    namespace = var.namespace
  }

  data = {
    "jaeger-config.yaml" = yamlencode({
      sampling = {
        default = {
          type  = "probabilistic"
          param = 0.1
        }
      }
      reporter = {
        logSpans = true
        localAgentHostPort = "jaeger-agent:6831"
      }
    })
    "otel-config.yaml" = yamlencode({
      receivers = {
        otlp = {
          protocols = {
            grpc = {}
            http = {}
          }
        }
      }
      processors = {
        batch = {}
      }
      exporters = {
        otlp = {
          endpoint = "opentelemetry-collector:4317"
          tls = {
            insecure = true
          }
        }
      }
      service = {
        pipelines = {
          traces = {
            receivers  = ["otlp"]
            processors = ["batch"]
            exporters  = ["otlp"]
          }
        }
      }
    })
  }

  depends_on = [kubernetes_namespace.tracing]
}

# Service Account for Tracing
resource "kubernetes_service_account" "tracing" {
  metadata {
    name      = "tracing-sa"
    namespace = var.namespace
  }

  depends_on = [kubernetes_namespace.tracing]
}

# RBAC for Tracing
resource "kubernetes_cluster_role" "tracing" {
  metadata {
    name = "tracing-role"
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "services", "endpoints"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_cluster_role_binding" "tracing" {
  metadata {
    name = "tracing-role-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.tracing.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.tracing.metadata[0].name
    namespace = var.namespace
  }
}

# Tracing Sidecar Injector (optional)
resource "kubernetes_config_map" "tracing_sidecar" {
  count = var.enable_sidecar_injection ? 1 : 0

  metadata {
    name      = "tracing-sidecar-config"
    namespace = var.namespace
  }

  data = {
    "sidecar-template.yaml" = templatefile("${path.module}/templates/sidecar-template.yaml.tpl", {
      tracing_backend = var.tracing_backend
      jaeger_endpoint = var.tracing_backend == "jaeger" ? "jaeger-agent:6831" : ""
      otel_endpoint   = var.tracing_backend == "otel" ? "opentelemetry-collector:4317" : ""
    })
  }

  depends_on = [kubernetes_namespace.tracing]
}

# Outputs
output "jaeger_ui_url" {
  description = "Jaeger UI access URL"
  value = var.tracing_backend == "jaeger" ? (
    var.enable_ingress ? "https://jaeger.${var.domain}" : "http://localhost:16686"
  ) : null
}

output "xray_group_name" {
  description = "AWS X-Ray group name"
  value       = var.cloud_provider == "aws" ? aws_xray_group.application[0].group_name : null
}

output "application_insights_key" {
  description = "Azure Application Insights instrumentation key"
  value       = var.cloud_provider == "azure" ? azurerm_application_insights.tracing[0].instrumentation_key : null
  sensitive   = true
}

output "tracing_endpoint" {
  description = "Tracing endpoint for applications"
  value = var.tracing_backend == "jaeger" ? "jaeger-agent:6831" : (
    var.tracing_backend == "otel" ? "opentelemetry-collector:4317" : ""
  )
} 