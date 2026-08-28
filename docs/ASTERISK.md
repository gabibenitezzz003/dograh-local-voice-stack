# Asterisk: PJSIP, Echo, ARI y WebSocket Media

## Archivos administrados

`scripts/configure-asterisk.sh` agrega bloques marcados en:

- `/etc/asterisk/http.conf`
- `/etc/asterisk/ari.conf`
- `/etc/asterisk/pjsip.conf`
- `/etc/asterisk/extensions.conf`
- `/etc/asterisk/websocket_client.conf`

Antes de modificarlos crea backups con timestamp en `.runtime/backups/`. Volver a ejecutar el script reemplaza solo sus bloques administrados y no duplica secciones.

## Transportes PJSIP y restart completo

<a id="transportes-pjsip-y-restart-completo"></a>

El proyecto configura UDP y TCP en el puerto SIP. Asterisk documenta que cambios en objetos `transport` **no se aplican con un reload normal**; requieren restart completo.

Referencia oficial: https://docs.asterisk.org/Asterisk_20_Documentation/API_Documentation/Module_Configuration/res_pjsip/

Verificación:

```bash
sudo asterisk -rx "pjsip show transports"
```

**Resultado esperado:** `transport-udp` y `transport-tcp`.

## Extensión 2001

El endpoint usa `auth`, `aor`, `ulaw/alaw`, `direct_media=no`, `rtp_symmetric=yes`, `force_rport=yes` y `rewrite_contact=yes`. La relación endpoint/auth/AoR sigue el modelo PJSIP oficial:

https://docs.asterisk.org/Configuration/Channel-Drivers/SIP/Configuring-res_pjsip/PJSIP-Configuration-Sections-and-Relationships/

```bash
sudo asterisk -rx "pjsip show endpoint 2001"
sudo asterisk -rx "pjsip show contacts"
```

**Resultado esperado:** endpoint configurado; después de iniciar sesión en Linphone, un contacto `2001/...` disponible.

## Echo 600

El dialplan administrado crea `600@from-internal` con `Answer()`, `Wait(1)`, `Echo()` y `Hangup()`.

```bash
sudo asterisk -rx "dialplan show 600@from-internal"
```

**Resultado esperado:** la extensión 600 y la aplicación Echo. El test real se hace desde Linphone y requiere escucharte.

## ARI HTTP

ARI requiere HTTP habilitado y un usuario. El proyecto crea el usuario `dograh` con contraseña aleatoria local.

Referencia oficial: https://docs.asterisk.org/Configuration/Interfaces/Asterisk-REST-Interface-ARI/Asterisk-Configuration-for-ARI/

Sin credenciales:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8088/ari/asterisk/info
```

**Resultado esperado:** `401`. Eso prueba reachability, no autenticación.

Con la credencial local, `verify-stack.sh` exige `200` sin imprimirla.

## WebSocket Media

La plantilla usa:

```ini
[dograh]
type = websocket_client
uri = ws://127.0.0.1:8000/api/v1/telephony/ws/ari
protocols = media
connection_type = per_call_config
```

Asterisk documenta que `chan_websocket` para conexiones salientes de media usa `websocket_client.conf` y solo admite `per_call_config`.

Referencias:

- https://docs.asterisk.org/Configuration/Channel-Drivers/WebSocket/
- https://docs.asterisk.org/Latest_API/API_Documentation/Module_Configuration/res_websocket_client/

## Restart timeout de systemd

Si `systemctl restart asterisk` devuelve timeout, el script no asume que todo murió: espera y consulta `systemctl is-active`. Esto cubre el caso real en que systemd mata un proceso atascado y el `Restart=` del servicio levanta una instancia sana segundos después.

Ver [Troubleshooting](TROUBLESHOOTING.md#asterisk-restart-timeout).
