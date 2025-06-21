# AWS Monitoring Configuration
# Integrates monitoring, logging, and tracing for AWS EKS

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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

# Data sources
data "aws_eks_cluster" "main" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "main" {
  name = var.cluster_name
}

# Provider configuration
provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.main.token
  }
}

# Variables
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "domain" {
  description = "Domain for ingress"
  type        = string
  default     = ""
}

variable "enable_ingress" {
  description = "Enable ingress for monitoring UIs"
  type        = bool
  default     = false
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
}

variable "kibana_admin_password" {
  description = "Kibana admin password"
  type        = string
  sensitive   = true
}

# Monitoring Module
module "monitoring" {
  source = "../modules/monitoring"

  environment              = var.environment
  cloud_provider          = "aws"
  cluster_name            = var.cluster_name
  namespace               = "monitoring"
  prometheus_retention_days = 15
  grafana_admin_password  = var.grafana_admin_password
  enable_ingress          = var.enable_ingress
  domain                  = var.domain

  alert_manager_config = {
    slack_webhook_url = var.slack_webhook_url
    email_smtp_host   = var.email_smtp_host
    email_smtp_port   = var.email_smtp_port
    email_from        = var.email_from
    email_to          = var.email_to
  }

  monitoring_resources = {
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

  retention_policy = {
    prometheus_retention = "15d"
    grafana_retention    = "30d"
    logs_retention       = 30
  }

  backup_config = {
    enabled          = true
    schedule         = "0 2 * * *"  # Daily at 2 AM
    retention_days   = 30
    storage_location = "s3://${var.backup_bucket}/monitoring"
  }
}

# Logging Module
module "logging" {
  source = "../modules/logging"

  environment           = var.environment
  cloud_provider       = "aws"
  cluster_name         = var.cluster_name
  namespace            = "logging"
  log_retention_days   = 30
  elasticsearch_replicas = 1
  kibana_admin_password = var.kibana_admin_password
  enable_elasticsearch = true

  # AWS-specific variables
  aws_region = var.aws_region
}

# Tracing Module
module "tracing" {
  source = "../modules/tracing"

  environment      = var.environment
  cloud_provider   = "aws"
  cluster_name     = var.cluster_name
  namespace        = "tracing"
  tracing_backend  = "jaeger"
  storage_backend  = "elasticsearch"
  jaeger_replicas  = 1
  enable_ingress   = var.enable_ingress
  domain           = var.domain

  # AWS-specific variables
  aws_region = var.aws_region
}

# Additional AWS-specific monitoring resources

# CloudWatch Dashboard for EKS
resource "aws_cloudwatch_dashboard" "eks_dashboard" {
  dashboard_name = "${var.cluster_name}-eks-dashboard"

  dashboard_body = jsonencode({
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
            [".", "cluster_node_count", ".", "."],
            [".", "cluster_control_plane_requests_total", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "EKS Cluster Overview"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/EKS", "cluster_node_cpu_utilization", "ClusterName", var.cluster_name],
            [".", "cluster_node_memory_utilization", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Node Resource Utilization"
        }
      }
    ]
  })
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "cluster_node_count" {
  alarm_name          = "${var.cluster_name}-node-count"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "cluster_node_count"
  namespace           = "AWS/EKS"
  period              = "300"
  statistic           = "Average"
  threshold           = "2"
  alarm_description   = "This metric monitors EKS cluster node count"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterName = var.cluster_name
  }
}

resource "aws_cloudwatch_metric_alarm" "cluster_cpu_utilization" {
  alarm_name          = "${var.cluster_name}-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "cluster_node_cpu_utilization"
  namespace           = "AWS/EKS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors EKS cluster CPU utilization"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterName = var.cluster_name
  }
}

# SNS Topic for Alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.cluster_name}-alerts"
}

resource "aws_sns_topic_subscription" "email_alerts" {
  count     = length(var.alert_emails)
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_emails[count.index]
}

# IAM Role for CloudWatch Container Insights
resource "aws_iam_role" "cloudwatch_agent" {
  name = "${var.cluster_name}-cloudwatch-agent"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(data.aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}"
        }
        Condition = {
          StringEquals = {
            "${replace(data.aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:amazon-cloudwatch:cloudwatch-agent"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "cloudwatch_agent" {
  name = "${var.cluster_name}-cloudwatch-agent-policy"
  role = aws_iam_role.cloudwatch_agent.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "ec2:DescribeVolumes",
          "ec2:DescribeTags",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups",
          "logs:CreateLogStream",
          "logs:CreateLogGroup"
        ]
        Resource = "*"
      }
    ]
  })
}

data "aws_caller_identity" "current" {}

# Variables for alerting
variable "slack_webhook_url" {
  description = "Slack webhook URL for alerts"
  type        = string
  default     = ""
}

variable "email_smtp_host" {
  description = "SMTP host for email alerts"
  type        = string
  default     = ""
}

variable "email_smtp_port" {
  description = "SMTP port for email alerts"
  type        = number
  default     = 587
}

variable "email_from" {
  description = "From email address for alerts"
  type        = string
  default     = ""
}

variable "email_to" {
  description = "List of email addresses to receive alerts"
  type        = list(string)
  default     = []
}

variable "alert_emails" {
  description = "List of email addresses for CloudWatch alarms"
  type        = list(string)
  default     = []
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "backup_bucket" {
  description = "S3 bucket for monitoring backups"
  type        = string
  default     = ""
}

# Outputs
output "grafana_url" {
  description = "Grafana access URL"
  value       = module.monitoring.grafana_url
}

output "prometheus_url" {
  description = "Prometheus access URL"
  value       = module.monitoring.prometheus_url
}

output "jaeger_ui_url" {
  description = "Jaeger UI access URL"
  value       = module.tracing.jaeger_ui_url
}

output "kibana_url" {
  description = "Kibana access URL"
  value       = module.logging.kibana_url
}

output "cloudwatch_dashboard_url" {
  description = "CloudWatch dashboard URL"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.eks_dashboard.dashboard_name}"
}

output "xray_group_name" {
  description = "AWS X-Ray group name"
  value       = module.tracing.xray_group_name
}

output "cloudwatch_log_groups" {
  description = "CloudWatch log group names"
  value       = module.logging.cloudwatch_log_groups
} 