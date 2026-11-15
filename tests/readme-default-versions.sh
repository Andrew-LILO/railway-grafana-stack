#!/usr/bin/env bash
# Usage: readme-default-versions.sh [repo root]. Needs no Docker.
set -euo pipefail

root=${1:-"$(cd "$(dirname "$0")/.." && pwd)"}
failures=0

section=$(awk '/^### Version Control/ { on = 1; next } on && /^##/ { exit } on' "$root/README.md")

if [ -z "$section" ]; then
	echo "FAIL: README.md has no \"Version Control\" section" >&2
	exit 1
fi

defaults=$(grep -i 'default' <<<"$section" || true)

for entry in grafana:Grafana loki:Loki prometheus:Prometheus tempo:Tempo; do
	dir=${entry%%:*}
	name=${entry#*:}
	version=$(sed -n 's/^ARG VERSION=//p' "$root/$dir/dockerfile" | head -n 1)
	if [ -z "$version" ]; then
		echo "FAIL: $dir/dockerfile has no ARG VERSION default" >&2
		failures=$((failures + 1))
		continue
	fi
	pattern="${name}[^\`]*\`${version//./\\.}\`"
	if grep -Eq "$pattern" <<<"$defaults"; then
		echo "PASS: README.md states the $name default, $version"
	else
		echo "FAIL: README.md does not state the $name default, $version from $dir/dockerfile" >&2
		failures=$((failures + 1))
	fi
done

if [ "$failures" -gt 0 ]; then
	echo "checks failed: $failures" >&2
	exit 1
fi
