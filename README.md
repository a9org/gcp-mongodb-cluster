# Terraform Module for MongoDB Cluster on GCP

This Terraform module automates the creation of a MongoDB cluster within your Google Cloud Platform (GCP) project, providing a robust and scalable infrastructure for your database needs.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Variables](#variables)
- [Outputs](#outputs)
- [Usage](#usage)
    - [Module Example](#module-example)
- [Cleanup](#cleanup)
- [License](#license)
- [Author](#author)

### Overview

This module offers an efficient and reliable way to provision a MongoDB cluster, customizable through variables to meet your specific needs. Key features include:

- **MongoDB Cluster Creation:** Configures all essential components to create a MongoDB cluster, including shards, nodes, load balancers, and networking.
- **High Availability:** Implements a robust architecture with multiple shards and nodes across different availability zones.
- **Autoscaling:** Built-in support for automatic scaling based on CPU utilization and custom metrics.
- **Monitoring:** Integrated monitoring and alerting through Google Cloud Monitoring.
- **Security:** Implements security best practices with firewalls and private networks.

### Architecture

This module creates the following resources in GCP:

- **MongoDB Shards:** Three independent shards for data distribution
- **Instance Groups:** Managed instance groups for each shard with autoscaling
- **Load Balancers:** Internal load balancers for traffic distribution
- **Monitoring:** Cloud Monitoring alerts and health checks
- **DNS:** Internal DNS configuration for service discovery

### Prerequisites

- **Google Cloud Account:** Active account on Google Cloud Platform
- **Terraform:** Install and configure Terraform on your machine
- **Google Cloud Provider for Terraform:** Configured Google Cloud provider
- **GCP CLI:** Google Cloud command-line tool
- **MongoDB:** Understanding of MongoDB sharding and replication concepts

### Variables

This module supports the following variables for customization:

### Required Variables

- `project`: The GCP project name
- `region`: The region where the cluster will be created
- `environment`: The environment (development, staging, production)
- `min_nodes`: The minimum number of nodes per shard
- `max_nodes`: The maximum number of nodes per shard
- `machine_type`: The machine type for MongoDB instances
* `network`: The name or self-link of the Google Compute Engine network.
* `subnetwork`: The name or self-link of the Google Compute Engine subnet.

For more details, see `variables.tf`

### Outputs

The module provides comprehensive outputs including:

- Instance group information
- Load balancer IPs
- DNS records
- Connection strings
- Monitoring configuration

For additional details, refer to `outputs.tf`

## Usage

### Module Example

To use this module in your Terraform configuration:

```hcl
module "mongodb_cluster" {
  source       = "github.com/your-org/mongodb-cluster-gcp"
  project      = "your-project"
  region       = "us-central1"
  environment  = "production"
  min_nodes    = 3
  max_nodes    = 5
  machine_type = "e2-standard-2"
  network      = "your_network_self_link"
  subnetwork   = "your_subnet_self_link"
}
```

### Standalone Usage

1. **Clone the Repository**

    ```bash
    git clone <repository-url>
    cd <repository-directory>
    ```

2. **Initialize Terraform**

    ```bash
    terraform init
    ```

3. **Configure Variables**

    Create a `terraform.tfvars` file:

    ```hcl
    project      = "your-project"
    region       = "us-central1"
    environment  = "production"
    min_nodes    = 3
    max_nodes    = 5
    machine_type = "e2-standard-2"
    network      = "mongodb-network"
    subnetwork   = "mongodb-subnet"
    ```

4. **Apply the Configuration**

    ```bash
    terraform plan
    terraform apply
    ```

## Cleanup

To destroy the infrastructure:

```bash
terraform destroy
```

## License

This project is licensed under the MIT License. See the LICENSE file for details.

## Author

- **Leonardo Issamu** - Initial work and Terraform configuration.