# Dimensionamiento

**Para quién:** quien decide cuántas VMs caben y qué tamaños ofrece el catálogo de pve-platform-iac.
**Qué necesitas antes:** CPU (hilos), RAM y discos de cada nodo.
**Cómo sabrás que ha salido bien:** la suma de lo que ofrece el catálogo, en el peor día, cabe en
lo **asignable** de la tabla de abajo.

## La fórmula

Por nodo se reserva una parte para el propio host, y en el cluster se deja un colchón:

| Concepto | Valor por defecto | Por qué |
|---|---|---|
| CPU del host | 2 hilos por nodo | E/S, red y gestión sin competir con las VMs |
| RAM del host | 4 GiB por nodo | Proxmox y sus servicios |
| ARC de ZFS | min(10 % de la RAM, 16 GiB) (`zfs_arc_max_mib: auto`) | El caché de ZFS; sin límite, crece hasta la mitad de la RAM |
| Colchón | 20 % de lo que queda | Picos, migraciones, mantenimiento (un nodo menos) |
| Espacio libre en ZFS | 15-20 % del pool | Por encima del 80-85 % de ocupación, ZFS va mucho más lento |
| Overcommit de CPU | hasta 1,5:1 en desarrollo; 1:1 en producción | Las VMs de desarrollo casi nunca usan toda su CPU a la vez |

```
asignable_RAM = (Σ RAM_nodo − N × (4 GiB + ARC)) × 0,8
asignable_CPU = (Σ hilos − N × 2) × 0,8 × overcommit
asignable_disco = Σ disco_útil × 0,8          (útil: raid0 = 100 %, raid1 = 50 %, raidz-1 = (d−1)/d)
```

**La RAM es casi siempre el límite**, no la CPU: no se puede sobreasignar sin que el host acabe
sacrificando procesos (OOM).

## Ejemplos

| | 2 nodos | 3 nodos | 5 nodos |
|---|---|---|---|
| Por nodo | 8 hilos, 32 GiB, 1 × 500 GB | 32 hilos, 62 GiB, 1 × 900 GB | 48 hilos, 256 GiB, 2-3 × 960 GB |
| ARC | 3,2 GiB | 6 GiB (fijo) | 16 GiB |
| **RAM asignable** | ~39 GiB | ~124 GiB | ~944 GiB |
| **vCPU asignables** (1:1) | ~10 | ~72 | ~184 |
| vCPU con 1,5:1 | ~15 | ~108 | — (producción: 1:1) |
| **Disco asignable** | ~800 GB | ~2,1 TB | ~5,4 TB (3 espejos + 2 raidz-1) |
| Caben, por ejemplo | 8 VMs de 4 GiB | 6 clusters k3s de 3 nodos (20 GiB) o 30 VMs de 4 GiB | Decenas de servicios con su réplica |

## Si un nodo cae

Con N nodos, el resto tiene que poder con lo crítico. El colchón del 20 % cubre la caída de un
nodo en un cluster de 5, pero no en uno de 2. En un cluster pequeño, decide qué VMs son críticas
(las que tienen réplica) y que **solo esas** quepan en un nodo.

## Del dimensionamiento al catálogo

Los tamaños que los equipos pueden pedir están en `catalog/flavors.yaml` de pve-platform-iac. Que su
suma no pase de lo asignable: el catálogo es **cerrado** precisamente para eso.
