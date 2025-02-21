# Firewall Rules
resource "google_compute_firewall" "mongodb_firewall" {
  name    = "${local.prefix_name}-mongodb-firewall"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["27017", "22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["mongodb-node"]

  labels = local.common_tags
}
