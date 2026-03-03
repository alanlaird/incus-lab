# tf3-debian: Debian 13 VM Lab on Incus

Three Debian 13 (Trixie) virtual machines provisioned on an Incus cluster using Terraform, bootstrapped via `incus exec`, then configured with Ansible.

## Quick start

```sh
make create   # terraform apply + bootstrap + ansible
make list     # show running VMs and SSH commands
make destroy  # tear down all VMs
```

## Makefile targets

| Target    | Description |
|-----------|-------------|
| `create`  | Full lab: `apply` + `bootstrap` + `ansible` |
| `apply`   | `terraform init` + `apply` (generates SSH key if absent) |
| `bootstrap` | Install openssh-server and inject SSH key on each VM via `incus exec` |
| `ansible` | Run Ansible playbook |
| `list`    | Show running VMs and SSH commands |
| `ssh`     | SSH into a VM — `make ssh VM=debian1` |
| `destroy` | Destroy all VMs |

If a VM's IP is `pending` after `apply`, run `terraform refresh` then `make apply` again before running `bootstrap`.

## Architecture

| Property   | Value |
|------------|-------|
| Image      | `images:debian/13/cloud` |
| Type       | Virtual machine |
| vCPUs      | 1 |
| Memory     | 512 MiB |
| Disk       | 4 GiB (ZFS pool: `local`) |
| Network    | `physnet` macvlan (172.16.11.0/24) |
| SSH key    | ED25519, generated on first `apply`, stored as `debian_id_ed25519` |

## Bootstrap notes

The Debian 13 cloud image ships without `openssh-server` and with root locked. The `bootstrap` target handles this via `incus exec`:

- Installs `openssh-server` with `DEBIAN_FRONTEND=noninteractive`
- Pushes the public key to `/root/.ssh/authorized_keys` via `incus file push`
- Unlocks root with `passwd -d root`
- Enables and starts `ssh`

## Ansible

The playbook (`ansible/playbook.yml`) installs `python3` and `zsh`, and adds the sftp subsystem to `sshd_config`. An `ansible.cfg` in this directory enables pipelining to avoid sftp/scp transfer warnings.

## Differences from tf3-alpine

| Aspect | tf3-alpine | tf3-debian |
|--------|------------|------------|
| Image | `images:alpine/3.21` | `images:debian/13/cloud` |
| Python pre-installed | No | Yes (python3.13) |
| cloud-init | Not present | Full support |
| Root account | Enabled | Locked — `passwd -d root` in bootstrap |
| Package manager | `apk` | `apt` |
| Ansible bootstrap | Raw tasks to install Python + SSH | `apt` module directly |
