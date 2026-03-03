# create IncusOS cluster

read https://linuxcontainers.org/incus-os/docs/main/tutorials/incus-cluster/

Create usb img with:
https://incusos-customizer.linuxcontainers.org/ui/

You will need one image for your first cluster node with default settings applied.

You will need another image for nodes that you want to join to the cluster without default settings applied.

In my case, I used 4 dell 3000 thin clients configured for secure boot in audit mode (on first boot they will copy keys) and configred static dhcp for them so they were:

incus1 172.16.11.141
incus2 172.16.11.142
incus3 172.16.11.143
incus4 172.16.11.144

Then, I did something like:

```
incus remote add incus1 172.16.11.141:8443
incus config set incus1: cluster.https_address=172.16.11.141:8443
incus cluster enable cluster: incus1:
incus remote add cluster: incus1:
incus remote remove incus1
```

The rest of the nodes were similar like:
```
incus remote add incus2 172.16.11.142:8443
incus remote add cluster: incus2:
incus remote remove incus2
```
