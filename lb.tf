# Load Balancer
resource "google_compute_region_backend_service" "mongodb_backend" {
  name          = "${local.prefix_name}-mongodb-backend"
  region        = var.region
  protocol      = "TCP"
  health_checks = [google_compute_health_check.mongodb_health_check.id]

  backend {
    group          = google_compute_region_instance_group_manager.mongodb_nodes.instance_group
    balancing_mode = "CONNECTION"
  }
}

# Forwarding Rule
resource "google_compute_forwarding_rule" "mongodb_forwarding_rule" {
  name                  = "${local.prefix_name}-mongodb-forwarding-rule"
  region                = var.region
  ports                = ["27017"]  # Alterado de port_range para ports
  backend_service       = google_compute_region_backend_service.mongodb_backend.id
  load_balancing_scheme = "INTERNAL"
  network              = var.network
  subnetwork           = var.subnetwork
  labels               = local.common_tags
}

# Cloud Monitoring Alert Policy
resource "google_monitoring_alert_policy" "mongodb_cpu_alert" {
  display_name = "${local.prefix_name}-mongodb-cpu-alert"
  combiner     = "OR"

  conditions {
    display_name = "CPU Usage above 80%"
    condition_threshold {
      filter          = "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" AND resource.type=\"gce_instance\""
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
