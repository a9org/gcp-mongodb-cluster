# Firewall rules for MongoDB cluster
resource "google_compute_firewall" "mongodb_internal" {
  name    = "${local.prefix_name}-mongodb-internal"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["27017", "27018", "27019"] # Portas para replicação e sharding
  }

  source_tags = ["mongodb-node"]
  target_tags = ["mongodb-node"]
}

resource "google_compute_firewall" "mongodb_admin" {
  name    = "${local.prefix_name}-mongodb-admin"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["22", "27017"]
  }

  # Usar variável para ranges permitidos
  source_ranges = var.allowed_ip_ranges
  target_tags   = ["mongodb-node"]
}

resource "google_compute_firewall" "mongodb_egress" {
  name      = "${local.prefix_name}-mongodb-egress"
  network   = var.network
  direction = "EGRESS"

  allow {
    protocol = "tcp"
    ports    = ["443", "80"] # Permitir apenas HTTPS/HTTP para updates
  }

  target_tags = ["mongodb-node"]

  # Definir destinos específicos para egress
  destination_ranges = ["0.0.0.0/0"]
}