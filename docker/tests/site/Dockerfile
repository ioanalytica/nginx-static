# A site's image as the chart's README describes it, for smoke-test.sh: the
# base image with the site's files and one file of configuration copied in.
ARG BASE
# hadolint ignore=DL3006
FROM ${BASE}
COPY --chown=101:101 public/ /var/www/html/
COPY custom.d/ /etc/nginx/custom.d/
