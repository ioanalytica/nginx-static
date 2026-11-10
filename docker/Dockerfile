# syntax=docker/dockerfile:1
#
# NGINX for static websites behind an ingress controller, built from source.
#
# TLS ends at the ingress controller, so the pod speaks plain HTTP/1.1 and
# NGINX is built without TLS: no http_ssl, no HTTP/2, no HTTP/3, and so no
# OpenSSL in the image at all. Nothing that proxies or generates responses is
# compiled in either. What is left serves files: static, index, gzip,
# rewrite, headers, access, realip, map, charset, log.
#
# The binary is linked statically and is the only program in the image: no
# shell, no package manager, no libraries. A site's image is this image with
# the site's files and configuration copied in (COPY, there is nothing to
# RUN).

# The tag says which Alpine, the digest which build of it; Renovate moves
# both. The packages are installed afresh by every release build.
FROM alpine:3.24@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf AS build

# A failing command in a pipe fails the step.
SHELL ["/bin/ash", "-o", "pipefail", "-c"]

# The stable branch. Renovate moves it, together with appVersion in
# chart/Chart.yaml, which names the same version.
ARG NGINX_VERSION=1.30.6

# The build cache keeps this layer as long as the base image is unchanged,
# which would link an older build's zlib or PCRE2. The release workflow
# passes the tag here, so every release installs the packages afresh.
ARG APK_REFRESH
# hadolint ignore=DL3018
RUN apk add --no-cache build-base linux-headers pcre2-dev pcre2-static zlib-dev zlib-static gnupg curl

WORKDIR /src
# The source, checked against the signature of an NGINX developer: the keys
# in keys/ are the ones nginx.org lists (https://nginx.org/en/pgp_keys.html),
# checked in so that a build does not take the keys from where it takes the
# source.
COPY keys/ /keys/
RUN curl -fsSLO "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" \
 && curl -fsSLO "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz.asc" \
 && cat /keys/*.key | gpg --dearmor > /tmp/nginx-keys.gpg \
 && gpgv --keyring /tmp/nginx-keys.gpg "nginx-${NGINX_VERSION}.tar.gz.asc" "nginx-${NGINX_VERSION}.tar.gz" \
 && tar -xzf "nginx-${NGINX_VERSION}.tar.gz" --strip-components=1

# Every path NGINX writes to is under /tmp, so the root filesystem can be
# mounted read-only with a volume there. Modules that are on by default are
# switched off one by one; ./configure has no list to choose from.
RUN ./configure \
      --prefix=/etc/nginx \
      --sbin-path=/usr/sbin/nginx \
      --conf-path=/etc/nginx/nginx.conf \
      --error-log-path=/dev/stderr \
      --http-log-path=/dev/stdout \
      --pid-path=/tmp/nginx.pid \
      --lock-path=/tmp/nginx.lock \
      --http-client-body-temp-path=/tmp/client_body \
      --user=nginx --group=nginx \
      --with-http_realip_module \
      --with-http_gzip_static_module \
      --without-http_ssi_module \
      --without-http_userid_module \
      --without-http_auth_basic_module \
      --without-http_mirror_module \
      --without-http_autoindex_module \
      --without-http_geo_module \
      --without-http_split_clients_module \
      --without-http_referer_module \
      --without-http_proxy_module \
      --without-http_fastcgi_module \
      --without-http_uwsgi_module \
      --without-http_scgi_module \
      --without-http_grpc_module \
      --without-http_memcached_module \
      --without-http_limit_conn_module \
      --without-http_limit_req_module \
      --without-http_empty_gif_module \
      --without-http_browser_module \
      --without-http_upstream_hash_module \
      --without-http_upstream_ip_hash_module \
      --without-http_upstream_least_conn_module \
      --without-http_upstream_random_module \
      --without-http_upstream_keepalive_module \
      --without-http_upstream_zone_module \
      --with-cc-opt='-Os -static -fstack-protector-strong -D_FORTIFY_SOURCE=2' \
      --with-ld-opt='-static' \
 && make -j"$(nproc)" \
 && strip objs/nginx \
 # Fails the build if the binary is not what the header says: static, and
 # without TLS.
 && if ldd objs/nginx 2>/dev/null | grep -q '=>'; then echo "nginx is not statically linked" >&2; exit 1; fi \
 && if objs/nginx -V 2>&1 | grep -qiE 'ssl|http_v2|http_v3'; then echo "nginx is built with TLS or HTTP/2" >&2; exit 1; fi

# The files of the final image, laid out as its root.
WORKDIR /rootfs
RUN mkdir -p usr/sbin etc/nginx tmp var/www/html \
 && cp /src/objs/nginx usr/sbin/nginx \
 && cp /src/conf/mime.types etc/nginx/mime.types \
 && echo 'nginx:x:101:101:nginx:/nonexistent:/sbin/nologin' > etc/passwd \
 && echo 'nginx:x:101:' > etc/group \
 && chmod 1777 tmp
# What the binary is linked with, in the form a scanner reads. zlib, PCRE2
# and musl are inside the static binary, where no scanner finds them, so the
# image carries their entries of this stage's Alpine package database, and
# the release file that says which Alpine they are from. A scanner then
# reports a vulnerability in one of them for this image, and for every
# site's image built on it, as it would for an image with the packages
# installed. The entries name no files: there are none.
RUN mkdir -p lib/apk/db etc \
 && awk -v RS= -v ORS='\n\n' '/(^|\n)P:(musl|zlib-static|pcre2-static)(\n|$)/' /lib/apk/db/installed \
      | grep -E '^([PVALomUTc]:|$)' > lib/apk/db/installed \
 && [ "$(grep -c '^P:' lib/apk/db/installed)" = 3 ] \
 && cp /etc/alpine-release etc/alpine-release \
 && cp -L /etc/os-release etc/os-release
COPY rootfs/ /rootfs/
# The configuration is checked with the binary it is for: a directive of a
# module that is not compiled in fails the build, not the first start.
RUN chown -R 101:101 var/www/html \
 && cp -a /rootfs/etc/nginx /etc/nginx && mkdir -p /var/www && cp -a /rootfs/var/www/html /var/www/html \
 && cat /rootfs/etc/passwd >> /etc/passwd && cat /rootfs/etc/group >> /etc/group \
 && /rootfs/usr/sbin/nginx -t

FROM scratch

# Links the GHCR package to this repository.
LABEL org.opencontainers.image.source="https://github.com/ioanalytica/nginx-static"
LABEL org.opencontainers.image.title="nginx-static"
LABEL org.opencontainers.image.description="NGINX for static websites behind an ingress controller: built from source without TLS, one static binary, no shell"
LABEL org.opencontainers.image.licenses="Apache-2.0 AND BSD-2-Clause"

COPY --from=build /rootfs/ /

USER 101:101
EXPOSE 8080
# A graceful stop: NGINX finishes the requests it has.
STOPSIGNAL SIGQUIT
# Arguments are added to it: `docker run --rm IMAGE -t` checks the
# configuration of a site's image, with the binary it will run on.
ENTRYPOINT ["/usr/sbin/nginx", "-g", "daemon off;"]
