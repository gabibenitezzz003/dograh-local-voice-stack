# Cómo funciona

## Arquitectura

```text
┌──────────────────────┐
│ Linphone / SIP 2001  │
└──────────┬───────────┘
           │ SIP 5060/udp + RTP 10000-20000/udp
           ▼
┌──────────────────────┐
│ Asterisk en el host  │
│ PJSIP + Echo + ARI   │
└──────────┬───────────┘
           │ ARI HTTP/WebSocket :8088
           ▼
┌──────────────────────┐       OpenAI-compatible :11434      ┌────────────────────┐
│ Dograh API en Docker │─────────────────────────────────────►│ Ollama en el host   │
└──────────────────────┘                                      │ Qwen local          │
                                                              └────────────────────┘
```

Asterisk vive en el host porque debe manejar señalización SIP, RTP y WebSocket Media de forma predecible. Dograh vive en Docker. Ollama vive en el host para usar GPU directamente sin exigir `nvidia-container-toolkit` dentro de Docker.

## Por qué existen dos pruebas de audio

Primero `Linphone → 600 → Echo()`. Si eso falla, el problema está en SIP/PJSIP/RTP/firewall/audio del teléfono y no tiene sentido depurar Dograh.

Después `Dograh Test Call → Asterisk → SIP endpoint 2001`. Esa prueba incorpora ARI, WebSocket Media y el pipeline de voz de Dograh.

## Red Docker

El proyecto crea una red de integración dedicada, por defecto `automation-net`. Solo el servicio API de Dograh necesita esa red compartida. No conectes n8n u otros stacks a `dograh_app-network`: los nombres internos como `postgres` pueden colisionar y resolver al contenedor equivocado.

Referencia oficial de redes bridge: https://docs.docker.com/engine/network/drivers/bridge/

## ARI versus media

ARI usa el HTTP server de Asterisk para control y un WebSocket de eventos. La media de Dograh usa `chan_websocket` con una entrada en `websocket_client.conf` de tipo `per_call_config`. Son funciones relacionadas, pero no se debe reutilizar una misma conexión WebSocket para ambos propósitos.

Referencia oficial: https://docs.asterisk.org/Configuration/Channel-Drivers/WebSocket/

## Localidad

- SIP entre Linphone y Asterisk puede permanecer en la LAN.
- Asterisk y Dograh pueden ser self-hosted.
- Ollama/Qwen se ejecuta localmente.
- Elegir una voz administrada o un proveedor BYOK puede enviar audio/texto fuera de tu máquina.
- Un número celular/PSTN no aparece mágicamente por tener SIP: requiere infraestructura telefónica externa.
