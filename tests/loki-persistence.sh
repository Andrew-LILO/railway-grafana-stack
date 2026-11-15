#!/usr/bin/env bash
# Usage: loki-persistence.sh [repo root]. Needs docker and curl.
set -euo pipefail

root=$(cd "${1:-$(dirname "$0")/..}" && pwd)
id="loki-persistence-$$"
line="synthetic line $id"
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
	for _ in $(seq 60); do
		if "$@"; then return 0; fi
		sleep 2
	done
	echo "FAIL: timed out waiting for $what" >&2
	exit 1
}

metric() {
	curl -fsS "$url/metrics" | awk -v name="$1" '
		{ n = $1; sub(/\{.*/, "", n) }
		n == name { sum += $NF; found = 1 }
		END { if (!found) exit 1; printf "%d\n", sum }'
}

must_metric() {
	metric "$1" || { echo "FAIL: could not read $1" >&2; exit 1; }
}

ready() { curl -fsS -o /dev/null "$url/ready" 2>/dev/null; }
stream_evicted() { local n; n=$(metric loki_ingester_memory_streams) && [ "$n" -eq 0 ]; }
checkpoints_reach() { local n; n=$(metric loki_ingester_checkpoint_creations_total) && [ "$n" -ge "$1" ]; }

start_loki() {
	docker run -d --name "$id" --user root -v "$id:/loki" -p 127.0.0.1::3100 "$id" \
		-config.file=/etc/loki/loki-config.yaml "$@" >/dev/null
	url="http://$(docker port "$id" 3100/tcp | head -n 1)"
	wait_for "Loki to be ready" ready
}

docker build -q -f "$root/loki/dockerfile" -t "$id" "$root" >/dev/null
docker volume create "$id" >/dev/null

# The WAL is on the volume and replays a flushed line until a checkpoint drops it.
# A 1s checkpoint interval stands in for the default 5m so the test stays short.
start_loki -ingester.checkpoint-duration=1s
echo "Loki $(curl -fsS "$url/loki/api/v1/status/buildinfo" | sed 's/.*"version":"\([^"]*\)".*/\1/')"

curl -fsS -o /dev/null -H 'Content-Type: application/json' "$url/loki/api/v1/push" \
	-d "{\"streams\":[{\"stream\":{\"job\":\"$id\"},\"values\":[[\"$(date +%s)000000000\",\"$line\"]]}]}"
curl -fsS -o /dev/null -X POST "$url/flush"
wait_for "the ingester to evict the flushed stream" stream_evicted
checkpoints=$(must_metric loki_ingester_checkpoint_creations_total)
wait_for "the WAL to checkpoint past the flushed line" checkpoints_reach "$((checkpoints + 2))"

echo "Files Loki wrote outside the volume:"
docker diff "$id" | sed 's/^/  /'

docker rm -f "$id" >/dev/null
start_loki

recovered=$(must_metric loki_ingester_wal_recovered_streams_total)
if [ "$recovered" -ne 0 ]; then
	echo "FAIL: the WAL replayed $recovered stream(s), so this run proves nothing about the object store" >&2
	exit 1
fi

if curl -fsS -G "$url/loki/api/v1/query_range" --data-urlencode "query={job=\"$id\"}" | grep -qF "$line"; then
	echo "PASS: the line pushed before the replacement is still queryable"
else
	echo "FAIL: the line pushed before the replacement is gone" >&2
	exit 1
fi
