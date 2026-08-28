# Arch Linux / CachyOS

## Camino recomendado

Primero:

```bash
sudo ./scripts/install.sh --dry-run
```

**Resultado esperado:** `detect-system.sh` identifica `OS_FAMILY=arch` y el instalador muestra qué paquetes usaría. Si `asterisk` no está en los repositorios configurados, **el dry-run no se detiene**: muestra el fallback AUR que utilizaría.

Luego:

```bash
sudo ./scripts/install.sh
```

El instalador sigue este orden para Asterisk:

1. Si `asterisk` ya existe en el sistema, lo conserva y no lo reinstala.
2. Si `pacman -Si asterisk` lo encuentra, lo instala con `pacman`.
3. Si no está en los repositorios configurados, usa el paquete comunitario AUR `asterisk`.

## Asterisk no disponible en pacman

<a id="asterisk-no-disponible"></a>

En Arch/CachyOS es normal que:

```bash
pacman -Si asterisk
```

no encuentre un paquete en los repositorios habilitados. El instalador ya contempla ese caso y usa:

```text
https://aur.archlinux.org/asterisk.git
```

Antes instala `base-devel` y `git`. La compilación se ejecuta como el usuario normal que invocó `sudo`, porque **`makepkg` no debe ejecutarse como root**. El paquete resultante se instala después con `pacman -U`.

Durante `--dry-run` solo se imprimen esos comandos; no se clona ni compila nada.

AUR es un repositorio comunitario/no oficial. Podés revisar el PKGBUILD antes de continuar en:

https://aur.archlinux.org/packages/asterisk

ArchWiki recomienda instalar `base-devel` y ejecutar `makepkg` como usuario no root:

https://wiki.archlinux.org/title/Arch_User_Repository

Si preferís instalar Asterisk manualmente, también podés hacerlo y luego ejecutar:

```bash
sudo ./scripts/install.sh --resume
```

El instalador detectará `asterisk` ya presente y no lo recompilará.

## Módulos obligatorios

Comprobá:

```bash
sudo asterisk -rx "module show like websocket"
sudo asterisk -rx "module show like ari"
```

**Resultado esperado:** entre los módulos disponibles/cargados deben existir `chan_websocket.so`, `res_http_websocket.so`, `res_pjsip_transport_websocket.so`, `res_websocket_client.so` y módulos ARI. Si faltan, el build/paquete de Asterisk no es suficiente para este stack; revisá [Asterisk](ASTERISK.md).

## Nota de versión

La disponibilidad exacta de Asterisk en repositorios CachyOS/Arch puede cambiar. El instalador detecta el estado actual en cada ejecución y no asume que siempre será necesario usar AUR.
