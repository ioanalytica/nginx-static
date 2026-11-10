# Changelog

## Unreleased

* **Values schema.** The chart has a `values.schema.json`: Helm checks the
  values of every install, upgrade, template and lint against it, and
  Artifact Hub shows it as the values reference. It refuses a switch
  (`*.enabled`) given as text, a malformed entry of `ingress.hosts`, and an
  `ingress.className` or `resourcesPreset` outside the listed ones; keys it
  does not list are left to the chart. See "Upgrading" in the chart's README.

* **Signed releases.** A release signs the chart with Sigstore cosign,
  keyless, and sets its tag in the registry only once the signature is in
  place. "Verify a release" in the README has the command.

* **The Ingress names the Service's port by its name.** A `service.port`
  given with `--set` rendered an Ingress backend without a port, which the
  API server refuses. The backend now refers to the port `http`.

* **One `annotations` map on the Service.** A key set in both
  `commonAnnotations` and `service.annotations` was rendered twice, which a
  strict YAML parser such as the one of Flux refuses. The two are merged, and
  `service.annotations` wins.

* **A probe with two handlers, or with none, is refused.** A release that
  gives a probe another kind of handler keeps the chart's default one beside
  it unless it sets that one to `null`, and the startup probe has no handler
  until it is given one. The chart now fails to render such a probe and names
  the value, where the API server refused the Deployment.

* Every value is documented in `values.yaml`, and the chart's README covers
  the image the chart expects, the three ingress classes, the redirect and
  the security context.

* A new page, "Try it locally", runs the chart in a throwaway k3d cluster.

### Project and CI

* The repository has one branch, `main`; the chart lives in `chart/`, the
  example values in `examples/sites/`.
* Release tags carry no `v` any more: the tag is the chart version.
* Tests for the templates, the schema, the workflows and the release
  scripts, and the page "Try it locally" end to end in k3d.
* A documentation site, built from the READMEs.
* The repository is registered on Artifact Hub; its metadata names the ID.

## 0.2.2

* Annotation propagation on the Traefik-path redirect resources. The
  chart-emitted `Middleware`, `IngressRoute`, and `Certificate` now
  carry `metadata.annotations` populated from `ingress.commonAnnotations
  + redirect.annotations` (same convention the primary Ingress already
  followed). This closes a gap from 0.2.0 where commonAnnotations were
  only applied to the primary Ingress and silently dropped on the
  traefik-path resources.

* New helper `nginx-static.redirect.traefikAnnotations` makes the merge
  reusable across all three traefik-path templates.

## 0.2.1

* **Retired** the chart-default
  `nginx.ingress.kubernetes.io/server-snippet` (dot-ban + PHP-ban +
  WP-scan-ban). The snippet was only effective when served by
  ingress-nginx and silently ignored by Traefik. The equivalent
  protection is now expected to live in the site image's nginx
  configuration (typically `custom.d/02-userconfig.conf`), where it
  runs regardless of which ingress controller fronts the pod and works
  identically across `nginx`, `nginx-traefik`, and `traefik` classes.

* `ingress.commonAnnotations` is empty by default. Set it explicitly to
  apply extra annotations across all chart-emitted resources (primary
  Ingress + traefik-path Middleware/IngressRoute/Certificate when
  redirect is enabled).

* No template changes — purely a values default flip. Existing users
  who already set `commonAnnotations` explicitly are unaffected.

## 0.2.0

* **First-class Traefik support**. `ingress.className` is now a
  required, validated field with three allowed values:
  - `nginx` — served by ingress-nginx (or rke2-ingress-nginx). Legacy
    path. nginx-style annotations interpreted natively.
  - `nginx-traefik` — served by Traefik's `kubernetesIngressNGINX`
    bridge provider. Same `kind:Ingress` manifest, swap controllers
    without touching annotations. The bridge translates most
    nginx-style annotations (proxy-body-size, whitelist-source-range,
    auth-url, backend-protocol, cors-*, …) into Traefik's internal
    middleware chain.
  - `traefik` — served by Traefik's native `kubernetesIngress`
    provider. nginx-style annotations on the primary Ingress are
    silently ignored AND stripped by the
    `nginx-static.ingress.primaryAnnotations` helper. Steady state
    after the nginx → Traefik migration.

* **Optional redirect resource** via the existing `redirect:` values
  block, rendered per `ingress.className`:
  - `nginx`: one `kind:Ingress` with
    `nginx.ingress.kubernetes.io/permanent-redirect`. Cert managed by
    cert-manager ingress-shim. Path is **not** preserved (annotation
    limitation).
  - `nginx-traefik` / `traefik`: one `kind:Middleware` (RedirectRegex
    with capture group → path-preserving 308) +
    `kind:IngressRoute` matching all `redirect.hosts`, plus a
    free-standing `kind:Certificate` if
    `redirect.annotations["cert-manager.io/cluster-issuer"]` is set
    (cert-manager's ingress-shim doesn't watch IngressRoute).

* The redirect block accepts any list of source hostnames (vanity
  domains, backup TLDs, www variants) collapsed into a single TLS list,
  so cert-manager issues one SAN cert covering them all.
