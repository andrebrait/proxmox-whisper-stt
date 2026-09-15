#!/usr/bin/env bash
set -Eeuo pipefail

if (( $# < 1 || $# > 2 )); then
  echo "Usage: $0 AUDIO_FILE [ENDPOINT]" >&2
  exit 2
fi

AUDIO_FILE="$1"
ENDPOINT="${2:-http://127.0.0.1:8080/v1/audio/transcriptions}"
[[ -r "$AUDIO_FILE" ]] || { echo "Cannot read $AUDIO_FILE" >&2; exit 1; }
command -v curl >/dev/null
command -v ffprobe >/dev/null

duration="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$AUDIO_FILE")"
response_file="$(mktemp)"
trap 'rm -f "$response_file"' EXIT
read -r status elapsed < <(
  curl --silent --show-error \
    --output "$response_file" \
    --write-out '%{http_code} %{time_total}\n' \
    --form "file=@${AUDIO_FILE}" \
    "$ENDPOINT"
)
rtf="$(awk -v elapsed="$elapsed" -v duration="$duration" 'BEGIN { printf "%.3f", elapsed / duration }')"
throughput="$(awk -v elapsed="$elapsed" -v duration="$duration" 'BEGIN { printf "%.3f", duration / elapsed }')"

printf 'Audio:      %.3f s\n' "$duration"
printf 'HTTP:       %.3f s\n' "$elapsed"
printf 'RTF:        %s\n' "$rtf"
printf 'Throughput: %sx realtime\n' "$throughput"
printf 'Status:     %s\n' "$status"
printf 'Response:\n'
cat "$response_file"
printf '\n'

[[ "$status" == 2* ]]
