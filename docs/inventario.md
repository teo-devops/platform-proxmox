# Inventario

**Para quién:** el admin que prepara un entorno.
**Qué necesitas antes:** la topología decidida ([arquitectura.md](arquitectura.md)), la IP de
gestión, las NIC y los discos de cada nodo, y `ansible-core`, `check-jsonschema` y `jq` en tu
máquina.
**Cómo sabrás que ha salido bien:** `make check ENV=<entorno>` termina con «Inventario correcto».

```sh
make new ENV=produccion FROM=3-nodos        # copia examples/3-nodos a inventory/produccion/
$EDITOR inventory/produccion/hosts.yml inventory/produccion/group_vars/all/main.yml
$EDITOR inventory/produccion/group_vars/all/vault.yml && ansible-vault encrypt inventory/produccion/group_vars/all/vault.yml
make check ENV=produccion
```

El inventario se puede subir a tu fork o a tu copia del repo: los secretos van cifrados en el
vault, y lo demás (IPs internas, nombres) no da acceso por sí solo. Los ficheros generados
(`build/`) no se suben: llevan el hash de la contraseña de root.

## `hosts.yml`: los nodos

Grupo `pve_nodes`. **El primero crea el cluster** y el resto se une, en ese orden. El nombre del
host es el nombre del nodo en Proxmox: elígelo bien, renombrar un nodo después es delicado.

| Campo | Obligatorio | Qué es |
|---|---|---|
| `ansible_host` | sí | IP de gestión del nodo (la del bridge) |
| `pve_nic` | sí | Interfaz del bridge: la NIC física (en PVE 9, `nic0`, `nic1`…) o `bond0` si hay `pve_bond` |
| `pve_disks` | sí | Discos del sistema, sin `/dev/` (`nvme0n1`, `sda`). Con ext4/xfs, solo uno |
| `pve_mac` | no | MAC de la NIC de gestión: el instalador la usa para elegir la NIC correcta |
| `pve_bond` | no | `{slaves: [nic0, nic1], mode: active-backup}` (también `802.3ad`, que necesita LACP en el switch, o `balance-alb`) |
| `pve_zfs_raid` | no | Modo de ZFS. Por defecto: 1 disco → `raid0`, 2 → `raid1`, 3 o más → `raidz-1` |
| `pve_corosync_link1` | no | `{nic: nic2, ip: 10.31.0.11}`: red dedicada de corosync. En todos los nodos o en ninguno |
| `pve_expect` | no | Mínimos que comprueba `make preflight`: `{cpu_threads, ram_gib, disk_gib}` |
| `bmc` | no | `{host: <IP de la BMC>, interface: lanplus}` para `bmc/ipmi.sh` |

## `group_vars/all/main.yml`: el entorno

| Bloque | Campo | Qué es |
|---|---|---|
| `cluster` | `name` | Nombre del cluster: **máximo 15 caracteres** |
| | `domain` | Dominio: el FQDN de cada nodo es `<nodo>.<domain>` |
| | `qdevice_host` | IP de la máquina del QDevice (obligatorio con un número par de nodos) |
| | `accept_no_quorum_on_failure` | `true` para asumir un número par de nodos sin QDevice |
| | `corosync_link1_cidr_bits` | Máscara de la red dedicada de corosync |
| `pve` | `major` | `8` o `9` |
| | `repo` | `no-subscription` o `enterprise` (con suscripción) |
| | `upgrade` | `apt full-upgrade` en la post-instalación (no reinicia) |
| | `filesystem` | `zfs`, `ext4` o `xfs` |
| | `zfs_ashift`, `zfs_compress` | `12` y `lz4` valen para casi todo (SSD/NVMe de 4K) |
| | `zfs_arc_max_mib` | `auto` (10 % de la RAM, máximo 16 GiB) o un número en MiB |
| `network` | `cidr_bits`, `gateway`, `dns` | Red de gestión. Comprueba que el DNS **responde** (`dig @<dns> github.com`) |
| | `bridge` | `vmbr0` |
| | `vlan_aware`, `vlan_ids` | Bridge con VLAN para las VMs |
| | `mtu` | Opcional |
| | `apply` | `false` por defecto: la red solo se aplica con `true` (D-05) |
| `install` | `keyboard`, `country`, `timezone`, `mailto` | Del instalador |
| | `root_password_hash` | `"{{ vault_root_password_hash }}"` (va en el vault) |
| | `root_ssh_keys` | Claves con las que Ansible entra como root |
| `access` | `admins` | `[{user, comment}]`: usuarios `@pve` con el rol Administrator |
| | `pools` | Pools que se crean vacíos (pve-platform-iac crea los suyos) |
| `storage` | `image_datastore` | Donde se importan las imágenes base (`local`) |
| | `enable_import_content` | Activa el contenido `import` (lo necesita pve-platform-iac) |
| `replication` | `enabled`, `schedule`, `jobs` | Replicación `pvesr`: `[{vmid, target}]`, solo con ZFS |
| `backup` | `pbs` | Storage de Proxmox Backup Server y trabajo diario ([postinstalacion.md](postinstalacion.md#copias-de-seguridad)) |

El esquema completo, con sus valores válidos, está en `schema/`. El rol `topology` comprueba lo que
un esquema no puede: un número par de nodos sin QDevice, IPs repetidas, link1 a medias, ext4 con
varios discos, o una replicación a un nodo que no existe.

## Secretos: `group_vars/all/vault.yml`

| Variable | Qué es | Cómo se genera |
|---|---|---|
| `vault_root_password_hash` | Hash de la contraseña de root (va al instalador) | `openssl passwd -6` |
| `vault_root_password` | La contraseña en claro: solo la usa el join al cluster (D-04) | Tu gestor de contraseñas |
| `vault_pbs_token_secret` | Secreto del token de PBS (si hay copias) | `proxmox-backup-manager user generate-token` |

Cífralo (`ansible-vault encrypt …`) y guarda la contraseña del vault en tu gestor de contraseñas. Los
`make` la piden, o la leen de `VAULT_PASS_FILE=<fichero>` (fuera del repo; `.vault-pass` está en
`.gitignore`).
