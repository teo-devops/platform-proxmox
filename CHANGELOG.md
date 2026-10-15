# Changelog

Versionado semántico; mientras sea `0.x`, puede haber cambios incompatibles entre versiones menores.

## v0.1.0-beta — 15-oct-2026 — Primera versión pública

De servidores sin instalar a un cluster Proxmox VE de 1 a N nodos, a partir de un inventario de Ansible.
Generaliza un método de instalación manual anterior (scripts de bash para un cluster concreto de 3 nodos).

- Inventario validado por esquema (`schema/`) y por coherencia (rol `topology`): quórum, QDevice con un número
  par de nodos, link1 de corosync, discos y replicación. Ejemplos de 2, 3 y 5 nodos.
- Instalación desatendida: `answer.toml` por nodo (`make answers`), validado con el validador oficial, e ISO por
  nodo (`make iso`). Alternativas: TUI manual y GRUB de un solo arranque (`install/grub-oneshot.sh`).
- Post-instalación (`make plan` / `make apply` / `make validate`): repos (deb822 en PVE 9), ARC de ZFS, red con
  bond/VLAN/link1 y vuelta atrás automática, cluster por la API, QDevice, contenido `import`, admins y pools,
  replicación `pvesr` y copias en PBS.
- `make handoff`: el bloque `proxmox:` del `platform.yaml` de pve-platform-iac.
- CI sin hardware: lint (perfil production de ansible-lint), ficheros de referencia (`tests/golden/`),
  validación de `answer.toml` y gitleaks.
- **Sin probar todavía en servidores reales.**
