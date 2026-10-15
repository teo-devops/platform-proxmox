# Operaciones

**Para quién:** el admin, en el día a día.
**Qué necesitas antes:** el inventario del entorno y la contraseña del vault.
**Cómo sabrás que ha salido bien:** `make validate ENV=x` en verde después de cada operación.

## Actualizar los nodos

`make apply ENV=x ARGS="--tags repos"` actualiza los paquetes, pero **no reinicia**. Para un kernel nuevo,
de uno en uno:
1. Migra las VMs del nodo a otro, o apágalas: Nodo → *Bulk Migrate*, o `qm migrate <vmid> <otro>`.
2. `reboot`; espera a que vuelva y a que `pvecm status` diga `Quorate: Yes`.
3. Siguiente nodo.

Nunca reinicies a la vez más nodos de los que el quórum aguanta (con 3, uno; con 5, dos).

## Añadir un nodo

1. Añádelo **al final** de `pve_nodes` en `hosts.yml` (el primero sigue creando el cluster).
2. Si pasas a un número par de nodos, hace falta un QDevice (`cluster.qdevice_host`). Si pasas a
   impar y tenías QDevice, quítalo antes: `pvecm qdevice remove`.
3. Instálalo ([instalacion.md](instalacion.md)), `make known-hosts ENV=x` y `make apply ENV=x`. Los
   nodos que ya están en el cluster no se tocan.
4. Si usas pve-platform-iac: `make handoff ENV=x` y PR con el nodo nuevo en `platform.yaml`. Ojo:
   allí las VMs se reparten por `vmid % número de nodos`, así que añadir un nodo **cambia el nodo**
   de muchas VMs; revisa su plan VM a VM.

## Quitar un nodo

1. Migra o borra sus VMs y sus trabajos de replicación (Datacenter → Replication).
2. Apágalo y **no lo vuelvas a encender en esa red con su instalación actual** (volvería a unirse).
3. Desde otro nodo:

   ```sh
   pvecm delnode <nodo>
   rm -r /etc/pve/nodes/<nodo>     # solo cuando ya no aparezca en pvecm nodes
   ```
4. Quítalo de `hosts.yml`. Si queda un número par de nodos, añade el QDevice.

## Reinstalar un nodo

Quítalo del cluster (arriba), reinstálalo con el mismo nombre e IP, `make known-hosts ENV=x` (su
clave de host ha cambiado: compárala con la consola) y `make apply ENV=x`.

## Red rota

Si un nodo pierde la red tras aplicar `network`:
1. **Espera 3 minutos.** La vuelta atrás automática restaura la configuración anterior.
2. Si no vuelve, entra por la consola fuera de banda (`bmc/ipmi.sh x <nodo> sol`, o la consola de
   vídeo de la BMC) y:

   ```sh
   cp /etc/network/interfaces.platform-bak /etc/network/interfaces && ifreload -a
   ```
3. Corrige el inventario y repite con `make plan ENV=x` antes de aplicar.

## Cambiar el ARC de ZFS

Cambia `pve.zfs_arc_max_mib` y `make apply ENV=x ARGS="--tags zfs"`. Se aplica en caliente, sin reiniciar.

## Encendido y apagado fuera de banda

```sh
export IPMI_USER=<usuario>; read -rs IPMI_PASSWORD; export IPMI_PASSWORD
bmc/ipmi.sh x pve1 status
bmc/ipmi.sh x pve1 cycle        # pide escribir el nombre del nodo para confirmar
```
