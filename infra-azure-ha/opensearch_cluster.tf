# The OpenSearch cluster this configuration builds when search_engine is "opensearch" and
# opensearch_create is not false. One VM per node on Ubuntu 24.04 for Arm, set up at first boot by
# templates/opensearch-node.yaml.tftpl. With one data node that node also manages the cluster and IQ
# Server reaches it directly. With three or more there are three dedicated cluster managers, and IQ
# Server reaches the data nodes through a Standard internal load balancer.

locals {
  os_create  = local.opensearch_enabled && coalesce(var.opensearch_create, var.opensearch_endpoint == "")
  os_cluster = var.opensearch_data_node_count > 1
  os_prefix  = var.cluster_name

  os_organization = "${local.os_prefix}-opensearch"
  os_zones        = length(var.opensearch_zones) > 0 ? var.opensearch_zones : ["1", "2", "3"]
  os_lb_ip        = cidrhost(var.opensearch_subnet_cidr, 100)

  # Half of the VM size's memory, at most 31 GB, from the size names this configuration publishes.
  # A size not listed needs opensearch_data_heap_gb or opensearch_manager_heap_gb.
  os_vm_memory_gb = {
    Standard_D2pls_v6 = 4
    Standard_D4pls_v6 = 8
    Standard_D2ps_v6  = 8
    Standard_D4ps_v6  = 16
    Standard_D8ps_v6  = 32
    Standard_E2ps_v6  = 16
    Standard_E4ps_v6  = 32
    Standard_E8ps_v6  = 64
    # The previous Arm series, which deploy.sh suggests when a zone has no v6 capacity.
    Standard_D2pls_v5 = 4
    Standard_D4pls_v5 = 8
    Standard_D2ps_v5  = 8
    Standard_D4ps_v5  = 16
    Standard_D8ps_v5  = 32
    Standard_E2ps_v5  = 16
    Standard_E4ps_v5  = 32
    Standard_E8ps_v5  = 64
  }
  os_data_heap_gb    = coalesce(var.opensearch_data_heap_gb, min(31, floor(lookup(local.os_vm_memory_gb, var.opensearch_data_instance_type, 0) / 2)))
  os_manager_heap_gb = coalesce(var.opensearch_manager_heap_gb, min(31, floor(lookup(local.os_vm_memory_gb, var.opensearch_manager_instance_type, 0) / 2)))

  # A single node has its own key, name and address. A node is set up only at first boot, so
  # moving between one and three or more data nodes replaces every data node and its disk.
  os_data_nodes = {
    for i in range(var.opensearch_data_node_count) : (local.os_cluster ? "data-${i + 1}" : "solo-1") => {
      name     = local.os_cluster ? "${local.os_prefix}-os-data-${i + 1}" : "${local.os_prefix}-os-solo-1"
      ip       = cidrhost(var.opensearch_subnet_cidr, local.os_cluster ? 11 + i : 10)
      zone     = local.os_zones[i % length(local.os_zones)]
      roles    = local.os_cluster ? "data,ingest" : "cluster_manager,data,ingest"
      vm_size  = var.opensearch_data_instance_type
      heap_mb  = local.os_data_heap_gb * 1024
      has_data = true
    }
  }
  os_manager_nodes = {
    for i in range(local.os_cluster ? 3 : 0) : "mgr-${i + 1}" => {
      name     = "${local.os_prefix}-os-mgr-${i + 1}"
      ip       = cidrhost(var.opensearch_subnet_cidr, 21 + i)
      zone     = local.os_zones[i % length(local.os_zones)]
      roles    = "cluster_manager"
      vm_size  = var.opensearch_manager_instance_type
      heap_mb  = local.os_manager_heap_gb * 1024
      has_data = false
    }
  }
  os_nodes = local.os_create ? merge(local.os_data_nodes, local.os_manager_nodes) : {}

  # The node that creates the IQ Server user: the first manager, or the single node.
  os_bootstrap_key = local.os_cluster ? "mgr-1" : "solo-1"

  os_endpoint = local.os_create ? (local.os_cluster ? local.os_lb_ip : cidrhost(var.opensearch_subnet_cidr, 10)) : var.opensearch_endpoint
  os_password = local.os_create && var.opensearch_password == "" ? try(random_password.os_iq[0].result, "") : var.opensearch_password
  os_ca_pem   = local.os_create ? tls_self_signed_cert.os_ca[0].cert_pem : ""
  # Base64 of the authority IQ Server trusts, in the form the container entrypoint decodes.
  os_ca_pem_b64 = local.os_create ? base64encode(local.os_ca_pem) : var.opensearch_ca_pem
  # A replica needs a second data node, so a created single node gets none.
  os_replicas = local.os_create ? min(var.opensearch_index_replicas, var.opensearch_data_node_count - 1) : var.opensearch_index_replicas

  os_admin_password = var.opensearch_admin_password != "" ? var.opensearch_admin_password : try(random_password.os_admin[0].result, "")
  os_username       = var.opensearch_username != "" ? var.opensearch_username : "iq-server"

  os_force_zones = length(distinct(local.os_zones)) >= 3 ? join(",", distinct(local.os_zones)) : ""
}

resource "azurerm_subnet" "opensearch" {
  count                = local.os_create ? 1 : 0
  name                 = "snet-opensearch"
  resource_group_name  = azurerm_resource_group.iq_rg.name
  virtual_network_name = azurerm_virtual_network.iq_vnet.name
  address_prefixes     = [var.opensearch_subnet_cidr]
  service_endpoints    = ["Microsoft.KeyVault"]

  # Checks that compare variables, here so they fail at plan rather than on a node at boot.
  lifecycle {
    precondition {
      condition     = var.opensearch_use_tls
      error_message = "opensearch_use_tls must be true when this configuration builds the OpenSearch cluster: the security plugin it installs serves HTTPS only."
    }

    precondition {
      condition     = local.os_data_heap_gb >= 1 && (!local.os_cluster || local.os_manager_heap_gb >= 1)
      error_message = "The OpenSearch heap cannot be derived for this VM size. Set opensearch_data_heap_gb and opensearch_manager_heap_gb."
    }

    precondition {
      condition     = can(regex("^Standard_[A-Z][0-9]+[a-z]*p[a-z]*_v[0-9]+$", var.opensearch_data_instance_type)) && (!local.os_cluster || can(regex("^Standard_[A-Z][0-9]+[a-z]*p[a-z]*_v[0-9]+$", var.opensearch_manager_instance_type)))
      error_message = "The OpenSearch nodes run Ubuntu for Arm, so opensearch_data_instance_type and opensearch_manager_instance_type must be Arm VM sizes, such as Standard_D2ps_v6."
    }

    precondition {
      condition     = cidrsubnet(var.opensearch_subnet_cidr, 0, 0) == var.opensearch_subnet_cidr && tonumber(split("/", var.opensearch_subnet_cidr)[1]) <= 25
      error_message = "opensearch_subnet_cidr must be a network address with a prefix of /25 or shorter, so the fixed node and load balancer addresses fit."
    }
  }
}

resource "azurerm_network_security_group" "opensearch" {
  count               = local.os_create ? 1 : 0
  name                = "nsg-opensearch-${var.cluster_name}"
  location            = azurerm_resource_group.iq_rg.location
  resource_group_name = azurerm_resource_group.iq_rg.name

  security_rule {
    name                       = "AllowIQServer"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9200"
    source_address_prefixes    = local.os_iq_subnet_cidrs
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowCluster"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["9200", "9300"]
    source_address_prefix      = var.opensearch_subnet_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowLoadBalancerProbe"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9200"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = merge(local.os_tags, {
    Name = "nsg-opensearch-${var.cluster_name}"
  })
}

resource "azurerm_subnet_network_security_group_association" "opensearch" {
  count                     = local.os_create ? 1 : 0
  subnet_id                 = azurerm_subnet.opensearch[0].id
  network_security_group_id = azurerm_network_security_group.opensearch[0].id
}

# A VM behind a Standard internal load balancer has no default outbound access, and every node
# downloads its package at first boot, so the subnet gets its own NAT gateway.
resource "azurerm_public_ip" "os_nat" {
  count               = local.os_create ? 1 : 0
  name                = "pip-nat-opensearch-${var.cluster_name}"
  location            = azurerm_resource_group.iq_rg.location
  resource_group_name = azurerm_resource_group.iq_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]

  tags = merge(local.os_tags, {
    Name = "pip-nat-opensearch-${var.cluster_name}"
  })
}

resource "azurerm_nat_gateway" "opensearch" {
  count                   = local.os_create ? 1 : 0
  name                    = "nat-opensearch-${var.cluster_name}"
  location                = azurerm_resource_group.iq_rg.location
  resource_group_name     = azurerm_resource_group.iq_rg.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10

  tags = merge(local.os_tags, {
    Name = "nat-opensearch-${var.cluster_name}"
  })
}

resource "azurerm_nat_gateway_public_ip_association" "opensearch" {
  count                = local.os_create ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.opensearch[0].id
  public_ip_address_id = azurerm_public_ip.os_nat[0].id
}

resource "azurerm_subnet_nat_gateway_association" "opensearch" {
  count          = local.os_create ? 1 : 0
  subnet_id      = azurerm_subnet.opensearch[0].id
  nat_gateway_id = azurerm_nat_gateway.opensearch[0].id
}
