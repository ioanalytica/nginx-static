#!/usr/bin/env bash
#
# Say whether a release is the repository's newest: "true" when no published
# release has a higher version, "false" otherwise, and always "false" for a
# release candidate. The release job of release.yml marks the GitHub Release
# as Latest only then, so a late re-run of an older release's failed job
# does not take Latest back from a newer release.
#
# The versions of the published releases come on standard input, one a
# line; the version itself may be among them. The caller reads them in a
# step of their own, so that a failed listing stops it and is not taken for
# "nothing published yet":
#
#   published="$(gh api --paginate repos/OWNER/REPO/releases --jq '.[] | select(.draft or .prerelease | not) | .tag_name')"
#   scripts/release-is-latest.sh 0.3.0 <<<"$published"
set -euo pipefail

version="${1:-}"
[ -n "$version" ] || { echo "usage: release-is-latest.sh VERSION < VERSIONS" >&2; exit 2; }

# A version with a -suffix is a release candidate.
if [[ "$version" == *-rc.* ]]; then
  echo false
  exit 0
fi

# Version order. The tags up to v0.2.2 carry a "v", which would sort them
# above every version without one, so it is dropped before the comparison.
newest="$({ cat; echo "$version"; } | sed 's/^v//' | grep -v '^$' | sort -V | tail -n 1)"
if [ "$newest" = "$version" ]; then echo true; else echo false; fi
