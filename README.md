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
- An optional redirect `Ingress` that points any number of alias hosts at one `targetUrl` via `nginx.ingress.kubernetes.io/permanent-redirect`. One Ingress means one TLS list, so cert-manager issues a single SAN cert for all aliases.

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

## Redirect ingress

A release optionally renders one redirect `Ingress` covering every alias host.
All hosts share the same `targetUrl` (the only thing
`nginx.ingress.kubernetes.io/permanent-redirect` accepts) and the same TLS list,
which keeps cert-manager requests simple even with dozens of aliases. The
chart's `ingress.commonAnnotations` (default: WAF-style snippet blocking
dotfiles, PHP, and common WordPress scan paths) are merged in;
`redirect.annotations` override.

```yaml
redirect:
  enabled: true
  targetUrl: https://example.com
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - www.example.com
    - example.net
  tls:
    - hosts: [www.example.com, example.net]
      secretName: example-aliases-tls
```

Set `redirect.enabled: false` (the default) to skip the redirect Ingress
entirely.

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
| `ingress.commonAnnotations` | dotfile/PHP/WP server-snippet | Merged into primary + redirect ingresses. |
| `ingress.hosts` | `[example.com]` | Hosts and paths for the primary ingress. |
| `redirect.enabled` | `false` | Render a single redirect Ingress for `redirect.hosts`. |
| `redirect.targetUrl` | `""` | Required when `redirect.enabled` is true. |

## License

Apache-2.0
