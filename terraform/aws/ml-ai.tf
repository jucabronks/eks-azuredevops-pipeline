# AWS ML/AI Configuration
# Integrates ML/AI capabilities with existing infrastructure

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

data "aws_vpc" "main" {
  id = var.vpc_id
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  tags = {
    Type = "private"
  }
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

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

# ML/AI Module
module "ml_ai" {
  source = "../modules/ml-ai"

  environment = var.environment
  cloud_provider = "aws"
  cluster_name = var.cluster_name
  namespace = "ml-ai"

  # Enable all ML/AI services
  enable_anomaly_detection = true
  enable_predictive_scaling = true
  enable_intelligent_monitoring = true
  enable_cost_optimization = true

  # AWS-specific variables
  aws_region = var.aws_region
  vpc_id = var.vpc_id
  private_subnet_ids = data.aws_subnets.private.ids

  # ML/AI Configuration
  ml_model_config = {
    algorithm = "isolation_forest"
    version   = "1.0"
    parameters = {
      contamination = "0.1"
      random_state  = "42"
    }
  }

  anomaly_detection_config = {
    sensitivity = 0.8
    window_size = "5m"
    threshold   = 0.7
  }

  predictive_scaling_config = {
    prediction_horizon = "30m"
    min_replicas      = 1
    max_replicas      = 10
    scale_up_threshold = 0.7
    scale_down_threshold = 0.3
  }

  intelligent_monitoring_config = {
    log_analysis_enabled = true
    trace_analysis_enabled = true
    performance_analysis_enabled = true
    alert_correlation_enabled = true
  }

  cost_optimization_config = {
    auto_scaling_enabled = true
    spot_instances_enabled = true
    resource_rightsizing_enabled = true
    idle_resource_cleanup_enabled = true
    budget_alerts_enabled = true
  }

  ml_resources = {
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

  data_retention = {
    training_data_retention = "90d"
    model_artifacts_retention = "365d"
    predictions_retention = "30d"
    logs_retention = "60d"
  }

  model_training_config = {
    auto_retrain_enabled = true
    retrain_interval = "7d"
    model_evaluation_threshold = 0.8
    feature_store_enabled = true
  }

  security_config = {
    encryption_enabled = true
    network_isolation_enabled = true
    audit_logging_enabled = true
    data_governance_enabled = true
  }

  monitoring_endpoints = {
    prometheus_url = "http://prometheus-operated:9090"
    grafana_url = "http://grafana:3000"
    elasticsearch_url = "http://elasticsearch-master:9200"
    jaeger_url = "http://jaeger-query:16686"
  }
}

# Additional AWS-specific ML/AI resources

# S3 Bucket for ML Data
resource "aws_s3_bucket" "ml_data" {
  bucket = "${var.cluster_name}-ml-data-${var.environment}"

  tags = {
    Environment = var.environment
    Cluster     = var.cluster_name
    Purpose     = "ML Data Storage"
  }
}

resource "aws_s3_bucket_versioning" "ml_data" {
  bucket = aws_s3_bucket.ml_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ml_data" {
  bucket = aws_s3_bucket.ml_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# CloudWatch Log Groups for ML/AI
resource "aws_cloudwatch_log_group" "ml_ai_logs" {
  name              = "/aws/eks/${var.cluster_name}/ml-ai-logs"
  retention_in_days = 30

  tags = {
    Environment = var.environment
    Cluster     = var.cluster_name
  }
}

resource "aws_cloudwatch_log_group" "ml_training_logs" {
  name              = "/aws/eks/${var.cluster_name}/ml-training-logs"
  retention_in_days = 90

  tags = {
    Environment = var.environment
    Cluster     = var.cluster_name
  }
}

# CloudWatch Dashboard for ML/AI
resource "aws_cloudwatch_dashboard" "ml_ai_dashboard" {
  dashboard_name = "${var.cluster_name}-ml-ai-dashboard"

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
            ["AWS/SageMaker/Endpoints", "Invocations", "EndpointName", "${var.cluster_name}-ml-endpoint"],
            [".", "ModelLatency", ".", "."],
            [".", "OverheadLatency", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "ML Model Performance"
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
            ["AWS/SageMaker/Endpoints", "Invocation4XXErrors", "EndpointName", "${var.cluster_name}-ml-endpoint"],
            [".", "Invocation5XXErrors", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "ML Model Errors"
        }
      }
    ]
  })
}

# CloudWatch Alarms for ML/AI
resource "aws_cloudwatch_metric_alarm" "ml_model_errors" {
  alarm_name          = "${var.cluster_name}-ml-model-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Invocation5XXErrors"
  namespace           = "AWS/SageMaker/Endpoints"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors ML model 5XX errors"
  alarm_actions       = [aws_sns_topic.ml_alerts.arn]

  dimensions = {
    EndpointName = "${var.cluster_name}-ml-endpoint"
  }
}

resource "aws_cloudwatch_metric_alarm" "ml_model_latency" {
  alarm_name          = "${var.cluster_name}-ml-model-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ModelLatency"
  namespace           = "AWS/SageMaker/Endpoints"
  period              = "300"
  statistic           = "Average"
  threshold           = "1000"
  alarm_description   = "This metric monitors ML model latency"
  alarm_actions       = [aws_sns_topic.ml_alerts.arn]

  dimensions = {
    EndpointName = "${var.cluster_name}-ml-endpoint"
  }
}

# SNS Topic for ML/AI Alerts
resource "aws_sns_topic" "ml_alerts" {
  name = "${var.cluster_name}-ml-alerts"
}

resource "aws_sns_topic_subscription" "ml_email_alerts" {
  count     = length(var.ml_alert_emails)
  topic_arn = aws_sns_topic.ml_alerts.arn
  protocol  = "email"
  endpoint  = var.ml_alert_emails[count.index]
}

# IAM Role for ML/AI Services
resource "aws_iam_role" "ml_ai_service" {
  name = "${var.cluster_name}-ml-ai-service"

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
            "${replace(data.aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:ml-ai:ml-ai-sa"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "ml_ai_service" {
  name = "${var.cluster_name}-ml-ai-service-policy"
  role = aws_iam_role.ml_ai_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sagemaker:*",
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          aws_s3_bucket.ml_data.arn,
          "${aws_s3_bucket.ml_data.arn}/*",
          aws_cloudwatch_log_group.ml_ai_logs.arn,
          aws_cloudwatch_log_group.ml_training_logs.arn
        ]
      }
    ]
  })
}

data "aws_caller_identity" "current" {}

# Variables for ML/AI
variable "ml_alert_emails" {
  description = "List of email addresses for ML/AI alerts"
  type        = list(string)
  default     = []
}

# Outputs
output "sagemaker_domain_id" {
  description = "AWS SageMaker domain ID"
  value       = module.ml_ai.sagemaker_domain_id
}

output "ml_ai_dashboard_url" {
  description = "ML/AI Dashboard access URL"
  value       = module.ml_ai.ml_ai_dashboard_url
}

output "ml_data_bucket" {
  description = "S3 bucket for ML data"
  value       = aws_s3_bucket.ml_data.bucket
}

output "ml_ai_log_group" {
  description = "CloudWatch log group for ML/AI"
  value       = aws_cloudwatch_log_group.ml_ai_logs.name
} 