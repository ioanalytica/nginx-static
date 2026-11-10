#!/usr/bin/env bash
#
# Print the chart/CHANGELOG.md entry of one version: the lines below its
# "## VERSION" heading up to the next "## " heading, without the heading and
# the blank lines around the entry. A release candidate without a section of
# its own prints the entry of its release (0.3.0-rc.1: "## 0.3.0"): it is
# tagged on the commit its release will be tagged on, and that commit's
# changelog has one section, the release's. A version with no section prints
# nothing, and the release then carries GitHub's generated notes alone.
#
# The release job of release.yml puts this in front of those generated notes,
# so a release page shows what changed, not only the pull requests that
# changed it.
#
#   scripts/changelog-section.sh 0.3.0 [chart/CHANGELOG.md]
set -euo pipefail

version="${1:-}"
[ -n "$version" ] || { echo "usage: changelog-section.sh VERSION [FILE]" >&2; exit 2; }
file="${2:-$(dirname "${BASH_SOURCE[0]}")/../chart/CHANGELOG.md}"
[ -r "$file" ] || { echo "changelog-section: cannot read $file" >&2; exit 1; }

# A candidate with a section of its own keeps it.
if [[ "$version" =~ ^(.+)-rc\.[0-9]+$ ]] && ! grep -qxF "## $version" "$file"; then
  version="${BASH_REMATCH[1]}"
fi

awk -v want="## $version" '
  $0 == want { inside = 1; next }
  inside && /^## / { exit }
  inside { lines[++n] = $0 }
  END {
    first = 1; while (first <= n && lines[first] == "") first++
    last = n;  while (last >= first && lines[last] == "") last--
    for (i = first; i <= last; i++) print lines[i]
  }
' "$file"
