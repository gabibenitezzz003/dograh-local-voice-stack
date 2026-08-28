# Troubleshooting basado en fallos reales

Ejecutá primero:

```bash
./scripts/doctor.sh
```

El objetivo de esta guía es aislar la capa que falla. No cambies SIP, Docker, ARI y modelos al mismo tiempo.

## Baresip: `Protocol not supported [93]`

### Síntoma
Baresip 4.6.0 aborta el registro con `SIP register failed: Protocol not supported [93]` antes de que Asterisk vea un REGISTER.

### Causa
En el caso observado, Baresip usando `127.0.0.1` no llegó a emitir tráfico SIP. Cambiar al IP LAN hizo que el REGISTER saliera. Esto es una ruta de diagnóstico específica, **no una regla universal de Baresip**.

### Diagnóstico
Activá logger PJSIP en Asterisk o tcpdump y comprobá si llega algún REGISTER. Revisá también las direcciones locales que Baresip enumera al iniciar.

### Solución
Probá el IP LAN real de la máquina como dominio/listen y una versión actual de Baresip/libre. Para este proyecto, el cliente de referencia es Linphone en el teléfono; no dependemos de Baresip para el camino feliz.

### Verificación
Asterisk recibe `REGISTER`; si luego aparece 401 Digest, pasá al incidente siguiente en vez de volver a tocar red.

## Segundo `401 Unauthorized` después de Authorization

### Síntoma
Asterisk devuelve un primer `401 Unauthorized`, el cliente reintenta con header `Authorization`, y Asterisk vuelve a responder `401 Unauthorized`.

### Causa
El primer 401 es el challenge Digest normal. El **segundo** indica que la autenticación no verificó: usuario, contraseña, realm/digest o credencial cargada no coincide.

### Diagnóstico
Usá `pjsip set logger on` y distinguí el REGISTER inicial del segundo. Compará la credencial del endpoint con la que usa el cliente sin publicarla.

### Solución
Sincronizá `auth_user` y contraseña. En este repo, regenerá/configurá Asterisk con `sudo ./scripts/configure-asterisk.sh` y copiá localmente la `SIP_PASSWORD` exacta a Linphone.

### Verificación
La secuencia termina en `200 OK` y `pjsip show contacts` muestra el contacto.

## `No objects found` en `pjsip show contacts`

### Síntoma
`sudo asterisk -rx "pjsip show contacts"` devuelve `No objects found`.

### Causa
No hay ningún dispositivo registrado en un AoR dinámico. Tener el endpoint 2001 configurado no crea un contacto por sí mismo.

### Diagnóstico
Comprobá `pjsip show endpoint 2001` y `pjsip show aor 2001`. Luego revisá si Linphone figura conectado.

### Solución
Registrá Linphone con usuario/auth user `2001`, IP LAN del servidor, puerto 5060 UDP y la contraseña correcta.

### Verificación
`pjsip show contacts` muestra `2001/...` y Linphone puede llamar al 600.

## ARI timeout desde Docker

<a id="ari-timeout-desde-docker"></a>

### Síntoma
Desde el host `curl http://127.0.0.1:8088/...` responde, pero desde el contenedor Dograh un socket a `<gateway>:8088` termina en `TimeoutError`.

### Causa
La ruta Docker → host está filtrada. En el caso observado, UFW bloqueaba esa entrada aunque Asterisk escuchaba en `0.0.0.0:8088`.

### Diagnóstico
Compará `ss -ltnp | grep :8088`, un curl desde host y un socket/curl desde `docker exec` del API Dograh.

### Solución
Permití `8088/tcp` **solo desde la subnet Docker de integración**. Usá `sudo ./scripts/configure-firewall.sh` o una regla equivalente de tu firewall.

### Verificación
Desde Dograh el socket abre; sin credenciales ARI devuelve 401 y con credenciales válidas devuelve HTTP 200.

## UFW bloqueando Docker → host

### Síntoma
ARI 8088 y/o Ollama 11434 funcionan en el host, pero Dograh hace timeout.

### Causa
UFW trata el tráfico que entra por el bridge Docker como tráfico entrante al host y no existe una regla para esa subnet.

### Diagnóstico
`sudo ufw status numbered`, `docker network inspect automation-net` y una prueba desde el contenedor API.

### Solución
Ejecutá `sudo ./scripts/configure-firewall.sh`. No uses `ufw allow 8088`/`11434` globales.

### Verificación
`doctor.sh` marca `firewall.ari`, `firewall.ollama`, `asterisk.ari_auth` y `ollama.from_dograh` como PASS.

## Dograh `Backend connection failed`

<a id="dograh-backend-connection-failed"></a>

### Síntoma
La UI de Dograh muestra `Backend connection failed` aun cuando `http://127.0.0.1:8000/api/v1/health` responde 200.

### Causa
En una versión observada, `BACKEND_API_ENDPOINT=http://localhost:8000` causaba un camino de health/backend incorrecto para la UI y disparaba lógica auxiliar. Este comportamiento es **sensible a versión**.

### Diagnóstico
Confirmá primero API 200 y revisá `.runtime/dograh/.env` y logs. Aplicá este workaround solo si el síntoma coincide.

### Solución
Usá un hostname local dedicado, por ejemplo `dograh.test`, resolviéndolo al host, y configurá `BACKEND_API_ENDPOINT=http://dograh.test:8000`; reiniciá los servicios afectados. En versiones nuevas, preferí la configuración que indique el upstream y no fuerces esta variable si no hace falta.

### Verificación
La UI deja de mostrar el error y `/api/v1/health` continúa en 200.

## Ollama escucha solo en `127.0.0.1:11434`

<a id="ollama-escucha-solo-en-12700111434"></a>

### Síntoma
`ss` muestra `127.0.0.1:11434`; el host accede a Ollama pero Dograh hace timeout.

### Causa
Loopback solo es accesible dentro del namespace del host. Un contenedor necesita llegar a una interfaz/gateway del host.

### Diagnóstico
`sudo ss -ltnp | grep :11434` y una conexión desde `docker exec` al gateway de `automation-net`.

### Solución
Ejecutá `sudo ./scripts/configure-ollama.sh`; instala el override `OLLAMA_HOST=0.0.0.0:11434` y restringí acceso con firewall desde la subnet Docker.

### Verificación
`/v1/models` y `/v1/chat/completions` responden desde dentro del API Dograh; `doctor.sh` marca `ollama.from_dograh` PASS.

## Colisión Docker con hostname `postgres`

### Síntoma
Otro stack, por ejemplo n8n, empieza a fallar con autenticación PostgreSQL después de conectarlo a una red de Dograh.

### Causa
El contenedor ajeno fue conectado a `dograh_app-network`. Docker DNS resolvió el hostname genérico `postgres` al PostgreSQL de Dograh en lugar del PostgreSQL propio del otro stack.

### Diagnóstico
Inspeccioná las redes de ambos contenedores y resolvé `postgres` desde el contenedor afectado. `verify-stack.sh` también reporta `docker.dns_collision`.

### Solución
Desconectá el stack ajeno de la red interna de Dograh. Compartí únicamente `automation-net` con los servicios que realmente necesitan integración.

### Verificación
El hostname `postgres` del stack ajeno vuelve a resolver a su DB correcta y `docker.dns_collision` queda PASS.

## Asterisk restart timeout

<a id="asterisk-restart-timeout"></a>

### Síntoma
`systemctl restart asterisk` falla con `start operation timed out`, pero segundos después Asterisk puede aparecer `active (running)`.

### Causa
Un proceso de Asterisk puede quedar atascado durante shutdown/start; systemd lo termina y, por la política `Restart=`, levanta una nueva instancia.

### Diagnóstico
Revisá `systemctl status asterisk`, `journalctl -xeu asterisk.service` y `asterisk -rx "core show uptime"`.

### Solución
No ejecutes reinicios en bucle. El configurador espera y consulta `systemctl is-active`; si no se recupera, inspeccioná logs antes de volver a tocar configuración.

### Verificación
Servicio `active (running)`, nuevo uptime y comandos CLI de Asterisk respondiendo.

## Linphone Unauthorized

<a id="linphone-unauthorized"></a>

### Síntoma
Linphone muestra `Unauthorized` al iniciar sesión.

### Causa
Usuario de autenticación o contraseña SIP incorrecta. En el caso observado, la contraseña se había tipeado mal.

### Diagnóstico
Confirmá que `Username=2001` y `Auth username=2001`. Consultá la contraseña local sin compartirla. Si hace falta, `pjsip set logger on` muestra el challenge/response.

### Solución
Volvé a escribir la `SIP_PASSWORD` exacta y mantené servidor = IP LAN del host, puerto 5060, UDP.

### Verificación
Linphone queda registrado y `pjsip show contacts` lista 2001.

## SIP conecta pero no hay audio/RTP

<a id="sip-conecta-pero-no-hay-audiortp"></a>

### Síntoma
La llamada establece señalización pero no escuchás audio, o hay audio en una sola dirección.

### Causa
SIP 5060 y RTP son flujos distintos. Firewall, NAT, direcciones SDP o puertos RTP pueden bloquear media aun cuando INVITE/200 OK funcionen.

### Diagnóstico
Probá primero Linphone → 600. Revisá reglas `10000:20000/udp`, `rtp set debug on` si necesitás detalle y la IP anunciada.

### Solución
Permití RTP desde la LAN, mantené `direct_media=no`, `rtp_symmetric=yes`, `force_rport=yes`, `rewrite_contact=yes` para el endpoint de prueba y corregí NAT/firewall antes de Dograh.

### Verificación
En 600 te escuchás a vos mismo de manera estable.

## Caller ID no es SIP endpoint

<a id="caller-id-no-es-sip-endpoint"></a>

### Síntoma
En Test Call solo aparece `Dograh Local - 1002` y no aparece `2001` en el desplegable Caller ID.

### Causa
Caller ID define quién origina/identifica la llamada; `2001` es el **destino SIP**.

### Diagnóstico
En el modal de llamada buscá el enlace `Use SIP endpoint instead`.

### Solución
Dejá Caller ID `1002`, elegí `Use SIP endpoint instead` e ingresá destino `2001`.

### Verificación
Asterisk origina hacia `PJSIP/2001` y Linphone suena.

## `ari show apps` vacío con Dograh conectado

### Síntoma
`ari show apps` no lista una aplicación, pero Dograh dice tener ARI Manager activo.

### Causa
Ese comando aislado no es una prueba suficiente del flujo que usa la versión actual de Dograh. La evidencia útil es el WebSocket ARI real y la sesión TCP establecida.

### Diagnóstico
Buscá `WebSocket connected to` en logs Dograh y `ESTAB` hacia 8088 con `ss -tnp`.

### Solución
No cambies Stasis/credenciales solo por `ari show apps` vacío si ambas pruebas reales están sanas. Si el WebSocket no existe, depurá endpoint, UFW y credencial.

### Verificación
`doctor.sh` muestra `dograh.ari_manager` y `dograh.ari_websocket` PASS.
