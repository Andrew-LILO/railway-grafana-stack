#!/usr/bin/env bash
# Usage: compose-loopback-ports.sh [repo root]. Needs docker with the compose plugin and jq.
set -euo pipefail

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"

if ! config="$(env GF_SECURITY_ADMIN_PASSWORD=unused docker compose --env-file /dev/null -f "$root/docker-compose.yml" config --format json)"; then
  echo "FAIL: docker compose config could not load $root/docker-compose.yml" >&2
  exit 1
fi

rows="$(jq -r '
  ["prometheus", "loki", "tempo", "example_api"][] as $s
  | if .services | has($s) | not then [$s, "missing", ""]
    else .services[$s].ports // [] | .[]
      | [$s, (if (.published // "" | tostring) == "" then "random for target \(.target)" else (.published | tostring) end), (.host_ip // "")]
    end
  | @tsv' <<<"$config")"

failed=0
checked=0
while IFS=$'\t' read -r service published host_ip; do
  [[ -n "$service" ]] || continue
  if [[ "$published" == "missing" ]]; then
    echo "FAIL: service $service is missing from the Compose model"
    failed=1
    continue
  fi
  checked=$((checked + 1))
  if [[ "$host_ip" != "127.0.0.1" ]]; then
    echo "FAIL: $service publishes port $published on ${host_ip:-every interface}"
    failed=1
  fi
done <<<"$rows"

if [[ "$checked" -eq 0 ]]; then
  echo "FAIL: no published ports found for prometheus loki tempo example_api"
  exit 1
fi
if [[ "$failed" -ne 0 ]]; then
  exit 1
fi
echo "PASS: $checked published ports bind to 127.0.0.1"
