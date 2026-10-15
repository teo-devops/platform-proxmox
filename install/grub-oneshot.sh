#!/usr/bin/env bash
# grub-oneshot.sh — arranca el instalador de Proxmox VE en un nodo SIN medio de
# arranque remoto (sin licencia de Virtual Media en la BMC, sin USB, sin PXE).
#
# Sirve cuando el nodo ya corre un Linux con GRUB accesible por SSH:
#   1. Construye un initrd = el initrd de la ISO + la ISO entera embebida como
#      /proxmox.iso (una ruta que el instalador de Proxmox admite de serie: "found
#      proxmox ISO image inside initrd image").
#   2. Copia ese initrd y el kernel de la ISO (linux26) al /boot del nodo.
#   3. Añade una entrada de GRUB y la arma para UN SOLO arranque (grub-reboot): si
#      algo falla, el nodo vuelve solo a su sistema y no se pierde el acceso.
#   4. Reinicia (con --reboot); la instalacion se sigue por la consola de video de la
#      BMC (iKVM, que no necesita licencia) o por IPMI SOL.
#
#   install/grub-oneshot.sh --env <entorno> --node <nodo> --iso <proxmox-ve.iso>
#                           [--host <ip>] [--confirm [--reboot]] [--build-only]
#
# Por defecto es un ensayo (--dry-run): no toca nada. --host, si el sistema actual
# del nodo tiene otra IP que la del inventario. Usuario SSH: SSH_USER (root por
# defecto; si no es root, necesita sudo sin contraseña). Solo clave SSH.
# Requiere en esta maquina: xorriso, cpio, zstd, ssh/scp y ansible-inventory.
set -euo pipefail

REMOTE_DIR="/boot/pve-installer"
GRUB_TITLE="platform-proxmox: Proxmox VE Installer (embedded ISO)"
GRUB_CUSTOM="/boot/grub/custom.cfg"
# Linea del kernel: la de la entrada "Install Proxmox VE (Terminal UI)" de la ISO, TAL
# CUAL. NUNCA añadas console=:
#   - console=ttyS* -> el instalador lo toma por una instalacion por puerto serie y
#     dibuja la TUI en un serie que nadie ve;
#   - console=tty0  -> la TUI corre en /dev/tty0 (alias, no un VT real), falla con
#     "inappropriate ioctl for device" y cae a una shell de depuracion.
# Sin console= el initrd usa tty1, que es lo que enseña la consola de la BMC.
KERNEL_CMDLINE="${KERNEL_CMDLINE:-ro ramdisk_size=16777216 rw quiet splash=silent proxtui}"
WORKDIR="${WORKDIR:-/var/tmp/platform-proxmox-pve-build}"
SSH_USER="${SSH_USER:-root}"

usage() { sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

ENV=""; NODE=""; ISO=""; HOST=""; DRY_RUN=true; DO_REBOOT=false; BUILD_ONLY=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --env) ENV="$2"; shift 2 ;;
    --node) NODE="$2"; shift 2 ;;
    --iso) ISO="$2"; shift 2 ;;
    --host) HOST="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --confirm) DRY_RUN=false; shift ;;
    --reboot) DO_REBOOT=true; shift ;;
    --build-only) BUILD_ONLY=true; shift ;;
    *) usage ;;
  esac
done
[ -n "$ISO" ] && [ -f "$ISO" ] || { echo "--iso: no existe '$ISO'" >&2; exit 1; }

build_installer_files() {
  for t in xorriso cpio zstd; do command -v "$t" >/dev/null || { echo "Falta '$t'." >&2; exit 1; }; done
  local tag dir; tag=$(basename "$ISO" .iso); dir="$WORKDIR/$tag"
  KERNEL_FILE="$dir/linux26"; INITRD_FILE="$dir/pve-installer.initrd"
  if [ -f "$KERNEL_FILE" ] && [ -f "$INITRD_FILE" ] && [ "$KERNEL_FILE" -nt "$ISO" ] && [ "$INITRD_FILE" -nt "$ISO" ]; then
    echo "Uso los ficheros ya construidos en $dir"; return
  fi
  echo "Construyendo kernel + initrd en $dir (lee la ISO entera)..."
  mkdir -p "$dir"
  xorriso -osirrox on -indev "$ISO" -extract /boot/linux26 "$KERNEL_FILE" \
    -extract /boot/initrd.img "$dir/initrd.img" 2>/dev/null
  # La ISO va en el initrd como UN SOLO bloque zstd, no concatenada en crudo: GRUB/UEFI
  # y el cargador de initramfs del kernel no son fiables cruzando el limite
  # comprimido->cpio. Se descomprime el cpio original (sin extraerlo: conserva nodos y
  # permisos), se le añade un cpio con /proxmox.iso y se recomprime todo junto.
  zstd -d -f "$dir/initrd.img" -o "$dir/orig.cpio" 2>/dev/null
  ln -sf "$(readlink -f "$ISO")" "$dir/proxmox.iso"
  ( cd "$dir" && echo proxmox.iso | cpio -H newc -o -L --quiet > iso.cpio )
  cat "$dir/orig.cpio" "$dir/iso.cpio" > "$dir/combined.cpio"
  zstd -1 -f -T0 "$dir/combined.cpio" -o "$INITRD_FILE" 2>/dev/null
  rm -f "$dir/proxmox.iso" "$dir/iso.cpio" "$dir/orig.cpio" "$dir/combined.cpio" "$dir/initrd.img"
  echo "Kernel $(du -h "$KERNEL_FILE" | cut -f1), initrd $(du -h "$INITRD_FILE" | cut -f1)."
}

grub_entry() {
  cat <<GRUB
menuentry '$GRUB_TITLE' --class os {
    insmod part_gpt
    insmod ext2
    search --no-floppy --file --set=root $REMOTE_DIR/linux26
    linux $REMOTE_DIR/linux26 $KERNEL_CMDLINE
    initrd $REMOTE_DIR/pve-installer.initrd
}
GRUB
}

if [ "$BUILD_ONLY" = true ]; then build_installer_files; exit 0; fi
[ -n "$ENV" ] && [ -n "$NODE" ] || usage
root="$(cd "$(dirname "$0")/.." && pwd)"
hv=$(ansible-inventory -i "$root/inventory/$ENV" --host "$NODE")
HOST="${HOST:-$(jq -r .ansible_host <<<"$hv")}"
BMC=$(jq -r '.bmc.host // "la BMC del nodo"' <<<"$hv")
build_installer_files

as_root() { if [ "$SSH_USER" = root ]; then ssh "$SSH_USER@$HOST" bash -s; else ssh "$SSH_USER@$HOST" sudo -n bash -s; fi; }

echo "--- $NODE ($HOST), usuario SSH '$SSH_USER' ---"
if [ "$DRY_RUN" = true ]; then
  echo "[ENSAYO] Copiaria $KERNEL_FILE y $INITRD_FILE a $HOST:$REMOTE_DIR/"
  echo "[ENSAYO] Escribiria en $GRUB_CUSTOM:"; grub_entry | sed 's/^/    /'
  echo "[ENSAYO] Armaria UN arranque: grub-reboot '$GRUB_TITLE'"
  echo "Repite con --confirm (y --reboot para reiniciar ya)."
  exit 0
fi

echo "1/3 Copiando el instalador..."
echo "mkdir -p $REMOTE_DIR" | as_root
scp "$KERNEL_FILE" "$SSH_USER@$HOST:/tmp/pve-linux26"
scp "$INITRD_FILE" "$SSH_USER@$HOST:/tmp/pve-installer.initrd"
as_root <<REMOTE
set -e
mv /tmp/pve-linux26 $REMOTE_DIR/linux26
mv /tmp/pve-installer.initrd $REMOTE_DIR/pve-installer.initrd
chmod 644 $REMOTE_DIR/linux26 $REMOTE_DIR/pve-installer.initrd
REMOTE

echo "2/3 Entrada de GRUB y arranque unico..."
# custom.cfg lo lee el 41_custom de Debian/Ubuntu sin update-grub.
as_root <<REMOTE
set -e
cat > $GRUB_CUSTOM <<'ENTRY'
$(grub_entry)
ENTRY
grub-reboot '$GRUB_TITLE'
REMOTE

echo "3/3"
if [ "$DO_REBOOT" = true ]; then
  echo "Reiniciando $NODE al instalador..."
  echo reboot | as_root || true
else
  echo "Listo, sin reiniciar. Reinicia cuando tengas la consola abierta (repite con --reboot)."
fi
echo "Sigue la instalacion en la consola de video de $BMC (o: bmc/ipmi.sh $ENV $NODE sol)."
echo "Si arranca el sistema anterior, GRUB no tomo la entrada unica: revisa grub-reboot."
