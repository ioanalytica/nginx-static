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

Fixes go into the next chart version; there are no backports to older ones.
Upgrade to the
[latest release](https://github.com/ioanalytica/nginx-static/releases/latest).

## Scope

This policy covers what this repository builds: the **Helm chart** in
`chart/`, and the workflows and scripts that release it.

Not covered here:

- The **image** a release runs. The chart ships none: it is the image of the
  site, built by whoever runs the site. A vulnerability in NGINX or in a
  package of the image's base belongs to its project, and reaches a site
  with a rebuild of the site's image.
- The **ingress controller** and **cert-manager**, which the chart renders
  resources for.

## What the chart does and does not do

- **TLS ends at the ingress controller.** The pod serves plain HTTP inside
  the cluster, and the chart renders no HTTPS port, neither on the container
  nor on the Service.
- **The chart sets no security context by default.** What a site's image
  tolerates is the image's business. The chart's README gives the settings
  that meet the `restricted` Pod Security Standard for an image that runs
  NGINX as a non-root user; the page "Try it locally" runs with them, in a
  namespace that enforces the standard.
- **Rules that deny paths belong in the image.** The chart injects no
  ingress annotations that block hidden files or script paths: such a rule
  holds for one ingress controller only, and in the image's NGINX
  configuration it holds for all of them.
- **No NetworkPolicy** is rendered. A site's pods accept connections from
  the whole cluster unless the namespace has a policy of its own.

## Verifying a release

A release signs the chart with Sigstore cosign;
[Verify a release](https://nginx-static.ioanalytica.com/security/verify) has
the command.
