# Ubuntu / Debian

## Instalación

```bash
sudo ./scripts/install.sh --dry-run
```

**Resultado esperado:** `OS_FAMILY=debian` y comandos APT sin cambios.

```bash
sudo ./scripts/install.sh
```

El instalador usa `apt-get`, instala `docker.io`, Asterisk, UFW y una variante disponible de Docker Compose v2/plugin.

## Validar Docker Compose

```bash
docker compose version
```

**Resultado esperado:** versión Compose v2. Si el comando no existe, instalá Compose desde la documentación oficial de Docker y reintentá con `--resume`.

Docker Engine: https://docs.docker.com/engine/install/

## Validar Asterisk

```bash
sudo asterisk -rx "core show version"
sudo asterisk -rx "pjsip show transports"
```

**Resultado esperado:** Asterisk responde y, después de la fase de configuración, aparecen `transport-udp` y `transport-tcp`.

Si el transporte TCP no aparece tras un `pjsip reload`, no sigas repitiendo reloads: los transportes requieren restart completo según Asterisk. Ver [Asterisk](ASTERISK.md#transportes-pjsip-y-restart-completo).

## UFW

El proyecto no activa UFW si estaba inactivo, para evitar cortar acceso remoto accidentalmente. Si UFW ya está activo, agrega reglas acotadas y registra cuáles creó para poder retirarlas de manera segura.

Referencia: https://ubuntu.com/server/docs/security-firewall/
