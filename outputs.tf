# MongoDB password
output "mongodb_password" {
  description = "MongoDB admin password"
  sensitive   = true
  value       = resource.random_password.mongodb.result
}