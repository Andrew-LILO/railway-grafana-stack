#!/usr/bin/env bash
# Usage: compose-build.sh [repo root]. Needs docker with the compose plugin.
set -euo pipefail

root=${1:-"$(cd "$(dirname "$0")/.." && pwd)"}
project="compose-build-$$"
# A build needs neither the Grafana admin password nor a local .env file, so
# give Compose a placeholder and keep it from reading .env.
compose=(env GF_SECURITY_ADMIN_PASSWORD=unused docker compose --env-file /dev/null -p "$project" -f "$root/docker-compose.yml")

services=$("${compose[@]}" config --services)

cleanup() {
	local out
	out=$("${compose[@]}" down --rmi all 2>&1) && return
	echo "$out" >&2
	echo "FAIL: could not remove the images of Compose project $project" >&2
	return 1
}
trap cleanup EXIT

# One build per service, because a combined build stops at the first error
# and hides the rest.
failed=()
for service in $services; do
	echo "== $service"
	"${compose[@]}" --progress plain build "$service" || failed+=("$service")
done

if [ "${#failed[@]}" -ne 0 ]; then
	echo "FAIL: docker compose build failed for: ${failed[*]} (errors above)" >&2
	exit 1
fi

trap - EXIT
cleanup
echo "PASS: every service in docker-compose.yml builds"
