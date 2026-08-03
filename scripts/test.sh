#!/bin/sh
set -eu

base_url='http://localhost:8080'
tmp_dir="${TMPDIR:-/tmp}/winwin-test-$$"
mkdir "$tmp_dir"
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

# Verify all contract fields while allowing ENV_NAME to be customized.
body="$(curl --fail --silent --show-error "$base_url/healthz")"
printf '%s' "$body" | grep -Eq '^\{"status":"ok","service":"app","env":"[^"]+"\}$'
printf 'Healthcheck OK: %s\n' "$body"

# The app echoes the ID that nginx forwarded, making the full path observable.
request_id='reviewer-test-123'
headers="$(curl --fail --silent --show-error --dump-header - --output /dev/null \
  --header "X-Request-ID: $request_id" "$base_url/healthz")"
printf '%s\n' "$headers" | tr -d '\r' | grep -Fxiq "X-Request-ID: ${request_id}"
printf 'Request-ID pass-through OK: %s\n' "$request_id"

# Parallel requests reliably exceed the 10 r/s per-client nginx limit.
seq 1 20 | xargs -P 20 -I '{}' sh -c \
  'curl --silent --output /dev/null --write-out "%{http_code}\n" "$1/healthz"' _ "$base_url" \
  > "$tmp_dir/statuses"
sort "$tmp_dir/statuses" | uniq -c
grep -qx '429' "$tmp_dir/statuses"
printf 'Rate-limit OK: at least one request returned HTTP 429.\n'
