#!/usr/bin/env bash
# Usage: compose-config-warnings.sh [repo root]. Needs docker with the compose plugin.
set -euo pipefail

root=${1:-"$(cd "$(dirname "$0")/.." && pwd)"}

# Compose can warn on stderr and still exit 0.
if ! warnings=$(env GF_SECURITY_ADMIN_PASSWORD=unused docker compose --env-file /dev/null \
	-f "$root/docker-compose.yml" config --quiet 2>&1); then
	echo "$warnings" >&2
	echo "FAIL: docker compose config could not load $root/docker-compose.yml" >&2
	exit 1
fi

if [ -n "$warnings" ]; then
	echo "$warnings" >&2
	echo "FAIL: docker compose config writes warnings for docker-compose.yml" >&2
	exit 1
fi

echo "PASS: docker compose config loads docker-compose.yml without warnings"
