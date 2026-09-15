#!/usr/bin/env bash
set -Eeuo pipefail

if (( $# != 2 )); then
  echo "Usage: $0 AUDIO_WAV {vulkan|cpu}" >&2
  exit 2
fi

AUDIO_FILE="$1"
MODE="$2"
MODEL="/var/lib/whisper/models/ggml-small.bin"
PROMPT="Technical bilingual dictation in English and Brazilian Portuguese. Common terms: Git status, GitHub, OMP, ompweb, Proxmox LXC, Debian Linux, TypeScript API, JavaScript, Python, Rust, JSON, YAML, SSH, HTTPS, systemd, Docker container, Kubernetes, PostgreSQL, SQLite, regex, CLI, SDK, HTTP, TCP/IP. Transcrição técnica bilíngue em português brasileiro e inglês."
extra_args=()
runner=()
if (( EUID == 0 )); then
  runuser -u whisper -- test -r "$AUDIO_FILE" || {
    echo "whisper user cannot read $AUDIO_FILE" >&2
    exit 1
  }
  runner=(runuser -u whisper --)
fi

case "$MODE" in
  vulkan) ;;
  cpu) extra_args+=(--no-gpu) ;;
  *) echo "Mode must be vulkan or cpu." >&2; exit 2 ;;
esac

[[ -r "$AUDIO_FILE" ]] || { echo "Cannot read $AUDIO_FILE" >&2; exit 1; }
cd /var/lib/whisper
exec "${runner[@]}" /opt/whisper.cpp/build/bin/whisper-cli \
  --model "$MODEL" \
  --file "$AUDIO_FILE" \
  --language auto \
  --threads 6 \
  --beam-size 5 \
  --no-timestamps \
  --prompt "$PROMPT" \
  "${extra_args[@]}"
