# Dograh Local Voice Stack

Repositorio reproducible para levantar y diagnosticar un stack de voz local con **Dograh + Asterisk/PJSIP/ARI + Linphone + Ollama**, evitando los fallos que suelen aparecer cuando Docker, SIP, RTP, ARI y el firewall se configuran todos a la vez.

El recorrido validado por este proyecto separa cada capa y no avanza hasta comprobar la anterior:

```text
Linphone (teléfono)
        │ SIP 5060 / RTP 10000-20000
        ▼
Asterisk en el host
        │ ARI HTTP/WebSocket 8088
        ▼
Dograh en Docker
        │ OpenAI-compatible API 11434
        ▼
Ollama en el host → qwen2.5:7b-instruct-q5_K_M
```

> **Importante:** Asterisk, SIP local, Dograh self-hosted y Ollama pueden ejecutarse en tu propia máquina. Una voz administrada de Dograh, por ejemplo **Pedro**, puede depender de servicios externos y de su política de precios. Una llamada SIP dentro de tu LAN tampoco es una llamada PSTN/celular: para marcar un número telefónico real hace falta un trunk/carrier/gateway.

## Sistemas soportados

- Arch Linux / CachyOS.
- Ubuntu / Debian con systemd.
- Docker Engine + Docker Compose v2.

El instalador detecta distribución, IP LAN, interfaz, subnet de la red Docker y firewall. **No hardcodea** direcciones como `192.168.1.44` o `172.20.0.0/16`.

## Instalación rápida

Cloná el repositorio y revisá primero qué haría:

```bash
git clone https://github.com/gabibenitezzz003/dograh-local-voice-stack.git
cd dograh-local-voice-stack
sudo ./scripts/install.sh --dry-run
```

**Resultado esperado:** una secuencia de fases `preflight → platform → asterisk → sip_checkpoint → network → firewall → dograh → ari_checkpoint → ollama → final_verify` sin modificar el sistema.

Si el dry-run falla, consultá [Troubleshooting](docs/TROUBLESHOOTING.md) y la guía de tu plataforma: [Arch/CachyOS](docs/ARCH-CACHYOS.md) o [Ubuntu/Debian](docs/UBUNTU-DEBIAN.md).

## Validación antes de instalar

Ejecutá toda la suite estática con un solo comando:

```bash
bash tests/run-static.sh
```

**Resultado esperado:** termina con `PASS: suite estática completa`. Esta suite valida sintaxis Bash, contrato de archivos/configuración, seguridad de `--dry-run` y el fallback Arch/AUR en aislamiento.

El repositorio también incluye `.github/workflows/ci.yml`, por lo que GitHub Actions ejecuta esta misma suite en cada `push` y `pull_request`.

Para instalar:

```bash
sudo ./scripts/install.sh
```

**Resultado esperado:** el instalador se detiene en dos checkpoints humanos en vez de dar por bueno el audio automáticamente. Si una fase falla, ejecutá `./scripts/doctor.sh` y abrí [Troubleshooting](docs/TROUBLESHOOTING.md).

Si corregiste un problema y querés continuar sin rehacer fases válidas:

```bash
sudo ./scripts/install.sh --resume
```

**Resultado esperado:** mensajes `Fase ... ya estaba completa y sigue válida; se omite` para fases que realmente siguen sanas. Si una verificación dejó de pasar, esa fase se ejecuta nuevamente.

## Checkpoint 1 — Linphone → 600

Instalá [Linphone](https://www.linphone.org/en/download/) en el teléfono conectado a la misma LAN. El instalador imprime la IP correcta; configurá la cuenta manual SIP con:

```text
Usuario:        2001
Auth username:  2001
Servidor:       <IP_LAN_DE_LA_PC>
Puerto:         5060
Transporte:     UDP
Contraseña:     la SIP_PASSWORD generada localmente
```

Para consultar **solo** la contraseña SIP en la máquina donde instalaste el stack:

```bash
sudo awk -F= '$1=="SIP_PASSWORD"{print $2}' .runtime/secrets.env
```

**Resultado esperado:** una única línea con la clave local. No la pegues en issues, logs ni commits. Si no aparece, revisá [Seguridad](docs/SECURITY.md) y [Asterisk](docs/ASTERISK.md).

Desde Linphone llamá al **600**. Tenés que escucharte a vos mismo.

**Resultado esperado:** audio de ida y vuelta por `Echo()`. Esto valida registro SIP, PJSIP, RTP, codec, micrófono, parlante y firewall **antes** de involucrar Dograh. Si registra pero no hay audio, seguí [SIP conecta pero no hay audio/RTP](docs/TROUBLESHOOTING.md#sip-conecta-pero-no-hay-audiortp).

## Checkpoint 2 — Asterisk ARI dentro de Dograh

Abrí `http://localhost:3010`, entrá a **Telephony → Add configuration → Asterisk ARI** y cargá:

```text
Name:                       Asterisk Local
ARI Endpoint:               http://<GATEWAY_DE_AUTOMATION_NET>:8088
Stasis App Name:            dograh
ARI Password:               <ARI_PASSWORD local>
websocket_client.conf Name: dograh
```

El instalador imprime el gateway correcto. Para consultar solo la clave ARI:

```bash
sudo awk -F= '$1=="ARI_PASSWORD"{print $2}' .runtime/secrets.env
```

**Resultado esperado:** la configuración se guarda y, poco después, `docker logs` del API contiene `WebSocket connected to`. Si ARI hace timeout desde Docker o devuelve un segundo error de autenticación, revisá [Dograh](docs/DOGRAH.md), [Firewall](docs/FIREWALL.md) y [Troubleshooting](docs/TROUBLESHOOTING.md).

Agregá un Caller ID local, por ejemplo `1002`. Ese valor es **origen**, no el destino de la llamada.

## Primera llamada a tu teléfono

En el agente de Dograh elegí **Test Call**. Seleccioná `Asterisk Local`, Caller ID `1002` y hacé clic en:

```text
Use SIP endpoint instead
```

Como destino ingresá:

```text
2001
```

**Resultado esperado:** Linphone empieza a sonar. Al atender, el audio circula `Dograh ↔ Asterisk ↔ Linphone`. Si `2001` no aparece en el selector de Caller ID, eso es correcto: usá **Use SIP endpoint instead**. Ver [Caller ID no es SIP endpoint](docs/TROUBLESHOOTING.md#caller-id-no-es-sip-endpoint).

## Ollama local

El modelo recomendado por defecto es:

```text
qwen2.5:7b-instruct-q5_K_M
```

Comprobá el stack:

```bash
./scripts/doctor.sh
```

**Resultado esperado:** checks `ollama.api`, `ollama.model` y `ollama.from_dograh` en `PASS`. Si Dograh no llega a Ollama pero el host sí, revisá [Ollama escucha solo en 127.0.0.1](docs/TROUBLESHOOTING.md#ollama-escucha-solo-en-12700111434).

Salida estructurada para automatización:

```bash
./scripts/verify-stack.sh --json
```

**Resultado esperado:** JSON válido con cada chequeo y su estado, sin secretos.

## Qué es local y qué puede tener costo

| Componente | Local/self-hosted | Costo de servicio por uso |
|---|---|---|
| Asterisk + SIP/RTP LAN | Sí | No |
| Linphone como extensión SIP | Sí | No |
| Dograh OSS | Sí | No por la plataforma self-hosted |
| Ollama + Qwen local | Sí | No; consume tu hardware/electricidad |
| Voz administrada Dograh como Pedro | No necesariamente | Puede depender de servicios/planes de Dograh |
| Gemini/OpenAI/otros BYOK | No | Depende del proveedor y tu cuota |
| PSTN/celular real | No solo con este repo | Requiere trunk/carrier/gateway/SIM |

## Diagnóstico rápido

```bash
./scripts/doctor.sh
```

**Resultado esperado:** grupos `SYSTEM`, `ASTERISK`, `SIP`, `DOGRAH`, `OLLAMA`, `FIREWALL` y `DOCKER` con `PASS/WARN/FAIL` y una solución concreta para cada fallo. Nunca sustituye los dos checkpoints humanos de audio.

Para un smoke test de servicios ya instalados:

```bash
./tests/smoke-test.sh
```

**Resultado esperado:** verificaciones automáticas de PJSIP/Echo y una completion real Dograh → Ollama. El script **no** inventa un `PASS` de audio humano.

## Guías profundas

- [Cómo funciona el stack](docs/HOW-IT-WORKS.md)
- [Arch Linux / CachyOS](docs/ARCH-CACHYOS.md)
- [Ubuntu / Debian](docs/UBUNTU-DEBIAN.md)
- [Asterisk, PJSIP, ARI y WebSocket Media](docs/ASTERISK.md)
- [Dograh y Asterisk ARI](docs/DOGRAH.md)
- [Linphone y la extensión 2001](docs/LINPHONE.md)
- [Ollama, Qwen y GPU](docs/OLLAMA.md)
- [Firewall y redes Docker](docs/FIREWALL.md)
- [Troubleshooting basado en fallos reales](docs/TROUBLESHOOTING.md)
- [Seguridad, secretos y límites de localidad](docs/SECURITY.md)

## Referencias oficiales principales

- Dograh: https://github.com/dograh-hq/dograh
- Dograh Docker: https://docs.dograh.com/deployment/docker
- Asterisk ARI: https://docs.asterisk.org/Configuration/Interfaces/Asterisk-REST-Interface-ARI/Asterisk-Configuration-for-ARI/
- Asterisk PJSIP: https://docs.asterisk.org/Configuration/Channel-Drivers/SIP/Configuring-res_pjsip/PJSIP-Configuration-Sections-and-Relationships/
- Asterisk WebSocket Media: https://docs.asterisk.org/Configuration/Channel-Drivers/WebSocket/
- Ollama Linux: https://docs.ollama.com/linux
- Ollama OpenAI compatibility: https://docs.ollama.com/api/openai-compatibility
- Docker networking: https://docs.docker.com/engine/network/
- Linphone: https://www.linphone.org/en/download/
- Ubuntu UFW: https://ubuntu.com/server/docs/security-firewall/

## Licencia

MIT para este repositorio. Dograh, Asterisk, Ollama, Linphone y los modelos/proveedores conservan sus propias licencias y condiciones.
