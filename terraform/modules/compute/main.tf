# =============================================================================
# MÓDULO COMPUTE - MULTICLOUD
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

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "subnet_ids" {
  description = "Map of subnet IDs"
  type        = map(string)
}

variable "instance_type" {
  description = "Instance type/size"
  type        = string
  default     = "t3.micro"
}

variable "instance_count" {
  description = "Number of instances to create"
  type        = number
  default     = 2
}

variable "ami_id" {
  description = "AMI/Image ID"
  type        = string
  default     = ""
}

variable "ssh_key_name" {
  description = "SSH key pair name"
  type        = string
  default     = ""
}

variable "user_data" {
  description = "User data script"
  type        = string
  default     = ""
}

variable "security_group_rules" {
  description = "Security group rules"
  type = list(object({
    type        = string
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
    description = string
  }))
  default = [
    {
      type        = "ingress"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "SSH access"
    },
    {
      type        = "ingress"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "HTTP access"
    },
    {
      type        = "ingress"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "HTTPS access"
    },
    {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
      description = "All outbound traffic"
    }
  ]
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# =============================================================================
# AWS COMPUTE RESOURCES
# =============================================================================

data "aws_ami" "ubuntu" {
  count = var.cloud_provider == "aws" ? 1 : 0

  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "main" {
  count = var.cloud_provider == "aws" ? 1 : 0

  name_prefix = "${var.project_name}-${var.environment}-sg"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = [for rule in var.security_group_rules : rule if rule.type == "ingress"]
    content {
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
      description = ingress.value.description
    }
  }

  dynamic "egress" {
    for_each = [for rule in var.security_group_rules : rule if rule.type == "egress"]
    content {
      from_port   = egress.value.from_port
      to_port     = egress.value.to_port
      protocol    = egress.value.protocol
      cidr_blocks = egress.value.cidr_blocks
      description = egress.value.description
    }
  }

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-sg"
    Environment = var.environment
    Project     = var.project_name
  })
}

resource "aws_instance" "main" {
  count = var.cloud_provider == "aws" ? var.instance_count : 0

  ami                    = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu[0].id
  instance_type          = var.instance_type
  key_name              = var.ssh_key_name
  vpc_security_group_ids = [aws_security_group.main[0].id]
  subnet_id              = var.subnet_ids["private-1"]

  user_data = base64encode(var.user_data)

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-instance-${count.index + 1}"
    Environment = var.environment
    Project     = var.project_name
  })
}

# =============================================================================
# AZURE COMPUTE RESOURCES
# =============================================================================

data "azurerm_image" "ubuntu" {
  count = var.cloud_provider == "azure" ? 1 : 0

  name                = "UbuntuServer"
  resource_group_name = "Microsoft.Compute"
}

resource "azurerm_network_security_group" "main" {
  count = var.cloud_provider == "azure" ? 1 : 0

  name                = "${var.project_name}-${var.environment}-nsg"
  location            = data.azurerm_resource_group.current.location
  resource_group_name = data.azurerm_resource_group.current.name

  dynamic "security_rule" {
    for_each = var.security_group_rules
    content {
      name                       = security_rule.value.description
      priority                   = index(var.security_group_rules, security_rule.value) * 100 + 100
      direction                  = security_rule.value.type == "ingress" ? "Inbound" : "Outbound"
      access                     = "Allow"
      protocol                   = security_rule.value.protocol
      source_port_range          = "*"
      destination_port_range     = security_rule.value.from_port == 0 ? "*" : tostring(security_rule.value.from_port)
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  }

  tags = var.tags
}

resource "azurerm_network_interface" "main" {
  count = var.cloud_provider == "azure" ? var.instance_count : 0

  name                = "${var.project_name}-${var.environment}-nic-${count.index + 1}"
  location            = data.azurerm_resource_group.current.location
  resource_group_name = data.azurerm_resource_group.current.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_ids["private-1"]
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_security_group_association" "main" {
  count = var.cloud_provider == "azure" ? var.instance_count : 0

  network_interface_id      = azurerm_network_interface.main[count.index].id
  network_security_group_id = azurerm_network_security_group.main[0].id
}

resource "azurerm_linux_virtual_machine" "main" {
  count = var.cloud_provider == "azure" ? var.instance_count : 0

  name                = "${var.project_name}-${var.environment}-vm-${count.index + 1}"
  resource_group_name = data.azurerm_resource_group.current.name
  location            = data.azurerm_resource_group.current.location
  size                = var.instance_type
  admin_username      = "ubuntu"

  network_interface_ids = [
    azurerm_network_interface.main[count.index].id
  ]

  admin_ssh_key {
    username   = "ubuntu"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 20
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  custom_data = base64encode(var.user_data)

  tags = var.tags
}

# =============================================================================
# GCP COMPUTE RESOURCES
# =============================================================================

resource "google_compute_firewall" "main" {
  count = var.cloud_provider == "gcp" ? 1 : 0

  name    = "${var.project_name}-${var.environment}-firewall"
  network = var.vpc_id

  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["${var.project_name}-${var.environment}"]
}

resource "google_compute_instance" "main" {
  count = var.cloud_provider == "gcp" ? var.instance_count : 0

  name         = "${var.project_name}-${var.environment}-instance-${count.index + 1}"
  machine_type = var.instance_type
  zone         = data.google_client_config.current.zone

  tags = ["${var.project_name}-${var.environment}"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 20
    }
  }

  network_interface {
    subnetwork = var.subnet_ids["private-1"]

    access_config {
      // Ephemeral public IP
    }
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }

  metadata_startup_script = var.user_data

  service_account {
    scopes = ["cloud-platform"]
  }

  labels = var.tags
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

output "instance_ids" {
  description = "List of instance IDs"
  value = var.cloud_provider == "aws" ? aws_instance.main[*].id : (
    var.cloud_provider == "azure" ? azurerm_linux_virtual_machine.main[*].id : (
      var.cloud_provider == "gcp" ? google_compute_instance.main[*].id : []
    )
  )
}

output "instance_private_ips" {
  description = "List of private IP addresses"
  value = var.cloud_provider == "aws" ? aws_instance.main[*].private_ip : (
    var.cloud_provider == "azure" ? azurerm_linux_virtual_machine.main[*].private_ip_address : (
      var.cloud_provider == "gcp" ? google_compute_instance.main[*].network_interface[0].network_ip : []
    )
  )
}

output "instance_public_ips" {
  description = "List of public IP addresses"
  value = var.cloud_provider == "aws" ? aws_instance.main[*].public_ip : (
    var.cloud_provider == "azure" ? azurerm_linux_virtual_machine.main[*].public_ip_address : (
      var.cloud_provider == "gcp" ? google_compute_instance.main[*].network_interface[0].access_config[0].nat_ip : []
    )
  )
}

output "security_group_id" {
  description = "Security group/NSG ID"
  value = var.cloud_provider == "aws" ? aws_security_group.main[0].id : (
    var.cloud_provider == "azure" ? azurerm_network_security_group.main[0].id : (
      var.cloud_provider == "gcp" ? google_compute_firewall.main[0].id : null
    )
  )
} 