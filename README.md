# platform-proxmox

> **Beta (v0.1.0).** Inventories, templates and roles are checked in CI (linting, golden files and
> Proxmox's own answer-file validator), but the platform has **not yet been run on real servers**.

**From bare-metal servers to a healthy Proxmox VE cluster, from 2 nodes to N**, driven by a
single Ansible inventory. Built for in-house infrastructure teams at companies and SMBs: the same
repository installs a two-node lab with a QDevice and a five-node production cluster with
mirrored disks, bonded NICs and a dedicated corosync network.

```
servers ──(1) install──► Proxmox VE on every node ──(2) make apply──► cluster ready ──(3) make handoff──► pve-platform-iac
          answer.toml per node                     repos, ZFS, network,                 self-service VMs
          (USB, BMC or GRUB)                       cluster, QDevice, admins, backups    via GitOps
```

1. **Install**: `make answers` renders one [automated-installer](https://pve.proxmox.com/wiki/Automated_Installation)
   `answer.toml` per node (disk layout, network, FQDN, root key), and `make iso` builds the ISO. For
   servers without remote media there is a one-shot GRUB method.
2. **Configure**: `make plan` shows the changes and `make apply` makes them. Every step is an
   idempotent Ansible role:
   - repositories (deb822 on PVE 9) and the ZFS ARC limit;
   - bridge, bond, VLAN and corosync link1, with an **automatic network rollback**;
   - cluster create and join through the API, and the QDevice for even node counts;
   - admin accounts, ZFS replication and Proxmox Backup Server.
3. **Hand off**: `make handoff` prints the `proxmox:` block for
   [pve-platform-iac](https://github.com/teo-devops/pve-platform-iac), where teams request VMs
   through pull requests.

## Quick start

```sh
make new ENV=lab FROM=2-nodos          # or 3-nodos, 5-nodos
$EDITOR inventory/lab/hosts.yml inventory/lab/group_vars/all/main.yml
ansible-vault encrypt inventory/lab/group_vars/all/vault.yml
make check ENV=lab                     # schema + topology checks, no servers needed
make iso ENV=lab NODE=pve1 ISO=proxmox-ve_9.x.iso
# ...boot each node from its ISO...
make known-hosts ENV=lab && make plan ENV=lab && make apply ENV=lab && make validate ENV=lab
make handoff ENV=lab
```

Requirements on your machine: `ansible-core`, `check-jsonschema`, `jq`, and either
`proxmox-auto-install-assistant` or Docker. Run `make` to list every target.

## Topologies

| | 2 nodes | 3 nodes | 5 nodes |
|---|---|---|---|
| Quorum | 2 + QDevice | 3 | 5 |
| Disks | single, ZFS raid0 | single, ZFS raid0 | mirror / raidz-1 |
| Network | 1 NIC | 1 NIC | bond + dedicated corosync link |
| Example | [`examples/2-nodos`](examples/2-nodos) | [`examples/3-nodos`](examples/3-nodos) | [`examples/5-nodos`](examples/5-nodos) |

Sizing rules (host reservations, ZFS ARC, headroom, overcommit) are in
[docs/dimensionamiento.md](docs/dimensionamiento.md). Ceph is out of scope for v0.1
([D-06](docs/arquitectura.md#decisiones)).

## Documentation

The documentation is in Spanish: [docs/README.md](docs/README.md). Start with
[arquitectura.md](docs/arquitectura.md), then [inventario.md](docs/inventario.md),
[instalacion.md](docs/instalacion.md) and [postinstalacion.md](docs/postinstalacion.md).

## Why "platform-proxmox"

The name carries the hypervisor. Should another one be supported later, it will be a sibling
`platform-<hypervisor>` repository with the same shape: inventory, install, post-install and
hand-off ([D-09](docs/arquitectura.md#decisiones)).

## License

[Apache-2.0](LICENSE). Security reports: [SECURITY.md](SECURITY.md).
