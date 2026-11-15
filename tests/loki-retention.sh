#!/usr/bin/env bash
# Usage: loki-retention.sh [repo root]. Needs docker and curl.
set -euo pipefail

# shellcheck source=loki-lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/loki-lib.sh"

# By default the compactor applies retention about every 15m and deletes a chunk 2h after marking it.
# The two compactor flags shorten both so the test stays short.
flags=(-validation.reject-old-samples=false -compactor.compaction-interval=5s -compactor.retention-delete-delay=1s)

chunks() { docker exec "$id" /busybox/find /loki/chunks/fake -type f 2>/dev/null | sort; }
chunk_count_is() { [ "$(chunks | wc -l)" -eq "$1" ]; }
gone() { docker exec "$id" /busybox/test ! -e "$1"; }

push() {
	curl -fsS -o /dev/null -H 'Content-Type: application/json' "$url/loki/api/v1/push" \
		-d "{\"streams\":[{\"stream\":{\"job\":\"$id-$1\"},\"values\":[[\"${2}000000000\",\"$1 line\"]]}]}"
	curl -fsS -o /dev/null -X POST "$url/flush"
}

start_loki "${flags[@]}"

push expired $(($(date +%s) - 45 * 86400))
wait_for "the expired chunk to reach the volume" chunk_count_is 1
expired=$(chunks)
push fresh "$(date +%s)"
wait_for "the fresh chunk to reach the volume" chunk_count_is 2
fresh=$(chunks | grep -vxF "$expired")

# The compactor reads the index from the object store. A restart ships the index there.
docker rm -f "$id" >/dev/null
start_loki "${flags[@]}"

if ! (wait_for "the compactor to delete the 45-day-old chunk" gone "$expired"); then
	echo "Chunks still on the volume:"
	chunks | sed 's/^/  /'
	exit 1
fi
if ! docker exec "$id" /busybox/test -e "$fresh"; then
	echo "FAIL: could not confirm that the fresh chunk is still on the volume" >&2
	exit 1
fi

# Retention turns the deletion API on, and this Loki has no authentication.
status=$(curl -sS -o /dev/null -w '%{http_code}' -X POST -G "$url/loki/api/v1/delete" \
	--data-urlencode 'query={job="any"}' --data-urlencode "start=$(($(date +%s) - 3600))") || true
if [ "$status" != 403 ]; then
	echo "FAIL: the deletion API answered $status, expected 403" >&2
	exit 1
fi
echo "PASS: the compactor deleted the 45-day-old chunk and kept the fresh one, and the deletion API is off"
