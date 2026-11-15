#!/usr/bin/env bash
# Usage: grafana-admin-password.sh [repo root]. Needs docker, curl, openssl, and git.
set -euo pipefail

root=$(cd "${1:-$(dirname "$0")/..}" && pwd)
project="grafana-admin-password-$$"
tmp=$(mktemp -d -t grafana-admin-password)
override="$tmp/override.yml"
failures=0
url=

pw1=$(openssl rand -hex 16)
pw2=$(openssl rand -hex 16)

compose_as() (
	if [ "$1" = unset ]; then unset GF_SECURITY_ADMIN_PASSWORD; else export GF_SECURITY_ADMIN_PASSWORD=$1; fi
	shift
	docker compose --project-directory "$root" --env-file /dev/null \
		-p "$project" -f "$root/docker-compose.yml" "$@"
)

cleanup() {
	compose_as "$pw1" -f "$override" down -v --rmi local >/dev/null 2>&1 || true
	rm -rf "$tmp"
}
trap cleanup EXIT

pass() { echo "PASS: $1"; }
fail() {
	echo "FAIL: $1" >&2
	failures=$((failures + 1))
}

# curl reads the credentials from stdin, so they stay off the command line.
status() {
	printf 'user = "admin:%s"\n' "$1" |
		curl -sS -K - -o /dev/null -w '%{http_code}' "$url/api/user" || true
}

start_grafana() {
	compose_as "$1" -f "$override" up -d --build grafana >/dev/null 2>&1 || return 1
	url="http://$(compose_as "$1" -f "$override" port grafana 3000)"
	for _ in $(seq 120); do
		if curl -fsS -o /dev/null "$url/api/health" 2>/dev/null; then return 0; fi
		sleep 2
	done
	echo "timed out waiting for Grafana" >&2
	return 1
}

expect() {
	local good bad
	good=$(status "$2")
	bad=$(status "$3")
	if [ "$good" = 200 ] && [ "$bad" = 401 ]; then
		pass "$1"
	else
		fail "$1 (accepted password: HTTP $good, rejected password: HTTP $bad)"
	fi
}

cat >"$override" <<EOF
services:
  grafana:
    build:
      context: $root
      dockerfile: grafana/dockerfile
    ports: !override
      - "127.0.0.1::3000"
    environment:
      GF_INSTALL_PLUGINS: ""
EOF

check="1. docker compose config, ps, and down refuse an unset GF_SECURITY_ADMIN_PASSWORD"
accepted=
for command in config ps down; do
	if compose_as unset "$command" >/dev/null 2>&1; then accepted="$accepted $command"; fi
done
if [ -n "$accepted" ]; then
	fail "$check (exit 0:$accepted)"
elif ! grep -q GF_SECURITY_ADMIN_PASSWORD <<<"$(compose_as unset config 2>&1)"; then
	fail "$check (the config error does not name the variable)"
else
	pass "$check"
fi

check="2. docker compose config refuses an empty GF_SECURITY_ADMIN_PASSWORD"
if compose_as "" config >/dev/null 2>&1; then
	fail "$check (exit 0)"
else
	pass "$check"
fi

check="3. a fresh volume takes the admin password from GF_SECURITY_ADMIN_PASSWORD"
if start_grafana "$pw1"; then
	expect "$check" "$pw1" "$pw2"
else
	fail "$check (Grafana did not start)"
fi

check="4a. an existing volume keeps its admin password when GF_SECURITY_ADMIN_PASSWORD changes"
if start_grafana "$pw2"; then
	expect "$check" "$pw1" "$pw2"
else
	fail "$check (Grafana did not start)"
fi

check="4b. the README rotation command sets the admin password from GF_SECURITY_ADMIN_PASSWORD"
rotate=$(sed -n 's/^[[:space:]]*docker compose \(exec grafana .*reset-admin-password.*\)$/\1/p' "$root/README.md")
if [ -z "$rotate" ]; then
	fail "$check (README.md has no docker compose exec grafana ... reset-admin-password line)"
elif ! eval "compose_as \"\$pw2\" -f \"\$override\" $rotate" >/dev/null 2>&1; then
	fail "$check (the command failed)"
else
	expect "$check" "$pw2" "$pw1"
fi

check="5. git ignores .env"
if git -C "$root" check-ignore -q .env; then
	pass "$check"
else
	fail "$check"
fi

if [ "$failures" -gt 0 ]; then
	echo "checks failed: $failures" >&2
	exit 1
fi
