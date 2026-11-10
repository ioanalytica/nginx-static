{{/*
Copyright IO ANALYTICA. All Rights Reserved.
SPDX-License-Identifier: Apache-2.0
*/}}

{{/*
Merged annotation map for the primary ingress: commonAnnotations + ingress.annotations.

On className == "traefik" all `nginx.ingress.kubernetes.io/*` keys are
stripped — the native kubernetesIngress provider ignores them anyway, so
emitting them is dead weight (and misleading when operators inspect the
Ingress: it looks like dot-ban/PHP-ban/WP-ban are active when they're
actually no-ops).

On className == "nginx-traefik" the keys are KEPT: the
kubernetesIngressNGINX bridge provider translates most of them
(backend-protocol, proxy-*, cors-*, whitelist-source-range, etc.).
Untranslatable ones (server-snippet, configuration-snippet) are ignored
by the bridge — harmless, kept for parity with the nginx path so config
stays portable.

Usage: {{ include "nginx-static.ingress.primaryAnnotations" . }}
*/}}
{{- define "nginx-static.ingress.primaryAnnotations" -}}
{{- $base := default (dict) .Values.ingress.commonAnnotations -}}
{{- $extra := default (dict) .Values.ingress.annotations -}}
{{- $merged := mergeOverwrite (deepCopy $base) $extra -}}
{{- $out := dict -}}
{{- $stripNginx := eq .Values.ingress.className "traefik" -}}
{{- range $k, $v := $merged -}}
{{-   if and $stripNginx (hasPrefix "nginx.ingress.kubernetes.io/" $k) -}}
{{-   else -}}
{{-     $_ := set $out $k $v -}}
{{-   end -}}
{{- end -}}
{{- $out | toYaml -}}
{{- end -}}

{{/*
Merged annotation map for the redirect ingress: ingress.commonAnnotations +
auto-injected permanent-redirect + redirect.annotations.
Usage: {{ include "nginx-static.ingress.redirectAnnotations" . }}
*/}}
{{- define "nginx-static.ingress.redirectAnnotations" -}}
{{- $base := default (dict) .Values.ingress.commonAnnotations -}}
{{- $auto := dict "nginx.ingress.kubernetes.io/permanent-redirect" .Values.redirect.targetUrl -}}
{{- $extra := default (dict) .Values.redirect.annotations -}}
{{- mergeOverwrite (deepCopy $base) $auto $extra | toYaml -}}
{{- end -}}

{{/*
Validate ingress.className. Must be one of: nginx, nginx-traefik, traefik.
Empty fails.

Class semantics for the REDIRECT:
  - nginx:
      Renders kind:Ingress with the `permanent-redirect` annotation.
      Served by rke2-ingress-nginx, which drops the request path
      (nginx-ingress limitation, no path-preservation mechanism).
  - nginx-traefik, traefik:
      Both presume Traefik is present in the cluster. The redirect is
      rendered as kind:Middleware (RedirectRegex with capture group)
      + kind:IngressRoute (which itself uses ingressClassName: traefik,
      independent of the primary's class) + optional kind:Certificate.
      Path preserved.

      Pick nginx-traefik over traefik when the PRIMARY needs the
      bridge provider to translate nginx-style annotations in
      commonAnnotations / ingress.annotations during migration; the
      redirect is identical between the two.

Usage: {{ include "nginx-static.ingress.validateClass" . }}
*/}}
{{- define "nginx-static.ingress.validateClass" -}}
{{- $allowed := list "nginx" "nginx-traefik" "traefik" -}}
{{- $cls := .Values.ingress.className | default "" -}}
{{- if not (has $cls $allowed) -}}
{{- fail (printf "ingress.className is required and must be one of %v; got %q" $allowed $cls) -}}
{{- end -}}
{{- end -}}

{{/*
Name of the redirect Middleware (class=traefik only). Used by both the
Middleware itself and the IngressRoute's middlewares reference.
Usage: {{ include "nginx-static.redirect.middlewareName" . }}
*/}}
{{- define "nginx-static.redirect.middlewareName" -}}
{{- printf "%s-redirect-preserve-path" (include "common.names.fullname" .) -}}
{{- end -}}

{{/*
Merged annotation map for the chart-emitted redirect resources on the
TRAEFIK path (Middleware, IngressRoute, Certificate):
ingress.commonAnnotations + redirect.annotations. Mirrors the convention
that every chart-emitted resource carries commonAnnotations, plus the
redirect-specific annotation overrides. No auto-injected nginx
permanent-redirect on this path (that's nginx-only, handled separately
by redirectAnnotations).
Usage: {{ include "nginx-static.redirect.traefikAnnotations" . }}
*/}}
{{- define "nginx-static.redirect.traefikAnnotations" -}}
{{- $base := default (dict) .Values.ingress.commonAnnotations -}}
{{- $extra := default (dict) .Values.redirect.annotations -}}
{{- mergeOverwrite (deepCopy $base) $extra | toYaml -}}
{{- end -}}

{{/*
Returns the cluster-issuer name from redirect.annotations, or empty string.
Used to decide whether to emit a Certificate CR for the redirect (class=traefik).
Usage: {{ include "nginx-static.redirect.clusterIssuer" . }}
*/}}
{{- define "nginx-static.redirect.clusterIssuer" -}}
{{- index (default (dict) .Values.redirect.annotations) "cert-manager.io/cluster-issuer" | default "" -}}
{{- end -}}
