# Instance Groups Outputs
output "instance_group_details" {
  description = "Details of MongoDB shard instance groups"
  value = {
    for idx, ig in google_compute_region_instance_group_manager.mongodb_shard : "shard-${idx + 1}" => {
      name               = ig.name
      base_instance_name = ig.base_instance_name
      target_size        = ig.target_size
      region             = ig.region
      instance_group     = ig.instance_group
    }
  }
}

# Load Balancer Outputs
output "load_balancer_ips" {
  description = "Internal IP addresses of the MongoDB load balancers"
  value = {
    for idx, rule in google_compute_forwarding_rule.mongodb_forwarding_rule : "shard-${idx + 1}" => {
      name       = rule.name
      ip_address = rule.ip_address
      port_range = rule.port_range
    }
  }
}

# DNS Outputs
output "dns_details" {
  description = "DNS information for MongoDB cluster"
  value = {
    zone_name = google_dns_managed_zone.mongodb_zone[0].name
    dns_name  = google_dns_managed_zone.mongodb_zone[0].dns_name
    records = {
      for idx, record in google_dns_record_set.mongodb : "shard-${idx + 1}" => {
        name    = record.name
        rrdatas = record.rrdatas
      }
    }
  }
}

# Autoscaler Outputs
output "autoscaler_details" {
  description = "Details of autoscaling configurations"
  value = {
    for idx, scaler in google_compute_region_autoscaler.mongodb_autoscaler : "shard-${idx + 1}" => {
      name         = scaler.name
      target       = scaler.target
      min_replicas = scaler.autoscaling_policy[0].min_replicas
      max_replicas = scaler.autoscaling_policy[0].max_replicas
      cpu_target   = scaler.autoscaling_policy[0].cpu_utilization[0].target
    }
  }
}

# Health Check Outputs
output "health_check_details" {
  description = "MongoDB health check configuration"
  value = {
    name               = google_compute_health_check.mongodb_health_check.name
    check_interval_sec = google_compute_health_check.mongodb_health_check.check_interval_sec
    timeout_sec        = google_compute_health_check.mongodb_health_check.timeout_sec
    tcp_port           = google_compute_health_check.mongodb_health_check.tcp_health_check[0].port
  }
}

# Connection String Outputs
output "mongodb_connection_strings" {
  description = "MongoDB connection strings for each shard"
  value = {
    for idx, rule in google_compute_forwarding_rule.mongodb_forwarding_rule : "shard-${idx + 1}" => {
      standard = "mongodb://${rule.ip_address}:27017"
      dns      = "mongodb://shard-${idx + 1}.mongodb.internal:27017"
    }
  }
}

# Monitoring Outputs
output "monitoring_policy_details" {
  description = "Details of monitoring alert policies"
  value = {
    for idx, policy in google_monitoring_alert_policy.mongodb_cpu_alert : "shard-${idx + 1}" => {
      name      = policy.display_name
      condition = policy.conditions[0].display_name
      threshold = policy.conditions[0].condition_threshold[0].threshold_value
    }
  }
}

# MongoDB password
output "mongodb_password" {
  description = "MongoDB admin password"
  sensitive   = true
  value       = resource.random_password.mongodb.result
}