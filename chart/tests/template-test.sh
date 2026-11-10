#!/bin/bash
# Template test for the nginx-static chart.
#
# Renders the chart across a matrix of value combinations and checks what
# `helm lint` does not: that the resources of a render refer to each other
# (check-manifests.py: selectors, Service and Ingress ports, the autoscaler's
# target, the redirect's Middleware and Certificate), and that each ingress
# class renders the resources and annotations the chart documents for it.
#
#   ./template-test.sh [chart-dir]

set -euo pipefail

CHART="${1:-$(dirname "$0")/..}"
HERE="$(dirname "$0")"
REPO="$HERE/../.."
FAILURES=0

# chart/charts/ is gitignored, so a fresh checkout has no dependencies and
# every render would fail with the same message. Say so once, clearly.
# The output is captured first: under `set -o pipefail` a pipeline from a
# failing helm would carry its exit status, not grep's.
preflight="$(helm template tst "$CHART" 2>&1 || true)"
if grep -q "missing in charts/ directory" <<<"$preflight"; then
    echo "ERROR: chart dependencies are missing. Run:"
    echo "         helm dependency update $CHART"
    exit 1
fi

ok()   { echo "ok:   $1"; }
fail() { echo "FAIL: $1"; FAILURES=$((FAILURES + 1)); }

# Every render names its namespace: without -n, helm takes the one of the
# current kube context, and the output would differ from machine to machine.
render() { helm template tst "$CHART" -n default "$@"; }

# check <desc> <helm args...>: the chart renders, and the manifests hold
# together.
check() {
    local desc="$1" out; shift
    if ! out="$(render "$@" 2>&1)"; then
        fail "$desc — helm template failed"
        printf '%s\n' "$out" | sed 's/^/      /' | tail -5
        return
    fi
    # Herestring, not a pipe: see expect below.
    if python3 "$HERE/check-manifests.py" "$desc" <<<"$out"; then ok "$desc"
    else FAILURES=$((FAILURES + 1)); fi
}

# expect <desc> <"present"|"absent"> <needle> <helm args...>
expect() {
    local desc="$1" mode="$2" needle="$3" out; shift 3
    out="$(render "$@" 2>&1)" || { fail "$desc — helm template failed"; return; }
    # Herestring, NOT a pipe: grep -q exits on the first match, and a
    # printf still writing into the closed pipe then fails with EPIPE.
    # Under `pipefail` that makes a FOUND needle report as not found.
    if grep -qF -- "$needle" <<<"$out"; then
        if [ "$mode" = "present" ]; then ok "$desc"
        else fail "$desc — found '$needle' but expected it absent"; fi
    else
        if [ "$mode" = "absent" ]; then ok "$desc"
        else fail "$desc — expected '$needle', not found"; fi
    fi
}

# refuses <desc> <needle> <helm args...>: the render fails, and says why.
refuses() {
    local desc="$1" needle="$2" out; shift 2
    if out="$(render "$@" 2>&1)"; then
        fail "$desc — rendered, expected it to fail"
    elif grep -qF -- "$needle" <<<"$out"; then
        ok "$desc"
    else
        fail "$desc — failed, but without '$needle'"
        printf '%s\n' "$out" | sed 's/^/      /' | tail -3
    fi
}

# kinds <helm args...>: the kinds of a render with their counts, on one line.
kinds() {
    render "$@" | sed -n 's/^kind: //p' | sort | uniq -c | awk '{ printf "%s%s=%s", sep, $2, $1; sep = " " }'
}

# renders_kinds <desc> <expected> <helm args...>
renders_kinds() {
    local desc="$1" want="$2" got; shift 2
    got="$(kinds "$@" 2>&1)" || true
    if [ "$got" = "$want" ]; then ok "$desc"
    else fail "$desc — rendered '$got', expected '$want'"; fi
}

REDIRECT=(--set redirect.enabled=true --set redirect.targetUrl=https://example.com
          --set 'redirect.hosts={www.example.com,example.net}'
          --set 'redirect.tls[0].secretName=aliases-tls'
          --set 'redirect.tls[0].hosts={www.example.com,example.net}')
ISSUER=(--set 'redirect.annotations.cert-manager\.io/cluster-issuer=letsencrypt')
BASE="Deployment=1 HorizontalPodAutoscaler=1"

echo "=== Chart metadata"
chart_version=$(sed -n 's/^version: *//p' "$CHART/Chart.yaml" | tr -d '"')
app_version=$(sed -n 's/^appVersion: *//p' "$CHART/Chart.yaml" | tr -d '"')
# appVersion is the NGINX in the base image. Renovate raises both together;
# a bump by hand that forgets one would ship a chart that names another
# NGINX than its image holds.
nginx_version=$(sed -n 's/^ARG NGINX_VERSION=//p' "$REPO/docker/Dockerfile")
if [ -n "$nginx_version" ] && [ "$nginx_version" = "$app_version" ]; then
    ok "appVersion is the NGINX version of the image, $nginx_version"
else
    fail "appVersion is '$app_version', the Dockerfile's NGINX_VERSION is '$nginx_version'"
fi
# The chart version is the tag of the base image: the templates take it from
# .Chart.Version, and a release builds, signs and tags the image and the
# chart together. A chart that named another tag would run an image its
# release did not build.
rendered_image=$(render --set ingress.className=nginx | sed -n 's/^ *image: *//p' | tr -d '"')
if [ "$rendered_image" = "ghcr.io/ioanalytica/nginx-static:$chart_version" ]; then
    ok "the default image is the base image at the chart version"
else
    fail "the default image is '$rendered_image', expected ghcr.io/ioanalytica/nginx-static:$chart_version"
fi
# The list Artifact Hub reads and scans names the same image.
listed=$(sed -n 's/^      image: *//p' "$CHART/Chart.yaml")
if [ "$listed" = "ghcr.io/ioanalytica/nginx-static:$chart_version" ]; then
    ok "artifacthub.io/images names the base image at the chart version"
else
    fail "artifacthub.io/images names '$listed'"
fi
if grep -qE '^appVersion: "[0-9]+\.[0-9]*[02468]\.[0-9]+"$' "$CHART/Chart.yaml"; then
    ok "appVersion is quoted, and a stable NGINX release"
else
    fail "appVersion is not a quoted version of an NGINX stable branch (an even minor)"
fi
if [[ "$chart_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    ok "the chart version is a plain SemVer version"
else
    fail "the chart version '$chart_version' is not X.Y.Z; a release candidate gets its suffix from its tag"
fi
# A release takes its notes and its Artifact Hub changes from the entry.
if grep -qxF "## $chart_version" "$CHART/CHANGELOG.md" || grep -qxF "## Unreleased" "$CHART/CHANGELOG.md"; then
    ok "CHANGELOG.md has a section for $chart_version, or an Unreleased one"
else
    fail "CHANGELOG.md has neither '## $chart_version' nor '## Unreleased'"
fi
if [ "$(grep -m 1 '^## ' "$CHART/CHANGELOG.md")" = "## Unreleased" ] || ! grep -qxF "## Unreleased" "$CHART/CHANGELOG.md"; then
    ok "an Unreleased section is the first one of CHANGELOG.md"
else
    fail "'## Unreleased' is not the first section of CHANGELOG.md"
fi
# The two annotations of a release are written when it packages the chart
# (scripts/artifacthub-annotations.sh), never here.
for key in artifacthub.io/changes artifacthub.io/prerelease; do
    if grep -q "^  $key:" "$CHART/Chart.yaml"; then fail "Chart.yaml carries $key; a release writes it"
    else ok "Chart.yaml leaves $key to the release"; fi
done

echo "=== The manifests hold together"
for class in nginx nginx-traefik traefik; do
    check "$class: defaults"                         --set ingress.className="$class"
    check "$class: redirect"                         --set ingress.className="$class" "${REDIRECT[@]}"
    check "$class: redirect with an issuer"          --set ingress.className="$class" "${REDIRECT[@]}" "${ISSUER[@]}"
    check "$class: no autoscaling, no PDB"           --set ingress.className="$class" --set autoscaling.enabled=false --set pdb.enabled=false
    check "$class: redirect without the site's Ingress" --set ingress.className="$class" --set ingress.enabled=false "${REDIRECT[@]}"
done
check "no Ingress at all"                            --set ingress.enabled=false
check "pod labels reach every selector"              --set ingress.className=nginx --set podLabels.tier=web
check "name overrides"                               --set ingress.className=nginx --set fullnameOverride=site --set namespaceOverride=web
# A number given with --set is an int64, one from a values file a float64.
check "another container and Service port"           --set ingress.className=nginx --set containerPort=8081 --set service.port=8000
check "a startup probe"                              --set ingress.className=nginx --set probes.startup.enabled=true \
                                                     --set probes.startup.httpGet.path=/healthz --set probes.startup.httpGet.port=http
check "several hosts and paths"                      --set ingress.className=nginx \
    --set-json 'ingress.hosts=[{"host":"a.example.com"},{"host":"b.example.com","paths":[{"path":"/x","pathType":"Prefix"},{"path":"/y"}]}]'
check "the same annotation for all and for the Service" --set ingress.className=nginx \
    --set commonAnnotations.team=web --set service.annotations.team=ops

echo "=== The ingress class decides what is rendered"
renders_kinds "nginx: one Ingress"                    "$BASE Ingress=1 PodDisruptionBudget=1 Service=1" --set ingress.className=nginx
renders_kinds "nginx: the redirect is a second Ingress" "$BASE Ingress=2 PodDisruptionBudget=1 Service=1" --set ingress.className=nginx "${REDIRECT[@]}"
renders_kinds "nginx: an issuer adds no Certificate"  "$BASE Ingress=2 PodDisruptionBudget=1 Service=1" --set ingress.className=nginx "${REDIRECT[@]}" "${ISSUER[@]}"
for class in nginx-traefik traefik; do
    renders_kinds "$class: the redirect is a Middleware and an IngressRoute" \
        "$BASE Ingress=1 IngressRoute=1 Middleware=1 PodDisruptionBudget=1 Service=1" --set ingress.className="$class" "${REDIRECT[@]}"
    renders_kinds "$class: an issuer adds a Certificate" \
        "Certificate=1 $BASE Ingress=1 IngressRoute=1 Middleware=1 PodDisruptionBudget=1 Service=1" --set ingress.className="$class" "${REDIRECT[@]}" "${ISSUER[@]}"
    renders_kinds "$class: no Certificate without a TLS entry" \
        "$BASE Ingress=1 IngressRoute=1 Middleware=1 PodDisruptionBudget=1 Service=1" --set ingress.className="$class" \
        --set redirect.enabled=true --set redirect.targetUrl=https://example.com --set 'redirect.hosts={www.example.com}' "${ISSUER[@]}"
done
renders_kinds "no Ingress, no redirect: the class is not asked for" "$BASE PodDisruptionBudget=1 Service=1" --set ingress.enabled=false
renders_kinds "no autoscaling, no PDB"                "Deployment=1 Ingress=1 Service=1" --set ingress.className=nginx --set autoscaling.enabled=false --set pdb.enabled=false

echo "=== A missing or unknown value is refused, with its reason"
refuses "no ingress class"                    "ingress.className is required"       # the defaults
refuses "no ingress class for the redirect"   "ingress.className is required"       --set ingress.enabled=false "${REDIRECT[@]}"
refuses "an unknown ingress class"            "ingress/className"                   --set ingress.className=haproxy
refuses "a redirect without a target"         "redirect.targetUrl is required"      --set ingress.className=nginx --set redirect.enabled=true --set 'redirect.hosts={www.example.com}'
refuses "a redirect without hosts"            "redirect.hosts must not be empty"    --set ingress.className=nginx --set redirect.enabled=true --set redirect.targetUrl=https://example.com
refuses "a Traefik redirect without a target" "redirect.targetUrl is required"      --set ingress.className=traefik --set redirect.enabled=true --set 'redirect.hosts={www.example.com}'
refuses "a Traefik redirect without hosts"    "redirect.hosts must not be empty"    --set ingress.className=traefik --set redirect.enabled=true --set redirect.targetUrl=https://example.com
refuses "a startup probe without a handler"   "probes.startup is enabled without a handler" --set ingress.className=nginx --set probes.startup.enabled=true
refuses "a probe whose only handler is set to null" "probes.readiness is enabled without a handler" --set ingress.className=nginx \
    --set-json 'probes.readiness.tcpSocket=null'
# A null where the chart has no default reaches the template as a key
# without a value: it is no handler.
refuses "a startup probe whose only handler is null" "probes.startup is enabled without a handler" --set ingress.className=nginx \
    --set probes.startup.enabled=true --set-json 'probes.startup.tcpSocket=null'
refuses "a second probe handler beside the default" "probes.readiness has more than one handler (httpGet, tcpSocket)" --set ingress.className=nginx \
    --set probes.readiness.httpGet.path=/ --set probes.readiness.httpGet.port=http
refuses "a second handler of the liveness probe" "probes.liveness has more than one handler (exec, httpGet)" --set ingress.className=nginx \
    --set-json 'probes.liveness.exec={"command":["true"]}'
refuses "an unknown resources preset"         "resourcesPreset"                     --set ingress.className=nginx --set resourcesPreset=huge

echo "=== Ingress of the site"
NGINX_ANN=(--set 'ingress.annotations.nginx\.ingress\.kubernetes\.io/proxy-body-size=8m' --set 'ingress.commonAnnotations.example\.com/team=web')
expect "nginx: the class is set"                       present 'ingressClassName: "nginx"'          --set ingress.className=nginx
expect "nginx-traefik: the class is set"               present 'ingressClassName: "nginx-traefik"'  --set ingress.className=nginx-traefik
expect "nginx: nginx annotations stay"                 present 'nginx.ingress.kubernetes.io/proxy-body-size: 8m' --set ingress.className=nginx "${NGINX_ANN[@]}"
expect "nginx-traefik: nginx annotations stay"         present 'nginx.ingress.kubernetes.io/proxy-body-size: 8m' --set ingress.className=nginx-traefik "${NGINX_ANN[@]}"
expect "traefik: nginx annotations are left out"       absent  'nginx.ingress.kubernetes.io/'       --set ingress.className=traefik "${NGINX_ANN[@]}"
expect "traefik: other annotations stay"               present 'example.com/team: web'              --set ingress.className=traefik "${NGINX_ANN[@]}"
expect "ingress.annotations wins over commonAnnotations" present 'example.com/team: ops'            --set ingress.className=nginx "${NGINX_ANN[@]}" \
    --set 'ingress.annotations.example\.com/team=ops'
expect "a host without paths serves /"                 present 'path: /'                            --set ingress.className=nginx --set-json 'ingress.hosts=[{"host":"a.example.com"}]'
expect "a path without a type takes ingress.pathType"  present 'pathType: Prefix'                   --set ingress.className=nginx --set ingress.pathType=Prefix \
    --set-json 'ingress.hosts=[{"host":"a.example.com","paths":[{"path":"/x"}]}]'
expect "TLS entries reach the Ingress"                 present 'secretName: site-tls'               --set ingress.className=nginx \
    --set 'ingress.tls[0].secretName=site-tls' --set 'ingress.tls[0].hosts={example.com}'

echo "=== Redirect"
expect "nginx: the redirect annotation names the target"  present 'nginx.ingress.kubernetes.io/permanent-redirect: https://example.com' --set ingress.className=nginx "${REDIRECT[@]}"
expect "nginx: every alias host has a rule"               present '- host: "example.net"'      --set ingress.className=nginx "${REDIRECT[@]}"
expect "nginx: the issuer annotation reaches the redirect Ingress" present 'cert-manager.io/cluster-issuer: letsencrypt' --set ingress.className=nginx "${REDIRECT[@]}" "${ISSUER[@]}"
for class in nginx-traefik traefik; do
    expect "$class: no nginx redirect annotation"         absent  'permanent-redirect'         --set ingress.className="$class" "${REDIRECT[@]}"
    # SC2016: the needles are Traefik's own syntax, backticks and ${1} included.
    # shellcheck disable=SC2016
    expect "$class: the replacement keeps the path"       present 'replacement: "https://example.com${1}"' --set ingress.className="$class" "${REDIRECT[@]}"
    # shellcheck disable=SC2016
    expect "$class: one rule matches every alias host"    present 'match: Host(`www.example.com`) || Host(`example.net`)' --set ingress.className="$class" "${REDIRECT[@]}"
    expect "$class: the redirect is permanent"            present 'permanent: true'            --set ingress.className="$class" "${REDIRECT[@]}"
    expect "$class: the IngressRoute reads the TLS Secret" present 'secretName: "aliases-tls"' --set ingress.className="$class" "${REDIRECT[@]}"
    expect "$class: the Certificate names the issuer"     present 'name: "letsencrypt"'        --set ingress.className="$class" "${REDIRECT[@]}" "${ISSUER[@]}"
    expect "$class: the Certificate covers every alias host" present '- "example.net"'         --set ingress.className="$class" "${REDIRECT[@]}" "${ISSUER[@]}"
    expect "$class: common annotations reach the redirect" present 'example.com/team: web'     --set ingress.className="$class" --set ingress.enabled=false "${REDIRECT[@]}" \
        --set 'ingress.commonAnnotations.example\.com/team=web'
done

echo "=== Workload"
expect "the image is registry, repository and tag"   present 'image: "registry.example/sites/blog:1.2.3"' --set ingress.className=nginx \
    --set image.registry=registry.example --set image.repository=sites/blog --set image.tag=1.2.3
expect "a digest takes the place of the tag"         present 'image: "registry.example/sites/blog@sha256:0123"' --set ingress.className=nginx \
    --set image.registry=registry.example --set image.repository=sites/blog --set image.tag=1.2.3 --set image.digest=sha256:0123
expect "global.imageRegistry replaces the registry"  present 'image: "mirror.example/ioanalytica/nginx-static:' --set ingress.className=nginx --set global.imageRegistry=mirror.example
expect "an image without a tag takes the chart version" present "image: \"registry.example/sites/blog:$chart_version\"" --set ingress.className=nginx \
    --set image.registry=registry.example --set image.repository=sites/blog
expect "pull secrets reach the pod"                  present '- name: regcred'             --set ingress.className=nginx --set 'image.pullSecrets={regcred}'
expect "global pull secrets reach the pod"           present '- name: regcred'             --set ingress.className=nginx --set 'global.imagePullSecrets={regcred}'
expect "the container is named after the release"    present '- name: tst-nginx-static'    --set ingress.className=nginx
expect "the container port is the value"             present 'containerPort: 8081'         --set ingress.className=nginx --set containerPort=8081
expect "replicaCount without autoscaling"            present 'replicas: 3'                 --set ingress.className=nginx --set autoscaling.enabled=false --set replicaCount=3
expect "the default resources"                       present 'ephemeral-storage: 256Mi'    --set ingress.className=nginx
expect "a preset wins over resources"                absent  'ephemeral-storage: 256Mi'    --set ingress.className=nginx --set resourcesPreset=small
expect "the liveness probe asks /healthz"            present 'path: /healthz'              --set ingress.className=nginx
expect "a disabled probe is left out"                absent  'livenessProbe'               --set ingress.className=nginx --set probes.liveness.enabled=false
expect "a probe's switch stays out of the manifest"  absent  'enabled:'                    --set ingress.className=nginx
expect "a default handler set to null is left out"   absent  'tcpSocket'                    --set ingress.className=nginx \
    --set-json 'probes.readiness.tcpSocket=null' --set probes.readiness.httpGet.path=/ --set probes.readiness.httpGet.port=http
check  "a probe with another handler than the default" --set ingress.className=nginx \
    --set-json 'probes.readiness.tcpSocket=null' --set probes.readiness.httpGet.path=/ --set probes.readiness.httpGet.port=http \
    --set-json 'probes.liveness.httpGet=null' --set-json 'probes.liveness.exec={"command":["true"]}'
expect "a null handler without a default is left out" absent 'tcpSocket: null'              --set ingress.className=nginx \
    --set probes.startup.enabled=true --set-json 'probes.startup.tcpSocket=null' \
    --set probes.startup.httpGet.path=/healthz --set probes.startup.httpGet.port=http
check  "a null handler beside a valid one"           --set ingress.className=nginx \
    --set probes.startup.enabled=true --set-json 'probes.startup.tcpSocket=null' \
    --set probes.startup.httpGet.path=/healthz --set probes.startup.httpGet.port=http
expect "extra probe keys pass through"               present 'failureThreshold: 7'         --set ingress.className=nginx --set probes.readiness.failureThreshold=7
expect "a security context reaches the container"    present 'allowPrivilegeEscalation: false' --set ingress.className=nginx --set containerSecurityContext.allowPrivilegeEscalation=false
TMP_VOLUME=(--set-json 'extraVolumes=[{"name":"tmp","emptyDir":{}}]' --set-json 'extraVolumeMounts=[{"name":"tmp","mountPath":"/tmp"}]')
check  "a volume for /tmp"                           --set ingress.className=nginx "${TMP_VOLUME[@]}" --set containerSecurityContext.readOnlyRootFilesystem=true
expect "an extra volume reaches the pod"             present 'emptyDir: {}'                --set ingress.className=nginx "${TMP_VOLUME[@]}"
expect "an extra mount reaches the container"        present 'mountPath: /tmp'             --set ingress.className=nginx "${TMP_VOLUME[@]}"
expect "no volumes by default"                       absent  'volumes:'                    --set ingress.className=nginx
expect "no mounts by default"                        absent  'volumeMounts:'               --set ingress.className=nginx
expect "a security context reaches the pod"          present 'runAsNonRoot: true'          --set ingress.className=nginx --set podSecurityContext.runAsNonRoot=true
expect "pod annotations are rendered as templates"   present "release: 'tst'"               --set ingress.className=nginx --set-json 'podAnnotations={"release":"{{ .Release.Name }}"}'
expect "a node selector reaches the pod"             present 'disktype: ssd'               --set ingress.className=nginx --set nodeSelector.disktype=ssd
expect "the namespace override reaches the resources" present 'namespace: "web"'           --set ingress.className=nginx --set namespaceOverride=web

echo "=== Autoscaling, PodDisruptionBudget, Service"
expect "the CPU target"                          present 'averageUtilization: 70'  --set ingress.className=nginx
expect "no memory metric at 0"                   absent  'name: memory'            --set ingress.className=nginx
expect "a memory target adds the metric"         present 'name: memory'            --set ingress.className=nginx --set autoscaling.targetMemoryUtilizationPercentage=80
expect "extra metrics are appended"              present 'name: requests_per_second' --set ingress.className=nginx \
    --set-json 'autoscaling.metrics=[{"type":"Pods","pods":{"metric":{"name":"requests_per_second"},"target":{"type":"AverageValue","averageValue":"50"}}}]'
expect "the scaling behavior"                    present 'stabilizationWindowSeconds: 300' --set ingress.className=nginx
expect "minAvailable by default"                 present 'minAvailable: 1'         --set ingress.className=nginx
expect "maxUnavailable as a percentage"          present 'maxUnavailable: 25%'     --set ingress.className=nginx --set pdb.minAvailable= --set pdb.maxUnavailable=25%
expect "the Service type"                        present 'type: NodePort'          --set ingress.className=nginx --set service.type=NodePort
expect "a Service annotation wins over a common one" present 'team: ops'           --set ingress.className=nginx --set commonAnnotations.team=web --set service.annotations.team=ops
expect "common labels reach the resources"       present 'team: web'               --set ingress.className=nginx --set commonLabels.team=web

echo "=== Examples"
# Every values file under examples/ renders, holds together, and sets only
# keys the chart has: helm ignores an unknown key, so a renamed one would go
# unnoticed.
examples=0
for example in "$REPO"/examples/*/*.yaml; do
    [ -f "$example" ] || continue
    examples=$((examples + 1))
    name="${example#"$REPO"/}"
    check "$name" -f "$example"
    # A check that fails (a values file that is no YAML) is one failure,
    # not the end of the run: the other examples are still checked.
    if ! unknown="$(python3 "$HERE/check-example-keys.py" "$CHART/values.yaml" "$example" 2>&1)"; then
        fail "$name — check-example-keys.py failed: $(tail -n 1 <<<"$unknown")"
    elif [ -z "$unknown" ]; then ok "$name sets only keys of the chart"
    else fail "$name sets keys the chart does not have: $(tr '\n' ' ' <<<"$unknown")"; fi
done
if [ "$examples" -ge 4 ]; then ok "$examples example values files found"
else fail "only $examples example values files found under examples/"; fi

echo
if [ "$FAILURES" -gt 0 ]; then
    echo "=== $FAILURES check(s) FAILED"
    exit 1
fi
echo "=== All checks passed"
