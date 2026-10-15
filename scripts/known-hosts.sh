#!/usr/bin/env bash
# known-hosts.sh — claves de host de los nodos de un entorno, para que Ansible entre
# con verificacion estricta (nunca StrictHostKeyChecking=no).
#
#   scripts/known-hosts.sh <entorno>      (make known-hosts ENV=<entorno>)
#
# Primera conexion = confianza en el primer uso (TOFU): el script escribe
# inventory/<entorno>/known_hosts y enseña la huella de cada nodo. Compruebala en la
# consola del nodo (ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub) antes de seguir.
# Reinstalar un nodo cambia su clave: vuelve a ejecutarlo para ese entorno.
set -euo pipefail
env="${1:?entorno}"
root="$(cd "$(dirname "$0")/.." && pwd)"
kh="$root/inventory/$env/known_hosts"
hosts=$(ansible-inventory -i "$root/inventory/$env" --list | jq -r '._meta.hostvars | to_entries[] | .value.ansible_host')
tmp=$(mktemp)
for h in $hosts; do
  ssh-keyscan -T 5 -t ed25519 "$h" 2>/dev/null >> "$tmp" || echo "! $h no responde" >&2
done
sort -u "$tmp" > "$kh"; rm -f "$tmp"
echo "Escrito $kh. Compara cada huella con la de la consola del nodo:"
ssh-keygen -lf "$kh"
