#!/usr/bin/env bash
# make-iso.sh — ISO de instalacion desatendida de UN nodo (answer.toml embebido).
#
#   install/make-iso.sh <answer.toml> <proxmox-ve.iso> <salida.iso>
#   (normalmente: make iso ENV=<entorno> NODE=<nodo> ISO=<ruta a la ISO oficial>)
#
# Graba la ISO resultante en un USB (o montala por la BMC) y arranca el nodo: se
# instala solo, con el disco, la red y la clave de root del inventario. Cada nodo
# tiene su ISO porque su answer.toml lleva su IP y su nombre. Para muchos nodos,
# el modo http (docs/instalacion.md) sirve una sola ISO para todos.
#
# Usa proxmox-auto-install-assistant si esta instalado (Debian/Proxmox); si no, el
# contenedor de install/Dockerfile.assistant.
set -euo pipefail
answer="${1:?answer.toml}"; iso="${2:?ISO de Proxmox VE}"; out="${3:?ISO de salida}"
[ -f "$answer" ] || { echo "No existe $answer (make answers ENV=...)" >&2; exit 1; }
[ -f "$iso" ] || { echo "No existe la ISO $iso" >&2; exit 1; }

if command -v proxmox-auto-install-assistant >/dev/null; then
  pai() { proxmox-auto-install-assistant "$@"; }
  a="$answer"; i="$iso"; o="$out"
else
  command -v docker >/dev/null || { echo "Hace falta proxmox-auto-install-assistant o docker." >&2; exit 1; }
  here="$(cd "$(dirname "$0")" && pwd)"
  docker image inspect platform-proxmox-assistant >/dev/null 2>&1 \
    || docker build -t platform-proxmox-assistant -f "$here/Dockerfile.assistant" "$here"
  # Cada fichero, montado en su propia ruta del contenedor (solo lo necesario).
  outdir="$(cd "$(dirname "$out")" && pwd)"
  pai() {
    docker run --rm -u "$(id -u):$(id -g)" \
      -v "$(realpath "$answer"):/in/answer.toml:ro" -v "$(realpath "$iso"):/in/source.iso:ro" \
      -v "$outdir:/out" platform-proxmox-assistant "$@"
  }
  a=/in/answer.toml; i=/in/source.iso; o="/out/$(basename "$out")"
fi

pai validate-answer "$a"
pai prepare-iso "$i" --fetch-from iso --answer-file "$a" --output "$o"
echo "ISO lista: $out"
echo "Graba: sudo dd if=$out of=/dev/<usb> bs=4M conv=fsync status=progress   (comprueba el dispositivo dos veces)"
