# nginx-static

Helm chart for deploying a static, nginx-served website (one Helm release per
site). Built on top of the [`common`](https://github.com/ioanalytica/common-helm)
library chart.

Each release renders:

- A `Deployment` with configurable image, probes, resources (preset or explicit), and pod-level overrides.
- A `Service` exposing the container port.
- An optional `HorizontalPodAutoscaler` (CPU and/or memory based, plus arbitrary extra metrics) with a configurable `behavior` block — this is how scaling is driven from values.
- An optional `PodDisruptionBudget`.
- An optional primary `Ingress`.
- An optional redirect that points any number of alias hosts at one `targetUrl`. Form depends on `ingress.className`:
  - `nginx`: a single `Ingress` with `nginx.ingress.kubernetes.io/permanent-redirect` (path drops — nginx-ingress limitation).
  - `traefik`: a `Middleware` (RedirectRegex with capture group, path-preserving) + an `IngressRoute` (Traefik CRDs) + an optional `Certificate` CR when `redirect.annotations` carries a `cert-manager.io/cluster-issuer` (ingress-shim doesn't watch IngressRoute).

## Install

```sh
helm install my-site oci://ghcr.io/ioanalytica/charts/nginx-static \
  -n websites-static --create-namespace \
  -f my-values.yaml
```

See [`examples/`](./examples) for ready-to-use values for `ioanalytica.com`,
`juliafranck.de`, and `tiferet`.

## Scaling

Scaling is driven from values:

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
  targetCPUUtilizationPercentage: 70
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 15
      policies:
        - type: Percent
          value: 100
          periodSeconds: 30
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Pods
          value: 1
          periodSeconds: 60
```

When `autoscaling.enabled: false`, the deployment uses `replicaCount` instead.

## Ingress class

`ingress.className` is **required** and must be one of:

| Value | Primary provider | Primary kind | Redirect form | Path preserved? |
|---|---|---|---|---|
| `nginx`         | rke2-ingress-nginx                                                            | `kind: Ingress` | `kind: Ingress` with `nginx.ingress.kubernetes.io/permanent-redirect` | **No** |
| `nginx-traefik` | Traefik `kubernetesIngressNGINX` (bridge — translates 85+ nginx annotations) | `kind: Ingress` | `kind: Middleware` (capture group) + `kind: IngressRoute` + optional `kind: Certificate` | **Yes** |
| `traefik`       | Traefik `kubernetesIngress` (native)                                          | `kind: Ingress` (cert-shim still works) | same as `nginx-traefik`                                                                  | **Yes** |

Both `nginx-traefik` and `traefik` presume Traefik is present in the
cluster, so the chart emits the path-preserving redirect form in both
cases (the IngressRoute itself declares `ingressClassName: traefik`,
independent of the primary's class). Pick `nginx-traefik` over `traefik`
when the PRIMARY needs the bridge provider to translate nginx-style
annotations in `commonAnnotations` / `ingress.annotations` during
migration; the redirect output is identical.

The chart fails with a clear error if `ingress.className` is empty or
unknown — defaulting is unsafe in mixed-controller clusters.

## Redirect ingress

A release optionally renders a redirect covering every alias host. All
hosts share the same `targetUrl` and the same TLS secret. On
`className: nginx` the chart's `ingress.commonAnnotations` (default:
WAF-style snippet blocking dotfiles, PHP, and common WordPress scan paths)
are merged into the redirect Ingress; on `className: traefik` the
RedirectRegex middleware terminates the request with HTTP 308 before any
backend lookup, so the snippet would have nothing to apply to.

```yaml
ingress:
  className: traefik   # or nginx
redirect:
  enabled: true
  targetUrl: https://example.com
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod   # triggers Certificate CR on traefik
  hosts:
    - www.example.com
    - example.net
  tls:
    - hosts: [www.example.com, example.net]
      secretName: example-aliases-tls
```

If `redirect.tls[0].secretName` already exists in the namespace (e.g.,
reflected from cert-manager), omit the `cert-manager.io/cluster-issuer`
annotation and the chart will not emit a Certificate CR.

Set `redirect.enabled: false` (the default) to skip the redirect entirely.

## Values reference

See [`values.yaml`](./values.yaml) for the full schema and defaults.

| Key | Default | Description |
|---|---|---|
| `image.registry` / `repository` / `tag` | harbor.ioanalytica.com / `io/websites/example` / `""` | Tag falls back to `Chart.AppVersion`. |
| `containerPort` | `8080` | Pod port; service `targetPort` is named `http`. |
| `resourcesPreset` | `""` | One of `nano`, `micro`, `small`, `medium`, `large`, `xlarge`, `2xlarge` (from common). Wins over `resources` when set. |
| `resources` | small request/limit pair | Used when `resourcesPreset` is empty. |
| `probes.readiness` / `liveness` / `startup` | TCP `/healthz` defaults | Each gated by `enabled`; remaining keys are passed verbatim. |
| `autoscaling.enabled` | `true` | When false, `replicaCount` is used. |
| `pdb.enabled` | `true` | Disables the PodDisruptionBudget when false. |
| `ingress.className` | `""` (REQUIRED) | One of `nginx`, `traefik`. Empty/other → render fails. |
| `ingress.commonAnnotations` | dotfile/PHP/WP server-snippet | Merged into primary + (on `className: nginx`) the redirect ingress. |
| `ingress.hosts` | `[example.com]` | Hosts and paths for the primary ingress. |
| `redirect.enabled` | `false` | Render a redirect for `redirect.hosts` (form depends on `ingress.className`). |
| `redirect.targetUrl` | `""` | Required when `redirect.enabled` is true. |

## License

Apache-2.0
