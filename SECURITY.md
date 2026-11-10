# Security policy

## Reporting a vulnerability

Report it privately through GitHub:
[**Report a vulnerability**](https://github.com/ioanalytica/nginx-static/security/advisories/new)
(the Security tab of this repository). Please do not open a public issue or
pull request for a vulnerability that is not public yet.

A useful report names the chart version, the values it needs and what an
attacker gains. We confirm the report, keep you informed while we work on it,
and credit you in the advisory unless you prefer otherwise.

## Supported versions

Fixes go into the next version; there are no backports to older ones. The
chart version is also the tag of the base image, so the
[latest release](https://github.com/ioanalytica/nginx-static/releases/latest)
has both.

A fix in the base image reaches a site once the site's image is built again
on the new tag: the base image is a part of the site's image, not something
the chart swaps underneath it.

## Scope

This policy covers what this repository builds:

- the **Helm chart** in `chart/`;
- the **`nginx-static` base image** in `docker/`: how NGINX is built, the
  configuration the image ships, and the workflows that build, sign and
  release it.

Not covered here:

- A vulnerability in **NGINX** itself, or in zlib, PCRE2 or musl, belongs to
  its project. One that is already public is no secret: a normal issue that
  asks for a new build is fine.
- The **image of a site**: its files and its own NGINX configuration belong
  to whoever builds it.
- The **ingress controller** and **cert-manager**, which the chart renders
  resources for.

## What the image is, and is not

- **No TLS, by design.** TLS ends at the ingress controller. The image's
  NGINX is built without TLS, HTTP/2 and HTTP/3, contains no OpenSSL, and
  listens for plain HTTP on port 8080 only. The chart renders no HTTPS port,
  neither on the container nor on the Service.
- **Nothing but NGINX.** The image is one static binary and its
  configuration: no shell, no package manager, no libraries. NGINX is built
  without the modules that proxy or generate responses.
- **Non-root, read-only.** The image runs as user 101 and writes only below
  `/tmp`.
- **The chart sets no security context by default**, since a release may run
  another image. The chart's README gives the settings the base image is
  made for: the `restricted` Pod Security Standard and a read-only root
  filesystem. The page "Try it locally" runs with them, in a namespace that
  enforces the standard.
- **Rules that deny paths belong in the image.** The chart injects no
  ingress annotations that block hidden files or script paths: such a rule
  holds for one ingress controller only, and in the image's NGINX
  configuration it holds for all of them. The base image refuses hidden
  files.
- **No NetworkPolicy** is rendered. A site's pods accept connections from
  the whole cluster unless the namespace has a policy of its own.

## What the daily scan covers

Once a day a workflow scans the base image as last released with
[Trivy](https://trivy.dev/) for known vulnerabilities of severity high and
critical. All findings go to the repository's code scanning. The run fails
when a finding has a fixed version: the signal for a new release, which
builds the image with the packages of that day. A finding that a new build
cannot fix yet is listed, with its reason and an expiry date, in
[`.github/cve-scan-accepted.yaml`](.github/cve-scan-accepted.yaml) and fails
the run again once that date has passed.

The image has no packages installed, and the libraries NGINX is linked with
are inside its binary, where a scanner does not find them. So the image
carries the entries of the Alpine package database for exactly those
libraries, **zlib**, **PCRE2** and **musl**, at the versions the binary was
built with. A scanner reports a vulnerability in one of them for the base
image, and for every site's image built on it, as it would for an installed
package. The entries name no files, because there are none.

The scan does not see **NGINX** itself: it is built from source and is no
package. A green scan therefore says that the three libraries have no known
high or critical vulnerability with a fixed version; it says nothing about
NGINX. NGINX's releases are followed by Renovate, which opens the pull
request for a new one; the source of each build is checked against the
signature of an NGINX developer. The image stays on NGINX's stable branch; a
new branch is a deliberate move by the maintainers.

## Verifying a release

A release signs the base image and the chart with Sigstore cosign;
[Verify a release](https://nginx-static.ioanalytica.com/security/verify) has
the commands.
