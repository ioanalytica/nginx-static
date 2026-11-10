#!/usr/bin/env bash
#
# Give the chart a release packages the version of its tag. A release
# candidate is tagged on the commit its release will be tagged on
# (X.Y.Z-rc.1, then X.Y.Z on the same commit once the candidate has passed,
# so the release is the source the candidate tested), and that commit's
# chart/Chart.yaml carries the release's version. The candidate's chart gets
# the tag's version, and the same appVersion: the chart ships no image, so
# appVersion follows the chart version. For a release the file already says
# so and stays as it is. The chart job of release.yml runs it after
# check-release-tag.sh.
#
#   scripts/chart-release-version.sh 0.3.0-rc.1 [chart/Chart.yaml]
set -euo pipefail

version="${1:-}"
[ -n "$version" ] || { echo "usage: chart-release-version.sh VERSION [CHART_YAML]" >&2; exit 2; }
chart="${2:-$(dirname "${BASH_SOURCE[0]}")/../chart/Chart.yaml}"

# A tag equal to the chart's version: the file already says what it should.
if grep -qxF "version: $version" "$chart"; then
  echo "$chart: already at $version"
  exit 0
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
# Each of the two once, or the file is not the one this was written for.
if ! awk -v v="$version" '
  /^version: /    { print "version: " v; a++; next }
  /^appVersion: / { print "appVersion: \"" v "\""; b++; next }
  { print }
  END { exit !(a == 1 && b == 1) }' "$chart" >"$tmp"; then
  echo "chart-release-version: expected version: and appVersion: once each in $chart" >&2
  exit 1
fi
cat "$tmp" >"$chart"

echo "$chart: version $version"
