# Load Balancer
resource "google_compute_region_backend_service" "mongodb_backend" {
  count         = 3
  name          = "${local.prefix_name}-mongodb-backend-${count.index + 1}"
  region        = var.region
  protocol      = "TCP"
  health_checks = [google_compute_health_check.mongodb_health_check.id]

  backend {
    group = google_compute_region_instance_group_manager.mongodb_shard[count.index].instance_group
  }

  labels = local.common_tags
}

# Forwarding Rule
resource "google_compute_forwarding_rule" "mongodb_forwarding_rule" {
  count                 = 3
  name                  = "${local.prefix_name}-mongodb-forwarding-rule-${count.index + 1}"
  region                = var.region
  port_range            = "27017"
  backend_service       = google_compute_region_backend_service.mongodb_backend[count.index].id
  load_balancing_scheme = "INTERNAL"
  network               = var.network
  subnetwork            = var.subnetwork

  labels = local.common_tags
}

# Cloud Monitoring Alert Policy
resource "google_monitoring_alert_policy" "mongodb_cpu_alert" {
  count        = 3
  display_name = "${local.prefix_name}-mongodb-cpu-alert-${count.index + 1}"
  combiner     = "OR"

  conditions {
    display_name = "CPU Usage above 80%"
    condition_threshold {
      filter          = "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" AND resource.type=\"gce_instance\" AND metadata.user_labels.shard=\"${count.index + 1}\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8

      trigger {
        count = 1
      }

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  user_labels = local.common_tags
}