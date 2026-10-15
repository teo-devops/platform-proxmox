# Accesos

**Para quién:** los admins del cluster.
**Qué necesitas antes:** el cluster montado (`make apply`).
**Cómo sabrás que ha salido bien:** cada admin entra con su usuario, su contraseña y su TOTP, y
`root@pam` solo se usa en emergencias.

## Quién entra y cómo

| Cuenta | Para | Cómo se crea |
|---|---|---|
| `root@pam` | Consola y emergencias. No para el día a día | El instalador (contraseña del vault y `root_ssh_keys`) |
| `<admin>@pve` | Administrar el cluster | `make apply` (`access.admins`) |
| `iac@pve!apply` / `iac@pve!plan` | Automatización de pve-platform-iac, con privilegios mínimos y ninguno en `/` | `make proxmox-acl` en pve-platform-iac, **no** aquí |
| `pve@pbs!backup` | Copias (en el PBS, no en el cluster) | En el PBS ([postinstalacion.md](postinstalacion.md#copias-de-seguridad)) |

Después de `make apply`, cada admin (como root, una vez):

```sh
pveum passwd <usuario>@pve
```

En el login de la interfaz, el usuario va **sin** `@pve` y el realm (*Proxmox VE authentication
server*) se elige en el desplegable. Si escribes `usuario@pve` con el realm *Linux PAM*, Proxmox
busca `usuario@pve@pam` y falla sin dar ninguna explicación.

## Segundo factor

Cada usuario lo activa **en su cuenta**: Datacenter → Permissions → Two Factor → Add → TOTP.

**No** actives TOTP en el realm (`pveum realm modify pve --tfa type=oath`). Es el mecanismo antiguo:
exige que un admin cargue antes la clave de cada usuario, y si falta, **bloquea el realm entero**
(`missing required 2nd keys` en `journalctl -u pvedaemon`). `make apply` falla si lo detecta. Para
quitarlo:

```sh
pveum realm modify pve --delete tfa     # una vez: /etc/pve se replica a todos los nodos
```

## Roles propios

Si creas roles para equipos (por ejemplo, un rol de desarrollador limitado a su pool), recuerda:
- `VM.Monitor` **ya no existe en PVE 9**: incluirlo hace fallar `pveum role add`.
- Deja fuera de esos roles `Sys.Modify`, `Sys.Console`, `Permissions.Modify` y `VM.Migrate`.

Con pve-platform-iac, los equipos normalmente no entran en Proxmox: piden por PR y entran por SSH a
sus VMs.

## Exposición

Ni `:8006` (interfaz y API) ni el SSH de los nodos se abren a Internet. Para administrar desde fuera,
usa una VPN o un acceso con identidad (Cloudflare Zero Trust, WireGuard, Tailscale…) limitado a los
admins. La guía de Cloudflare está en el §10 del bootstrap de pve-platform-iac.
