output "vm_ips" {
  description = "IPv4 addresses of the Debian VMs"
  value = {
    for vm in incus_instance.debian : vm.name => vm.ipv4_address
  }
}

output "ssh_private_key_path" {
  description = "Path to the generated SSH private key"
  value       = "${abspath(path.module)}/debian_id_ed25519"
}

output "ssh_example" {
  description = "Example SSH command (substitute actual IP from vm_ips)"
  value       = "ssh -i ${"${abspath(path.module)}/debian_id_ed25519"} root@<vm_ip>"
}
