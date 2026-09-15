#!/usr/bin/env bash
set -Eeuo pipefail

if (( EUID != 0 )); then
  echo "Run this script as root inside the Debian LXC." >&2
  exit 1
fi

WHISPER_CPP_VERSION="v1.9.4"
WHISPER_DIR="/opt/whisper.cpp"
MODEL_NAME="small"
MODEL_PATH="/var/lib/whisper/models/ggml-small.bin"
MODEL_SHA256="1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b"
RENDER_GID="${RENDER_GID:-992}"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y full-upgrade
apt-get install -y --no-install-recommends \
  build-essential ca-certificates cmake curl ffmpeg git glslc \
  libvulkan-dev mesa-vulkan-drivers spirv-headers vulkan-tools

if getent group render >/dev/null; then
  actual_render_gid="$(getent group render | cut -d: -f3)"
  if [[ "$actual_render_gid" != "$RENDER_GID" ]]; then
    echo "render group GID is $actual_render_gid, but GPU passthrough expects $RENDER_GID." >&2
    echo "Recreate the LXC with GUEST_RENDER_GID=$actual_render_gid." >&2
    exit 1
  fi
else
  groupadd --system --gid "$RENDER_GID" render
fi

if ! id whisper >/dev/null 2>&1; then
  useradd --system --home-dir /var/lib/whisper --create-home --shell /usr/sbin/nologin whisper
fi
usermod -aG render whisper
install -d -o whisper -g whisper /var/lib/whisper/models /var/lib/whisper/tmp

if [[ ! -d "$WHISPER_DIR/.git" ]]; then
  git clone --branch "$WHISPER_CPP_VERSION" --depth 1 \
    https://github.com/ggml-org/whisper.cpp.git "$WHISPER_DIR"
else
  current_version="$(git -C "$WHISPER_DIR" describe --tags --always --dirty)"
  if [[ "$current_version" != "$WHISPER_CPP_VERSION" ]]; then
    echo "$WHISPER_DIR is $current_version; expected $WHISPER_CPP_VERSION. Refusing to overwrite it." >&2
    exit 1
  fi
fi

cmake -S "$WHISPER_DIR" -B "$WHISPER_DIR/build" \
  -DGGML_VULKAN=ON \
  -DCMAKE_BUILD_TYPE=Release
cmake --build "$WHISPER_DIR/build" --config Release --parallel "$(nproc)" \
  --target whisper-cli whisper-server

if ! printf '%s  %s\n' "$MODEL_SHA256" "$MODEL_PATH" | sha256sum --check --status; then
  rm -f "$WHISPER_DIR/models/ggml-${MODEL_NAME}.bin" "$MODEL_PATH"
  "$WHISPER_DIR/models/download-ggml-model.sh" "$MODEL_NAME"
  install -o root -g whisper -m 0640 \
    "$WHISPER_DIR/models/ggml-${MODEL_NAME}.bin" "$MODEL_PATH"
fi
printf '%s  %s\n' "$MODEL_SHA256" "$MODEL_PATH" | sha256sum --check

[[ -f /etc/systemd/system/whisper-server.service ]] || {
  echo "Missing /etc/systemd/system/whisper-server.service" >&2
  exit 1
}

runuser -u whisper -- bash -c 'cd /var/lib/whisper && vulkaninfo --summary >/dev/null'
systemctl daemon-reload
systemctl enable --now whisper-server

for _ in $(seq 1 30); do
  if curl --fail --silent http://127.0.0.1:8080/health >/dev/null; then
    echo "whisper-server is healthy."
    exit 0
  fi
  sleep 1
done

systemctl status whisper-server --no-pager || true
exit 1
