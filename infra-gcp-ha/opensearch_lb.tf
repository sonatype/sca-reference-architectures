# At M and above, Nexus IQ Server reaches the three data nodes through an internal passthrough
# load balancer on one address, which every data node certificate names. TLS passes through.

resource "google_compute_address" "os_lb" {
  count        = local.os_cluster ? 1 : 0
  name         = "${local.os_prefix}-os-lb-ip"
  address_type = "INTERNAL"
  subnetwork   = local.os_zone_subnets[0]
  region       = var.gcp_region
  project      = var.gcp_project_id
}

resource "google_compute_region_health_check" "os" {
  count               = local.os_cluster ? 1 : 0
  name                = "${local.os_prefix}-os-health"
  region              = var.gcp_region
  project             = var.gcp_project_id
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 2

  tcp_health_check {
    port = 9200
  }
}

# One unmanaged group per zone, since a group holds instances of one zone only.
resource "google_compute_instance_group" "os" {
  for_each = local.os_cluster ? toset(local.os_data_zones) : toset([])
  name     = "${local.os_prefix}-os-${each.key}"
  zone     = each.key
  network  = local.os_network
  project  = var.gcp_project_id
}

# Membership is replaced with the node, so a replaced node with the same name rejoins.
resource "google_compute_instance_group_membership" "os" {
  for_each       = local.os_cluster ? local.os_data_nodes : {}
  instance       = google_compute_instance.os[each.key].self_link
  instance_group = google_compute_instance_group.os[local.os_zones[each.value.zone_index]].name
  zone           = local.os_zones[each.value.zone_index]
  project        = var.gcp_project_id

  lifecycle {
    replace_triggered_by = [google_compute_instance.os[each.key].instance_id]
  }
}

resource "google_compute_region_backend_service" "os" {
  count                 = local.os_cluster ? 1 : 0
  name                  = "${local.os_prefix}-os"
  region                = var.gcp_region
  project               = var.gcp_project_id
  load_balancing_scheme = "INTERNAL"
  protocol              = "TCP"
  health_checks         = [google_compute_region_health_check.os[0].id]

  dynamic "backend" {
    for_each = google_compute_instance_group.os
    content {
      group          = backend.value.id
      balancing_mode = "CONNECTION"
    }
  }
}

resource "google_compute_forwarding_rule" "os" {
  count                 = local.os_cluster ? 1 : 0
  name                  = "${local.os_prefix}-os"
  region                = var.gcp_region
  project               = var.gcp_project_id
  load_balancing_scheme = "INTERNAL"
  ip_protocol           = "TCP"
  ports                 = ["9200"]
  ip_address            = google_compute_address.os_lb[0].address
  backend_service       = google_compute_region_backend_service.os[0].id
  network               = local.os_network
  subnetwork            = local.os_zone_subnets[0]
}

# Google's health check ranges, which reach the data nodes directly.
resource "google_compute_firewall" "os_health" {
  count   = local.os_cluster ? 1 : 0
  name    = "${local.os_prefix}-os-health"
  network = local.os_network
  project = var.gcp_project_id

  allow {
    protocol = "tcp"
    ports    = ["9200"]
  }

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["nexus-iq-opensearch"]
  description   = "Health checks for the OpenSearch internal load balancer"
}
