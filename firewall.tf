#tfsec:ignore:google-compute-no-public-ingress
resource "google_compute_firewall" "mongodb_firewall" {
  name    = "${local.prefix_name}-mongodb-firewall"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["27017", "22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["mongodb-node", "${local.prefix_name}-mongodb-node"]
}

resource "google_compute_firewall" "mongodb" {
  name    = "${local.prefix_name}-mongodb-allow-replicaset"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["27017"]
  }

  source_tags = ["${local.prefix_name}-mongodb-node"]
  target_tags = ["${local.prefix_name}-mongodb-node"]
}
