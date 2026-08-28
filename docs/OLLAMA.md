# Ollama y Qwen local

- Linux: https://docs.ollama.com/linux
- OpenAI compatibility: https://docs.ollama.com/api/openai-compatibility

Modelo por defecto:

```text
qwen2.5:7b-instruct-q5_K_M
```

## Por qué corre en el host

El proyecto ejecuta Ollama en el host. Así puede usar la GPU que Ollama soporte sin exigir que Docker tenga `nvidia-container-toolkit`. Que `docker run --gpus all ...` falle no implica que Ollama host esté usando CPU.

## Listener accesible desde Dograh

El override systemd configura:

```ini
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
```

Eso hace que el socket escuche en todas las interfaces; **la restricción real la pone el firewall**, permitiendo 11434 solo desde la subnet de integración Docker.

```bash
sudo ss -ltnp | grep ':11434'
```

**Resultado esperado:** `0.0.0.0:11434` asociado a Ollama.

## API OpenAI-compatible

```bash
curl -fsS http://127.0.0.1:11434/v1/models
```

**Resultado esperado:** JSON que contiene `qwen2.5:7b-instruct-q5_K_M`.

`configure-ollama.sh` repite el test **desde el contenedor API de Dograh** y hace una llamada a `/v1/chat/completions`. Eso detecta el caso engañoso donde funciona en el host pero UFW bloquea Docker → host.

## GPU

```bash
ollama ps
```

**Resultado esperado en NVIDIA funcionando correctamente:** `100% GPU`. `CPU` también es válido funcionalmente, aunque más lento.

## Si solo escucha 127.0.0.1

Dograh no podrá llegar al host. Ver [Troubleshooting](TROUBLESHOOTING.md#ollama-escucha-solo-en-12700111434).
