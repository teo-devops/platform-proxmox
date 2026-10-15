# Documentación

Qué leer, en orden, para pasar de unos servidores sin instalar a un cluster de Proxmox VE listo
para [pve-platform-iac](https://github.com/teo-devops/pve-platform-iac).

| # | Documento | Para |
|---|---|---|
| 1 | [arquitectura.md](arquitectura.md) | Qué topología montar (2, 3 o 5 nodos), quórum, red, almacenamiento y decisiones |
| 2 | [dimensionamiento.md](dimensionamiento.md) | Cuánto cabe: reservas del host, colchón y overcommit |
| 3 | [inventario.md](inventario.md) | Describir tus nodos y tu red: cada campo, secretos y ejemplos |
| 4 | [instalacion.md](instalacion.md) | Instalar Proxmox en cada nodo: desatendido (USB/BMC), manual o por GRUB |
| 5 | [postinstalacion.md](postinstalacion.md) | `make apply`: repos, ZFS, red, cluster, QDevice, accesos, replicación y copias |
| 6 | [accesos.md](accesos.md) | Cuentas de admin, segundo factor y exposición de la interfaz |
| 7 | [integracion-iac.md](integracion-iac.md) | El paso a pve-platform-iac (`make handoff`) |
| — | [operaciones.md](operaciones.md) | Día a día: añadir o quitar nodos, actualizar, reinstalar, recuperar la red |

## Convenciones

- Cada documento dice **para quién es**, **qué necesitas antes** y **cómo saber que ha salido bien**.
- Las decisiones (`D-nn`, en [arquitectura.md](arquitectura.md#decisiones)) se citan con ese número
  también desde el código.
- Todo lo que cambia un nodo es un rol de Ansible idempotente: se puede repetir, y
  `make plan` enseña lo que haría sin hacerlo.
- Las fechas, en formato `15-oct-2026`.
