# Instalación de Proxmox VE en los nodos

**Para quién:** quien tiene acceso físico o remoto (BMC) a los servidores.
**Qué necesitas antes:**
- el inventario validado (`make check ENV=x`);
- la ISO oficial de Proxmox VE (proxmox.com → Downloads; comprueba su sha256);
- `proxmox-auto-install-assistant` o Docker;
- un USB, o una BMC con medios virtuales, o el método de GRUB (C).

**Cómo sabrás que ha salido bien:** `https://<ip>:8006` responde en cada nodo y
`ssh root@<ip>` entra con tu clave.

> [!WARNING]
> Instalar **borra los discos** de `pve_disks`. Comprueba dos veces el nodo, el disco y, al
> grabar un USB, el dispositivo (`lsblk`).

## A. Desatendida (recomendada)

Cada nodo arranca una ISO que lleva su `answer.toml`: disco, red, nombre, zona horaria y clave de
root, sacados del inventario (D-03). No hay que teclear nada.

```sh
make answers ENV=x                                   # build/x/answers/<nodo>.toml (validados)
make iso ENV=x NODE=pve1 ISO=~/isos/proxmox-ve_9.x.iso   # build/x/pve1-auto.iso
sudo dd if=build/x/pve1-auto.iso of=/dev/sdX bs=4M conv=fsync status=progress
```

Arranca el nodo desde el USB (o monta la ISO en la BMC y usa `bmc/ipmi.sh x pve1 bootdev-cdrom`
seguido de `cycle`). La instalación tarda unos minutos y reinicia sola. Repite con cada nodo:
**cada uno necesita su ISO**, porque lleva su IP y su nombre.

**Muchos nodos (modo http, avanzado):** una sola ISO para todos (`prepare-iso --fetch-from http
--url …`) y un servidor que devuelve a cada nodo su `answer.toml` según su MAC (`pve_mac`). El
servidor no viene en este repo. Si lo montas, sirve las respuestas por **HTTPS** con
`--cert-fingerprint`, porque llevan el hash de root
([wiki de Proxmox](https://pve.proxmox.com/wiki/Automated_Installation)).

## B. Manual (TUI)

Si prefieres instalar a mano, en el instalador gráfico o de texto usa los valores del inventario:

| Pantalla | Valor |
|---|---|
| Disco → Options | `pve.filesystem`; con ZFS, el modo de `pve_zfs_raid` (o el que corresponde al número de discos), `ashift` 12 y `compress` lz4 |
| Localización | `install.country`, `install.timezone`, `install.keyboard` |
| Contraseña y email | La del vault; `install.mailto` |
| Management interface | La NIC **con enlace**: el instalador de PVE 9 las llama `nic0`, `nic1`…; la buena suele ser la que trae ya una IP por DHCP |
| Hostname (FQDN) | `<nodo>.<cluster.domain>` (**el mismo nombre que en el inventario**) |
| IP, gateway, DNS | `ansible_host`/`network.cidr_bits`, `network.gateway`, `network.dns[0]` |

Después añade tu clave a `/root/.ssh/authorized_keys` de cada nodo (con la desatendida ya está).

## C. Sin USB ni medios virtuales: GRUB de un solo arranque

Para servidores que ya corren un Linux con GRUB accesible por SSH, cuando la BMC no monta ISOs (en
muchas placas, el *Virtual Media* necesita una licencia; la consola de vídeo no) y no hay PXE.
`install/grub-oneshot.sh` mete la ISO entera dentro de un initrd, lo copia al `/boot` del nodo y
arma una entrada de GRUB para **un solo arranque**: si algo falla, el nodo vuelve a su sistema.

```sh
install/grub-oneshot.sh --env x --node pve1 --iso ~/isos/proxmox-ve_9.x.iso            # ensayo
install/grub-oneshot.sh --env x --node pve1 --iso ~/isos/proxmox-ve_9.x.iso --confirm  # prepara
install/grub-oneshot.sh --env x --node pve1 --iso ~/isos/proxmox-ve_9.x.iso --confirm --reboot
```

Arranca el instalador manual (B). Síguelo en la consola de vídeo de la BMC o con
`bmc/ipmi.sh x pve1 sol`. Si el sistema actual del nodo tiene otra IP que la del inventario, pasa
`--host <ip>`.

> No añadas `console=` a la línea del kernel: con `console=ttyS*` el instalador dibuja la interfaz en
> un puerto serie que nadie ve, y con `console=tty0` cae a una shell de depuración. El script ya lo
> tiene en cuenta.

## Después de instalar

```sh
make known-hosts ENV=x     # claves de host: compara cada huella con la consola del nodo
make preflight ENV=x       # ¿los nodos son lo que dice el inventario?
```

Y sigue con [postinstalacion.md](postinstalacion.md).

## Si algo va mal

| Síntoma | Causa probable |
|---|---|
| El instalador no encuentra el disco | Nombre distinto en el instalador; mira `proxmox-auto-install-assistant device-info -t disk` en un sistema vivo del nodo |
| Configura otra NIC | Varias NIC con enlace: pon `pve_mac` |
| `make known-hosts`: «no responde» | El nodo aún reinicia, o la IP no es la del inventario |
| `make preflight`: «resuelve a 127.0.1.1» | `/etc/hosts` del nodo: su nombre tiene que apuntar a `ansible_host` |
