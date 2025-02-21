terraform {
  required_version = ">= 1.0.0"
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.3"
    }
    google = {
      source  = "hashicorp/google"
      version = ">= 4.5.0"
    }
  }
}