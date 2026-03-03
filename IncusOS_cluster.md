# IncusOS Cluster Setup

Reference: https://linuxcontainers.org/incus-os/docs/main/tutorials/incus-cluster/

## 1. Create bootable images

Use the customizer at https://incusos-customizer.linuxcontainers.org/ui/ to generate two images:

- **First node** — with default settings applied (seeds the cluster CA and config)
- **Joining nodes** — without default settings (they receive config from the first node)

## 2. Boot and network

Boot each node from USB. Assign static DHCP leases before first boot so nodes come up at known addresses. This cluster uses:

```
incus1  172.16.11.141
incus2  172.16.11.142
incus3  172.16.11.143
incus4  172.16.11.144
```

## 3. Initialize the first node

From the Mac, add the first node and enable clustering on it:

```sh
incus remote add incus1 172.16.11.141:8443
incus config set incus1: cluster.https_address=172.16.11.141:8443
incus cluster enable incus1: incus1
incus remote add cluster incus1:
incus remote remove incus1
```

## 4. Join remaining nodes

```sh
for ip in 172.16.11.142 172.16.11.143 172.16.11.144; do
  node=incus$(echo $ip | cut -d. -f4 | awk '{print $1-140}')
  incus remote add $node $ip:8443
  incus cluster add cluster: $node:
  incus remote remove $node
done
```

Verify:

```sh
incus cluster list cluster:
```

All nodes should show `ONLINE`.

## 5. Storage

IncusOS creates a ZFS storage pool named `local` on each node automatically during first boot, using whatever disk is available after the OS partition. Verify with:

```sh
incus storage list cluster:
incus storage info cluster:local
```

To inspect per-node pool state:

```sh
for node in incus1 incus2 incus3 incus4; do
  echo "=== $node ==="
  incus storage info cluster:local --target=$node
done
```

The `local` pool is node-local — instances are stored on whichever node they run on, not shared across nodes.

## 6. Networking

### Bridge network (internal, managed)

`incusbr0` provides an internal managed bridge with DHCP and DNS via dnsmasq. Useful for instances that only need cluster-internal connectivity.

Network creation in a cluster requires a two-phase approach: create a pending entry on each node with `--target`, then finalize without it:

```sh
for node in incus1 incus2 incus3 incus4; do
  incus network create cluster:incusbr0 --type=bridge --target=$node
done
incus network create cluster:incusbr0 --type=bridge
```

This assigns a private subnet (e.g. `10.8.106.0/24`) and starts dnsmasq on each node.

### Physical network (macvlan)

`physnet` attaches instances directly to the host's physical NIC via macvlan, giving them addresses from the upstream router (172.16.11.0/24 in this lab). Instances appear as peers on the physical network.

First, identify the physical interface name. On IncusOS the NIC is bridged internally — launch a temporary privileged container to inspect the host network namespace:

```sh
incus launch cluster:images/alpine/3.21 probe --target=incus1 \
  --config security.privileged=true \
  --config raw.lxc="lxc.net.0.type=none"
incus exec cluster:probe -- ip link show
incus delete --force cluster:probe
```

The bridge interface connected to the physical NIC is `enp1s0` on this hardware. Then create the macvlan network (same two-phase approach):

```sh
for node in incus1 incus2 incus3 incus4; do
  incus network create cluster:physnet --type=macvlan parent=enp1s0 --target=$node
done
incus network create cluster:physnet --type=macvlan
```

> **macvlan limitation**: instances on `physnet` cannot communicate with the Incus host node they run on. This is a kernel-level restriction of macvlan. Use `incusbr0` if host↔instance communication is needed.

## 7. Default profile

On a fresh IncusOS cluster the default profile has no devices. Add a root disk and NIC so instances inherit them automatically:

```sh
incus profile device add cluster:default root disk pool=local path=/
incus profile device add cluster:default eth0 nic network=incusbr0 name=eth0
```

Verify:

```sh
incus profile show cluster:default
```

## 8. Verify with a test instance

```sh
incus launch cluster:images/alpine/3.21 test-vm --vm \
  --config security.secureboot=false \
  --config limits.cpu=1 \
  --config limits.memory=512MiB
incus list cluster:
incus delete --force cluster:test-vm
```

The VM should come up on `incusbr0` with a DHCP address in the `10.x.x.x` range. To place it on `physnet` instead, override the NIC device before starting:

```sh
incus init cluster:images/alpine/3.21 test-vm --vm \
  --config security.secureboot=false
incus config device override cluster:test-vm eth0 network=physnet
incus start cluster:test-vm
incus list cluster:
incus delete --force cluster:test-vm
```

The VM should receive a `172.16.11.x` address from the upstream DHCP server.
