# Seguridad, secretos y límites

## Secretos

El repositorio público nunca debe contener credenciales reales. Los secretos de ejecución viven en `.runtime/secrets.env`; Dograh mantiene su propio `.env` dentro del checkout ignorado `.runtime/dograh`.

`.gitignore` excluye `.runtime/` y `.env`.

Antes de publicar cambios:

```bash
git status --short
git ls-files .runtime .env
```

**Resultado esperado:** ningún archivo de secretos trackeado.

Si una contraseña apareció en una captura, terminal compartida, issue o chat, tratala como filtrada y **rotala**. No reutilices la misma clave para SIP, ARI, Docker, Google, OpenWA u otros servicios.

## ARI 8088

Asterisk ARI controla llamadas. No expongas `8088/tcp` a `Anywhere` ni a Internet sin una arquitectura de seguridad deliberada. Este proyecto permite ARI solamente desde la subnet Docker de integración.

## Ollama 11434

Ollama no debe quedar abierto indiscriminadamente. `OLLAMA_HOST=0.0.0.0:11434` es necesario para que Dograh en Docker llegue al host, pero UFW debe restringir `11434/tcp` a la subnet autorizada.

## SIP/RTP

Para la prueba local, SIP 5060/udp y RTP 10000-20000/udp se permiten desde la LAN detectada. No conviertas esas reglas en exposición pública sin TLS/SRTP, autenticación robusta, rate limiting y un diseño específico de VoIP perimetral.

## Pedro y otros modelos

Que Dograh sea self-hosted no significa que toda voz seleccionada se ejecute localmente. Una voz administrada como **Pedro** puede depender de servicios externos y tener costos o límites propios. Lo mismo aplica a Gemini/OpenAI/otros proveedores BYOK.

Ollama/Qwen es la ruta local documentada para LLM. El proyecto no afirma que Pedro sea gratuito, offline ni local.

## PSTN/celular

SIP en tu LAN permite que un teléfono con Linphone actúe como extensión. Eso **no** permite marcar gratuitamente un número PSTN/celular. Para salir a la red telefónica se necesita un **trunk**, **carrier** o **gateway** (por ejemplo GSM/VoLTE con SIM), sujeto a costos/condiciones del operador.
