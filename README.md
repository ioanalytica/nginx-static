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
- An optional list of redirect `Ingress` objects, each pointing a set of hosts at one `targetUrl` via `nginx.ingress.kubernetes.io/permanent-redirect`.

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

## Redirect ingresses

Redirects are optional and per-release. Each entry produces one Ingress with
its hosts redirected to `targetUrl`. The chart's `ingress.commonAnnotations`
(default: WAF-style snippet blocking dotfiles, PHP, and common WordPress scan
paths) are merged into every redirect; per-redirect `annotations` override.

```yaml
redirects:
  - name: aliases
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

Set `enabled: false` on an entry to keep it in values without rendering it.

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
| `redirects` | `[]` | Optional list of redirect ingresses (see above). |

## License

Apache-2.0
