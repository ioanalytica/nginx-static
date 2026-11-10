# Parameters

Every value is described where it is defined, in
[`values.yaml`](https://github.com/ioanalytica/nginx-static/blob/main/chart/values.yaml),
and
[`values.schema.json`](https://github.com/ioanalytica/nginx-static/blob/main/chart/values.schema.json)
lists them with their types and defaults; Helm checks the values of every
install and upgrade against it. This page says which part of the
documentation covers which group of values.

| Values | Page |
|---|---|
| `image`, `containerPort`, `global.imageRegistry`, `global.imagePullSecrets` | [The image](/reference/image) |
| `resources`, `resourcesPreset`, `probes` | [Resources and probes](/features/resources) |
| `autoscaling`, `replicaCount`, `pdb` | [Autoscaling](/features/autoscaling) |
| `ingress` | [Ingress](/features/ingress) |
| `redirect` | [Redirect](/features/redirect) |
| `podSecurityContext`, `containerSecurityContext`, `extraVolumes`, `extraVolumeMounts` | [Security context](/security/security-context) |

The remaining values are described in `values.yaml` alone: the names of the
release's resources, labels and annotations, scheduling (`nodeSelector`,
`tolerations`, `affinity`) and the Service (`service.type`, `service.port`,
`service.annotations`).

Three things are set for every release: the image of the site,
`ingress.className` and `ingress.hosts`. [Install](/guide/install)
shows them in a first values file.
