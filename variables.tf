variable "region" {
  description = "The region where the resources will be created"
  type        = string
}

variable "owner" {
  description = "The owner of the infraestructure resources"
  type        = string
}

variable "project" {
  description = "The project name associated with the infraestructure resources"
  type        = string
}

variable "environment" {
  description = "The environment type (e.g., 'development', 'staging', 'production')"
  type        = string
}

variable "min_nodes" {
  description = "The minimum number of nodes in the cluster"
  type        = number
  default     = 3
}

variable "max_nodes" {
  description = "The maximum number of nodes in the cluster"
  type        = number
  default     = 5
}

variable "machine_type" {
  description = "The machine type of the nodes in the cluster"
  type        = string
  default     = "e2-standard-2"
}

variable "network" {
  description = "The name or self_link of the Google Compute Engine network to which the cluster is connected. For Shared VPC, set this to the self link of the shared network."
  type        = string
}

variable "subnetwork" {
  description = "The name or self_link of the Google Compute Engine subnetwork in which the cluster's instances are launched."
  type        = string
}

variable "autoscaling_enabled" {
  description = "Enable or disable autoscaling for the node pool.  When enabled, the node pool will automatically adjust its size between 'min_nodes' and 'max_nodes' based on resource utilization.  Set to 'true' to enable, 'false' to disable."
  type        = bool
  default     = true
}

variable "create_dns" {
  description = "Determines whether a DNS record will be created for the load balancer. When set to 'true', a DNS record will be created, pointing to the load balancer's IP address. When set to 'false', no DNS record will be created. Use this option if you already have a DNS record or want to manage it manually."
  type        = bool
  default     = true
}

variable "mongodb_data_disk_size" {
  description = "Size of the MongoDB data disk in GB"
  type        = number
  default     = 300
}

variable "mongodb_logs_disk_size" {
  description = "Size of the MongoDB logs disk in GB"
  type        = number
  default     = 50
}

variable "is_cluster" {
  description = "Enable a MongoDB cluster"
  type        = bool
  default     = true
}

variable "admin_ip_ranges" {
  description = "Lista de ranges IP permitidos para acesso administrativo"
  type        = list(string)
  default     = []
}

variable "app_ip_ranges" {
  description = "Lista de ranges IP das aplicações que acessarão o MongoDB"
  type        = list(string)
  default     = []
}