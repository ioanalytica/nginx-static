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
