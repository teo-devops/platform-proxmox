#!/usr/bin/env bash
# ipmi.sh — control fuera de banda de un nodo por IPMI (cualquier fabricante con
# IPMI-over-LAN: Supermicro, Dell iDRAC, HPE iLO, Lenovo XCC...).
#
#   bmc/ipmi.sh <entorno> <nodo> status|on|off|cycle|bootdev-cdrom|bootdev-pxe|bootdev-disk|sol
#
# La IP de la BMC sale del inventario (bmc.host); el usuario y la contraseña, de las
# variables IPMI_USER e IPMI_PASSWORD (nunca en el inventario ni en la linea de
# comandos: la contraseña viaja por el entorno, -E, y no aparece en `ps`).
# Las acciones que apagan o reinician piden confirmacion.
set -euo pipefail
env="${1:?entorno}"; node="${2:?nodo}"; action="${3:?accion}"
: "${IPMI_USER:?exporta IPMI_USER}" "${IPMI_PASSWORD:?exporta IPMI_PASSWORD (read -rs IPMI_PASSWORD; export IPMI_PASSWORD)}"
command -v ipmitool >/dev/null || { echo "Falta ipmitool (apt install ipmitool)." >&2; exit 1; }

root="$(cd "$(dirname "$0")/.." && pwd)"
hostvars=$(ansible-inventory -i "$root/inventory/$env" --host "$node")
bmc=$(jq -r '.bmc.host // empty' <<<"$hostvars")
iface=$(jq -r '.bmc.interface // "lanplus"' <<<"$hostvars")
[ -n "$bmc" ] || { echo "$node no tiene bmc.host en inventory/$env" >&2; exit 1; }

ipmi() { IPMITOOL_PASSWORD="$IPMI_PASSWORD" ipmitool -I "$iface" -H "$bmc" -U "$IPMI_USER" -E "$@"; }
confirm() { read -r -p "$1 $node ($bmc)? Escribe el nombre del nodo para seguir: " a; [ "$a" = "$node" ] || { echo "Cancelado."; exit 1; }; }

case "$action" in
  status)        ipmi chassis power status ;;
  on)            ipmi chassis power on ;;
  off)           confirm "APAGAR de golpe"; ipmi chassis power off ;;
  cycle)         confirm "REINICIAR de golpe"; ipmi chassis power cycle ;;
  bootdev-cdrom) ipmi chassis bootdev cdrom ;;     # solo el siguiente arranque
  bootdev-pxe)   ipmi chassis bootdev pxe ;;
  bootdev-disk)  ipmi chassis bootdev disk ;;
  sol)           echo "Consola serie (salir: ~.)"; ipmi sol activate ;;
  *) echo "accion desconocida: $action" >&2; exit 2 ;;
esac
