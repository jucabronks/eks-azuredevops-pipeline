# =============================================================================
# MÓDULO KUBERNETES - MULTICLOUD
# =============================================================================

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

# =============================================================================
# VARIABLES
# =============================================================================

variable "cloud_provider" {
  description = "Cloud provider (aws, azure, gcp)"
  type        = string
  validation {
    condition     = contains(["aws", "azure", "gcp"], var.cloud_provider)
    error_message = "Cloud provider must be aws, azure, or gcp."
  }
}

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "subnet_ids" {
  description = "Map of subnet IDs"
  type        = map(string)
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
  default     = ""
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.33"
}

variable "node_groups" {
  description = "Map of node group configurations"
  type = map(object({
    instance_type = string
    min_size      = number
    max_size      = number
    desired_size  = number
    disk_size     = number
    labels        = map(string)
    taints        = list(object({
      key    = string
      value  = string
      effect = string
    }))
  }))
  default = {
    default = {
      instance_type = "t3.medium"
      min_size      = 1
      max_size      = 3
      desired_size  = 2
      disk_size     = 20
      labels = {
        "node.kubernetes.io/role" = "worker"
      }
      taints = []
    }
  }
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# =============================================================================
# AWS EKS CLUSTER
# =============================================================================

resource "aws_eks_cluster" "main" {
  count = var.cloud_provider == "aws" ? 1 : 0

  name     = var.cluster_name != "" ? var.cluster_name : "${var.project_name}-${var.environment}"
  role_arn = aws_iam_role.eks_cluster[0].arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = values(var.subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = true
    security_group_ids      = [aws_security_group.eks_cluster[0].id]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy[0],
    aws_iam_role_policy_attachment.eks_vpc_resource_controller[0],
  ]

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-eks"
    Environment = var.environment
    Project     = var.project_name
  })
}

resource "aws_iam_role" "eks_cluster" {
  count = var.cloud_provider == "aws" ? 1 : 0

  name = "${var.project_name}-${var.environment}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  count = var.cloud_provider == "aws" ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster[0].name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  count = var.cloud_provider == "aws" ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster[0].name
}

resource "aws_security_group" "eks_cluster" {
  count = var.cloud_provider == "aws" ? 1 : 0

  name_prefix = "${var.project_name}-${var.environment}-eks-cluster"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-eks-cluster-sg"
    Environment = var.environment
    Project     = var.project_name
  })
}

resource "aws_eks_node_group" "main" {
  for_each = var.cloud_provider == "aws" ? var.node_groups : {}

  cluster_name    = aws_eks_cluster.main[0].name
  node_group_name = "${var.project_name}-${var.environment}-${each.key}"
  node_role_arn   = aws_iam_role.eks_nodes[each.key].arn
  subnet_ids      = [var.subnet_ids["private-1"]]

  instance_types = [each.value.instance_type]

  scaling_config {
    desired_size = each.value.desired_size
    max_size     = each.value.max_size
    min_size     = each.value.min_size
  }

  disk_size = each.value.disk_size

  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  labels = each.value.labels

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.ec2_container_registry_read_only,
  ]

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-${each.key}-ng"
    Environment = var.environment
    Project     = var.project_name
  })
}

resource "aws_iam_role" "eks_nodes" {
  for_each = var.cloud_provider == "aws" ? var.node_groups : {}

  name = "${var.project_name}-${var.environment}-${each.key}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  for_each = var.cloud_provider == "aws" ? var.node_groups : {}

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes[each.key].name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  for_each = var.cloud_provider == "aws" ? var.node_groups : {}

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes[each.key].name
}

resource "aws_iam_role_policy_attachment" "ec2_container_registry_read_only" {
  for_each = var.cloud_provider == "aws" ? var.node_groups : {}

  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes[each.key].name
}

# =============================================================================
# AZURE AKS CLUSTER
# =============================================================================

resource "azurerm_kubernetes_cluster" "main" {
  count = var.cloud_provider == "azure" ? 1 : 0

  name                = var.cluster_name != "" ? var.cluster_name : "${var.project_name}-${var.environment}"
  location            = data.azurerm_resource_group.current.location
  resource_group_name = data.azurerm_resource_group.current.name
  dns_prefix          = "${var.project_name}-${var.environment}"

  kubernetes_version = var.kubernetes_version

  default_node_pool {
    name                = "default"
    vm_size             = "Standard_D2s_v3"
    os_disk_size_gb     = 30
    node_count          = 2
    vnet_subnet_id      = var.subnet_ids["private-1"]
    type                = "VirtualMachineScaleSets"
    enable_auto_scaling = true
    min_count           = 1
    max_count           = 3
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin     = "azure"
    network_policy     = "azure"
    load_balancer_sku  = "standard"
    service_cidr       = "10.0.0.0/16"
    dns_service_ip     = "10.0.0.10"
    docker_bridge_cidr = "172.17.0.1/16"
  }

  addon_profile {
    oms_agent {
      enabled                    = true
      log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
    }
  }

  tags = var.tags
}

resource "azurerm_log_analytics_workspace" "main" {
  count = var.cloud_provider == "azure" ? 1 : 0

  name                = "${var.project_name}-${var.environment}-logs"
  location            = data.azurerm_resource_group.current.location
  resource_group_name = data.azurerm_resource_group.current.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = var.tags
}

# =============================================================================
# GCP GKE CLUSTER
# =============================================================================

resource "google_container_cluster" "main" {
  count = var.cloud_provider == "gcp" ? 1 : 0

  name     = var.cluster_name != "" ? var.cluster_name : "${var.project_name}-${var.environment}"
  location = data.google_client_config.current.region

  remove_default_node_pool = true
  initial_node_count       = 1

  network    = var.vpc_id
  subnetwork = var.subnet_ids["private-1"]

  ip_allocation_policy {
    cluster_ipv4_cidr_block  = "/16"
    services_ipv4_cidr_block = "/22"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  workload_identity_config {
    workload_pool = "${data.google_client_config.current.project}.svc.id.goog"
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
  }

  release_channel {
    channel = "regular"
  }

  depends_on = [google_project_service.container]

  labels = var.tags
}

resource "google_container_node_pool" "main" {
  for_each = var.cloud_provider == "gcp" ? var.node_groups : {}

  name       = "${var.project_name}-${var.environment}-${each.key}"
  location   = data.google_client_config.current.region
  cluster    = google_container_cluster.main[0].name
  node_count = each.value.desired_size

  node_config {
    machine_type = each.value.instance_type
    disk_size_gb = each.value.disk_size

    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/devstorage.read_only",
    ]

    labels = each.value.labels

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  autoscaling {
    min_node_count = each.value.min_size
    max_node_count = each.value.max_size
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  labels = var.tags
}

resource "google_project_service" "container" {
  count = var.cloud_provider == "gcp" ? 1 : 0

  project = data.google_client_config.current.project
  service = "container.googleapis.com"

  disable_dependent_services = true
  disable_on_destroy         = false
}

# =============================================================================
# DATA SOURCES
# =============================================================================

data "azurerm_resource_group" "current" {
  count = var.cloud_provider == "azure" ? 1 : 0
  name  = "your-resource-group-name" # Configure according to your Azure setup
}

data "google_client_config" "current" {
  count = var.cloud_provider == "gcp" ? 1 : 0
}

# =============================================================================
# OUTPUTS
# =============================================================================

output "cluster_id" {
  description = "ID of the Kubernetes cluster"
  value = var.cloud_provider == "aws" ? aws_eks_cluster.main[0].id : (
    var.cloud_provider == "azure" ? azurerm_kubernetes_cluster.main[0].id : (
      var.cloud_provider == "gcp" ? google_container_cluster.main[0].id : null
    )
  )
}

output "cluster_name" {
  description = "Name of the Kubernetes cluster"
  value = var.cloud_provider == "aws" ? aws_eks_cluster.main[0].name : (
    var.cloud_provider == "azure" ? azurerm_kubernetes_cluster.main[0].name : (
      var.cloud_provider == "gcp" ? google_container_cluster.main[0].name : null
    )
  )
}

output "cluster_endpoint" {
  description = "Endpoint of the Kubernetes cluster"
  value = var.cloud_provider == "aws" ? aws_eks_cluster.main[0].endpoint : (
    var.cloud_provider == "azure" ? azurerm_kubernetes_cluster.main[0].kube_config[0].host : (
      var.cloud_provider == "gcp" ? google_container_cluster.main[0].endpoint : null
    )
  )
}

output "kubeconfig" {
  description = "Kubeconfig for the cluster"
  value = var.cloud_provider == "aws" ? aws_eks_cluster.main[0].kubeconfig : (
    var.cloud_provider == "azure" ? azurerm_kubernetes_cluster.main[0].kube_config_raw : (
      var.cloud_provider == "gcp" ? google_container_cluster.main[0].master_auth[0].cluster_ca_certificate : null
    )
  )
  sensitive = true
}

output "node_groups" {
  description = "Node groups information"
  value = var.cloud_provider == "aws" ? {
    for k, v in aws_eks_node_group.main : k => {
      id   = v.id
      name = v.node_group_name
      arn  = v.arn
    }
  } : (
    var.cloud_provider == "azure" ? {
      default = {
        id   = azurerm_kubernetes_cluster.main[0].default_node_pool[0].id
        name = azurerm_kubernetes_cluster.main[0].default_node_pool[0].name
        arn  = azurerm_kubernetes_cluster.main[0].id
      }
    } : (
      var.cloud_provider == "gcp" ? {
        for k, v in google_container_node_pool.main : k => {
          id   = v.id
          name = v.name
          arn  = v.id
        }
      } : {}
    )
  )
} 