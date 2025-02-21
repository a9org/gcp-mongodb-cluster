# Cloud DNS (opcional)
resource "google_dns_managed_zone" "mongodb_zone" {
  count      = var.create_dns ? 1 : 0
  name       = "${local.prefix_name}-mongodb-zone"
  dns_name   = "mongodb.internal."
  visibility = "private"

  private_visibility_config {
    networks {
      network_url = var.network
    }
  }
  labels = local.common_tags
}

resource "google_dns_record_set" "mongodb" {
  count        = var.create_dns ? 1 : 0
  name         = "rs.mongodb.internal."
  managed_zone = google_dns_managed_zone.mongodb_zone[0].name
  type         = "A"
  ttl          = 300

  rrdatas = [google_compute_forwarding_rule.mongodb_forwarding_rule.ip_address]
}