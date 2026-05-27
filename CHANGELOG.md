# Changelog

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
