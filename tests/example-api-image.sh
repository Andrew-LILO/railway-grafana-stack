#!/usr/bin/env bash
# Usage: example-api-image.sh [repo root]. Needs docker and jq.
set -euo pipefail

root=$(cd "${1:-$(dirname "$0")/..}" && pwd)
app="$root/examples/api"
id="example-api-image-$$"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/example-api-image.XXXXXX")
context="$tmp/context"
failures=0

cleanup() {
	docker rm -f "$id" >/dev/null 2>&1 || true
	docker image rm "$id" >/dev/null 2>&1 || true
	rm -rf "$tmp"
}
trap cleanup EXIT

pass() { echo "PASS: $1"; }
fail() {
	echo "FAIL: $1" >&2
	failures=$((failures + 1))
}

mkdir -p "$context/node_modules/host-marker"
(cd "$app" && tar -cf - --exclude node_modules .) | tar -xf - -C "$context"
echo "from the host" >"$context/node_modules/host-marker/marker.txt"
docker build -q -t "$id" "$context" >/dev/null

check="1. a node_modules folder in the build context does not reach the image"
if docker run --rm "$id" test -e node_modules/host-marker/marker.txt; then
	fail "$check (the image holds node_modules/host-marker/marker.txt)"
else
	pass "$check"
fi

# No request is sent on purpose. With a pending log batch, winston-loki's
# exit hook can exit 143 before the tracer finishes.
check="2. docker stop of an idle container exits 0 after the tracer shuts down"
docker run -d --name "$id" "$id" >/dev/null
listening=
for _ in $(seq 60); do
	if docker logs "$id" 2>&1 | grep -q listening; then listening=1 && break; fi
	sleep 1
done
if [ -z "$listening" ]; then
	fail "$check (the API did not log \"listening\")"
else
	docker stop "$id" >/dev/null
	code=$(docker inspect -f '{{.State.ExitCode}}' "$id")
	logs=$(docker logs "$id" 2>&1)
	if [ "$code" != 0 ]; then
		fail "$check (exit code $code)"
	elif ! grep -q "Tracing terminated" <<<"$logs"; then
		fail "$check (no \"Tracing terminated\" line in the logs)"
	else
		pass "$check"
	fi
fi

check="3. the image command is the start script from examples/api/package.json"
command=$(docker image inspect -f '{{join .Config.Cmd " "}}' "$id")
script=$(jq -r '.scripts.start' "$app/package.json")
if [ "$command" = "$script" ]; then
	pass "$check"
else
	fail "$check (image: \"$command\", start script: \"$script\")"
fi

if [ "$failures" -gt 0 ]; then
	echo "checks failed: $failures" >&2
	exit 1
fi
