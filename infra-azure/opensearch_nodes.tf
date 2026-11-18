# The OpenSearch VMs, their identity and the Key Vault secrets they read at boot.

resource "azurerm_user_assigned_identity" "opensearch" {
  count               = local.os_create ? 1 : 0
  name                = "id-opensearch-${var.cluster_name}"
  location            = azurerm_resource_group.iq_rg.location
  resource_group_name = azurerm_resource_group.iq_rg.name

  tags = merge(local.os_tags, {
    Name = "id-opensearch-${var.cluster_name}"
  })
}

# One identity for every node: the nodes trust each other on the transport layer anyway, so a
# node reading another node's key gives it nothing it does not already have.
resource "azurerm_key_vault_access_policy" "opensearch" {
  count        = local.os_create ? 1 : 0
  key_vault_id = local.os_key_vault_id
  tenant_id    = azurerm_user_assigned_identity.opensearch[0].tenant_id
  object_id    = azurerm_user_assigned_identity.opensearch[0].principal_id

  secret_permissions = ["Get"]
}

locals {
  os_secret_names = local.os_create ? concat(
    ["os-ca-crt", "os-admin-crt", "os-admin-key", "os-admin-password", "os-iq-password"],
    [for k in keys(local.os_nodes) : "os-${k}-crt"],
    [for k in keys(local.os_nodes) : "os-${k}-key"],
  ) : []
  os_secret_values = local.os_create ? merge(
    {
      "os-ca-crt"         = local.os_ca_pem
      "os-admin-crt"      = tls_locally_signed_cert.os_admin[0].cert_pem
      "os-admin-key"      = tls_private_key.os_admin[0].private_key_pem_pkcs8
      "os-admin-password" = local.os_admin_password
      "os-iq-password"    = local.os_password
    },
    { for k, n in local.os_nodes : "os-${k}-crt" => tls_locally_signed_cert.os_node[k].cert_pem },
    # The security plugin reads PKCS#8 keys only.
    { for k, n in local.os_nodes : "os-${k}-key" => tls_private_key.os_node[k].private_key_pem_pkcs8 },
  ) : {}
}

resource "azurerm_key_vault_secret" "opensearch" {
  for_each     = toset(local.os_secret_names)
  name         = each.key
  value        = local.os_secret_values[each.key]
  key_vault_id = local.os_key_vault_id

  tags = merge(local.os_tags, {
    Name = each.key
  })
}

resource "azurerm_network_interface" "opensearch" {
  for_each            = local.os_nodes
  name                = "nic-${each.value.name}"
  location            = azurerm_resource_group.iq_rg.location
  resource_group_name = azurerm_resource_group.iq_rg.name

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.opensearch[0].id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.ip
  }

  tags = merge(local.os_tags, {
    Name = "nic-${each.value.name}"
  })
}

# Break-glass access only: the subnet admits no SSH, so reaching a node means az vm run-command or
# the serial console. The key stays in Terraform state.
resource "tls_private_key" "os_ssh" {
  count     = local.os_create ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_linux_virtual_machine" "opensearch" {
  for_each              = local.os_nodes
  name                  = each.value.name
  location              = azurerm_resource_group.iq_rg.location
  resource_group_name   = azurerm_resource_group.iq_rg.name
  size                  = each.value.vm_size
  zone                  = each.value.zone
  network_interface_ids = [azurerm_network_interface.opensearch[each.key].id]
  admin_username        = "azureuser"

  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.os_ssh[0].public_key_openssh
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.opensearch[0].id]
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.opensearch_os_disk_gb
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server-arm64"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/templates/opensearch-node.yaml.tftpl", {
    node_script = file("${path.module}/templates/opensearch-node.sh")
    settings = {
      OS_CLOUD                 = "azure"
      OS_AZURE_CLIENT_ID       = azurerm_user_assigned_identity.opensearch[0].client_id
      OS_AZURE_VAULT_URL       = trimsuffix(local.os_key_vault_uri, "/")
      OS_GCP_PROJECT           = ""
      OS_VERSION               = var.opensearch_version
      OS_CLUSTER_NAME          = local.os_organization
      OS_NODE_NAME             = each.value.name
      OS_NODE_IP               = each.value.ip
      OS_NODE_ZONE             = each.value.zone
      OS_NODE_ROLES            = each.value.roles
      OS_HAS_DATA              = tostring(each.value.has_data)
      OS_SINGLE_NODE           = tostring(!local.os_cluster)
      OS_SEED_HOSTS            = join(",", [for k, n in local.os_manager_nodes : n.ip])
      OS_MANAGER_NODES         = join(",", [for k, n in local.os_manager_nodes : n.name])
      OS_FORCE_ZONES           = local.os_force_zones
      OS_HEAP_MB               = tostring(each.value.heap_mb)
      OS_DATA_DISK             = "/dev/disk/azure/data/by-lun/0"
      OS_ADMIN_DN              = "CN=admin,O=${local.os_organization}"
      OS_NODES_DN              = "CN=${local.os_prefix}-os-*,O=${local.os_organization}"
      OS_SECRET_CA_CERT        = "os-ca-crt"
      OS_SECRET_NODE_CERT      = "os-${each.key}-crt"
      OS_SECRET_NODE_KEY       = "os-${each.key}-key"
      OS_SECRET_ADMIN_CERT     = each.value.has_data && local.os_cluster ? "" : "os-admin-crt"
      OS_SECRET_ADMIN_KEY      = each.value.has_data && local.os_cluster ? "" : "os-admin-key"
      OS_SECRET_ADMIN_PASSWORD = "os-admin-password"
      OS_SECRET_IQ_PASSWORD    = "os-iq-password"
      OS_IQ_USERNAME           = local.os_username
      OS_BOOTSTRAP_IQ_USER     = tostring(each.key == local.os_bootstrap_key)
    }
  }))

  tags = merge(local.os_tags, {
    Name = each.value.name
    role = each.value.has_data ? "opensearch-data" : "opensearch-manager"
  })

  # A node is set up once, at first boot. A later template change is rolled out deliberately,
  # one node at a time, rather than by replacing every node in one apply.
  lifecycle {
    ignore_changes = [custom_data]
  }

  depends_on = [
    azurerm_key_vault_access_policy.opensearch,
    azurerm_key_vault_secret.opensearch,
    azurerm_subnet_nat_gateway_association.opensearch,
    azurerm_subnet_network_security_group_association.opensearch,
    azurerm_nat_gateway_public_ip_association.opensearch,
  ]
}

resource "azurerm_managed_disk" "opensearch_data" {
  for_each             = { for k, n in local.os_nodes : k => n if n.has_data }
  name                 = "disk-${each.value.name}-data"
  location             = azurerm_resource_group.iq_rg.location
  resource_group_name  = azurerm_resource_group.iq_rg.name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.opensearch_data_disk_gb
  zone                 = each.value.zone

  tags = merge(local.os_tags, {
    Name = "disk-${each.value.name}-data"
  })
}

resource "azurerm_virtual_machine_data_disk_attachment" "opensearch_data" {
  for_each           = azurerm_managed_disk.opensearch_data
  managed_disk_id    = each.value.id
  virtual_machine_id = azurerm_linux_virtual_machine.opensearch[each.key].id
  lun                = 0
  caching            = "ReadOnly"
}
