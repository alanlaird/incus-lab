terraform {
  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "~> 0.3"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "incus" {
  config_dir                   = pathexpand("~/.config/incus")
  accept_remote_certificate    = false
  generate_client_certificates = false
}
