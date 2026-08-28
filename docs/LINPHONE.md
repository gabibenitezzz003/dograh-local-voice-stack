# Linphone

Descarga oficial: https://www.linphone.org/en/download/

Para este proyecto se recomienda inicialmente **Linphone en el teléfono** y no depender de un cliente SIP de escritorio específico.

## Cuenta 2001

Con teléfono y PC en la misma LAN:

```text
Usuario:        2001
Auth username:  2001
Contraseña:     SIP_PASSWORD local
Dominio/server: IP LAN de la PC
Puerto:         5060
Transporte:     UDP
Identidad:      sip:2001@<IP_LAN>
```

La IP correcta la muestra el instalador. No uses `127.0.0.1` desde el teléfono: loopback sería el propio teléfono.

## Verificar registro

```bash
sudo asterisk -rx "pjsip show contacts"
```

**Resultado esperado:** un contacto para `2001` después de que Linphone indique que inició sesión.

Si Linphone muestra `Unauthorized`, primero revisá usuario de autenticación y contraseña. Ver [Troubleshooting](TROUBLESHOOTING.md#linphone-unauthorized).

## Audio antes de Dograh

Marcá:

```text
600
```

**Resultado esperado:** te escuchás a vos mismo. Si la llamada conecta pero no vuelve el audio, el problema es RTP/firewall/audio, no Dograh.

## Llamada desde Dograh

No busques `2001` dentro de Caller ID. En Test Call elegí **Use SIP endpoint instead** y escribí `2001`.
