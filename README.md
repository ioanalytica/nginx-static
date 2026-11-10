# nginx-static

A Helm chart that serves a static website from an NGINX image on Kubernetes. Developed by [IO ANALYTICA](https://ioanalytica.com).

Documentation: [nginx-static.ioanalytica.com](https://nginx-static.ioanalytica.com)

## The chart

One release per site: a Deployment of the site's image, a Service, a HorizontalPodAutoscaler, a PodDisruptionBudget, an Ingress for ingress-nginx or Traefik, and a permanent redirect from any number of alias hosts to the site's URL.

```bash
helm install my-site oci://ghcr.io/ioanalytica/charts/nginx-static \
  --namespace websites --create-namespace \
  --set image.registry=registry.example.com \
  --set image.repository=sites/my-site \
  --set image.tag=1.0.0 \
  --set ingress.className=traefik \
  --set 'ingress.hosts[0].host=www.example.com'
```

The chart ships no image of its own: the image is the site's, an NGINX that listens on port 8080 as a non-root user and answers `GET /healthz` ([The image](chart/README.md#the-image)). `ingress.className` is required and one of `nginx`, `nginx-traefik` and `traefik` ([Ingress](chart/README.md#ingress)).

To see the chart run before you point it at a cluster of your own, follow [Try it locally](examples/k3d/README.md): a throwaway k3d cluster on one machine, with a redirect through Traefik, in about a minute.

See [chart/README.md](chart/README.md) for the full documentation, and [`examples/sites/`](examples/sites/) for the values of three real sites.

## Verify a release

<!-- #region verify -->
Releases after 0.2.2 sign the chart with
[Sigstore](https://www.sigstore.dev/) cosign, keyless: the certificate is
issued to this repository's `release.yml` running for the release tag, and
the signature is recorded in the public Rekor log.

A release sets its tag in the registry only once the signature is in place:
until then the chart is there under its digest alone, so no tag names a chart
that is not signed yet.

Resolve the tag once and use the digest from then on, so that what you
install is what you verified. The identity names the release's tag, so the
check also fails for a tag that was pointed at the chart of another release.
With [cosign](https://docs.sigstore.dev/cosign/system_config/installation/) 3:

```sh
version=<version>
repo=ghcr.io/ioanalytica/charts/nginx-static
digest=$(helm show chart "oci://$repo" --version "$version" 2>&1 | sed -n 's/^Digest: //p')
cosign verify "$repo@$digest" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity "https://github.com/ioanalytica/nginx-static/.github/workflows/release.yml@refs/tags/$version"
```

Helm installs by digest as well:

```sh
helm install my-site "oci://$repo@$digest" --namespace websites -f my-site.yaml
```

The image a release runs is the site's own and not part of this project;
whether it is signed is up to whoever builds it.
<!-- #endregion verify -->

## Contributing

Issues and pull requests are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). Report security issues privately, as [SECURITY.md](SECURITY.md) describes.

## License

Copyright &copy; 2024-2026 [IO ANALYTICA](https://ioanalytica.com).

Licensed under the Apache License, Version 2.0: see [LICENSE](LICENSE).
