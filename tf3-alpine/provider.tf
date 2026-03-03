terraform {
  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "~> 0.3"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "incus" {
  config_dir                   = pathexpand("~/.config/incus")
  accept_remote_certificate    = false
  generate_client_certificates = false
}
