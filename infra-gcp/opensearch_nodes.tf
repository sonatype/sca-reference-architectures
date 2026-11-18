# The OpenSearch nodes: a reserved internal address, a data disk on data nodes, and one
# Compute Engine instance each, configured by cloud-init on first boot.

resource "google_compute_address" "os" {
  for_each     = local.os_nodes
  name         = "${each.key}-ip"
  address_type = "INTERNAL"
  subnetwork   = local.os_zone_subnets[each.value.zone_index]
  region       = var.gcp_region
  project      = var.gcp_project_id
}

resource "google_compute_disk" "os_data" {
  for_each = local.os_data_nodes
  name     = "${each.key}-data"
  type     = can(regex("^(n4|n4a|n4d|c4|c4a|c4d)-", each.value.type)) ? "hyperdisk-balanced" : "pd-ssd"
  size     = var.opensearch_data_disk_gb
  zone     = local.os_zones[each.value.zone_index]
  project  = var.gcp_project_id
  labels   = local.os_labels
}

resource "google_compute_instance" "os" {
  for_each     = local.os_nodes
  name         = each.key
  machine_type = each.value.type
  zone         = local.os_zones[each.value.zone_index]
  project      = var.gcp_project_id
  tags         = ["nexus-iq-opensearch"]
  labels       = merge(local.os_labels, { opensearch-role = each.value.role })

  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = var.opensearch_boot_image != "" ? var.opensearch_boot_image : (
        can(regex("^(n4a|c4a|t2a)-", each.value.type)) ? "ubuntu-os-cloud/ubuntu-2404-lts-arm64" : "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
      )
      size = var.opensearch_boot_disk_gb
      type = can(regex("^(n4|n4a|n4d|c4|c4a|c4d)-", each.value.type)) ? "hyperdisk-balanced" : "pd-ssd"
    }
  }

  dynamic "attached_disk" {
    for_each = each.value.role == "data" ? [1] : []
    content {
      source      = google_compute_disk.os_data[each.key].self_link
      device_name = "osdata"
    }
  }

  network_interface {
    subnetwork = local.os_zone_subnets[each.value.zone_index]
    network_ip = google_compute_address.os[each.key].address
    nic_type   = "GVNIC"
  }

  service_account {
    email  = google_service_account.opensearch[0].email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
    user-data = templatefile("${path.module}/templates/opensearch-cloud-init.yaml.tftpl", {
      project   = var.gcp_project_id
      bootstrap = each.value.bootstrap
      setup_script = templatefile("${path.module}/templates/opensearch-node-setup.sh.tftpl", {
        node_name             = each.key
        is_data               = each.value.role == "data"
        bootstrap             = each.value.bootstrap
        single_node           = !local.os_cluster
        opensearch_version    = var.opensearch_version
        cluster_name          = local.os_org
        node_roles            = jsonencode(each.value.roles)
        zone                  = local.os_zones[each.value.zone_index]
        heap_mb               = each.value.heap_gb * 1024
        seed_hosts            = jsonencode([for k, v in local.os_manager_nodes : "${google_compute_address.os[k].address}:9300"])
        initial_managers      = jsonencode(keys(local.os_manager_nodes))
        force_zone_values     = length(distinct(local.os_zones)) >= 3 ? join(",", distinct(local.os_zones)) : ""
        admin_dn              = local.os_admin_dn
        nodes_dn              = local.os_nodes_dn
        ca_secret             = google_secret_manager_secret.opensearch_ca[0].secret_id
        crt_secret            = google_secret_manager_secret.os["${each.key}-crt"].secret_id
        key_secret            = google_secret_manager_secret.os["${each.key}-key"].secret_id
        admin_crt_secret      = google_secret_manager_secret.os["${local.os_prefix}-os-admin-crt"].secret_id
        admin_key_secret      = google_secret_manager_secret.os["${local.os_prefix}-os-admin-key"].secret_id
        admin_password_secret = google_secret_manager_secret.os["${local.os_prefix}-os-admin-password"].secret_id
      })
      iq_user_script = templatefile("${path.module}/templates/opensearch-iq-user.sh.tftpl", {
        node_ip               = google_compute_address.os[each.key].address
        data_node_count       = var.opensearch_data_node_count
        iq_username           = local.os_iq_username
        admin_password_secret = google_secret_manager_secret.os["${local.os_prefix}-os-admin-password"].secret_id
        iq_password_secret    = google_secret_manager_secret.opensearch_password[0].secret_id
      })
    })
  }

  lifecycle {
    # A change to the boot configuration is rolled out one node at a time by replacing that
    # node, never by replacing every node in one apply.
    ignore_changes = [metadata["user-data"]]

    precondition {
      condition     = var.opensearch_use_tls
      error_message = "opensearch_use_tls must be true when this configuration builds the OpenSearch cluster: the security plugin it runs needs TLS."
    }
    precondition {
      condition     = var.opensearch_port == 9200
      error_message = "opensearch_port must be 9200 when this configuration builds the OpenSearch cluster."
    }
    precondition {
      condition     = local.os_data_heap_gb >= 1 && local.os_mgr_heap_gb >= 1
      error_message = "The OpenSearch heap could not be derived from the machine type. Set opensearch_data_heap_gb and opensearch_manager_heap_gb."
    }
    precondition {
      condition     = local.os_zones_valid && length(local.os_zones) > 0
      error_message = "opensearch_zones must name zones this configuration has a private subnet in."
    }
  }

  depends_on = [
    google_secret_manager_secret_version.os,
    google_secret_manager_secret_version.opensearch_ca,
    google_secret_manager_secret_version.opensearch_password,
    google_secret_manager_secret_iam_member.os,
    google_secret_manager_secret_iam_member.os_ca,
    google_secret_manager_secret_iam_member.os_iq_password,
  ]
}

# Node to node traffic on the REST and transport ports.
resource "google_compute_firewall" "os_cluster" {
  count   = local.opensearch_create ? 1 : 0
  name    = "${local.os_prefix}-os-cluster"
  network = local.os_network
  project = var.gcp_project_id

  allow {
    protocol = "tcp"
    ports    = ["9200", "9300"]
  }

  source_tags = ["nexus-iq-opensearch"]
  target_tags = ["nexus-iq-opensearch"]
  description = "OpenSearch node to node traffic"
}
