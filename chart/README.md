# nginx-static Helm Chart

<!-- #region intro -->

A Helm chart that serves a static website from an NGINX image on Kubernetes: one release per site, with autoscaling, an Ingress for ingress-nginx or Traefik, and a permanent redirect from any number of alias hosts. It comes with a base image for a site's image to build on: NGINX built from source without TLS, one static binary of 2 MB. Developed by [IO ANALYTICA](https://ioanalytica.com).

<!-- #endregion intro -->

## Features

<!-- #region features -->

- **One release per site**: the chart runs the image a release names
- **A base image made for the job**: NGINX built from source without TLS and without anything that proxies, one static binary in an image with no shell, no package manager and no OpenSSL; it runs as a non-root user on a read-only root filesystem
- **Horizontal Pod Autoscaling** on CPU and memory, with extra metrics and a scaling behavior set from the values
- **PodDisruptionBudget** that keeps the site up through node drains
- **Ingress for three classes**: ingress-nginx, Traefik, and Traefik's ingress-nginx compatibility provider for the move from one to the other
- **Redirect of alias hosts** to the site's URL, with one certificate for all of them; on Traefik it keeps the request path
- **Resource presets** (nano through 2xlarge) for quick sizing
- **Values schema**: Helm checks the values of every install and upgrade, and refuses a misspelled host entry or an unknown ingress class before anything is deployed
- **Signed releases**: the chart and the base image are signed with Sigstore cosign, keyless; the image carries an SBOM and provenance

<!-- #endregion features -->

## Prerequisites

<!-- #region prerequisites -->

- Kubernetes 1.23+
- Helm 3.8+ (OCI registry support)
- An ingress controller: [ingress-nginx](https://kubernetes.github.io/ingress-nginx/) or [Traefik](https://traefik.io/traefik) 3; for the redirect on Traefik, its `traefik.io/v1alpha1` resource kinds (`IngressRoute`, `Middleware`)
- Optional: [cert-manager](https://cert-manager.io/) for the certificates, and a metrics server for autoscaling
- An image that serves the site: one built on the project's base image, or any other that meets [what the chart expects](#the-image)

<!-- #endregion prerequisites -->

## Quick Start

<!-- #region install -->

The chart is published to an OCI registry. Helm installs from it directly; there is no `helm repo add` step:

```bash
helm install my-site oci://ghcr.io/ioanalytica/charts/nginx-static \
  --namespace websites --create-namespace \
  --set image.registry=registry.example.com \
  --set image.repository=sites/my-site \
  --set image.tag=1.0.0 \
  --set ingress.className=traefik \
  --set 'ingress.hosts[0].host=www.example.com'
```

Three things are set for every release:

| Value | Why |
|---|---|
| `image.registry`, `image.repository`, `image.tag` | the image of the site; the defaults name the base image, which serves a placeholder page |
| `ingress.className` | `nginx`, `nginx-traefik` or `traefik`; the chart refuses to render without it, see [Ingress](#ingress) |
| `ingress.hosts` | the hostnames of the site |

A release usually keeps them in a values file:

```yaml
image:
  registry: registry.example.com
  repository: sites/my-site
  tag: "1.0.0"

ingress:
  className: traefik
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: www.example.com
  tls:
    - hosts: [www.example.com]
      secretName: www-example-com-tls
```

```bash
helm install my-site oci://ghcr.io/ioanalytica/charts/nginx-static \
  --namespace websites --create-namespace -f my-site.yaml
```

Without `--version`, Helm installs the latest release. The [`examples/`](https://github.com/ioanalytica/nginx-static/tree/main/examples) directory has the values of three real sites, and [Try it locally](https://github.com/ioanalytica/nginx-static/blob/main/examples/k3d/README.md) runs the chart in a throwaway k3d cluster.

<!-- #endregion install -->

## The image

<!-- #region image -->

A release names the image of the site it serves. The chart expects three things of it:

| The image | Value that changes it |
|---|---|
| listens for HTTP on port **8080** | `containerPort` |
| answers `GET /healthz` with a 2xx or 3xx status, for the liveness probe | `probes.liveness` |
| runs as a non-root user, so that it can run under a restrictive [security context](#security-context) | |

TLS ends at the ingress controller: the pod serves plain HTTP inside the cluster, and the chart renders no HTTPS port.

### The base image

The project's base image, `ghcr.io/ioanalytica/nginx-static`, meets all three, and is what the chart runs by default. It is NGINX's stable release, built from source for exactly this place behind an ingress controller:

- **No TLS.** NGINX is built without `http_ssl`, HTTP/2 and HTTP/3, so the image contains no OpenSSL at all.
- **Nothing that proxies or generates.** No proxy, FastCGI, uwsgi, SCGI, gRPC or memcached module, no SSI, no directory listings, no basic authentication. What is compiled in serves files: static, index, gzip and gzip_static, rewrite, headers, access, realip, map, charset.
- **One static binary.** The image is `FROM scratch`: NGINX, its configuration, and nothing else. No shell, no package manager, no libraries. It is about 2 MB, for `linux/amd64` and `linux/arm64`.
- **Non-root, read-only.** It runs as user 101 and writes only below `/tmp`, so the root filesystem can be read-only, see [Security context](#security-context).
- **Two workers.** NGINX runs two worker processes, whatever the node has in CPUs, so a pod's memory does not grow with the size of the node. More load is met by more pods.
- **Verified source.** A build checks the NGINX source against the signature of an NGINX developer.

The image's tag is the chart version; the chart's `appVersion` names the NGINX in it.

### A site's image

A site's image is the base image with the site's files copied in:

```dockerfile
FROM ghcr.io/ioanalytica/nginx-static:<version>
COPY --chown=101:101 public/ /var/www/html/
COPY custom.d/ /etc/nginx/custom.d/
```

There is nothing to `RUN`: the image has no shell. A step that prepares the files, such as a build of the site or a hash in asset URLs, belongs in an earlier stage of the Dockerfile, on any image that has the tools, from which the final stage copies the result.

The base image's one server block listens on port 8080 and includes every file in `/etc/nginx/custom.d/`. It ships these, and a site adds its own next to them:

| File | What it sets |
|---|---|
| `00-gzip.conf` | gzip for text, fonts and the like |
| `00-realip.conf` | the client's address from `X-Forwarded-For`, for requests from the cluster's private address ranges |
| `00-timeouts.conf` | send and body timeouts |
| `01-common.conf` | the document root `/var/www/html`, the access log, `X-Content-Type-Options` and `Referrer-Policy`, `/healthz`, and a 403 for hidden files |

A file of the site with one of these names replaces it. A site that replaces `01-common.conf` defines `/healthz` itself.

The document root is empty in the base image. While the site has no start page (`index.html`, or what the site's own `index` directive names), `/` answers with the base image's placeholder page, which is kept outside the document root and has no address of its own. `01-common.conf` does this in a `location = /`: a site that needs its own `location = /`, such as a redirect to a language's start page, replaces `01-common.conf`.

A site's own rules go into a file such as `02-site.conf`:

```nginx
# Files compressed at build time (style.css.gz next to style.css) are sent as they are.
gzip_static on;

location = /old-page {
    return 301 /new-page;
}

# This is not a PHP site: whoever asks for one is a scanner.
location ~ \.php$ {
    return 404;
}
```

Rules that protect the site belong here, in the image's NGINX configuration, and not in annotations of the Ingress: in the image they hold whichever ingress controller is in front. The chart injects no such annotations.

A directive of a module the image leaves out (`ssl_certificate`, `proxy_pass`, `http2`, `autoindex`) is an unknown directive to it. Check a site's image before it is deployed, with the binary it will run on:

```bash
docker run --rm registry.example.com/sites/my-site:1.0.0 -t
```

### Another image

Any image that meets the three expectations works, for example one built on `nginxinc/nginx-unprivileged`. The settings for the base image under [Security context](#security-context) may then need adapting: a stock NGINX image writes to more places than `/tmp`.

### Tag, digest and pull policy

`image.tag` is set for a site's image. Left empty, it means the chart's version, which is the tag of the base image released with the chart. `image.digest` takes the place of the tag when set, and pins the release to one build of the image.

The default pull policy is `Always`, so that a tag that was pushed again reaches the pods at their next start. With a tag per build, `IfNotPresent` saves the registry round trip.

<!-- #endregion image -->

## Configuration

Every value is described where it is defined, in [`values.yaml`](https://github.com/ioanalytica/nginx-static/blob/main/chart/values.yaml), and [`values.schema.json`](https://github.com/ioanalytica/nginx-static/blob/main/chart/values.schema.json) lists them with their types and defaults. The sections below cover what needs more than a line.

### Resources and probes

<!-- #region resources -->

The defaults fit a small static site: a request of 50m CPU and 64Mi memory, a limit of 250m and 128Mi. Set `resources` for other numbers, or pick a preset:

```yaml
resourcesPreset: small    # nano, micro, small, medium, large, xlarge, 2xlarge
```

A preset wins over `resources`. Autoscaling on CPU measures utilization against the request, so a request far above what a pod uses keeps the autoscaler from ever scaling up.

Each of the three probes has a switch, and every other key under it goes into the container's probe as it is. So any field of a Kubernetes probe can be set:

```yaml
probes:
  liveness:
    httpGet:
      path: /health        # the image answers here instead of /healthz
    failureThreshold: 5
  startup:
    enabled: true
    httpGet:
      path: /healthz
      port: http
    periodSeconds: 2
    failureThreshold: 30
```

A probe has one handler: `httpGet`, `tcpSocket`, `exec` or `grpc`. Helm merges a release's values into the chart's defaults, so a probe given another kind of handler would keep the default one beside it. Set the default handler to `null` to take it out; the chart refuses to render a probe with two, and one that is enabled without any, as the startup probe is until it is given a handler:

```yaml
probes:
  readiness:
    tcpSocket: null        # the default handler of the readiness probe
    httpGet:
      path: /healthz
      port: http
  liveness:
    httpGet: null          # the default handler of the liveness probe
    exec:
      command: [/usr/local/bin/healthcheck]
```

The readiness probe is a TCP check on the container port by default: NGINX accepts connections once its configuration is loaded, and a static site has nothing else to wait for.

<!-- #endregion resources -->

### Autoscaling

<!-- #region autoscaling -->

Autoscaling is on by default, between 2 and 5 replicas at 70 % CPU utilization:

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 0    # 0 leaves the metric out
```

It needs a metrics server in the cluster. `autoscaling.metrics` takes further metrics in the form of the HorizontalPodAutoscaler's `spec.metrics`, and `autoscaling.behavior` is its `spec.behavior`. The default behavior scales up fast and down slowly: a traffic peak doubles the pods within 30 seconds, and after it one pod a minute goes away once the load has been low for five minutes.

With `autoscaling.enabled: false` the Deployment runs `replicaCount` pods.

The PodDisruptionBudget keeps one pod available through voluntary disruptions such as a node drain (`pdb.minAvailable: 1`). With a single replica that blocks the drain of the node the pod runs on; set `pdb.enabled: false` for a site that runs one pod.

<!-- #endregion autoscaling -->

### Ingress

<!-- #region ingress -->

`ingress.className` selects the ingress controller and, with it, the form of the redirect. It has no default and is required while the Ingress or the redirect is enabled: in a cluster with more than one controller a default would pick one silently.

| Class | Who serves the site | Redirect is rendered as | Redirect keeps the path |
|---|---|---|---|
| `nginx` | ingress-nginx | a second `Ingress` with the annotation `nginx.ingress.kubernetes.io/permanent-redirect` | no |
| `nginx-traefik` | Traefik's ingress-nginx compatibility provider (`kubernetesIngressNGINX`), which reads `nginx.ingress.kubernetes.io/*` annotations | a `Middleware` and an `IngressRoute`, plus a `Certificate` when an issuer is named | yes |
| `traefik` | Traefik's `kubernetesIngress` provider | the same as `nginx-traefik` | yes |

The site itself is a plain `Ingress` for all three classes, so cert-manager issues its certificate from the usual annotation:

```yaml
ingress:
  className: traefik
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: www.example.com
  tls:
    - hosts: [www.example.com]
      secretName: www-example-com-tls
```

A host without `paths` serves `/`. A path without a `pathType` takes `ingress.pathType`.

Annotations come from two values: `ingress.commonAnnotations` reach the site's Ingress and every resource of the redirect, `ingress.annotations` the site's Ingress alone, where they win over a common annotation of the same name.

With the class `traefik`, annotations that start with `nginx.ingress.kubernetes.io/` are left out of the site's Ingress: Traefik's own provider does not read them, and an Ingress that carries them looks as if they were in effect. With `nginx-traefik` they stay, since that provider translates most of them. That makes `nginx-traefik` the class for the move from ingress-nginx to Traefik: the same values, served by the other controller.

`ingress.enabled: false` renders no Ingress for the site; the Service is then the way in.

<!-- #endregion ingress -->

### Redirect

<!-- #region redirect -->

A site usually answers on one hostname and has others that should lead there: `example.com` next to `www.example.com`, other top-level domains, former names. The redirect sends every host in `redirect.hosts` to `redirect.targetUrl` with a permanent redirect:

```yaml
redirect:
  enabled: true
  targetUrl: https://www.example.com      # no trailing slash
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - example.com
    - example.net
    - www.example.net
  tls:
    - hosts: [example.com, example.net, www.example.net]
      secretName: example-aliases-tls
```

All hosts share one TLS entry, so cert-manager issues one certificate for the whole list.

What a request to `https://example.net/docs/page?x=1` gets depends on the class:

| Class | Answer |
|---|---|
| `nginx` | `301` to `https://www.example.com`: the annotation of ingress-nginx redirects to the target URL as it is, without the path |
| `nginx-traefik`, `traefik` | `301` to `https://www.example.com/docs/page?x=1`; for a method other than `GET`, Traefik answers `308`, which keeps the method |

**With `nginx`**, the redirect is a second Ingress. `redirect.annotations` are its annotations, on top of `ingress.commonAnnotations`, so cert-manager issues the certificate from the annotation above, as for the site.

**With `nginx-traefik` and `traefik`**, the redirect is a Traefik `Middleware` (a `redirectRegex` that captures the path) and an `IngressRoute` that matches all the hosts:

- The IngressRoute listens on the entry point `websecure` and has the class `traefik`, whichever of the two classes the site's Ingress has.
- It reads the certificate from the Secret of the first entry of `redirect.tls`.
- cert-manager does not watch IngressRoutes. So when `redirect.annotations` has `cert-manager.io/cluster-issuer` and `redirect.tls` has an entry, the chart renders a `Certificate` for that Secret, with every host of `redirect.hosts`. A namespaced `Issuer` (`cert-manager.io/issuer`) is not read: create the Certificate yourself and name its Secret in `redirect.tls`.
- Without the annotation the chart renders no Certificate, and the Secret has to exist already.

The redirect needs `ingress.className` even while `ingress.enabled` is false, and fails to render without `redirect.targetUrl` or with an empty `redirect.hosts`.

<!-- #endregion redirect -->

### Security context

<!-- #region security-context -->

`podSecurityContext` and `containerSecurityContext` are empty by default: what a site's image tolerates is the image's business, and a setting it does not tolerate keeps the pods from starting.

The base image, and a site's image built on it, is made for the strictest settings. These pass the `restricted` [Pod Security Standard](https://kubernetes.io/docs/concepts/security/pod-security-standards/) and mount the root filesystem read-only:

```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 101
  runAsGroup: 101
  seccompProfile:
    type: RuntimeDefault

containerSecurityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: [ALL]

# The one place NGINX writes to: its pid file and its temporary files.
extraVolumes:
  - name: tmp
    emptyDir: {}
extraVolumeMounts:
  - name: tmp
    mountPath: /tmp
```

[Try it locally](https://github.com/ioanalytica/nginx-static/blob/main/examples/k3d/README.md) runs with exactly these settings, in a namespace that enforces the standard.

For another image, leave `readOnlyRootFilesystem` and the volume out unless the image is known to write nowhere else: a stock NGINX image also writes to `/var/cache/nginx` and `/run`. `runAsUser` as a number matters where an image names its user by name (`USER nginx`): the kubelet cannot tell that a named user is not root, and refuses the pod under `runAsNonRoot`.

`extraVolumes` and `extraVolumeMounts` take any volume of a pod and any mount of the container.

<!-- #endregion security-context -->

## Chart versions

<!-- #region chart-versions -->

The chart follows [Semantic Versioning](https://semver.org/). A release builds the base image and the chart together, and the chart version is also the image's tag: chart `0.3.0` runs `ghcr.io/ioanalytica/nginx-static:0.3.0` by default. `appVersion` names the NGINX in that image.

A new NGINX release, or a fix in a library NGINX is linked with, reaches a site in two steps: a release of this project builds the base image anew, and the site's image is built again on that tag.

A release is the git tag of its version, without a `v` (`0.3.0`); the tags up to `v0.2.2` carried one. The chart in the registry never had it: `--version 0.2.2` and `--version 0.3.0` both work.

A release candidate is published as `X.Y.Z-rc.N`, chart and image. Helm skips it unless `--version` names it or `--devel` is given, and so does a version range.

A published version is never published again. A change after a release, however small, gets the next version.

<!-- #endregion chart-versions -->

## Upgrading

<!-- #region upgrading -->

```bash
helm upgrade my-site oci://ghcr.io/ioanalytica/charts/nginx-static \
  --namespace websites -f my-site.yaml
```

The [changelog](https://github.com/ioanalytica/nginx-static/blob/main/chart/CHANGELOG.md) has every version. What an upgrade may ask of the values:

### To a version with the base image (after 0.2.2)

The default image is the project's base image, `ghcr.io/ioanalytica/nginx-static` at the chart's version, where it was a placeholder in a private registry. A release that sets `image.registry`, `image.repository` and `image.tag`, as every release of a site does, is not affected.

An empty `image.tag` now means the chart's version, where it meant the chart's `appVersion`. The two were equal up to 0.2.2; `appVersion` now names the NGINX version of the base image.

A site's image built on `nginx:alpine` or `nginx-unprivileged` keeps working with the chart. Moving it to the base image is a change to the image, see [A site's image](#a-sites-image): the base image brings its own `nginx.conf`, and has no TLS, HTTP/2, proxy or autoindex directives.

Helm checks the values against the chart's schema as of this version, and refuses an upgrade whose values it does not accept, with the path of the value:

- a switch (`*.enabled`) given as text, such as `--set-string ingress.enabled=false`. A template reads the text `"false"` as on, so the value never did what it said;
- an entry of `ingress.hosts` with a key other than `host` and `paths`, or a path with a key other than `path` and `pathType`;
- an `ingress.className` or a `resourcesPreset` outside the listed ones, which the chart refused before as well.

`helm template` with the release's values shows before the upgrade whether they pass.

The Ingress now names the Service's port by its name, `http`, where it gave the number. The Ingress changes once with the upgrade; requests are served throughout.

### To 0.2.1

The chart no longer injects a `nginx.ingress.kubernetes.io/server-snippet` that denied hidden files and PHP paths. It only ever worked with ingress-nginx. Move such rules into the site's image, see [The image](#the-image).

### To 0.2.0

`ingress.className` is required. Set it to the class the release was served by; for ingress-nginx that is `nginx`.

<!-- #endregion upgrading -->

## License

<!-- #region license -->

Copyright &copy; 2024-2026 [IO ANALYTICA](https://ioanalytica.com).

Licensed under the Apache License, Version 2.0: see [LICENSE](https://github.com/ioanalytica/nginx-static/blob/main/LICENSE).

<!-- #endregion license -->
