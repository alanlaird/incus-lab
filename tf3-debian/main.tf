# ── SSH key (generated on-demand, never stored in Terraform state) ────────────
#
# On first apply the script runs ssh-keygen to create debian_id_ed25519{,.pub}.
# On subsequent applies the key already exists, so the script is a no-op.
# Both files are gitignored; the private key never enters the tfstate.

data "external" "ssh_key" {
  program = ["bash", "-c", <<-SCRIPT
    KEY="${path.module}/debian_id_ed25519"
    if [ ! -f "$KEY" ]; then
      ssh-keygen -t ed25519 -f "$KEY" -N "" -C "incus-lab" >/dev/null 2>&1
    fi
    printf '{"public_key":"%s"}' "$(cat "$KEY.pub" | tr -d '\n')"
  SCRIPT
  ]
}

# ── Debian VMs ────────────────────────────────────────────────────────────────

resource "incus_instance" "debian" {
  count  = 3
  name   = "debian${count.index + 1}"
  image  = "images:debian/13/cloud"
  type   = "virtual-machine"
  remote = "cluster"

  config = {
    "security.secureboot"  = "false"
    "limits.cpu"           = "1"
    "limits.memory"        = "512MiB"
    "cloud-init.user-data" = <<-EOT
      #cloud-config
      disable_root: false
      users:
        - name: root
          ssh_authorized_keys:
            - ${trimspace(data.external.ssh_key.result.public_key)}
      ssh_pwauth: false
    EOT
  }

  device {
    name = "root"
    type = "disk"
    properties = {
      pool = "local"
      path = "/"
      size = "4GiB"
    }
  }

  device {
    name = "eth0"
    type = "nic"
    properties = {
      network = "physnet"
    }
  }
}

# ── Ansible inventory (written after IPs are known) ───────────────────────────

resource "local_file" "ansible_inventory" {
  depends_on = [incus_instance.debian]
  filename   = "${path.module}/ansible/inventory.ini"
  content    = <<-EOT
    [debian_vms]
    ${join("\n", [
  for vm in incus_instance.debian :
  "${vm.name} ansible_host=${coalesce(vm.ipv4_address, "pending")} ansible_user=root ansible_ssh_private_key_file=${abspath(path.module)}/debian_id_ed25519"
])}

    [debian_vms:vars]
    ansible_ssh_extra_args=-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
  EOT
}
