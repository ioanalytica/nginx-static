# nginx-static Helm Chart

<!-- #region intro -->

A Helm chart that serves a static website from an NGINX image on Kubernetes: one release per site, with autoscaling, an Ingress for ingress-nginx or Traefik, and a permanent redirect from any number of alias hosts. Developed by [IO ANALYTICA](https://ioanalytica.com).

<!-- #endregion intro -->

## Features

<!-- #region features -->

- **One release per site**: the chart runs the image a release names, and ships none of its own
- **Horizontal Pod Autoscaling** on CPU and memory, with extra metrics and a scaling behavior set from the values
- **PodDisruptionBudget** that keeps the site up through node drains
- **Ingress for three classes**: ingress-nginx, Traefik, and Traefik's ingress-nginx compatibility provider for the move from one to the other
- **Redirect of alias hosts** to the site's URL, with one certificate for all of them; on Traefik it keeps the request path
- **Resource presets** (nano through 2xlarge) for quick sizing
- **Values schema**: Helm checks the values of every install and upgrade, and refuses a misspelled host entry or an unknown ingress class before anything is deployed
- **Signed releases**: the chart is signed with Sigstore cosign, keyless

<!-- #endregion features -->

## Prerequisites

<!-- #region prerequisites -->

- Kubernetes 1.23+
- Helm 3.8+ (OCI registry support)
- An ingress controller: [ingress-nginx](https://kubernetes.github.io/ingress-nginx/) or [Traefik](https://traefik.io/traefik) 3; for the redirect on Traefik, its `traefik.io/v1alpha1` resource kinds (`IngressRoute`, `Middleware`)
- Optional: [cert-manager](https://cert-manager.io/) for the certificates, and a metrics server for autoscaling
- An image that serves the site, see [The image](#the-image)

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

Three things have no usable default and are set for every release:

| Value | Why |
|---|---|
| `image.registry`, `image.repository`, `image.tag` | the image of the site; the defaults name a placeholder |
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

The chart ships no image. A release names the image of the site it serves, and the chart expects three things of it:

| The image | Value that changes it |
|---|---|
| listens for HTTP on port **8080** | `containerPort` |
| answers `GET /healthz` with a 2xx or 3xx status, for the liveness probe | `probes.liveness` |
| runs as a non-root user, so that it can run under a restrictive [security context](#security-context) | |

TLS ends at the ingress controller: the pod serves plain HTTP inside the cluster, and the chart renders no HTTPS port.

A site's image is typically the NGINX image with the site's files and a server block copied in:

```dockerfile
FROM nginxinc/nginx-unprivileged:1.29-alpine
COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY public/ /usr/share/nginx/html/
```

```nginx
server {
    listen 8080;
    root /usr/share/nginx/html;

    location = /healthz {
        access_log off;
        return 204;
    }

    # Hidden files are never served.
    location ~ /\. {
        return 404;
    }
}
```

Rules that protect the site (denying hidden files, or script paths that scanners probe) belong in the image's NGINX configuration, as above, and not in annotations of the Ingress: in the image they hold whichever ingress controller is in front. The chart injects no such annotations.

`image.tag` is set for every release. Left empty, it falls back to the chart's `appVersion`, which is the chart's own version and names no site image. `image.digest` takes the place of the tag when set, and pins the release to one build of the image.

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

`podSecurityContext` and `containerSecurityContext` are empty by default: what a site's image tolerates is the image's business, and a setting it does not tolerate keeps the pods from starting. For an image that runs NGINX as a non-root user and listens on a port above 1024, such as one built on `nginxinc/nginx-unprivileged` (user id 101), this passes the `restricted` [Pod Security Standard](https://kubernetes.io/docs/concepts/security/pod-security-standards/):

```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 101
  runAsGroup: 101
  seccompProfile:
    type: RuntimeDefault

containerSecurityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]
```

[Try it locally](https://github.com/ioanalytica/nginx-static/blob/main/examples/k3d/README.md) runs with these settings. `runAsUser` as a number matters where the image names its user by name (`USER nginx`): the kubelet cannot tell that a named user is not root, and refuses the pod under `runAsNonRoot`.

`readOnlyRootFilesystem: true` needs an image whose NGINX writes its pid file, its cache and its temporary files to a mounted volume; the chart mounts none.

<!-- #endregion security-context -->

## Chart versions

<!-- #region chart-versions -->

The chart follows [Semantic Versioning](https://semver.org/). Since it ships no image, `appVersion` has nothing of its own to name and equals the chart version.

A release is the git tag of its version, without a `v` (`0.3.0`); the tags up to `v0.2.2` carried one. The chart in the registry never had it: `--version 0.2.2` and `--version 0.3.0` both work.

A release candidate is published as `X.Y.Z-rc.N`. Helm skips it unless `--version` names it or `--devel` is given, and so does a version range.

A published version is never published again. A change after a release, however small, gets the next version.

<!-- #endregion chart-versions -->

## Upgrading

<!-- #region upgrading -->

```bash
helm upgrade my-site oci://ghcr.io/ioanalytica/charts/nginx-static \
  --namespace websites -f my-site.yaml
```

The [changelog](https://github.com/ioanalytica/nginx-static/blob/main/chart/CHANGELOG.md) has every version. What an upgrade may ask of the values:

### To a version with a values schema (after 0.2.2)

Helm checks the values against the chart's schema, and refuses an upgrade whose values it does not accept, with the path of the value:

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
