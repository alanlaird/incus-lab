# Incus Lab Session Log

## Context

This document records the Incus commands applied in a Claude Code session to explore
a 4-node local Incus cluster and create a small Alpine Linux virtual machine.

---

## Commands Applied

### 1. Inspect the cluster

```sh
incus cluster list
```

Shows all cluster members, their roles, IPs, and health status. The cluster has
four nodes (incus1–incus4) all ONLINE, with incus1 as the database-leader.

---

### 2. Browse available Alpine images

```sh
incus image list images: alpine --columns=lfdapt
```

Lists Alpine images available from the `images:` remote. Used to find the latest
stable Alpine VM image (Alpine 3.21 amd64).

---

### 3. Check the default profile

```sh
incus profile show default
```

Revealed that the default profile has no devices (no root disk, no NIC). This
means every VM or container must have devices supplied explicitly or via a
custom profile.

---

### 4. Check storage pools

```sh
incus storage list
```

Found one pool: `local` (ZFS driver). This is used as the backing store for
the VM root disk.

---

### 5. Check existing networks

```sh
incus network list
```

No networks existed. A bridge had to be created before a VM with networking
could be launched.

---

### 6. Create a bridge network (cluster-aware)

In a clustered Incus environment, network creation must be done in two phases:
first create a pending entry on each member node with `--target`, then finalize
it without `--target`.

```sh
incus network create incusbr0 --type=bridge --target=incus1
incus network create incusbr0 --type=bridge --target=incus2
incus network create incusbr0 --type=bridge --target=incus3
incus network create incusbr0 --type=bridge --target=incus4
incus network create incusbr0 --type=bridge   # finalize
```

This creates a managed bridge (`incusbr0`) with a default 10.x.x.x/24 subnet
and DHCP/DNS provided by dnsmasq on each node.

---

### 7. Add devices to the default profile

```sh
incus profile device add default root disk pool=local path=/
incus profile device add default eth0 nic network=incusbr0 name=eth0
```

The default profile was completely empty, so `incus init` fails with "No root
device could be found" unless a root disk is present in the profile (or
supplied inline). Adding devices to the default profile means all future
instances will inherit them automatically.

Note: The `--device` flag on `init`/`launch` only *overrides* an existing
profile device — it cannot add a brand-new device that the profile doesn't
already define. That's why the profile must be populated first.

---

### 8. Initialize the Alpine VM

```sh
incus init images:alpine/3.21 alpine-vm --vm \
  --config limits.cpu=1 \
  --config limits.memory=512MiB \
  --device root,size=4GiB
```

Creates (but does not start) an Alpine 3.21 virtual machine named `alpine-vm`
with 1 vCPU, 512 MiB RAM, and a 4 GiB root disk (overriding the default pool
size). The `--vm` flag selects the VIRTUAL-MACHINE image instead of a
container. The image was already cached locally from a prior download attempt.

---

### 9. Disable Secure Boot and start the VM

```sh
incus config set alpine-vm security.secureboot=false
incus start alpine-vm
```

The Alpine 3.21 image is not signed for Secure Boot, so starting the VM
without disabling it produces: *"The image used by this instance is
incompatible with secureboot."* Setting `security.secureboot=false` on the
instance resolves this.

After boot the VM received a DHCP lease from `incusbr0`:

```sh
incus list alpine-vm
# RUNNING  10.8.106.24 (eth0)  fd42:…:c21d (eth0)  VIRTUAL-MACHINE  incus1
```

To open a shell:

```sh
incus exec alpine-vm -- sh
```

---

## Placing VMs on the physical 172.16.11.0/24 network

### 10. Discover host network topology

To find the physical interface name, a privileged container was temporarily
launched with `lxc.net.0.type=none` to expose the host's network namespace:

```sh
incus launch images:alpine/3.21 probe --target=incus1 \
  --config security.privileged=true \
  --config raw.lxc="lxc.net.0.type=none"

incus exec probe -- cat /proc/net/dev
incus exec probe -- ip addr show _venp1s0

incus delete --force probe
```

Findings:
- The physical NIC (Realtek r8169, kernel name `_pc45ab1ce30fd`) is enslaved to
  a Linux bridge called **`enp1s0`**.
- The host's `172.16.11.141/24` IP lives on a veth interface `_venp1s0` that
  peers into that bridge.
- To put VMs on the physical network, attach their NIC to `enp1s0` via macvlan.

---

### 11. Create a macvlan network (cluster-aware)

A `macvlan` type Incus network creates sub-interfaces directly on the host's
`enp1s0` bridge, giving VMs a presence on 172.16.11.0/24 with DHCP from the
upstream router. The same two-phase cluster approach is required:

```sh
for node in incus1 incus2 incus3 incus4; do
  incus network create physnet --type=macvlan parent=enp1s0 --target=$node
done
incus network create physnet --type=macvlan   # finalize
```

Note: VMs using macvlan cannot communicate with the host they run on (a
fundamental macvlan limitation). For host↔VM communication use `incusbr0`.

---

### 12. Launch an instance on physnet

The `--device` flag can only *override* an existing profile device — it cannot
add a new device. Use `config device override` after `init` instead:

```sh
incus init images:alpine/3.21 my-vm --vm \
  --config limits.cpu=1 \
  --config limits.memory=512MiB \
  --config security.secureboot=false

incus config device override my-vm eth0 network=physnet
incus start my-vm
```

The VM received `172.16.11.86` from the upstream DHCP server.

---

## Working with VMs on 172.16.11.0/24

### Create

```sh
incus init images:alpine/3.21 my-vm --vm \
  --config limits.cpu=1 \
  --config limits.memory=512MiB \
  --config security.secureboot=false \
  --device root,size=4GiB

incus config device override my-vm eth0 network=physnet
incus start my-vm
```

### List

```sh
incus list
```

### SSH

Wait for the VM to get a DHCP address (shown in `incus list`), then:

```sh
# From the list output, e.g. 172.16.11.95
ssh root@172.16.11.95
```

Alpine VMs boot with an empty root password by default. To set one first:

```sh
incus exec my-vm -- passwd root
```

Or inject your public key before starting:

```sh
incus config set my-vm cloud-init.user-data "$(cat <<'EOF'
#cloud-config
users:
  - name: root
    ssh_authorized_keys:
      - $(cat ~/.ssh/id_ed25519.pub)
EOF
)"
```

Alternatively, open a console directly without SSH:

```sh
incus exec my-vm -- sh
```

### Destroy

```sh
incus delete --force my-vm
```

---

## Summary

**alpine-vm** (on incusbr0 internal bridge):

| Resource     | Value                  |
|--------------|------------------------|
| Image        | Alpine 3.21 (amd64 VM) |
| VM name      | alpine-vm              |
| vCPU         | 1                      |
| RAM          | 512 MiB                |
| Disk         | 4 GiB (ZFS pool: local)|
| Network      | incusbr0 (bridge)      |
| IPv4         | 10.8.106.24 (DHCP)     |
| Cluster node | incus1 (auto-assigned) |

**physnet** (macvlan on enp1s0 → 172.16.11.0/24):

| Resource       | Value                          |
|----------------|--------------------------------|
| Network name   | physnet                        |
| Type           | macvlan (parent: enp1s0)       |
| Subnet         | 172.16.11.0/24 (upstream DHCP) |
| To use         | `incus config device override <vm> eth0 network=physnet` |
