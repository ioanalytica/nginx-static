#!/bin/bash
# Test for chart/values.schema.json.
#
# Helm checks the values of every install, upgrade, template and lint against
# the schema, and Artifact Hub shows it as the chart's values reference. The
# schema is written by hand, so two things can go wrong without any other test
# noticing: it falls behind values.yaml, or it refuses values a working
# release sets.
#
# check-schema.py covers the first: every `## @param` of values.yaml is in the
# schema with the same description, every schema entry is a key of values.yaml
# with the same default, and every key of values.yaml is in the schema.
#
# This script covers the second. The schema is permissive on purpose:
#   - no `required`, no `additionalProperties: false`, so a key the schema
#     does not know is left to the chart. The entries of ingress.hosts are the
#     exception: a misspelled `host` would render a rule for every hostname;
#   - an `enum` only where the set of values is fixed: the ingress class, the
#     resources preset and a path's type;
#   - numbers also as text, as --set-string and a quoted value in a values
#     file deliver them, and annotations the chart renders as templates also
#     as text.
# Switches are limited to true and false: a template's `if` reads the text
# "false" as on.
#
# --skip-schema-validation needs Helm 3.16 or later.
#
#   ./schema-test.sh [chart-dir]

set -euo pipefail

CHART="${1:-$(dirname "$0")/..}"
HERE="$(dirname "$0")"
REPO="$HERE/../.."
FAILURES=0

preflight="$(helm template tst "$CHART" 2>&1 || true)"
if grep -q "missing in charts/ directory" <<<"$preflight"; then
    echo "ERROR: chart dependencies are missing. Run:"
    echo "         helm dependency update $CHART"
    exit 1
fi

ok()   { echo "ok:   $1"; }
fail() { echo "FAIL: $1"; FAILURES=$((FAILURES + 1)); }

# The defaults name no ingress class, which the chart refuses, so every
# render here names one.
render() { helm template tst "$CHART" -n default --set ingress.className=nginx "$@"; }

# passes <helm args...>: the chart renders with these values, schema and all.
passes() {
    local out
    if out="$(render "$@" 2>&1)"; then
        ok "passes: $*"
    else
        fail "refused: $*"
        printf '%s\n' "$out" | sed 's/^/      /' | tail -4
    fi
}

# refused <path> <helm args...>: the schema refuses the value at <path>, and
# nothing else. <path> is given as /a/b/0, the way Helm 4 names it; Helm 3
# writes a.b.0.
refused() {
    local path="$1" dotted out; shift
    dotted="${path#/}"; dotted="${dotted//\//.}"
    if out="$(render "$@" 2>&1)"; then
        fail "rendered, expected the schema to refuse it: $*"
    elif grep -qF "the schema" <<<"$out" && { grep -qF -- "$path" <<<"$out" || grep -qF -- "$dotted" <<<"$out"; }; then
        ok "refused by the schema: $*"
    else
        fail "failed, but not at $path of the schema: $*"
        printf '%s\n' "$out" | sed 's/^/      /' | tail -4
    fi
}

echo "=== The schema keeps step with values.yaml"
if out="$(python3 "$HERE/check-schema.py" "$CHART" 2>&1)"; then
    ok "$(tail -n 1 <<<"$out")"
else
    fail "values.schema.json and values.yaml disagree"
    printf '%s\n' "$out" | sed 's/^/      /'
fi
# helm lint compiles the schema against its meta-schema and checks
# values.yaml with it.
if out="$(helm lint "$CHART" --set ingress.className=nginx 2>&1)"; then
    ok "values.yaml passes the schema"
else
    fail "helm lint"
    printf '%s\n' "$out" | sed 's/^/      /' | tail -6
fi

echo "=== Values in the forms --set, --set-string and values files deliver"
passes --set replicaCount=3 --set autoscaling.enabled=false
passes --set-string replicaCount=3 --set autoscaling.enabled=false
passes --set containerPort=8081
passes --set-string containerPort=8081
passes --set service.port=8000
passes --set-string service.port=8000
passes --set autoscaling.minReplicas=1 --set autoscaling.maxReplicas=3
passes --set-string autoscaling.minReplicas=1 --set-string autoscaling.maxReplicas=3
passes --set autoscaling.targetCPUUtilizationPercentage=0 --set autoscaling.targetMemoryUtilizationPercentage=80
passes --set pdb.minAvailable=50%
passes --set pdb.minAvailable= --set pdb.maxUnavailable=1
passes --set probes.liveness.httpGet.port=8080
passes --set probes.readiness.tcpSocket.port=8080
passes --set probes.readiness.initialDelaySeconds=0
passes --set image.tag=1.2.3
passes --set-string image.tag=1.2
passes --set resourcesPreset=micro
passes --set-json 'resources=null'
passes --set-json 'resources={}'

echo "=== Annotations the chart renders as templates also pass as text"
passes --set-string 'commonAnnotations=team: {{ .Release.Name }}'
passes --set-string 'podAnnotations=team: ops'
passes --set-string 'service.annotations=team: ops'

passes --set-json 'extraVolumes=[{"name":"tmp","emptyDir":{}}]' --set-json 'extraVolumeMounts=[{"name":"tmp","mountPath":"/tmp"}]'
passes --set-string 'extraVolumes=- name: tmp
  emptyDir: {}' --set-json 'extraVolumeMounts=[{"name":"tmp","mountPath":"/tmp"}]'

echo "=== A key the schema does not list is left to the chart"
passes --set unknownTopLevel.key=1
passes --set image.unknown=1
passes --set probes.startup.enabled=true --set probes.startup.httpGet.path=/healthz --set probes.startup.httpGet.port=http
passes --set probes.liveness.failureThreshold=5
passes --set autoscaling.behavior.scaleDown.selectPolicy=Min
passes --set-json 'redirect.tls=[{"secretName":"a","hosts":["a.example.com"],"extra":1}]'

echo "=== A value the chart cannot use is refused"
refused /ingress/className           --set ingress.className=haproxy
refused /resourcesPreset             --set resourcesPreset=huge
refused /ingress/enabled             --set-string ingress.enabled=false
refused /redirect/enabled            --set-string redirect.enabled=false
refused /autoscaling/enabled         --set autoscaling.enabled=1
refused /pdb/enabled                 --set-string pdb.enabled=true
refused /probes/liveness/enabled     --set-string probes.liveness.enabled=false
refused /replicaCount                --set-json 'replicaCount=1.5'
refused /replicaCount                --set-json 'replicaCount=[1]'
refused /image/repository            --set-json 'image.repository=["a"]'
refused /redirect/targetUrl          --set-json 'redirect.targetUrl=["https://example.com"]'
refused /redirect/hosts              --set-string redirect.hosts=www.example.com
refused /redirect/hosts/0            --set-json 'redirect.hosts=[{"host":"www.example.com"}]'
refused /redirect/tls                --set-string 'redirect.tls=- secretName: a'
refused /extraVolumes                --set-json 'extraVolumes={"name":"tmp"}'
refused /tolerations                 --set-json 'tolerations={}'
refused /nodeSelector                --set-json 'nodeSelector=[]'
refused /commonLabels                --set-string 'commonLabels=team: ops'
# The entries of ingress.hosts: a misspelled or missing key.
refused /ingress/hosts/0             --set-json 'ingress.hosts=[{"hostname":"example.com"}]'
refused /ingress/hosts/0             --set-json 'ingress.hosts=[{"host":"example.com","path":"/"}]'
refused /ingress/hosts/0             --set-json 'ingress.hosts=["example.com"]'
refused /ingress/hosts/0/host        --set-json 'ingress.hosts=[{"host":""}]'
refused /ingress/hosts/0/paths/0     --set-json 'ingress.hosts=[{"host":"example.com","paths":[{"pth":"/"}]}]'
refused /ingress/hosts/0/paths/0/pathType --set-json 'ingress.hosts=[{"host":"example.com","paths":[{"path":"/","pathType":"Regex"}]}]'

echo "=== The schema changes no render"
# same_render <desc> <helm args...>: with and without the schema the chart
# renders the same manifests.
same_render() {
    local desc="$1" with without; shift
    if with="$(helm template tst "$CHART" -n default "$@" 2>&1)" \
       && without="$(helm template tst "$CHART" -n default "$@" --skip-schema-validation 2>&1)" \
       && [ "$with" = "$without" ]; then
        ok "same render: $desc"
    else
        fail "the render differs with and without the schema: $desc"
    fi
}
same_render "defaults" --set ingress.className=nginx
same_render "Traefik redirect with a Certificate" --set ingress.className=traefik --set redirect.enabled=true \
        --set redirect.targetUrl=https://example.com --set 'redirect.hosts={www.example.com}' \
        --set 'redirect.tls[0].secretName=aliases-tls' --set 'redirect.annotations.cert-manager\.io/cluster-issuer=letsencrypt'
for example in "$REPO"/examples/*/*.yaml; do
    [ -f "$example" ] || continue
    same_render "example ${example#"$REPO"/}" -f "$example"
done

echo "=== The packaged chart carries the schema, and not the tests"
PKG_TMP="$(mktemp -d)"
trap 'rm -rf "$PKG_TMP"' EXIT
# The listing is captured first: grep -q leaves at the first match, and tar,
# still writing into the closed pipe, then fails the pipeline under pipefail.
if helm package "$CHART" -d "$PKG_TMP" >/dev/null 2>&1 \
   && packaged="$(tar -tzf "$PKG_TMP"/nginx-static-*.tgz)" \
   && grep -qx 'nginx-static/values.schema.json' <<<"$packaged"; then
    ok "values.schema.json is in the package"
else
    fail "values.schema.json is not in the package"
fi
for file in README.md CHANGELOG.md; do
    if grep -qx "nginx-static/$file" <<<"${packaged:-}"; then ok "$file is in the package"
    else fail "$file is not in the package"; fi
done
if grep -q '^nginx-static/tests/' <<<"${packaged:-}"; then
    fail "the package carries chart/tests/ (.helmignore)"
else
    ok "chart/tests/ stays out of the package"
fi

echo
if [ "$FAILURES" -gt 0 ]; then
    echo "=== $FAILURES check(s) FAILED"
    exit 1
fi
echo "=== All checks passed"
