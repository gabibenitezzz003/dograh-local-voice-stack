# Arch Linux / CachyOS

## Camino recomendado

Primero:

```bash
sudo ./scripts/install.sh --dry-run
```

**Resultado esperado:** `detect-system.sh` identifica `OS_FAMILY=arch` y el instalador muestra qué paquetes usaría.

Luego:

```bash
sudo ./scripts/install.sh
```

El instalador usa `pacman` y no compila Asterisk silenciosamente.

## Asterisk no disponible

<a id="asterisk-no-disponible"></a>

Si:

```bash
pacman -Si asterisk
```

no encuentra el paquete, el script se detiene. En Arch el fallback habitual es el paquete AUR oficial comunitario:

```bash
sudo pacman -S --needed base-devel git
git clone https://aur.archlinux.org/asterisk.git
cd asterisk
makepkg -si
```

**Resultado esperado:** `asterisk -V` devuelve una versión instalada y `systemctl enable --now asterisk` puede iniciar el servicio.

AUR: https://aur.archlinux.org/packages/asterisk

Después volvé al repo y ejecutá:

```bash
sudo ./scripts/install.sh --resume
```

**Resultado esperado:** la fase de plataforma vuelve a validarse y el flujo continúa.

## Módulos obligatorios

Comprobá:

```bash
sudo asterisk -rx "module show like websocket"
sudo asterisk -rx "module show like ari"
```

**Resultado esperado:** entre los módulos disponibles/cargados deben existir `chan_websocket.so`, `res_http_websocket.so`, `res_pjsip_transport_websocket.so`, `res_websocket_client.so` y módulos ARI. Si faltan, el build/paquete de Asterisk no es suficiente para este stack; revisá [Asterisk](ASTERISK.md).

## Nota de versión

La disponibilidad exacta de Asterisk en repositorios CachyOS/Arch puede cambiar. El script consulta el sistema actual con `pacman -Si`; la guía AUR es un fallback, no una suposición de que siempre sea necesario.
