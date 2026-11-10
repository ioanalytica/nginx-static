#!/usr/bin/env bash
#
# Run the page "Try it locally" (examples/k3d/README.md) end to end: every
# `sh` block of the page, in the page's order, in a k3d cluster of its own.
# A block that is followed by a plain block is one whose output the page
# shows: what the command prints has to be that block, word for word. The
# commands are read from the page, so a command changed there is a command
# changed in the test.
#
#   tests/try-locally/run.sh [CHART [HELM_FLAG...]]
#
# CHART takes the place of the released chart the page installs: a chart
# directory (./chart, with its dependencies resolved), or the page's own
# oci:// address followed by `--version X.Y.Z`. Without it the page runs as
# written, with the latest release. The values file is always the checkout's.
#
# The cluster gets a kubeconfig of its own, so the run changes neither the
# current context nor the file of whoever starts it, and is deleted at the
# end, also after a failure. Needs docker, k3d, kubectl, helm and curl, and
# the ports 8080 and 8443 free.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXAMPLES="$ROOT/examples/k3d"
PAGE="$EXAMPLES/README.md"
PAGE_URL="https://raw.githubusercontent.com/ioanalytica/nginx-static/main/examples/k3d"
PAGE_CHART="oci://ghcr.io/ioanalytica/charts/nginx-static"
CLUSTER="nginx-static"

chart="${1:-}"
[ $# -eq 0 ] || shift
extra="$*"
if [ -n "$chart" ] && [ -d "$chart" ]; then chart="$(cd "$chart" && pwd)"; fi

for tool in docker k3d kubectl helm curl; do
  command -v "$tool" >/dev/null || { echo "run.sh: $tool is not installed" >&2; exit 2; }
done
if k3d cluster list -o json | grep -q "\"name\": *\"$CLUSTER\""; then
  echo "run.sh: a k3d cluster named $CLUSTER exists already; delete it first (k3d cluster delete $CLUSTER)" >&2
  exit 2
fi

WORK="$(mktemp -d)"
export KUBECONFIG="$WORK/kubeconfig"
cleanup() {
  status=$?
  if [ "$status" -ne 0 ]; then
    echo "--- the run failed; what the cluster has:"
    kubectl get pods,ingress -A 2>&1 | sed 's/^/    /' || true
    kubectl -n site describe pods 2>&1 | tail -n 25 | sed 's/^/    /' || true
  fi
  k3d cluster delete "$CLUSTER" >/dev/null 2>&1 || true
  rm -rf "$WORK"
  exit "$status"
}
trap cleanup EXIT

# The page's blocks, in order, as files: N.sh for a `sh` block, N.out for the
# plain block that follows the sh block N directly (blank lines and prose
# between the two end the pairing).
awk -v dir="$WORK" '
  /^```/ && !fence {
    fence = 1; kind = substr($0, 4)
    if (kind == "sh") { n++; file = sprintf("%s/%02d.sh", dir, n); pending = 1 }
    else if (kind == "" && pending) { file = sprintf("%s/%02d.out", dir, n); pending = 0 }
    else { file = ""; pending = 0 }
    next
  }
  /^```$/ && fence { fence = 0; if (file != "") close(file); next }
  fence { if (file != "") print > file; next }
  # Prose between a command and a plain block: the block is not its output.
  NF && pending && !/^$/ { pending = 0 }
' "$PAGE"

blocks=("$WORK"/*.sh)
[ "${#blocks[@]}" -ge 6 ] || { echo "run.sh: only ${#blocks[@]} sh blocks found on the page" >&2; exit 1; }

# localize: stdin with the checkout's examples/k3d in place of the page's
# URL and, when a chart is given, that chart in place of the released one.
localize() {
  sed -e "s|^url=$PAGE_URL\$|url=$EXAMPLES|" \
      -e "s|$PAGE_CHART |${chart:-$PAGE_CHART} ${extra:+$extra }|g"
}

failures=0
for block in "${blocks[@]}"; do
  name="$(basename "$block" .sh)"
  script="$WORK/$name.run"
  localize <"$block" >"$script"
  # The clean-up block is the trap's business: a failure before it must
  # still find the cluster to report on.
  if grep -q '^k3d cluster delete' "$script"; then continue; fi
  echo "--- block $name"
  sed 's/^/  $ /' "$script"
  expected="$WORK/$name.out"
  if [ ! -e "$expected" ]; then
    bash -euo pipefail "$script"
    continue
  fi
  # A block whose output the page shows asks something of the cluster that
  # may take Traefik a moment after the rollout: asked again for up to a
  # minute, until the answer is the page's.
  got=""
  for _ in $(seq 1 30); do
    got="$(bash -euo pipefail "$script" 2>&1 || true)"
    [ "$got" = "$(cat "$expected")" ] && break
    sleep 2
  done
  if [ "$got" = "$(cat "$expected")" ]; then
    sed 's/^/  /' <<<"$got"
  else
    echo "FAIL: block $name prints"
    sed 's/^/      /' <<<"$got"
    echo "      the page shows"
    sed 's/^/      /' "$expected"
    failures=$((failures + 1))
  fi
done

if [ "$failures" -gt 0 ]; then
  echo "=== $failures block(s) of the page print something else than the page shows"
  exit 1
fi
echo "=== The page runs as written"
