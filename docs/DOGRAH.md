# Dograh

Dograh es la plataforma de agentes de voz. Este repo no copia su código: usa el upstream oficial y añade una red de integración y verificaciones alrededor.

- Proyecto: https://github.com/dograh-hq/dograh
- Docker: https://docs.dograh.com/deployment/docker
- Variables: https://docs.dograh.com/developer/environment-variables

## Arranque reproducible

`scripts/configure-dograh.sh` clona el upstream en `.runtime/dograh`, usa su helper de inicialización para generar los secretos requeridos, fuerza `ENABLE_TELEMETRY=false`, mantiene `ENABLE_ARI_MANAGER=true`, adjunta el API a `automation-net` y espera HTTP 200 en API/UI.

```bash
sudo ./scripts/configure-dograh.sh
```

**Resultado esperado:** `Dograh API HTTP 200 y UI disponible` y datos dinámicos de subnet/gateway/API guardados en `.runtime/state.env`.

> Sensible a versión: Dograh cambia su `docker-compose.yaml` y scripts upstream. Este proyecto valida archivos/servicios antes de continuar en lugar de asumir nombres de contenedores fijos.

## Configuración Asterisk ARI

En `http://localhost:3010`:

```text
Telephony → Add configuration
Name:                       Asterisk Local
Provider:                   Asterisk ARI
ARI Endpoint:               http://<DOGRAH_DOCKER_GATEWAY>:8088
Stasis App Name:            dograh
ARI Password:               <ARI_PASSWORD>
websocket_client.conf Name: dograh
```

Agregá Caller ID `1002` si querés un identificador local para test.

**Resultado esperado:** logs del API con `WebSocket connected to http://...:8088` y conexión TCP `ESTAB` hacia Asterisk.

`ari show apps` vacío por sí solo no invalida la conexión: `doctor.sh` comprueba el log del ARI Manager y la conexión establecida.

## Test Call correcto

El desplegable `Caller ID (from)` elige el **origen**. Para llamar al teléfono SIP 2001 usá:

```text
Use SIP endpoint instead → 2001
```

**Resultado esperado:** Linphone suena y podés atender.

## Voces y modelos

Dograh self-hosted es open source, pero la elección de un proveedor/voz define dónde se procesa la conversación. Una voz administrada como Pedro puede depender de infraestructura externa. BYOK (Gemini, OpenAI u otros) también implica el servicio del proveedor. Ollama local se documenta en [OLLAMA.md](OLLAMA.md).

## Backend connection failed

En una versión observada, fijar `BACKEND_API_ENDPOINT=http://localhost:8000` provocó `Backend connection failed` en la UI. No se aplica un workaround global porque es sensible a versión. Si aparece exactamente ese síntoma, seguí [Troubleshooting](TROUBLESHOOTING.md#dograh-backend-connection-failed).
