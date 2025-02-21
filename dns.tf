# Cloud DNS (opcional)
resource "google_dns_managed_zone" "mongodb_zone" {
  count      = var.create_dns ? 1 : 0
  name       = "${local.prefix_name}-mongodb-zone"
  dns_name   = "mongodb.internal."
  visibility = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.mongodb_network.id
    }
  }
  labels = local.common_tags
}

resource "google_dns_record_set" "mongodb" {
  count        = var.create_dns ? 3 : 0
  name         = "shard-${count.index + 1}.mongodb.internal."
  managed_zone = google_dns_managed_zone.mongodb_zone.name
  type         = "A"
  ttl          = 300

  rrdatas = [google_compute_forwarding_rule.mongodb_forwarding_rule[count.index].ip_address]
}