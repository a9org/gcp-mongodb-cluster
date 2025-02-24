# # Managed Instance Group (MIG)
# resource "google_compute_region_instance_group_manager" "mongodb_nodes" {
#   name = "${local.prefix_name}-mongodb-nodes"

#   base_instance_name = "${local.prefix_name}-mongodb-node"
#   region             = var.region

#   version {
#     instance_template = google_compute_instance_template.mongodb_template.id
#   }

#   target_size = var.replica_count

#   named_port {
#     name = "mongodb"
#     port = 27017
#   }

#   auto_healing_policies {
#     health_check      = google_compute_health_check.mongodb_health_check.id
#     initial_delay_sec = 300
#   }
# }

# # Health Check
# resource "google_compute_health_check" "mongodb_health_check" {
#   name               = "${local.prefix_name}-mongodb-health-check"
#   timeout_sec        = 5
#   check_interval_sec = 10

#   tcp_health_check {
#     port = 27017
#   }
# }

# Autoscaler (opcional)
# resource "google_compute_region_autoscaler" "mongodb_autoscaler" {
#   count  = var.autoscaling_enabled ? 1 : 0
#   name   = "${local.prefix_name}-mongodb-autoscaler"
#   region = var.region
#   target = google_compute_region_instance_group_manager.mongodb_nodes.id

#   autoscaling_policy {
#     max_replicas    = var.max_nodes
#     min_replicas    = var.min_nodes
#     cooldown_period = 60

#     cpu_utilization {
#       target = 0.7
#     }
#   }
# }