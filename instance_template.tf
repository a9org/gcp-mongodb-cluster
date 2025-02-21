resource "google_compute_instance_template" "mongodb_template" {
  name        = "mongodb-template"
  description = "Template for MongoDB instances"

  tags = ["mongodb-node"]

  machine_type = var.machine_type

  disk {
    source_image = "ubuntu-os-cloud/ubuntu-2004-lts"
    auto_delete  = true
    boot         = true
    disk_size_gb = 100
    disk_type    = "pd-ssd"
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y wget gnupg
    wget -qO - https://www.mongodb.org/static/pgp/server-5.0.asc | apt-key add -
    echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/5.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-5.0.list
    apt-get update
    apt-get install -y mongodb-org
    systemctl start mongod
    systemctl enable mongod
  EOF

  service_account {
    scopes = ["cloud-platform"]
  }
}