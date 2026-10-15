# Cómo colaborar

- **Issues** para fallos y propuestas. Los fallos de seguridad, no en un issue: [SECURITY.md](SECURITY.md).
- **Un PR por cambio**, desde tu fork, contra `main`.
- `make lint` y `make test` en verde. Son los mismos checks del CI, sin hardware ni secretos.
- Si cambias una plantilla (`answer.toml.j2`, `interfaces.j2`), actualiza los ficheros de
  referencia con `make golden` y revisa su diff en el PR: es exactamente lo que cambiará en los
  nodos.
- Todo lo que cambia un nodo va en un rol **idempotente**, con su comprobación en `make plan`
  (`--check`). Nada específico de un cluster en el código: va al inventario (D-02).
- Cada cambio de comportamiento lleva su documentación en el mismo PR y, si es una decisión, su
  `D-nn` en [docs/arquitectura.md](docs/arquitectura.md#decisiones).
- Nada de datos de tu instalación (IPs, nombres, hashes) en un PR: usa `examples/`.
- Licencia: al contribuir aceptas publicar tu aportación bajo [Apache-2.0](LICENSE).
