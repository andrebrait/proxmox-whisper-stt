#!/usr/bin/env bash
set -Eeuo pipefail

if (( EUID != 0 )); then
  echo "Run this script as root on the Proxmox VE host." >&2
  exit 1
fi

: "${TEMPLATE:?Set TEMPLATE to a downloaded Debian 13 template, for example local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst}"
: "${SSH_PUBLIC_KEY_FILE:?Set SSH_PUBLIC_KEY_FILE to an SSH public-key file}"

VMID="${VMID:-112}"
CT_HOSTNAME="${CT_HOSTNAME:-stt-server}"
STORAGE="${STORAGE:-local-zfs}"
BRIDGE="${BRIDGE:-vmbr0}"
CORES="${CORES:-6}"
MEMORY_MB="${MEMORY_MB:-8192}"
DISK_GB="${DISK_GB:-16}"
GPU_DEVICE="${GPU_DEVICE:-/dev/dri/renderD128}"
GUEST_RENDER_GID="${GUEST_RENDER_GID:-992}"
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

command -v pct >/dev/null
pvesm path "$TEMPLATE" >/dev/null
[[ -r "$SSH_PUBLIC_KEY_FILE" ]] || { echo "Cannot read $SSH_PUBLIC_KEY_FILE" >&2; exit 1; }
[[ -e "$GPU_DEVICE" ]] || { echo "GPU render node not found: $GPU_DEVICE" >&2; exit 1; }
if pct status "$VMID" >/dev/null 2>&1; then
  echo "VMID $VMID already exists; refusing to modify it." >&2
  exit 1
fi

pct create "$VMID" "$TEMPLATE" \
  --hostname "$CT_HOSTNAME" \
  --ostype debian \
  --arch amd64 \
  --unprivileged 1 \
  --cores "$CORES" \
  --memory "$MEMORY_MB" \
  --swap 0 \
  --rootfs "${STORAGE}:${DISK_GB}" \
  --net0 "name=eth0,bridge=${BRIDGE},ip=dhcp,ip6=auto" \
  --ssh-public-keys "$SSH_PUBLIC_KEY_FILE" \
  --onboot 1

pct set "$VMID" --dev0 "${GPU_DEVICE},gid=${GUEST_RENDER_GID},mode=0660"
pct start "$VMID"

network_ready=0
for _ in $(seq 1 60); do
  if pct exec "$VMID" -- getent hosts deb.debian.org >/dev/null 2>&1; then
    network_ready=1
    break
  fi
  sleep 2
done
if (( network_ready == 0 )); then
  echo "Container exists and is running, but networking did not become ready." >&2
  exit 1
fi

pct push "$VMID" "$REPO_DIR/scripts/install-whisper.sh" /root/install-whisper.sh
pct push "$VMID" "$REPO_DIR/systemd/whisper-server.service" /etc/systemd/system/whisper-server.service
pct exec "$VMID" -- chmod 0755 /root/install-whisper.sh
pct exec "$VMID" -- env RENDER_GID="$GUEST_RENDER_GID" /root/install-whisper.sh

printf '\nDeployment complete. Container addresses:\n'
pct exec "$VMID" -- hostname -I
