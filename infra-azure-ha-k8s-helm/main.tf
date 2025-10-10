terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.iq_aks.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.iq_aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.iq_aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.iq_aks.kube_config.0.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.iq_aks.kube_config.0.host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.iq_aks.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.iq_aks.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.iq_aks.kube_config.0.cluster_ca_certificate)
  }
}

data "azurerm_client_config" "current" {}

# Local variables for common configuration
locals {
  cluster_name        = var.cluster_name
  resource_group_name = "rg-${var.cluster_name}"
  availability_zones  = ["1", "2", "3"]

  common_tags = {
    Project     = "nexus-iq-server-ha"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Purpose     = "kubernetes-ha-deployment"
  }
}

# Resource Group
resource "azurerm_resource_group" "iq_rg" {
  name     = local.resource_group_name
  location = var.azure_region

  tags = local.common_tags
}

# Virtual Network
resource "azurerm_virtual_network" "iq_vnet" {
  name                = "vnet-${var.cluster_name}"
  address_space       = [var.vnet_cidr]
  location            = azurerm_resource_group.iq_rg.location
  resource_group_name = azurerm_resource_group.iq_rg.name

  tags = merge(local.common_tags, {
    Name = "vnet-${var.cluster_name}"
  })
}

# Public Subnet for Application Gateway
resource "azurerm_subnet" "public_subnet" {
  name                 = "snet-public"
  resource_group_name  = azurerm_resource_group.iq_rg.name
  virtual_network_name = azurerm_virtual_network.iq_vnet.name
  address_prefixes     = [var.public_subnet_cidr]
}

# Private Subnet for AKS nodes
resource "azurerm_subnet" "aks_subnet" {
  name                 = "snet-aks"
  resource_group_name  = azurerm_resource_group.iq_rg.name
  virtual_network_name = azurerm_virtual_network.iq_vnet.name
  address_prefixes     = [var.aks_subnet_cidr]

  service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault"]
}

# Database Subnet for PostgreSQL Flexible Server
resource "azurerm_subnet" "db_subnet" {
  name                 = "snet-database"
  resource_group_name  = azurerm_resource_group.iq_rg.name
  virtual_network_name = azurerm_virtual_network.iq_vnet.name
  address_prefixes     = [var.db_subnet_cidr]

  delegation {
    name = "postgres-delegation"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# Network Security Group for Public Subnet (Application Gateway)
resource "azurerm_network_security_group" "public_nsg" {
  name                = "nsg-public-${var.cluster_name}"
  location            = azurerm_resource_group.iq_rg.location
  resource_group_name = azurerm_resource_group.iq_rg.name

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowAppGatewayManagement"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  tags = merge(local.common_tags, {
    Name = "nsg-public-${var.cluster_name}"
  })
}

# Network Security Group for AKS Subnet
resource "azurerm_network_security_group" "aks_nsg" {
  name                = "nsg-aks-${var.cluster_name}"
  location            = azurerm_resource_group.iq_rg.location
  resource_group_name = azurerm_resource_group.iq_rg.name

  security_rule {
    name                       = "AllowAKSHTTP"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = var.public_subnet_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowAzureLoadBalancer"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowAKSHTTPS"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = var.public_subnet_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowNexusIQLoadBalancer"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["8070", "30000-32767"]  # Nexus IQ and NodePort range
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowNexusIQInternal"
    priority                   = 1004
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["8070", "8071"]
    source_address_prefix      = var.aks_subnet_cidr
    destination_address_prefix = "*"
  }

  tags = merge(local.common_tags, {
    Name = "nsg-aks-${var.cluster_name}"
  })
}

# Network Security Group for Database Subnet
resource "azurerm_network_security_group" "db_nsg" {
  name                = "nsg-db-${var.cluster_name}"
  location            = azurerm_resource_group.iq_rg.location
  resource_group_name = azurerm_resource_group.iq_rg.name

  security_rule {
    name                       = "AllowPostgreSQL"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = var.aks_subnet_cidr
    destination_address_prefix = "*"
  }

  tags = merge(local.common_tags, {
    Name = "nsg-db-${var.cluster_name}"
  })
}

# Associate NSGs with Subnets
resource "azurerm_subnet_network_security_group_association" "public_nsg_association" {
  subnet_id                 = azurerm_subnet.public_subnet.id
  network_security_group_id = azurerm_network_security_group.public_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "aks_nsg_association" {
  subnet_id                 = azurerm_subnet.aks_subnet.id
  network_security_group_id = azurerm_network_security_group.aks_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "db_nsg_association" {
  subnet_id                 = azurerm_subnet.db_subnet.id
  network_security_group_id = azurerm_network_security_group.db_nsg.id
}

# Random string for DNS uniqueness
resource "random_string" "dns_suffix" {
  length  = 6
  special = false
  upper   = false
}

# Public IP for Application Gateway
resource "azurerm_public_ip" "appgw_pip" {
  name                = "pip-appgw-${var.cluster_name}"
  resource_group_name = azurerm_resource_group.iq_rg.name
  location            = azurerm_resource_group.iq_rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = local.availability_zones
  domain_name_label   = "${var.cluster_name}-${random_string.dns_suffix.result}"

  tags = merge(local.common_tags, {
    Name = "pip-appgw-${var.cluster_name}"
  })
}
