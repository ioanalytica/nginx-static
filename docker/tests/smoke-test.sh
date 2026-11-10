#!/bin/bash
# Smoke test for the nginx-static image.
#
# Verifies what the chart and a site's image rely on: the container runs as
# a non-root user with a read-only root filesystem and no capabilities,
# listens for HTTP on port 8080 only, answers /healthz, serves files with
# gzip, never serves hidden files, and logs the client's address as the
# ingress controller reports it. It also checks what the image is made of:
# one static NGINX without TLS and nothing else, with the entries that tell
# a scanner which libraries the binary is linked with. A site's image, built
# on the image from tests/site/, has to serve the site's files and follow
# its configuration.
#
#   ./smoke-test.sh ghcr.io/ioanalytica/nginx-static:test

set -euo pipefail

IMAGE="${1:?usage: smoke-test.sh <image-ref>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
NAME="nginx-static-smoke-$$"
SITE_IMAGE="nginx-static-smoke-site:$$"
FAILURES=0

cleanup() {
    docker rm -f "$NAME" "$NAME-site" "$NAME-files" >/dev/null 2>&1 || true
    docker rmi -f "$SITE_IMAGE" >/dev/null 2>&1 || true
    rm -f "${TLS_CONF:-}"
}
trap cleanup EXIT

ok()   { echo "ok:   $1"; }
fail() { echo "FAIL: $1"; FAILURES=$((FAILURES + 1)); }

# The image has no shell and no curl, so requests come from outside, through
# a port published on the loopback address.
# start <container> <image>: run it as the chart's README recommends, and
# print the port it is published on.
start() {
    docker run -d --name "$1" --read-only --tmpfs /tmp:uid=101,gid=101,mode=1777 \
        --cap-drop ALL --security-opt no-new-privileges -p 127.0.0.1::8080 "$2" >/dev/null
    local port=""
    for _ in $(seq 1 50); do
        port="$(docker port "$1" 8080/tcp 2>/dev/null | sed -n 's/.*:\([0-9]*\)$/\1/p' | head -n 1)"
        if [ -n "$port" ] && curl -s -o /dev/null "http://127.0.0.1:$port/healthz"; then
            echo "$port"
            return 0
        fi
        sleep 0.2
    done
    echo "the container $1 did not answer" >&2
    docker logs "$1" >&2 || true
    return 1
}

# assert <description> <expected-status> <path> [expected-body-substring] [curl args...]
assert() {
    local desc="$1" want_status="$2" path="$3" want_body="${4:-}" status body
    shift 3; [ $# -eq 0 ] || shift
    body="$(mktemp)"
    status="$(curl -s -o "$body" -w '%{http_code}' "$@" "http://127.0.0.1:$PORT$path")"
    if [ "$status" != "$want_status" ]; then
        fail "$desc — expected HTTP $want_status, got $status ($path)"
    elif [ -n "$want_body" ] && ! grep -q -- "$want_body" "$body"; then
        fail "$desc — HTTP $status but body lacks '$want_body' ($path)"
    else
        ok "$desc ($path -> $status)"
    fi
    rm -f "$body"
}

# header <description> <"present"|"absent"> <header line pattern> <path> [curl args...]
header() {
    local desc="$1" mode="$2" pattern="$3" path="$4" headers; shift 4
    headers="$(curl -s -o /dev/null -D - "$@" "http://127.0.0.1:$PORT$path" | tr -d '\r')"
    if grep -qiE -- "$pattern" <<<"$headers"; then
        if [ "$mode" = present ]; then ok "$desc"; else fail "$desc — found a header matching '$pattern'"; fi
    else
        if [ "$mode" = absent ]; then ok "$desc"; else fail "$desc — no header matching '$pattern'"; fi
    fi
}

echo "=== What the image is made of"
version="$(docker run --rm "$IMAGE" -V 2>&1)"
if grep -q '^nginx version: nginx/' <<<"$version"; then ok "$(head -n 1 <<<"$version")"
else fail "nginx -V prints no version: $version"; fi
if grep -qiE 'ssl|http_v2|http_v3|openssl' <<<"$version"; then fail "NGINX is built with TLS or HTTP/2"
else ok "NGINX is built without TLS, HTTP/2 and HTTP/3"; fi
for module in proxy fastcgi uwsgi scgi grpc memcached ssi autoindex auth_basic; do
    if grep -q -- "--without-http_${module}_module" <<<"$version"; then ok "without the $module module"
    else fail "NGINX is built with the $module module"; fi
done
[ "$(docker inspect "$IMAGE" --format '{{.Config.User}}')" = "101:101" ] && ok "the image's user is 101:101" \
    || fail "the image's user is '$(docker inspect "$IMAGE" --format '{{.Config.User}}')', not 101:101"

# Every file of the image is one this list names: a file that a build left
# behind, or a second program, fails here.
docker create --name "$NAME-files" "$IMAGE" >/dev/null
files="$(docker export "$NAME-files" | tar -tf - | grep -v '/$' | sed 's|^\./||' \
    | grep -vxE '\.dockerenv|dev/console|etc/(hostname|hosts|resolv\.conf|mtab)|proc/.*|sys/.*' | sort)"
want="$(sort <<'LIST'
etc/alpine-release
etc/group
etc/nginx/conf.d/default.conf
etc/nginx/custom.d/00-gzip.conf
etc/nginx/custom.d/00-realip.conf
etc/nginx/custom.d/00-timeouts.conf
etc/nginx/custom.d/01-common.conf
etc/nginx/mime.types
etc/nginx/nginx.conf
etc/os-release
etc/passwd
lib/apk/db/installed
usr/sbin/nginx
usr/share/nginx-static/placeholder.html
LIST
)"
# The document root is there and empty, and it is the site's to fill. GNU
# tar prints the owner as 101/101, bsdtar in two columns.
if docker export "$NAME-files" | tar -tvf - | grep -E ' (\./)?var/www/html/$' | grep -qE '^drwxr-xr-x.* 101[ /]+101 '; then
    ok "the document root is an empty directory of user 101"
else
    fail "var/www/html is missing or not a directory of user 101"
fi
if [ "$files" = "$want" ]; then ok "the image holds NGINX, its configuration and nothing else ($(wc -l <<<"$files" | tr -d ' ') files)"
else
    fail "the image's files differ from the list:"
    diff <(echo "$want") <(echo "$files") | sed 's/^</      missing:/; s/^>/      not expected:/' | grep '^ ' || true
fi
# The entries that tell a scanner what the binary is linked with.
installed="$(docker cp "$NAME-files:/lib/apk/db/installed" - | tar -xOf -)"
packages="$(sed -n 's/^P://p' <<<"$installed" | sort | tr '\n' ' ')"
if [ "$packages" = "musl pcre2-static zlib-static " ] && [ "$(grep -c '^V:' <<<"$installed")" = 3 ] \
   && [ "$(grep -c '^o:' <<<"$installed")" = 3 ]; then
    ok "the package database names musl, PCRE2 and zlib, each with its version and origin"
else
    fail "lib/apk/db/installed names '$packages'"
fi
if docker cp "$NAME-files:/etc/alpine-release" - | tar -xOf - | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    ok "etc/alpine-release says which Alpine the libraries are from"
else fail "etc/alpine-release holds no version"; fi

echo "=== The container"
PORT="$(start "$NAME" "$IMAGE")"
if docker exec "$NAME" /bin/sh -c true >/dev/null 2>&1; then fail "the image has a shell"
else ok "there is no shell to exec"; fi
logs="$(docker logs "$NAME" 2>&1)"
if [ -z "$logs" ]; then ok "NGINX starts without a warning, on a read-only root filesystem and without capabilities"
else fail "NGINX logs at start: $logs"; fi
# One master and the two workers of nginx.conf, whatever the host has in CPUs.
top="$(docker top "$NAME" -eo pid,args)"
processes="$(grep -c ' nginx: ' <<<"$top" || true)"
workers="$(grep -c ' nginx: worker process' <<<"$top" || true)"
if [ "$processes" = 3 ] && [ "$workers" = 2 ]; then ok "NGINX runs a master and two workers"
else fail "NGINX runs $processes processes, $workers of them workers; expected a master and two workers"; fi
ports="$(docker inspect "$IMAGE" --format '{{range $p, $_ := .Config.ExposedPorts}}{{$p}} {{end}}')"
[ "$ports" = "8080/tcp " ] && ok "the image exposes port 8080 only" || fail "the image exposes '$ports'"

echo "=== Requests"
assert "the placeholder, while there is no site" 200 /            "nginx-static base image"
# The document root is empty: the placeholder has no address of its own that
# a site's image would inherit.
assert "the placeholder is no file of the site" 404 /index.html
assert "and its location is internal"          404 /nginx-static-placeholder
assert "the liveness probe's path"             200 /healthz     "OK"
assert "a file that is not there"              404 /nope
assert "a hidden file"                         403 /.env
assert "a hidden directory"                    403 /.git/config
assert "a method a static site has no use for is still answered" 405 / "" -X POST
header "the Server header names no version"    present '^Server: nginx$'                  /
header "X-Content-Type-Options"                present '^X-Content-Type-Options: nosniff$' /
header "the page is compressed when asked"     present '^Content-Encoding: gzip$'         / -H 'Accept-Encoding: gzip'
header "and not otherwise"                     absent  '^Content-Encoding:'               /
header "the page's charset"                    present '^Content-Type: text/html; charset=utf-8$' /
header "plain HTTP: no HSTS of the pod's own"  absent  '^Strict-Transport-Security:'      /

# The access log names the client the ingress controller reports, and the
# probe's path is not logged.
curl -s -o /dev/null -H 'X-Forwarded-For: 203.0.113.7' "http://127.0.0.1:$PORT/?realip"
curl -s -o /dev/null "http://127.0.0.1:$PORT/healthz"
sleep 0.3
logs="$(docker logs "$NAME" 2>&1)"
if grep -q '^203\.0\.113\.7 .*GET /?realip' <<<"$logs"; then ok "the access log names the client from X-Forwarded-For"
else fail "the access log does not name 203.0.113.7: $(grep realip <<<"$logs" || true)"; fi
if grep -q '/healthz' <<<"$logs"; then fail "the probe's requests are logged"
else ok "the probe's requests are not logged"; fi

if docker stop -t 10 "$NAME" >/dev/null && [ "$(docker inspect "$NAME" --format '{{.State.ExitCode}}')" = 0 ]; then
    ok "the container stops gracefully"
else
    fail "the container did not stop with status 0"
fi

echo "=== A site's image"
if docker build -q -t "$SITE_IMAGE" --build-arg BASE="$IMAGE" "$HERE/site" >/dev/null; then
    ok "a site's image builds with COPY alone"
else
    fail "the site's image does not build"
fi
if out="$(docker run --rm "$SITE_IMAGE" -t 2>&1)" && grep -q 'test is successful' <<<"$out"; then
    ok "IMAGE -t checks the site's configuration"
else
    fail "IMAGE -t: $out"
fi
PORT="$(start "$NAME-site" "$SITE_IMAGE")"
assert "the site's page takes the place of the placeholder" 200 /         "The site of the smoke test"
assert "the site's page under its own name"                 200 /index.html "The site of the smoke test"
assert "the placeholder is not part of the site"            404 /nginx-static-placeholder
assert "the site's stylesheet"                              200 /style.css "color"
assert "the site's own location"                            301 /old
assert "a path the site refuses"                            418 /index.php
assert "the base image's rules still hold"                  403 /.env
assert "and so does the probe's path"                       200 /healthz   "OK"
header "the stylesheet's type"                 present '^Content-Type: text/css'    /style.css
# gzip_static: the file compressed at build time is sent as it is.
if [ "$(curl -s -H 'Accept-Encoding: gzip' "http://127.0.0.1:$PORT/pre.css" | gunzip 2>/dev/null)" = "body{color:#222}" ]; then
    ok "a file compressed at build time is served in place of its original"
else
    fail "pre.css.gz is not served for pre.css"
fi
# A directive of a module the image leaves out fails the check, not the pod.
TLS_CONF="$(mktemp)"
echo 'ssl_protocols TLSv1.3;' >"$TLS_CONF"
chmod 644 "$TLS_CONF"
if out="$(docker run --rm -v "$TLS_CONF:/etc/nginx/custom.d/99-tls.conf:ro" "$SITE_IMAGE" -t 2>&1)"; then
    fail "a TLS directive passes the configuration check"
elif grep -q 'unknown directive "ssl_protocols"' <<<"$out"; then
    ok "a TLS directive is refused as unknown"
else
    fail "a TLS directive fails the check, but not as unknown: $out"
fi

echo
if [ "$FAILURES" -gt 0 ]; then
    echo "=== $FAILURES check(s) FAILED"
    exit 1
fi
echo "=== All checks passed"
