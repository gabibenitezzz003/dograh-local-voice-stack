# Firewall y redes

## Principio de mínimo acceso

El proyecto necesita cuatro aperturas lógicas:

```text
LAN            → host:5060/udp          SIP
LAN            → host:10000-20000/udp   RTP
Dograh subnet  → host:8088/tcp           ARI
Dograh subnet  → host:11434/tcp          Ollama
```

No usa reglas amplias como `ufw allow 8088` o `ufw allow 11434`.

## UFW

Si UFW ya está activo, `configure-firewall.sh` detecta LAN y subnet Docker y añade reglas acotadas. Si UFW está inactivo, el script **no lo activa automáticamente**, porque habilitar un firewall desde una sesión remota puede cortarte el acceso.

```bash
sudo ufw status numbered
```

**Resultado esperado:** reglas SIP/RTP desde la LAN y ARI/Ollama desde la subnet de integración, no desde `Anywhere`.

Referencia oficial: https://ubuntu.com/server/docs/security-firewall/

## firewalld o nftables

La primera versión del proyecto no muta automáticamente firewalld/nftables. `doctor.sh` detecta el gestor y la documentación te da los puertos/subnets necesarios; aplicá reglas equivalentes con tu política existente.

## Docker → host

Un servicio en `0.0.0.0:8088` puede responder desde el host y aun así hacer timeout desde un contenedor si UFW bloquea esa ruta. Por eso el diagnóstico debe probar **desde Dograh**, no solo con `curl localhost`.

## `automation-net` y colisiones DNS

Docker provee DNS por nombre en redes bridge definidas por el usuario. Si conectás un contenedor ajeno directamente a `dograh_app-network`, nombres genéricos como `postgres` pueden apuntar al Postgres de Dograh.

Usá `automation-net` como única red compartida. No conectes n8n u otros stacks a la red interna de Dograh.

Referencia Docker: https://docs.docker.com/engine/network/
