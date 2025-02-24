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

variable "mongodb_data_disk_size" {
  description = "Size of the MongoDB data disk in GB"
  type        = number
  default     = 100
}

variable "mongodb_logs_disk_size" {
  description = "Size of the MongoDB logs disk in GB"
  type        = number
  default     = 10
}

variable "replica_count" {
  description = "Number of nodes in the MongoDB ReplicaSet"
  type        = number
  default     = 3
}

variable "ssh_public_key" {
  description = "SSH public key for instance access"
  type        = string
}
