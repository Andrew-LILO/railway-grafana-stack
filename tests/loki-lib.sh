# shellcheck shell=bash

root=$(cd "${1:-$(dirname "$0")/..}" && pwd)
id="$(basename "$0" .sh)-$$"
url=

cleanup() {
	docker rm -f "$id" >/dev/null 2>&1 || true
	docker volume rm "$id" >/dev/null 2>&1 || true
	docker image rm "$id" >/dev/null 2>&1 || true
}
trap cleanup EXIT

wait_for() {
	local what=$1
	shift
	for _ in $(seq 100); do
		if "$@"; then return 0; fi
		sleep 2
	done
	echo "FAIL: timed out waiting for $what" >&2
	exit 1
}

ready() { curl -fsS -o /dev/null "$url/ready" 2>/dev/null; }

start_loki() {
	docker run -d --name "$id" --user root -v "$id:/loki" -p 127.0.0.1::3100 "$id" \
		-config.file=/etc/loki/loki-config.yaml "$@" >/dev/null
	url="http://$(docker port "$id" 3100/tcp | head -n 1)"
	wait_for "Loki to be ready" ready
}

docker build -q -f "$root/loki/dockerfile" -t "$id" "$root" >/dev/null
docker volume create "$id" >/dev/null
