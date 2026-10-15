# Arquitectura

**Para quién:** quien decide cómo montar el cluster: cuántos nodos, qué red y qué almacenamiento.
**Qué necesitas antes:** saber qué servidores tienes (CPU, RAM, discos y NIC de cada uno).
**Cómo sabrás que ha salido bien:** tu inventario se parece a uno de los ejemplos y `make check`
lo acepta.

## Qué hace este repo

```
servidores ──(1) instalación──► Proxmox VE en cada nodo ──(2) make apply──► cluster listo ──(3) make handoff──► pve-platform-iac
            answer.toml por nodo                         repos, ZFS, red,                   bloque proxmox:
            (USB, BMC o GRUB)                            cluster, QDevice,                  de platform.yaml
                                                         accesos, copias
```

1. **Instalación:** `make answers` genera un `answer.toml` por nodo a partir del inventario, y el
   instalador desatendido de Proxmox lo usa ([instalacion.md](instalacion.md)).
2. **Post-instalación:** Ansible deja cada nodo y el datacenter como dice el inventario
   ([postinstalacion.md](postinstalacion.md)).
3. **Handoff:** los datos que necesita [pve-platform-iac](https://github.com/teo-devops/pve-platform-iac)
   para que los equipos pidan VMs ([integracion-iac.md](integracion-iac.md)).

El **inventario es la única fuente**: número de nodos, NIC, discos, red y accesos. Nada de eso está
escrito en el código (D-02).

## Topologías

| | 2 nodos (`examples/2-nodos`) | 3 nodos (`examples/3-nodos`) | 5 nodos (`examples/5-nodos`) |
|---|---|---|---|
| Para | Laboratorio, pyme pequeña | Equipo de desarrollo, pyme | Producción interna |
| Quórum | 2 votos + **QDevice** | 3 votos | 5 votos |
| Si cae 1 nodo | Sigue (con QDevice) | Sigue | Sigue (y con 2 caídos, también) |
| Discos | 1 por nodo, ZFS `raid0` | 1 por nodo, ZFS `raid0` | 2-3 por nodo, ZFS `raid1` / `raidz-1` |
| Red | 1 NIC | 1 NIC | Bond de 2 NIC + NIC dedicada a corosync |
| Resiliencia de datos | Copias (PBS) | Replicación `pvesr` + copias | Espejo de discos + copias |

### Quórum

Proxmox solo acepta cambios (arrancar VMs, editar configuración) si **más de la mitad** de los
votos están presentes:
- **Un número impar de nodos** (3, 5…) aguanta la caída de `(N-1)/2` nodos.
- **Un número par** tiene un problema: con 2 nodos, si cae uno, el otro se queda con la mitad
  exacta y se bloquea.

La solución es un **QDevice**: un voto externo en una tercera máquina pequeña (una Raspberry Pi o
una VM en otro sitio, **no** dentro del propio cluster). `make check` no acepta un número par de
nodos sin `cluster.qdevice_host`, salvo que lo asumas con `accept_no_quorum_on_failure: true`.

### Red

- **Gestión y VMs:** un bridge (`vmbr0`) sobre una NIC o sobre un **bond** (`pve_bond`, con
  `active-backup` por defecto: no necesita nada del switch). Con `vlan_aware`, las VMs pueden ir
  en VLAN distintas.
- **Corosync:** es sensible a la **latencia**, no al ancho de banda. Con 1-3 nodos puede compartir
  la NIC de gestión. A partir de 4, o si la red de gestión va cargada (copias, migraciones), dale
  una red propia (`pve_corosync_link1`): corosync usa las dos redes y aguanta la caída de una.
- La red de gestión de los nodos (`:8006`, `:22`) **nunca** se expone a Internet
  ([accesos.md](accesos.md#exposición)).

### Almacenamiento

- **ZFS local** en cada nodo (por defecto):
  - el modo depende del número de discos: 1 → `raid0` (sin redundancia), 2 → `raid1` (espejo),
    3 o más → `raidz-1`;
  - snapshots instantáneos, compresión `lz4` y replicación nativa entre nodos;
  - el caché ARC se limita para no quitarle RAM a las VMs ([dimensionamiento.md](dimensionamiento.md)).
- **ext4/xfs** (LVM-thin) es posible, con un solo disco, pero sin replicación ni snapshots baratos.
- **Ceph no está en esta versión** (D-06): necesita al menos 3 nodos, red de 10 GbE dedicada y varios
  discos por nodo. Con 1 GbE y un disco por nodo es más lento que ZFS local, y deja un tercio del
  espacio útil.

### Resiliencia

| Riesgo | Con qué se cubre |
|---|---|
| Muere un disco | `raid1`/`raidz` (5 nodos); con un solo disco, la réplica o la copia |
| Cae un nodo | Quórum; sus VMs se recuperan desde la réplica `pvesr` del vecino (pierdes como mucho un intervalo, 15 min) o desde la copia |
| Error humano, ransomware | Copias en Proxmox Backup Server, en otro hardware y cifradas ([postinstalacion.md](postinstalacion.md#copias-de-seguridad)) |

No hay alta disponibilidad automática (HA) en esta versión: reiniciar una VM en otro nodo es una
decisión del admin.

## Decisiones

### D-01 · Ansible para la post-instalación — 15-oct-2026

**Decisión:** la configuración de los nodos y del cluster la hacen roles de Ansible, a partir del
inventario.
**Alternativas:** scripts de bash ejecutados en cada nodo, en orden (el método anterior).
**Por qué:** con N nodos, hacerlo a mano y en orden es frágil. Ansible es idempotente
(`make apply` se puede repetir), enseña lo que haría (`make plan`) y es coherente con
pve-platform-iac.

### D-02 · El inventario es la única fuente — 15-oct-2026

**Decisión:** nada específico de un cluster (número de nodos, nombres de NIC, discos, IPs, tamaños)
está en el código. `schema/` valida el inventario y el rol `topology` comprueba que es coherente.
**Por qué:** el mismo repo sirve para 2 nodos en un laboratorio y para 5 en producción. El método
anterior tenía los 3 nodos, la NIC y los tamaños escritos en los scripts.

### D-03 · Instalación desatendida por defecto — 15-oct-2026

**Decisión:** `answer.toml` por nodo generado del inventario (`make answers`) y una ISO por nodo
(`make iso`). Hay dos alternativas, también documentadas: la TUI manual, y el arranque por GRUB
para servidores sin medios de arranque remotos.
**Por qué:** el disco, la red, el nombre y la clave de root quedan como dice el inventario, sin
errores al teclear en una consola remota. Proxmox lo admite oficialmente desde la 8.2.

### D-04 · Unir nodos por la API, no por SSH — 15-oct-2026

**Decisión:** `pvesh create /cluster/config/join` con la huella del certificado del primer nodo y
la contraseña de root (en el vault).
**Alternativas:** `pvecm add --use_ssh`, que exige SSH de root entre nodos sin contraseña.
**Por qué:** no hay que repartir claves de root entre nodos, y la huella fija evita la pregunta
interactiva que rompe una ejecución desatendida.

### D-05 · La red no se aplica por defecto — 15-oct-2026

**Decisión:** `make apply` genera la configuración de red y enseña la diferencia. Aplicarla exige
`network.apply: true`, va nodo a nodo y arma antes una **vuelta atrás automática** de 3 minutos.
**Por qué:** un error de red deja un nodo inaccesible. La instalación ya deja la red básica bien;
cambiarla (bond, VLAN, link1) tiene que ser un acto consciente, con consola a mano.

### D-06 · Sin Ceph en la v0.1 — 15-oct-2026

**Decisión:** ZFS local + replicación nativa + copias. Ceph queda fuera de esta versión.
**Por qué:** Ceph solo compensa con 3 o más nodos, 10 GbE dedicada y varios discos por nodo, y es
mucho más complejo de operar. La mayoría de pymes no cumplen esos requisitos.

### D-07 · Replicación nativa (`pvesr`) en vez de `pve-zsync` — 15-oct-2026

**Decisión:** los trabajos de replicación son los de Proxmox (`pvesr`), que se ven y se gestionan
desde la interfaz.
**Alternativas:** `pve-zsync` (el método anterior).
**Por qué:** `pvesr` está integrado en el cluster (migración, estado en la UI). `pve-zsync` sirve
para copiar fuera del cluster, que aquí cubren las copias de PBS.

### D-08 · Claves de host: confianza en el primer uso, después estrictas — 15-oct-2026

**Decisión:** `make known-hosts` lee las claves de los nodos recién instalados y enseña sus
huellas para compararlas con la consola. Después, Ansible entra siempre con
`StrictHostKeyChecking=yes`.
**Alternativas:** `StrictHostKeyChecking=no` (el método anterior), que acepta cualquier nodo.
**Por qué:** sin verificación, alguien en la red podría hacerse pasar por un nodo y recibir la
contraseña de root del join.

### D-09 · El nombre lleva el hipervisor: `platform-proxmox` — 15-oct-2026

**Decisión:** el repo se llama por su hipervisor. Si más adelante hay otro, será otro repo
`platform-<hipervisor>` con la misma estructura (inventario, instalación, post-instalación,
handoff).
**Por qué:** cada hipervisor se instala y se configura de forma distinta; abstraerlos ahora sería
adivinar. Lo específico de Proxmox lleva el prefijo `pve` (`pve_nodes`, `pve_disks`…).

## Lecciones que el código ya comprueba

Aprendidas instalando clusters de Proxmox 9 a mano. Cada una tiene una comprobación o un comentario
en el código:

| Lección | Dónde |
|---|---|
| El nombre del cluster tiene un máximo de 15 caracteres (corosync) | `roles/topology` |
| El nombre del nodo tiene que resolver a su IP de gestión, no a `127.0.1.1` | `roles/preflight` |
| PVE 9 usa repos deb822: `Enabled: false` va sin línea en blanco delante | `roles/repos` |
| El privilegio `VM.Monitor` ya no existe en PVE 9 (`pveum role add` falla) | [accesos.md](accesos.md) |
| Activar TOTP en el realm bloquea el realm entero; el segundo factor va por usuario | `roles/access` |
| El instalador de PVE 9 llama a las NIC `nic0`, `nic1`… | [instalacion.md](instalacion.md) |
| No pongas `console=` en el arranque del instalador por GRUB | `install/grub-oneshot.sh` |
| Para contar los miembros, `pvecm nodes` (`pvecm status` solo lista el nodo local) | `roles/validate` |
| La puerta de enlace de muchas redes no sirve DNS | `examples/3-nodos`, `roles/network` |
