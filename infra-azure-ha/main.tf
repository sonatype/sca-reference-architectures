terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
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

data "azurerm_client_config" "current" {}

# Get available zones for HA deployment (using client config for region info)
locals {
  availability_zones = ["1", "2", "3"] # East US has zones 1, 2, 3
}

# Resource Group
resource "azurerm_resource_group" "iq_rg" {
  name     = "rg-ref-arch-iq-ha"
  location = var.azure_region

  tags = var.common_tags
}

# Virtual Network with multiple subnets for HA
resource "azurerm_virtual_network" "iq_vnet" {
  name                = "vnet-ref-arch-iq-ha"
  address_space       = [var.vnet_cidr]
  location            = azurerm_resource_group.iq_rg.location
  resource_group_name = azurerm_resource_group.iq_rg.name

  tags = merge(var.common_tags, {
    Name = "vnet-ref-arch-iq-ha"
  })
}

# Public Subnets (for Application Gateway) - Multiple zones for HA
resource "azurerm_subnet" "public_subnets" {
  count                = length(var.public_subnet_cidrs)
  name                 = "snet-public-${count.index + 1}"
  resource_group_name  = azurerm_resource_group.iq_rg.name
  virtual_network_name = azurerm_virtual_network.iq_vnet.name
  address_prefixes     = [var.public_subnet_cidrs[count.index]]
}

# Private Subnets (for Container Apps) - Multiple zones for HA
resource "azurerm_subnet" "private_subnets" {
  count                = length(var.private_subnet_cidrs)
  name                 = "snet-private-${count.index + 1}"
  resource_group_name  = azurerm_resource_group.iq_rg.name
  virtual_network_name = azurerm_virtual_network.iq_vnet.name
  address_prefixes     = [var.private_subnet_cidrs[count.index]]

  service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage"]
}

# Database Subnet (for PostgreSQL Flexible Server with zone redundancy)
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

# Network Security Group for Application Gateway (HA)
resource "azurerm_network_security_group" "public_nsg" {
  name                = "nsg-public-ha"
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

  tags = merge(var.common_tags, {
    Name = "nsg-public-ha"
  })
}

# Network Security Group for Container Apps (HA)
resource "azurerm_network_security_group" "private_nsg" {
  name                = "nsg-private-ha"
  location            = azurerm_resource_group.iq_rg.location
  resource_group_name = azurerm_resource_group.iq_rg.name

  security_rule {
    name                       = "AllowContainerAppsHTTP"
    priority                   = 900
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowContainerAppsHTTPS"
    priority                   = 901
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowAzureLoadBalancer"
    priority                   = 902
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "30000-32767"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  # Allow inter-replica communication for clustering
  security_rule {
    name                       = "AllowClusterCommunication"
    priority                   = 903
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["8070", "8071"]
    source_address_prefixes    = var.private_subnet_cidrs
    destination_address_prefix = "*"
  }

  tags = merge(var.common_tags, {
    Name = "nsg-private-ha"
  })
}

# Network Security Group for Database (HA)
resource "azurerm_network_security_group" "db_nsg" {
  name                = "nsg-database-ha"
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
    source_address_prefixes    = var.private_subnet_cidrs
    destination_address_prefix = "*"
  }

  tags = merge(var.common_tags, {
    Name = "nsg-database-ha"
  })
}

# Associate NSGs with subnets
resource "azurerm_subnet_network_security_group_association" "public_nsg_association" {
  count                     = length(azurerm_subnet.public_subnets)
  subnet_id                 = azurerm_subnet.public_subnets[count.index].id
  network_security_group_id = azurerm_network_security_group.public_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "private_nsg_association" {
  count                     = length(azurerm_subnet.private_subnets)
  subnet_id                 = azurerm_subnet.private_subnets[count.index].id
  network_security_group_id = azurerm_network_security_group.private_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "db_nsg_association" {
  subnet_id                 = azurerm_subnet.db_subnet.id
  network_security_group_id = azurerm_network_security_group.db_nsg.id
}