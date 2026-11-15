#!/usr/bin/env bash
# Usage: grafana-plugins.sh [repo root]. Needs docker with the compose plugin, curl, openssl,
# and network access to grafana.com, because Grafana downloads the plugins.
set -euo pipefail

root=$(cd "${1:-$(dirname "$0")/..}" && pwd)
project="grafana-plugins-$$"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/grafana-plugins.XXXXXX")
ports="$tmp/ports.yml"
failures=0
url=
log="$tmp/start.log"
password=$(openssl rand -hex 16)

# The first three use Angular.
old_default="grafana-simple-json-datasource,grafana-piechart-panel,grafana-worldmap-panel,grafana-clock-panel"

compose() {
	GF_SECURITY_ADMIN_PASSWORD=$password docker compose --project-directory "$root" \
		--env-file /dev/null -p "$project" -f "$root/docker-compose.yml" -f "$ports" "$@"
}

cleanup() {
	compose down -v --rmi local >/dev/null 2>&1 || true
	rm -rf "$tmp"
}
trap cleanup EXIT

pass() { echo "PASS: $1"; }
fail() {
	echo "FAIL: $1" >&2
	failures=$((failures + 1))
}

plugins_file() {
	local file
	file=$(mktemp "$tmp/plugins.XXXXXX")
	printf 'services:\n  grafana:\n    environment:\n      GF_INSTALL_PLUGINS: "%s"\n' "$1" >"$file"
	echo "$file"
}

container() { compose ps -q grafana 2>/dev/null; }

wait_loaded() {
	local id started
	id=$(container)
	if [ -z "$id" ]; then
		echo "no Grafana container" >&2
		return 1
	fi
	started=$(docker inspect -f '{{.State.StartedAt}}' "$id")
	url="http://$(compose port grafana 3000 2>/dev/null)"
	for _ in $(seq 150); do
		docker logs --since "$started" "$id" >"$log" 2>&1 || true
		if [ "$(docker inspect -f '{{.State.Running}}' "$id")" != true ]; then
			echo "Grafana exited; last log lines:" >&2
			tail -n 5 "$log" >&2
			return 1
		fi
		if grep -q 'logger=plugin.store .*msg="Plugins loaded"' "$log" &&
			curl -fsS -o /dev/null "$url/api/health" 2>/dev/null; then
			return 0
		fi
		sleep 2
	done
	echo "timed out waiting for Grafana to load its plugins" >&2
	return 1
}

start() {
	local out
	if ! out=$(compose "$@" up -d --build grafana 2>&1); then
		echo "docker compose up failed:" >&2
		tail -n 5 <<<"$out" >&2
		return 1
	fi
	wait_loaded
}

# The plugin IDs in a GF_INSTALL_PLUGINS value. An entry is "id", "id version",
# or "url;id".
plugin_ids() {
	tr ',' '\n' <<<"$1" | sed 's/^[[:space:]]*//; s/^.*;//; s/[[:space:]].*$//' | grep -v '^$' || true
}

registered() {
	printf 'user = "admin:%s"\n' "$password" |
		curl -sS -K - -o /dev/null -w '%{http_code}' "$url/api/plugins/$1/settings" || true
}

problems() {
	local errors id code
	errors=$(grep 'level=error' "$log" | grep -o 'msg="Plugin validation failed" pluginId=[^ ]*' |
		sed 's/.*pluginId=//' | sort -u | tr '\n' ' ' || true)
	[ -z "$errors" ] || echo "plugin validation failed for: ${errors% }"
	for id in $(plugin_ids "$1"); do
		code=$(registered "$id")
		[ "$code" = 200 ] || echo "$id is not registered (HTTP $code)"
	done
}

report() {
	local found
	found=$(problems "$2")
	if [ -n "$found" ]; then
		fail "$1 ($(tr '\n' ';' <<<"$found" | sed 's/;$//; s/;/; /g'))"
	else
		pass "$1"
	fi
}

running_value() { compose exec -T grafana printenv GF_INSTALL_PLUGINS </dev/null || true; }

cat >"$ports" <<'EOF'
services:
  grafana:
    ports: !override
      - "127.0.0.1::3000"
EOF

check="1. the GF_INSTALL_PLUGINS value in docker-compose.yml loads without a plugin validation error"
if start; then
	value=$(running_value)
	if [ -z "$value" ]; then
		fail "$check (the Grafana container has no GF_INSTALL_PLUGINS)"
	else
		report "$check" "$value"
	fi
else
	fail "$check (Grafana did not start)"
fi
compose down -v >/dev/null 2>&1 || true

check="2. the GF_INSTALL_PLUGINS default in README.md loads without a plugin validation error"
readme=$(sed -n 's/^| `GF_INSTALL_PLUGINS` |.*| `\([^`]*\)` |[[:space:]]*$/\1/p' "$root/README.md")
if [ -z "$readme" ]; then
	fail "$check (README.md has no GF_INSTALL_PLUGINS row with a default in backticks)"
elif start -f "$(plugins_file "$readme")"; then
	report "$check" "$readme"
else
	fail "$check (Grafana did not start)"
fi
compose down -v >/dev/null 2>&1 || true

check="3. the README removal commands move a Grafana container created with the old default to the new list"
remove=$(awk '
	/^```/ { if (inblock) { if (hit) { printf "%s", block; exit } inblock = 0; block = ""; hit = 0 } else inblock = 1; next }
	inblock { block = block $0 "\n"; if ($0 ~ /plugins remove/) hit = 1 }
' "$root/README.md")
if [ -z "$remove" ]; then
	fail "$check (README.md has no code block with a docker compose ... plugins remove command)"
elif grep -v '^docker compose ' <<<"$remove" | grep -q .; then
	fail "$check (the README block has a line that is not a docker compose command)"
elif ! start -f "$(plugins_file "$old_default")"; then
	fail "$check (Grafana did not start with the old default)"
elif ! grep -q 'msg="Plugin validation failed"' "$log"; then
	fail "$check (the fixture did not reproduce the Angular refusals)"
else
	before=$(docker inspect -f '{{.State.StartedAt}}' "$(container)")
	ran=ok
	while IFS= read -r line; do
		if ! eval "compose ${line#docker compose }" </dev/null >"$tmp/remove.out" 2>&1; then
			ran="'$line' failed: $(tail -n 1 "$tmp/remove.out")"
			break
		fi
	done <<<"$remove"
	if [ "$ran" != ok ]; then
		fail "$check ($ran)"
	elif [ "$(docker inspect -f '{{.State.StartedAt}}' "$(container)")" = "$before" ]; then
		fail "$check (the README commands do not restart Grafana)"
	elif ! wait_loaded; then
		fail "$check (Grafana did not start after the README commands)"
	else
		value=$(running_value)
		if [ -z "$value" ]; then
			fail "$check (the Grafana container has no GF_INSTALL_PLUGINS after the README commands)"
		else
			report "$check" "$value"
		fi
	fi
fi

if [ "$failures" -gt 0 ]; then
	echo "checks failed: $failures" >&2
	exit 1
fi
