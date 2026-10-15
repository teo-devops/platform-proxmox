# Integración con pve-platform-iac

**Para quién:** el admin, cuando el cluster ya pasa `make validate`.
**Qué necesitas antes:** el cluster montado y una copia de
[pve-platform-iac](https://github.com/teo-devops/pve-platform-iac) (`make init`).
**Cómo sabrás que ha salido bien:** en pve-platform-iac, `make preflight` dice «TLS verificado» y,
con su token exportado, «el token no tiene permisos en '/'».

## Qué pasa de un repo al otro

| Dato | De aquí | A pve-platform-iac |
|---|---|---|
| Endpoint de la API | IP del primer nodo | `platform.yaml` → `proxmox.endpoint` |
| Nodos | `hosts.yml` | `proxmox.nodes` (nombre → IP) |
| Datastore de las VMs | `local-zfs` con ZFS, `local-lvm` con ext4/xfs | `proxmox.datastore` |
| Datastore de imágenes (con contenido `import`) | `storage.image_datastore` | `proxmox.image_datastore` |
| Bridge | `network.bridge` | `proxmox.bridge` |
| CA del cluster | `/etc/pve/pve-root-ca.pem` | `terraform/certs/pve-root-ca.pem` |

```sh
make handoff ENV=x       # escribe e imprime build/x/platform.yaml-proxmox.yaml
```

Pega el bloque en el `platform.yaml` de pve-platform-iac (por PR) y sigue su
`docs/bootstrap.md` desde el §2: red de las VMs (`network:`), CA (§3), y tokens y ACL
(`make proxmox-acl`, §8). Los tokens de automatización los crea **pve-platform-iac**, con
privilegios mínimos; este repo solo crea los admins.

## Qué no se solapa

| Esto lo hace | Esto otro |
|---|---|
| platform-proxmox | El hipervisor: instalación, repos, ZFS, red de los nodos, cluster, QDevice, admins, replicación, conexión con PBS |
| pve-platform-iac | Lo que hay dentro: VMs y clusters k3s por peticiones, pools y tokens de los proyectos, cuentas en las VMs, VPN de los devs |
