# nginx-static

A Helm chart that serves a static website from an NGINX image on Kubernetes, and a minimal NGINX image to build the site's image on. Developed by [IO ANALYTICA](https://ioanalytica.com).

Documentation: [nginx-static.ioanalytica.com](https://nginx-static.ioanalytica.com)

## Components

### [Helm Chart](chart/)

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

The image is the site's: one built on the base image below, or any other NGINX that listens on port 8080 as a non-root user and answers `GET /healthz` ([The image](chart/README.md#the-image)). `ingress.className` is required and one of `nginx`, `nginx-traefik` and `traefik` ([Ingress](chart/README.md#ingress)).

The chart version is also the tag of the base image released with it; `appVersion` names the NGINX in that image.

To see the chart run before you point it at a cluster of your own, follow [Try it locally](examples/k3d/README.md): a throwaway k3d cluster on one machine, with a redirect through Traefik, in about a minute.

See [chart/README.md](chart/README.md) for the full documentation, and [`examples/sites/`](examples/sites/) for the values of three real sites.

### [Base image](docker/)

NGINX for a static site behind an ingress controller, built from source: without TLS, HTTP/2 and anything that proxies, as one static binary in an image with no shell and no OpenSSL. About 2 MB, multi-arch (`linux/amd64`, `linux/arm64`).

| Registry | Image |
|---|---|
| GitHub Container Registry | `ghcr.io/ioanalytica/nginx-static` |

A site's image copies its files in:

```dockerfile
FROM ghcr.io/ioanalytica/nginx-static:<version>
COPY --chown=101:101 public/ /var/www/html/
COPY custom.d/ /etc/nginx/custom.d/
```

[A site's image](chart/README.md#a-sites-image) in the chart's README says what the base image configures and how a site adds to it.

## Verify a release

<!-- #region verify -->
Releases after 0.2.2 sign the base image and the chart with
[Sigstore](https://www.sigstore.dev/) cosign, keyless: the certificate is
issued to this repository's `release.yml` running for the release tag, and
each signature is recorded in the public Rekor log. Every platform of the
image also carries an SPDX SBOM and SLSA provenance. Both are attestation
manifests listed in the image index, so the index's signature covers them.

A release sets its tags only once the signatures are in place: until then
the image and the chart are in the registry under their digests alone, so no
tag names an artifact that is not signed yet.

Resolve the tag once and use the digest from then on, so that what you use
is what you verified. The identity names the release's tag, so the check
also fails for a tag that was pointed at the artifact of another release.
With [cosign](https://docs.sigstore.dev/cosign/system_config/installation/) 3,
the image:

```sh
version=<version>
repo=ghcr.io/ioanalytica/nginx-static
digest=$(docker buildx imagetools inspect "$repo:$version" --format '{{json .Manifest}}' | jq -r .digest)
cosign verify "$repo@$digest" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity "https://github.com/ioanalytica/nginx-static/.github/workflows/release.yml@refs/tags/$version"
```

A site's Dockerfile can name that digest (`FROM ghcr.io/ioanalytica/nginx-static@sha256:…`).
The SBOM and the provenance of the image, per platform:

```sh
docker buildx imagetools inspect "$repo@$digest" --format '{{json .SBOM}}'
docker buildx imagetools inspect "$repo@$digest" --format '{{json .Provenance}}'
```

The chart:

```sh
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

The image of a site is built by whoever runs the site, on the base image or
not; whether it is signed is up to them.
<!-- #endregion verify -->

## Contributing

Issues and pull requests are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). Report security issues privately, as [SECURITY.md](SECURITY.md) describes.

## License

Copyright &copy; 2024-2026 [IO ANALYTICA](https://ioanalytica.com).

Licensed under the Apache License, Version 2.0: see [LICENSE](LICENSE).
