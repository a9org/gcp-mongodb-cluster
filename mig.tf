# Managed Instance Groups (MIG) for each shard
resource "google_compute_region_instance_group_manager" "mongodb_shard" {
  count = 3
  name  = "mongodb-shard-${count.index + 1}"

  base_instance_name = "mongodb-shard-${count.index + 1}"
  region            = var.region

  version {
    instance_template = google_compute_instance_template.mongodb_template.id
  }

  target_size = 3

  named_port {
    name = "mongodb"
    port = 27017
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.mongodb_health_check.id
    initial_delay_sec = 300
  }
}

# Health Check
resource "google_compute_health_check" "mongodb_health_check" {
  name               = "mongodb-health-check"
  timeout_sec        = 5
  check_interval_sec = 10

  tcp_health_check {
    port = 27017
  }
}

# Autoscaler for each shard
resource "google_compute_region_autoscaler" "mongodb_autoscaler" {
  count  = var.autoscaling_enabled ? 3 : 0
  name   = "mongodb-autoscaler-${count.index + 1}"
  region = "us-central1"
  target = google_compute_region_instance_group_manager.mongodb_shard[count.index].id

  autoscaling_policy {
    max_replicas    = 5
    min_replicas    = 3
    cooldown_period = 60

    cpu_utilization {
      target = 0.7
    }
  }
}