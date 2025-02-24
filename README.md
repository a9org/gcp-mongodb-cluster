# Terraform Module for MongoDB ReplicaSet on GCP

This Terraform module automates the deployment of a MongoDB ReplicaSet cluster on Google Cloud Platform (GCP), providing a secure and highly available database infrastructure.

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

This module provisions a MongoDB ReplicaSet tailored for your GCP project, customizable via variables to meet specific requirements. Key features include:

- **MongoDB ReplicaSet Creation:** Configures a ReplicaSet with a primary node (index `0`) and configurable secondary nodes.
- **High Availability:** Distributes instances across multiple zones in a specified region.
- **Security:** Generates a random admin password and a secure keyfile for authentication, with firewall rules to control access.
- **Dedicated Storage:** Provisions separate SSD disks for data and logs on each node.
- **Automation:** Fully automated setup via a startup script, including disk formatting, MongoDB installation, and ReplicaSet configuration.

### Architecture

This module creates the following resources in GCP:

- **Compute Instances:** A set of `google_compute_instance` resources named `<project>-<environment>-mongodb-node-XXXX` (e.g., `myproject-dev-mongodb-node-0000`), where `XXXX` is a zero-padded index (e.g., `0000`, `0001`).
- **Persistent Disks:** Two additional SSD disks per instance for data (`mongodb-data`) and logs (`mongodb-logs`).
- **Firewall Rules:**
  - External access for SSH (`port 22`) from any IP (configurable).
  - Internal communication between nodes on `port 27017` for ReplicaSet replication.
- **ReplicaSet:** A MongoDB ReplicaSet (`rs0`) with the primary node at index `0` and automatic joining of secondary nodes.

### Prerequisites

- **Google Cloud Account:** An active GCP account with a project configured.
- **Terraform:** Version 1.0.0 or higher installed on your machine.
- **Google Cloud Provider for Terraform:** Configured with valid credentials (e.g., via `gcloud auth application-default login`).
- **GCP CLI:** Optional, for manual debugging or verification.
- **MongoDB Knowledge:** Basic understanding of MongoDB ReplicaSet concepts.

### Variables

This module supports the following variables for customization:

#### Required Variables

| Name            | Description                                              | Type   |
|-----------------|----------------------------------------------------------|--------|
| `project`       | The GCP project name                                     | string |
| `region`        | The region where the cluster will be created             | string |
| `environment`   | The environment (e.g., `development`, `staging`, `production`) | string |
| `owner`         | The owner of the infrastructure resources                | string |
| `network`       | The name or self-link of the GCP network                 | string |
| `subnetwork`    | The name or self-link of the GCP subnetwork              | string |
| `ssh_public_key`| SSH public key for instance access                       | string |

#### Optional Variables

| Name                     | Description                              | Type   | Default          |
|--------------------------|------------------------------------------|--------|------------------|
| `machine_type`           | The machine type for instances           | string | `e2-standard-2`  |
| `replica_count`          | Number of nodes in the ReplicaSet        | number | `3`              |
| `mongodb_data_disk_size` | Size of the data disk in GB              | number | `100`            |
| `mongodb_logs_disk_size` | Size of the logs disk in GB              | number | `10`             |

For more details, see `variables.tf`.

### Outputs

The module provides the following output:

| Name               | Description                     | Sensitive |
|--------------------|---------------------------------|-----------|
| `mongodb_password` | MongoDB admin password          | Yes       |

To retrieve the password after deployment:
```bash
terraform output -raw mongodb_password
```

## Usage

### Module Example

To use this module in your Terraform configuration:

```hcl
module "mongodb_cluster" {
  source              = "./modules/mongodb_cluster"
  project             = "myproject"
  region              = "us-central1"
  environment         = "dev"
  owner               = "devops"
  network             = "default"
  subnetwork          = "default"
  ssh_public_key      = "ssh-rsa AAAAB3NzaC1yc2E... user@example.com"
  replica_count       = 3
  machine_type        = "e2-standard-2"
  mongodb_data_disk_size = 100
  mongodb_logs_disk_size = 10
}

output "mongodb_admin_password" {
  value     = module.mongodb_cluster.mongodb_password
  sensitive = true
}
```

### Standalone Usage

1. **Clone the Repository** (if hosted in a repo):
    ```bash
    git clone <repository-url>
    cd <repository-directory>
    ```

2. **Initialize Terraform**:
    ```bash
    terraform init
    ```

3. **Configure Variables**:
    Create a `terraform.tfvars` file:
    ```hcl
    project        = "myproject"
    region         = "us-central1"
    environment    = "dev"
    owner          = "devops"
    network        = "default"
    subnetwork     = "default"
    ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2E... user@example.com"
    replica_count  = 3
    ```

4. **Apply the Configuration**:
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

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Author

- **Leonardo Issamu** - Initial work and Terraform configuration.