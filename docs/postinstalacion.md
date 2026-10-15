# Post-instalación: `make apply`

**Para quién:** el admin, después de instalar Proxmox en todos los nodos.
**Qué necesitas antes:** [instalacion.md](instalacion.md) terminado, `make known-hosts ENV=x` con
las huellas comprobadas y la contraseña del vault.
**Cómo sabrás que ha salido bien:** `make validate ENV=x` termina sin fallos y la interfaz web
muestra todos los nodos en el cluster.

```sh
make preflight ENV=x    # solo comprobaciones
make plan ENV=x         # qué cambiaría (--check --diff); no toca nada
make apply ENV=x        # aplica; se puede repetir (idempotente)
make validate ENV=x
```

Para lanzar solo una fase o solo un nodo: `make apply ENV=x ARGS="--tags <tag>"` o
`ARGS="--limit <nodo>"`.

## Fases

| Tag | Rol | Qué hace | Dónde |
|---|---|---|---|
| (siempre) | `topology` | Comprueba que el inventario es coherente | — |
| `preflight` | `preflight` | Versión de PVE y Debian, nombre del nodo (y que resuelve a su IP), virtualización, mínimos de CPU/RAM/disco, enlace de las NIC, hora | cada nodo |
| `repos` | `repos` | Repos sin suscripción (o enterprise) y `apt full-upgrade` (sin reiniciar) | cada nodo |
| `zfs` | `zfs` | Límite del ARC, en caliente y para los reinicios | cada nodo (ZFS) |
| `network` | `network` | Red del inventario (bridge, bond, VLAN, link1) y DNS; ver abajo | nodo a nodo |
| `cluster` | `cluster` | El primer nodo crea el cluster; el resto se une por la API (D-04) | nodo a nodo |
| `qdevice` | `qdevice` | QDevice con un número par de nodos | todos |
| `datacenter` | `storage`, `access`, `replication`, `backup` | Contenido `import`, admins y pools, replicación `pvesr`, PBS y trabajo de copia | una vez |
| `validate` | `validate` | Servicios, repos sin 401, bridge, ZFS sano, quórum y votos, miembros, `import` | cada nodo |

## Red

La instalación ya deja la red básica: una NIC y un bridge con la IP de gestión. El rol `network`
genera **siempre** la configuración del inventario en `/etc/network/interfaces.platform` y enseña la
diferencia con la actual, pero **no la aplica** si `network.apply` es `false` (D-05).

Para aplicarla (bond, VLAN, link1 de corosync…):
1. Revisa la diferencia en `make plan ENV=x`.
2. Ten a mano la consola fuera de banda de los nodos (BMC o física).
3. Pon `network.apply: true` y ejecuta `make apply ENV=x ARGS="--tags network"`.

Va **nodo a nodo**. En cada uno, antes de tocar nada, se arma una **vuelta atrás automática**: si
en 3 minutos Ansible no confirma que el nodo sigue accesible, el propio nodo restaura su
configuración anterior (`/etc/network/interfaces.platform-bak`) y recarga la red. Si un nodo falla,
la ejecución se para ahí y el resto no se toca.

Después, vuelve a poner `network.apply: false`: la red queda como dice el inventario, y un cambio
futuro vuelve a necesitar el paso consciente.

## Cluster

- El **primer nodo** del inventario crea el cluster con su IP (y la de link1, si la hay).
- Los demás se unen **de uno en uno**, por la API del primero, verificando la huella de su
  certificado y con la contraseña de root del vault. No hace falta SSH entre nodos.
- Un nodo que ya está en un cluster no se toca. Para sacar o reinstalar un nodo:
  [operaciones.md](operaciones.md).

## QDevice (número par de nodos)

En la máquina del QDevice (`cluster.qdevice_host`), una vez y a mano:

```sh
apt install corosync-qnetd
# y la clave publica de root del PRIMER nodo en /root/.ssh/authorized_keys de esta maquina:
ssh root@<primer-nodo> cat /root/.ssh/id_rsa.pub   # pegala en el QDevice
```

`make apply` instala `corosync-qdevice` en los nodos y ejecuta `pvecm qdevice setup`. `make validate`
comprueba que los votos son N + 1.

## Copias de seguridad

El rol `backup` conecta el cluster con un **Proxmox Backup Server ya montado**: añade el storage de
PBS con cifrado en el cliente y crea el trabajo diario (`backup.pbs` en el inventario).

Para montar el PBS, con un datastore en S3 (p. ej. SeaweedFS) y retención, limpieza y
verificación, sigue el §11 del bootstrap de pve-platform-iac
([docs/bootstrap.md](https://github.com/teo-devops/pve-platform-iac/blob/main/docs/bootstrap.md)).
Usa un usuario `pve@pbs` con un token con solo `DatastoreBackup`; su secreto va al vault
(`vault_pbs_token_secret`).

> [!IMPORTANT]
> Con `encryption: true`, Proxmox crea la clave en `/etc/pve/priv/storage/<storage_id>.enc`. **Sin
> ella no se puede restaurar nada**, y vive en el mismo cluster que protege. Cópiala a tu gestor de
> contraseñas en cuanto `make apply` te lo recuerde.

## Si algo va mal

| Fallo | Qué hacer |
|---|---|
| `preflight`: versión o Debian | `pve.major` no coincide con lo instalado |
| `preflight`: resuelve a `127.0.1.1` | Corrige `/etc/hosts` del nodo: `<ip> <nodo>.<dominio> <nodo>` |
| `repos`: 401 | Repo enterprise sin suscripción: `pve.repo: no-subscription` |
| `network`: «no responde tras aplicar» | Espera 3 minutos (vuelta atrás automática) o entra por la consola: [operaciones.md](operaciones.md#red-rota) |
| `cluster`: el join falla por la huella | El certificado del primer nodo cambió (¿reinstalado?): repite `make apply` |
| `cluster`: no llega al quórum | Hora sin sincronizar, o corosync bloqueado entre nodos (UDP 5405-5412) |
| `access`: TFA en el realm | [accesos.md](accesos.md#segundo-factor) |
