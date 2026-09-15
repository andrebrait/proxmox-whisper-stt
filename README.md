# Proxmox Whisper STT with Intel Vulkan

Reproducible local speech-to-text service for [ompweb](https://github.com/kahme247/ompweb), running [`whisper.cpp`](https://github.com/ggml-org/whisper.cpp) in an unprivileged Debian 13 LXC on Proxmox VE. Intel UHD Graphics 630 acceleration uses Debian's Mesa Vulkan stack; no Docker image, adapter API, Intel oneAPI installation, or privileged container is required.

This repository is both a disaster-recovery runbook and a measured reference for similar Intel iGPU systems.

## Result

- OpenAI-shaped endpoint: `POST /v1/audio/transcriptions`
- Browser formats accepted through FFmpeg conversion: WebM/Opus, MP4/AAC, Ogg/Opus, WAV, and others supported by FFmpeg
- Automatic English and Portuguese language detection
- Multilingual Whisper `small`, beam size 5
- Intel UHD 630 passed directly to an unprivileged LXC
- systemd service running as unprivileged user `whisper`
- 62.44 seconds of real Brazilian Portuguese speech transcribed in 33.10 seconds through HTTP
- Complete measurements: [BENCHMARKS.md](BENCHMARKS.md)

## Tested system

| Component | Value |
|---|---|
| Proxmox VE | 9.2.11, kernel 7.0.14-14-pve |
| Host CPU | Intel Core i5-9500T, 6 cores, up to 3.7 GHz |
| Host GPU | Intel UHD Graphics 630, Coffee Lake GT2 |
| LXC | Unprivileged Debian 13.6, 6 cores, 8 GiB RAM, no swap, 16 GiB ZFS root |
| GPU node | `/dev/dri/renderD128` |
| Guest Vulkan | Mesa 25.0.7 Intel open-source driver, Vulkan 1.4.305 device API |
| whisper.cpp | v1.9.4, `GGML_VULKAN=ON` |
| Model | Multilingual `ggml-small.bin`, 487,601,967 bytes |
| Model SHA-256 | `1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b` |

Hardware identity values such as MAC addresses, device UUIDs, and site-specific hostnames are deliberately omitted. They do not affect reconstruction or performance interpretation.

## Architecture

```text
Browser microphone
      |
      | multipart/form-data: file=<audio>
      v
ompweb /api/stt
      |
      v
Debian LXC :8080
whisper-server --convert
      |
      +-- FFmpeg -> 16 kHz WAV
      +-- whisper.cpp small multilingual
      +-- Mesa Vulkan -> Intel UHD 630
      |
      v
{"text":"..."}
```

`ompweb` already sends the multipart `file` field and expects JSON containing `text`, matching `whisper-server` without an adapter.

## Prerequisites

On the Proxmox host:

- Proxmox VE with `pct`, `pvesm`, and a working bridge such as `vmbr0`
- Intel GPU exposed as `/dev/dri/renderD128`
- Debian 13 standard LXC template downloaded to Proxmox storage
- An SSH public-key file for the new container
- Internet access from the container during installation

Check the GPU:

```sh
ls -l /dev/dri/renderD128
```

Find and download a current Debian 13 template:

```sh
pveam update
pveam available --section system | grep debian-13-standard
pveam download local debian-13-standard_13.6-1_amd64.tar.zst
pveam list local
```

## One-command rebuild

Run on the Proxmox host as root:

```sh
git clone https://github.com/andrebrait/proxmox-whisper-stt.git
cd proxmox-whisper-stt

TEMPLATE='local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst' \
SSH_PUBLIC_KEY_FILE='/root/admin.pub' \
./scripts/rebuild-lxc.sh
```

Default LXC settings reproduce the measured deployment:

```text
VMID=112
CT_HOSTNAME=stt-server
STORAGE=local-zfs
BRIDGE=vmbr0
CORES=6
MEMORY_MB=8192
DISK_GB=16
GPU_DEVICE=/dev/dri/renderD128
GUEST_RENDER_GID=992
```

Override any value as an environment variable:

```sh
VMID=212 STORAGE=fast-zfs BRIDGE=vmbr1 \
TEMPLATE='local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst' \
SSH_PUBLIC_KEY_FILE='/root/admin.pub' \
./scripts/rebuild-lxc.sh
```

The script:

1. Refuses to touch an existing VMID.
2. Creates an unprivileged Debian LXC using DHCP.
3. Passes `/dev/dri/renderD128` with guest group ownership and mode `0660`.
4. Starts the container and waits for networking.
5. Installs build and Vulkan dependencies.
6. Builds pinned `whisper.cpp` v1.9.4 with `GGML_VULKAN=ON`.
7. Downloads and verifies the pinned multilingual `small` model.
8. Installs and starts the systemd service.
9. Waits for a successful health check.

It deliberately retains a partially built container after failure, allowing inspection with `pct enter <VMID>` instead of destroying evidence.

### Run only guest installation

When the LXC already exists, copy both files from the Proxmox host:

```sh
pct push 112 scripts/install-whisper.sh /root/install-whisper.sh
pct push 112 systemd/whisper-server.service /etc/systemd/system/whisper-server.service
pct exec 112 -- chmod 0755 /root/install-whisper.sh
pct exec 112 -- env RENDER_GID=992 /root/install-whisper.sh
```

The installer is safe to rerun against the expected source revision. It refuses to overwrite a different or modified `whisper.cpp` checkout.

## Network address

The container obtains its address through DHCP:

```sh
pct exec 112 -- hostname -I
```

For a stable endpoint, create a DHCP reservation after deployment or configure a static address appropriate for the site. Update `OMP_WEB_STT_ENDPOINT` after any address change.

## Verification

Inside the container:

```sh
systemctl is-enabled whisper-server
systemctl is-active whisper-server
systemctl status whisper-server --no-pager
runuser -u whisper -- bash -c 'cd /var/lib/whisper && vulkaninfo --summary'
sha256sum /var/lib/whisper/models/ggml-small.bin
curl --fail http://127.0.0.1:8080/health
```

Expected health response:

```json
{"status":"ok"}
```

The service log must identify the Intel GPU and `Vulkan0` backend:

```sh
journalctl -u whisper-server --no-pager | grep -E 'Intel|Vulkan0|use gpu'
```

Test transcription from any LAN client:

```sh
curl --fail \
  -F file=@sample.webm \
  http://STT_LXC_IP:8080/v1/audio/transcriptions
```

Expected response shape:

```json
{"text":"transcribed text"}
```

## ompweb configuration

Set only the endpoint:

```sh
OMP_WEB_STT_ENDPOINT=http://STT_LXC_IP:8080/v1/audio/transcriptions
```

Leave these unset for this single-model trusted-LAN deployment:

```sh
OMP_WEB_STT_MODEL=
OMP_WEB_STT_KEY=
```

At the version evaluated here, ompweb accepts files up to 25 MiB and applies a 60-second client timeout plus a separate 60-second proxy timeout. No ompweb adjustment was needed for the measured 62.44-second recording because transcription completed in 33.10 seconds.

## Operations

```sh
# Logs
journalctl -u whisper-server -f

# Restart
systemctl restart whisper-server

# Stop/start
systemctl stop whisper-server
systemctl start whisper-server

# Health
curl --fail http://127.0.0.1:8080/health
```

Temporary converted audio is stored under `/var/lib/whisper/tmp` while requests run. The model and source tree are immutable deployment artifacts; the service has no database or user state.

## Disaster recovery

After total LXC or host loss:

1. Restore or install Proxmox VE on compatible Intel hardware.
2. Confirm `/dev/dri/renderD128` exists.
3. Download a Debian 13 standard template.
4. Clone this repository on the Proxmox host.
5. Run `scripts/rebuild-lxc.sh` with the template and SSH public key.
6. Recreate the DHCP reservation if a stable address is required.
7. Set ompweb's endpoint to the new address.
8. Run the health check and one representative transcription.

No LXC data backup is required to reconstruct the service: source revision, build flags, model checksum, service definition, and benchmark procedure live here. A Proxmox backup remains useful only for faster recovery time.

## Benchmark reproduction

Measure the HTTP path, including upload, FFmpeg conversion, and inference:

```sh
./scripts/benchmark-endpoint.sh sample.webm \
  http://STT_LXC_IP:8080/v1/audio/transcriptions
```

For direct backend comparison, first convert a sample to the same WAV shape used here:

```sh
ffmpeg -i sample.m4a -ar 16000 -ac 1 -c:a pcm_s16le sample.wav
```

Copy `scripts/benchmark-backend.sh` and the WAV into the LXC, then run identical settings:

```sh
./benchmark-backend.sh sample.wav vulkan 2>&1 | tee vulkan.log
./benchmark-backend.sh sample.wav cpu    2>&1 | tee cpu.log
```

Calculate word error rate from UTF-8 reference and hypothesis files:

```sh
python3 scripts/wer.py \
  benchmarks/reference-pt-BR.txt \
  benchmarks/transcript-vulkan-pt-BR.txt
```

Raw voice recordings are intentionally excluded from this public repository. Reference text, model outputs, methodology, and measurements are retained.

## Security boundary

`whisper-server` binds to `0.0.0.0:8080` and this deployment adds no authentication or TLS. Keep it on a trusted LAN or restrict port 8080 with the Proxmox firewall. Add an authenticated TLS reverse proxy before any Internet exposure.

## Why not the alternatives?

- **CPU only:** works, but Vulkan reduced latency in both controlled comparisons.
- **Larger models:** materially slower in short-sample testing; long-form accuracy results are documented in [BENCHMARKS.md](BENCHMARKS.md).
- **Quantized medium/turbo models:** slower and less accurate than `small` on the original short technical sample.
- **OpenVINO in whisper.cpp:** not benchmarked. It accelerates the encoder only and adds model conversion/runtime coupling; measured Vulkan benefit came primarily from decoder work.
- **OpenVINO Model Server:** Intel GPU support is strong, but documented speech input support did not directly cover ompweb's complete browser-format mix.
- **Speaches/faster-whisper:** good API compatibility, but the backend targets CPU and NVIDIA CUDA rather than this Intel iGPU.
- **Custom adapter service:** unnecessary because `whisper-server --convert` already matches ompweb's request and response contract.

## Repository layout

```text
scripts/rebuild-lxc.sh          Proxmox-host disaster-recovery entry point
scripts/install-whisper.sh      Debian guest installation
scripts/benchmark-endpoint.sh   End-to-end HTTP benchmark
scripts/benchmark-backend.sh    Direct Vulkan/CPU comparison
scripts/wer.py                  Dependency-free word error rate calculator
systemd/whisper-server.service  Exact deployed service
benchmarks/                     Reference and model transcripts
BENCHMARKS.md                   Results and methodology
```

## Upstream references

- [whisper.cpp](https://github.com/ggml-org/whisper.cpp)
- [whisper.cpp server](https://github.com/ggml-org/whisper.cpp/tree/master/examples/server)
- [whisper.cpp v1.9.4](https://github.com/ggml-org/whisper.cpp/releases/tag/v1.9.4)
- [ompweb STT route](https://github.com/kahme247/ompweb/blob/main/app/api/stt/route.ts)
- [ompweb dictation hook](https://github.com/kahme247/ompweb/blob/main/hooks/useDictation.ts)
- [Debian mesa-vulkan-drivers](https://packages.debian.org/trixie/mesa-vulkan-drivers)
