{{/*
Copyright IO ANALYTICA. All Rights Reserved.
SPDX-License-Identifier: Apache-2.0
*/}}

{{/*
Merged annotation map for the primary ingress: commonAnnotations + ingress.annotations.
Usage: {{ include "nginx-static.ingress.primaryAnnotations" . }}
*/}}
{{- define "nginx-static.ingress.primaryAnnotations" -}}
{{- $base := default (dict) .Values.ingress.commonAnnotations -}}
{{- $extra := default (dict) .Values.ingress.annotations -}}
{{- mergeOverwrite (deepCopy $base) $extra | toYaml -}}
{{- end -}}

{{/*
Merged annotation map for a redirect ingress.
Usage:
  {{ include "nginx-static.ingress.redirectAnnotations" (dict "redirect" $r "context" $) }}
*/}}
{{- define "nginx-static.ingress.redirectAnnotations" -}}
{{- $ctx := .context -}}
{{- $r := .redirect -}}
{{- $base := default (dict) $ctx.Values.ingress.commonAnnotations -}}
{{- $auto := dict "nginx.ingress.kubernetes.io/permanent-redirect" $r.targetUrl -}}
{{- $extra := default (dict) $r.annotations -}}
{{- mergeOverwrite (deepCopy $base) $auto $extra | toYaml -}}
{{- end -}}

{{/*
Stable name suffix for a redirect ingress.
Usage: {{ include "nginx-static.redirect.name" (dict "redirect" $r "index" $i "context" $) }}
*/}}
{{- define "nginx-static.redirect.name" -}}
{{- $suffix := default (printf "%d" (add .index 1)) .redirect.name -}}
{{- printf "%s-redirect-%s" (include "common.names.fullname" .context) $suffix | trunc 63 | trimSuffix "-" -}}
{{- end -}}
