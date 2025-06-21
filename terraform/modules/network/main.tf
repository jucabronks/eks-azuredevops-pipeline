# =============================================================================
# MÓDULO NETWORK - MULTICLOUD
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

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnets" {
  description = "Map of subnet configurations"
  type = map(object({
    cidr_block = string
    az         = string
    public     = bool
  }))
  default = {
    public-1 = {
      cidr_block = "10.0.1.0/24"
      az         = "a"
      public     = true
    }
    private-1 = {
      cidr_block = "10.0.2.0/24"
      az         = "a"
      public     = false
    }
    public-2 = {
      cidr_block = "10.0.3.0/24"
      az         = "b"
      public     = true
    }
    private-2 = {
      cidr_block = "10.0.4.0/24"
      az         = "b"
      public     = false
    }
  }
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# =============================================================================
# AWS NETWORK RESOURCES
# =============================================================================

resource "aws_vpc" "main" {
  count = var.cloud_provider == "aws" ? 1 : 0

  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-vpc"
    Environment = var.environment
    Project     = var.project_name
  })
}

resource "aws_subnet" "subnets" {
  for_each = var.cloud_provider == "aws" ? var.subnets : {}

  vpc_id            = aws_vpc.main[0].id
  cidr_block        = each.value.cidr_block
  availability_zone = "${data.aws_region.current.name}${each.value.az}"

  map_public_ip_on_launch = each.value.public

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-${each.key}"
    Environment = var.environment
    Project     = var.project_name
    Type        = each.value.public ? "public" : "private"
  })
}

resource "aws_internet_gateway" "main" {
  count = var.cloud_provider == "aws" ? 1 : 0

  vpc_id = aws_vpc.main[0].id

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-igw"
    Environment = var.environment
    Project     = var.project_name
  })
}

resource "aws_eip" "nat" {
  count = var.cloud_provider == "aws" ? 1 : 0

  domain = "vpc"

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-nat-eip"
    Environment = var.environment
    Project     = var.project_name
  })
}

resource "aws_nat_gateway" "main" {
  count = var.cloud_provider == "aws" ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.subnets["public-1"].id

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-nat"
    Environment = var.environment
    Project     = var.project_name
  })
}

resource "aws_route_table" "public" {
  count = var.cloud_provider == "aws" ? 1 : 0

  vpc_id = aws_vpc.main[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[0].id
  }

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-public-rt"
    Environment = var.environment
    Project     = var.project_name
  })
}

resource "aws_route_table" "private" {
  count = var.cloud_provider == "aws" ? 1 : 0

  vpc_id = aws_vpc.main[0].id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[0].id
  }

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-private-rt"
    Environment = var.environment
    Project     = var.project_name
  })
}

resource "aws_route_table_association" "public" {
  for_each = var.cloud_provider == "aws" ? {
    for k, v in var.subnets : k => v if v.public
  } : {}

  subnet_id      = aws_subnet.subnets[each.key].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_route_table_association" "private" {
  for_each = var.cloud_provider == "aws" ? {
    for k, v in var.subnets : k => v if !v.public
  } : {}

  subnet_id      = aws_subnet.subnets[each.key].id
  route_table_id = aws_route_table.private[0].id
}

# =============================================================================
# AZURE NETWORK RESOURCES
# =============================================================================

resource "azurerm_resource_group" "network" {
  count = var.cloud_provider == "azure" ? 1 : 0

  name     = "${var.project_name}-${var.environment}-rg"
  location = data.azurerm_resource_group.current.location

  tags = var.tags
}

resource "azurerm_virtual_network" "main" {
  count = var.cloud_provider == "azure" ? 1 : 0

  name                = "${var.project_name}-${var.environment}-vnet"
  resource_group_name = azurerm_resource_group.network[0].name
  location            = azurerm_resource_group.network[0].location
  address_space       = [var.vpc_cidr]

  tags = var.tags
}

resource "azurerm_subnet" "subnets" {
  for_each = var.cloud_provider == "azure" ? var.subnets : {}

  name                 = "${var.project_name}-${var.environment}-${each.key}"
  resource_group_name  = azurerm_resource_group.network[0].name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = [each.value.cidr_block]

  dynamic "delegation" {
    for_each = each.value.public ? [1] : []
    content {
      name = "delegation"
      service_delegation {
        name    = "Microsoft.ContainerInstance/containerGroups"
        actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
      }
    }
  }
}

# =============================================================================
# GCP NETWORK RESOURCES
# =============================================================================

resource "google_compute_network" "main" {
  count = var.cloud_provider == "gcp" ? 1 : 0

  name                    = "${var.project_name}-${var.environment}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  depends_on = [google_project_service.compute]
}

resource "google_compute_subnetwork" "subnets" {
  for_each = var.cloud_provider == "gcp" ? var.subnets : {}

  name          = "${var.project_name}-${var.environment}-${each.key}"
  ip_cidr_range = each.value.cidr_block
  network       = google_compute_network.main[0].id
  region        = data.google_client_config.current.region

  dynamic "log_config" {
    for_each = each.value.public ? [1] : []
    content {
      aggregation_interval = "INTERVAL_5_SEC"
      flow_sampling        = 0.5
      metadata            = "INCLUDE_ALL_METADATA"
    }
  }
}

resource "google_compute_router" "main" {
  count = var.cloud_provider == "gcp" ? 1 : 0

  name    = "${var.project_name}-${var.environment}-router"
  region  = data.google_client_config.current.region
  network = google_compute_network.main[0].id
}

resource "google_compute_router_nat" "main" {
  count = var.cloud_provider == "gcp" ? 1 : 0

  name                               = "${var.project_name}-${var.environment}-nat"
  router                            = google_compute_router.main[0].name
  region                            = data.google_client_config.current.region
  nat_ip_allocate_option            = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# =============================================================================
# DATA SOURCES
# =============================================================================

data "aws_region" "current" {
  count = var.cloud_provider == "aws" ? 1 : 0
}

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

output "vpc_id" {
  description = "ID of the VPC"
  value = var.cloud_provider == "aws" ? aws_vpc.main[0].id : (
    var.cloud_provider == "azure" ? azurerm_virtual_network.main[0].id : (
      var.cloud_provider == "gcp" ? google_compute_network.main[0].id : null
    )
  )
}

output "subnet_ids" {
  description = "Map of subnet IDs"
  value = var.cloud_provider == "aws" ? {
    for k, v in aws_subnet.subnets : k => v.id
  } : (
    var.cloud_provider == "azure" ? {
      for k, v in azurerm_subnet.subnets : k => v.id
    } : (
      var.cloud_provider == "gcp" ? {
        for k, v in google_compute_subnetwork.subnets : k => v.id
      } : {}
    )
  )
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value = var.cloud_provider == "aws" ? [
    for k, v in aws_subnet.subnets : v.id if var.subnets[k].public
  ] : (
    var.cloud_provider == "azure" ? [
      for k, v in azurerm_subnet.subnets : v.id if var.subnets[k].public
    ] : (
      var.cloud_provider == "gcp" ? [
        for k, v in google_compute_subnetwork.subnets : v.id if var.subnets[k].public
      ] : []
    )
  )
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value = var.cloud_provider == "aws" ? [
    for k, v in aws_subnet.subnets : v.id if !var.subnets[k].public
  ] : (
    var.cloud_provider == "azure" ? [
      for k, v in azurerm_subnet.subnets : v.id if !var.subnets[k].public
    ] : (
      var.cloud_provider == "gcp" ? [
        for k, v in google_compute_subnetwork.subnets : v.id if !var.subnets[k].public
      ] : []
    )
  )
} 