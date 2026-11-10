#!/usr/bin/env bash
#
# Test for what CI and a release rely on outside the chart and the image:
# the rules every workflow follows, the scripts a release runs (tag check,
# release candidates, release notes, Artifact Hub annotations, tags after
# signing) and the order of its jobs, the daily CVE scan and the findings it
# accepts, the versions the page "Try it locally" names, and the Renovate
# configuration. tests/ci/fake-oras/oras stands in for the
# registry.
#
# Needs yq, jq and python3 with PyYAML.
#
#   tests/ci/test.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FAILURES=0
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ok()   { echo "ok:   $1"; }
fail() { echo "FAIL: $1"; FAILURES=$((FAILURES + 1)); }

# accepts <desc> <command...> / refuses <desc> <command...>
accepts() {
    local desc="$1" out; shift
    if out="$("$@" 2>&1)"; then ok "$desc"; else fail "$desc — refused: $out"; fi
}
refuses() {
    local desc="$1" out; shift
    if out="$("$@" 2>&1)"; then fail "$desc — accepted: $out"; else ok "$desc"; fi
}

echo "=== Workflows follow the rules"
if out="$(python3 "$HERE/check-workflows.py" "$ROOT" 2>&1)"; then
    ok "every workflow: pinned actions, time limits, pinned runners, least permissions"
else
    fail "workflow rules"
    printf '%s\n' "$out" | sed 's/^/      /'
fi

# The checker itself: a workflow that breaks every rule is reported for each.
mkdir -p "$WORK/bad/.github/workflows"
cat >"$WORK/bad/.github/workflows/bad.yml" <<'BAD'
name: bad
on: push
permissions:
  contents: write
env:
  TOOL_VERSION: 1.2.3
jobs:
  one:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1
      - run: echo "${{ github.event.pull_request.title }}"
  two:
    runs-on: ubuntu-26.04
    timeout-minutes: 5
    permissions: write-all
    steps:
      - run: "true"
  three:
    runs-on: ubuntu-26.04
    timeout-minutes: 5
    permissions:
      id-token: write
      pages: read
    steps:
      - run: "true"
  four:
    runs-on: ubuntu-26.04
    timeout-minutes: 5
    permissions:
      id-token: write
    steps:
      - {uses: docker/login-action@v4, with: {registry: ghcr.io}}
  five:
    uses: example/workflows/.github/workflows/build.yml@main
    permissions: write-all
  six:
    uses: ./.github/workflows/other.yml
    permissions:
      id-token: write
BAD
out="$(python3 "$HERE/check-workflows.py" "$WORK/bad" 2>&1 || true)"
for needle in "not pinned by a commit SHA" "has no '# vX.Y.Z' comment" "no timeout-minutes" \
              "not on a pinned runner image" "contents: write for every job" \
              "expression inside the run script" "keeps its token" "without a '# renovate:' line" \
              "job two has permissions: write-all" "job five has permissions: write-all" \
              "job four: docker/login-action@v4 is not pinned" \
              "job five: example/workflows/.github/workflows/build.yml@main is not pinned" \
              "more than one job can get an OIDC token: bad.yml: job three; bad.yml: job four; bad.yml: job six"; do
    if grep -qF -- "$needle" <<<"$out"; then ok "the checker reports: $needle"
    else fail "the checker misses: $needle"; fi
done

echo "=== Release tag check"
TAG_CHECK="$ROOT/scripts/check-release-tag.sh"
version="$(sed -n 's/^version: *//p' "$ROOT/chart/Chart.yaml" | tr -d '"')"
accepts "the chart's version as the tag"            "$TAG_CHECK" "$version"
refuses "another version as the tag"                "$TAG_CHECK" "${version}9"
refuses "the version with a v prefix"               "$TAG_CHECK" "v$version"
refuses "no tag at all"                             "$TAG_CHECK"
printf 'name: x\n' >"$WORK/noversion.yaml"
refuses "a Chart.yaml without a version"            "$TAG_CHECK" "$version" "$WORK/noversion.yaml"

echo "=== Release candidates"
accepts "a release candidate of the chart's version"   "$TAG_CHECK" "$version-rc.1"
accepts "a later candidate"                            "$TAG_CHECK" "$version-rc.12"
refuses "a candidate of another version"               "$TAG_CHECK" "${version}9-rc.1"
refuses "a candidate without a number"                 "$TAG_CHECK" "$version-rc"
refuses "a candidate number with a leading zero"       "$TAG_CHECK" "$version-rc.01"
refuses "another suffix than rc"                       "$TAG_CHECK" "$version-beta.1"

# The chart a candidate packages: the tag's version, and the base image at
# it; appVersion stays.
RELEASE_VERSION="$ROOT/scripts/chart-release-version.sh"
cp "$ROOT/chart/Chart.yaml" "$WORK/Chart.yaml"
accepts "a release leaves the chart as it is"          "$RELEASE_VERSION" "$version" "$WORK/Chart.yaml"
if cmp -s "$ROOT/chart/Chart.yaml" "$WORK/Chart.yaml"; then ok "the file is unchanged"
else fail "chart-release-version.sh changed the chart of a release"; fi
accepts "a candidate gets its version"                 "$RELEASE_VERSION" "$version-rc.1" "$WORK/Chart.yaml"
changed="$(diff "$ROOT/chart/Chart.yaml" "$WORK/Chart.yaml" | grep -c '^>' || true)"
if [ "$changed" = 2 ] \
   && grep -qxF "version: $version-rc.1" "$WORK/Chart.yaml" \
   && grep -qxF "      image: ghcr.io/ioanalytica/nginx-static:$version-rc.1" "$WORK/Chart.yaml" \
   && cmp -s <(grep '^appVersion:' "$ROOT/chart/Chart.yaml") <(grep '^appVersion:' "$WORK/Chart.yaml"); then
    ok "the candidate's chart names its version and its image, and nothing else changed"
else
    fail "the candidate's chart: $changed lines changed, expected version and the image"
fi
if [ "$(yq '.version' "$WORK/Chart.yaml")" = "$version-rc.1" ] && [ "$(yq '.dependencies | length' "$WORK/Chart.yaml")" = 1 ]; then
    ok "the candidate's Chart.yaml is still the chart's"
else
    fail "the candidate's Chart.yaml does not read as the chart's any more"
fi
printf 'version: 1.0.0\n' >"$WORK/short.yaml"
refuses "a chart without the image entry"              "$RELEASE_VERSION" 1.0.0-rc.1 "$WORK/short.yaml"

echo "=== Release notes and Artifact Hub changes come from the changelog"
SECTION="$ROOT/scripts/changelog-section.sh"
cat >"$WORK/CHANGELOG.md" <<'LOG'
# Changelog

## Unreleased

* Not released yet.

## 0.3.0

* **A lead in bold.** More text. Another sentence.
  * A nested bullet that belongs to the one above.
* A bullet without a lead, e.g. this one. A second sentence.
* See the [release notes](https://example.com/notes) and `code`.

### Project and CI

* A change to the repository alone.

## 0.2.2

* The release before.
LOG
got="$("$SECTION" 0.3.0 "$WORK/CHANGELOG.md" | head -n 1)"
if [ "$got" = "* **A lead in bold.** More text. Another sentence." ]; then ok "a version's section starts at its first line"
else fail "changelog-section 0.3.0 starts with '$got'"; fi
if [ "$("$SECTION" 0.3.0-rc.2 "$WORK/CHANGELOG.md")" = "$("$SECTION" 0.3.0 "$WORK/CHANGELOG.md")" ]; then
    ok "a candidate without a section gets its release's"
else fail "a candidate's notes differ from its release's"; fi
if [ "$("$SECTION" 0.2.2 "$WORK/CHANGELOG.md")" = "* The release before." ]; then ok "the last section ends with the file"
else fail "changelog-section 0.2.2"; fi
if [ -z "$("$SECTION" 0.4.0 "$WORK/CHANGELOG.md")" ]; then ok "a version without a section prints nothing"
else fail "changelog-section printed something for a version without a section"; fi
if "$SECTION" 0.3.0 "$WORK/CHANGELOG.md" | grep -q 'release before\|Not released'; then
    fail "a section runs into its neighbours"
else ok "a section ends at the next version"; fi

ANNOTATE="$ROOT/scripts/artifacthub-annotations.sh"
cp "$ROOT/chart/Chart.yaml" "$WORK/Chart.yaml"
accepts "the annotations of a release"                 "$ANNOTATE" 0.3.0 "$WORK/Chart.yaml" "$WORK/CHANGELOG.md"
changes="$(yq '.annotations["artifacthub.io/changes"]' "$WORK/Chart.yaml" | yq -o=json -I=0 .)"
want='["A lead in bold.","A bullet without a lead, e.g. this one.","See the release notes and code."]'
if [ "$changes" = "$want" ]; then ok "changes are the leads, as plain text, without the repository's own"
else fail "artifacthub.io/changes is $changes"; fi
if [ "$(yq '.annotations["artifacthub.io/prerelease"]' "$WORK/Chart.yaml")" = false ]; then ok "a release is no prerelease"
else fail "a release is marked as a prerelease"; fi
if [ "$(yq '.annotations["artifacthub.io/links"]' "$WORK/Chart.yaml" | yq 'length')" -gt 0 ]; then ok "the links are still there"
else fail "the links are gone"; fi
if [ "$(yq '.annotations["artifacthub.io/images"]' "$WORK/Chart.yaml" | yq 'length')" = 1 ]; then ok "the images list is still there"
else fail "the images list is gone"; fi
refuses "a chart that has the annotations already"     "$ANNOTATE" 0.3.0 "$WORK/Chart.yaml" "$WORK/CHANGELOG.md"
cp "$ROOT/chart/Chart.yaml" "$WORK/Chart.yaml"
accepts "the annotations of a candidate"               "$ANNOTATE" 0.3.0-rc.1 "$WORK/Chart.yaml" "$WORK/CHANGELOG.md"
if grep -qxF '  artifacthub.io/prerelease: "true"' "$WORK/Chart.yaml"; then ok "a candidate is a prerelease"
else fail "a candidate is not marked as a prerelease"; fi
# The chart's own changelog, as the next release will read it.
cp "$ROOT/chart/Chart.yaml" "$WORK/Chart.yaml"
sed 's/^## Unreleased$/## 99.0.0/' "$ROOT/chart/CHANGELOG.md" >"$WORK/own.md"
if grep -qxF '## 99.0.0' "$WORK/own.md"; then
    accepts "the annotations from the chart's own Unreleased section" "$ANNOTATE" 99.0.0 "$WORK/Chart.yaml" "$WORK/own.md"
    if yq -e '.annotations["artifacthub.io/changes"] | from_yaml | length > 0' "$WORK/Chart.yaml" >/dev/null 2>&1; then
        ok "the Unreleased section yields changes Artifact Hub can read"
    else
        fail "the Unreleased section of chart/CHANGELOG.md yields no readable changes"
    fi
else
    echo "skip: chart/CHANGELOG.md has no Unreleased section"
fi

echo "=== A release's changelog entry"
CHANGELOG_RELEASE="$ROOT/scripts/changelog-release.sh"
cp "$WORK/CHANGELOG.md" "$WORK/next.md"
accepts "Unreleased becomes the version's section"     "$CHANGELOG_RELEASE" 0.4.0 "" "$WORK/next.md"
if ! grep -qxF '## Unreleased' "$WORK/next.md" && [ "$("$SECTION" 0.4.0 "$WORK/next.md")" = "* Not released yet." ]; then
    ok "the entry is what stood under Unreleased"
else fail "changelog-release.sh did not turn Unreleased into 0.4.0"; fi
refuses "a version that has its section already"       "$CHANGELOG_RELEASE" 0.3.0 "" "$WORK/next.md"
refuses "no Unreleased section and no line"            "$CHANGELOG_RELEASE" 0.5.0 "" "$WORK/next.md"
accepts "no Unreleased section, with a line"           "$CHANGELOG_RELEASE" 0.5.0 "* A line of its own." "$WORK/next.md"
if [ "$(grep -m 1 '^## ' "$WORK/next.md")" = "## 0.5.0" ] && [ "$("$SECTION" 0.5.0 "$WORK/next.md")" = "* A line of its own." ]; then
    ok "the new section is the first one"
else fail "changelog-release.sh did not put 0.5.0 first"; fi

echo "=== Tags are set after signing, and a published version stays"
TAG_IMAGES="$ROOT/scripts/release-tag-images.sh"
I=ghcr.io/ioanalytica/nginx-static
C=ghcr.io/ioanalytica/charts/nginx-static
nl=$'\n'
export ORAS_FAKE_STATE="$WORK/registry"
mkdir -p "$ORAS_FAKE_STATE/runs"
for pair in aaa:12 ccc:13 ddd:14 old:; do echo "${pair#*:}" >"$ORAS_FAKE_STATE/runs/sha256:${pair%%:*}"; done
# tagged <image> <tag>: the digest the stand-in registry has for a tag.
tagged() { cat "$ORAS_FAKE_STATE/tags/${1//\//_}/$2" 2>/dev/null || true; }
with_oras() { PATH="$HERE/fake-oras:$PATH" "$@"; }

accepts "a release tags the image"     with_oras "$TAG_IMAGES" 0.3.0 "$I@sha256:aaa" "$I:0.3.0$nl$I:latest"
if [ "$(tagged "$I" 0.3.0)$(tagged "$I" latest)" = "sha256:aaasha256:aaa" ]; then
    ok "the version and latest name the release's digest"
else fail "tags after a release: $(grep -r . "$ORAS_FAKE_STATE/tags")"; fi
accepts "a re-run of the tag job"      with_oras "$TAG_IMAGES" 0.3.0 "$I@sha256:aaa" "$I:0.3.0$nl$I:latest"
refuses "latest for a candidate"       with_oras "$TAG_IMAGES" 0.3.1-rc.1 "$I@sha256:ccc" "$I:0.3.1-rc.1$nl$I:latest"
if [ -z "$(tagged "$I" 0.3.1-rc.1)" ]; then ok "a refused list sets no tag at all"
else fail "a refused list left a tag behind"; fi
refuses "a tag of another image"       with_oras "$TAG_IMAGES" 0.3.1 "$I@sha256:ccc" "$C:0.3.1"
refuses "an empty list"                with_oras "$TAG_IMAGES" 0.3.1 "$I@sha256:ccc" ""
refuses "an index of no release run"   with_oras "$TAG_IMAGES" 0.3.1 "$I@sha256:old" "$I:0.3.1"
refuses "a version published already"  with_oras "$TAG_IMAGES" 0.3.0 "$I@sha256:ddd" "$I:0.3.0$nl$I:latest"
if [ "$(tagged "$I" 0.3.0)$(tagged "$I" latest)" = "sha256:aaasha256:aaa" ]; then ok "the published version and latest stay"
else fail "a second build of 0.3.0 moved a tag"; fi
accepts "a later release moves latest" with_oras "$TAG_IMAGES" 0.3.1 "$I@sha256:ddd" "$I:0.3.1$nl$I:latest"
accepts "a late re-run of an older release" with_oras "$TAG_IMAGES" 0.3.2 "$I@sha256:ccc" "$I:0.3.2$nl$I:latest"
if [ "$(tagged "$I" latest)" = "sha256:ddd" ] && [ "$(tagged "$I" 0.3.2)" = "sha256:ccc" ]; then
    ok "latest stays on the later run's image"
else fail "a late re-run moved latest back"; fi
refuses "a registry that answers with an error" env ORAS_FAKE_BROKEN=1 PATH="$HERE/fake-oras:$PATH" \
    "$TAG_IMAGES" 0.3.3 "$I@sha256:ddd" "$I:0.3.3"

TAG_ONCE="$ROOT/scripts/release-tag-once.sh"
accepts "the chart gets its version"   with_oras "$TAG_ONCE" "$C@sha256:eee" 0.3.0
accepts "a re-run finds it there"      with_oras "$TAG_ONCE" "$C@sha256:eee" 0.3.0
refuses "another chart under the same version" with_oras "$TAG_ONCE" "$C@sha256:fff" 0.3.0
if [ "$(tagged "$C" 0.3.0)" = "sha256:eee" ]; then ok "the chart's version stays on the first chart"
else fail "the chart's version moved"; fi
refuses "a registry error while tagging" env ORAS_FAKE_BROKEN=1 PATH="$HERE/fake-oras:$PATH" "$TAG_ONCE" "$C@sha256:eee" 0.3.1
refuses "a reference without a digest"  with_oras "$TAG_ONCE" "$C:0.3.0" 0.3.0

# Artifact Hub's repository metadata moves forward only.
METADATA="$ROOT/scripts/release-artifacthub-metadata.sh"
accepts "the first release pushes the metadata"     with_oras "$METADATA" "$C" 12 "$ROOT/artifacthub-repo.yml"
accepts "a later release replaces it"               with_oras "$METADATA" "$C" 14 "$ROOT/artifacthub-repo.yml"
accepts "a late re-run of an older release"         with_oras "$METADATA" "$C" 13 "$ROOT/artifacthub-repo.yml"
if [ "$(tagged "$C" artifacthub.io)" = "sha256:pushed-by-run-14" ]; then ok "the later run's metadata stays"
else fail "an older run replaced the metadata: $(tagged "$C" artifacthub.io)"; fi
accepts "a re-run of the same release pushes again" with_oras "$METADATA" "$C" 14 "$ROOT/artifacthub-repo.yml"
refuses "a registry error while reading the metadata" env ORAS_FAKE_BROKEN=1 PATH="$HERE/fake-oras:$PATH" \
    "$METADATA" "$C" 15 "$ROOT/artifacthub-repo.yml"
refuses "a metadata file that is not there"         with_oras "$METADATA" "$C" 15 "$WORK/none.yml"
if yq -e '.ignore[] | select(.name == "nginx-static" and .version == "-")' "$ROOT/artifacthub-repo.yml" >/dev/null 2>&1; then
    ok "artifacthub-repo.yml keeps release candidates out of the listing"
else fail "artifacthub-repo.yml does not ignore versions with a -suffix"; fi

UNPUBLISHED="$ROOT/scripts/release-unpublished.sh"
accepts "a version no repository has"          with_oras "$UNPUBLISHED" 0.9.9 "$I" "$C"
refuses "a version one repository has"         with_oras "$UNPUBLISHED" 0.3.2 "$I" "$C"
refuses "a registry error while asking"        env ORAS_FAKE_BROKEN=1 PATH="$HERE/fake-oras:$PATH" "$UNPUBLISHED" 0.9.9 "$C"

echo "=== The release signs before it tags"
RELEASE="$ROOT/.github/workflows/release.yml"
BUILD="$ROOT/.github/workflows/build-image.yml"
if out="$(python3 "$HERE/check-release-workflow.py" "$RELEASE" "$BUILD" 2>&1)"; then ok "one job signs, tags follow the signatures, the release follows the tags"
else
    fail "the release workflow"
    printf '%s\n' "$out" | sed 's/^/      /'
fi
signer="$(sed -n "s/^  SIGNER: '\(.*\)'$/\1/p" "$RELEASE")"
# shellcheck disable=SC2016 # the README's and the workflow's own variables
if [ -n "$signer" ] && grep -qF -- "--certificate-identity \"$signer\$version\"" "$ROOT/README.md" \
   && grep -qF -- '--certificate-identity "$SIGNER$GITHUB_REF_NAME"' "$RELEASE"; then
    ok "the README verifies with the identity the release signs and checks with: the workflow at the version's tag"
else
    fail "README.md and release.yml do not verify with the same identity, '$signer' followed by the version"
fi
# The lint of the release is the lint of the tests.
lint='helm lint chart/ --set ingress.className=nginx'
if grep -qF "$lint" "$RELEASE" && grep -qF "$lint" "$ROOT/.github/workflows/test.yml"; then
    ok "release.yml and test.yml lint the chart the same way"
else fail "release.yml and test.yml do not both run '$lint'"; fi

# The smoke test of a release is the one of a pull request.
smoke='./docker/tests/smoke-test.sh'
if grep -qF "$smoke" "$RELEASE" && grep -qF "$smoke" "$ROOT/.github/workflows/test.yml"; then
    ok "release.yml and test.yml run the same smoke test"
else fail "release.yml and test.yml do not both run $smoke"; fi
# The release's image and the chart's default are one name.
if grep -qxF '      image: nginx-static' "$RELEASE" \
   && [ "$(yq '.image.registry + "/" + .image.repository' "$ROOT/chart/values.yaml")" = "ghcr.io/ioanalytica/nginx-static" ]; then
    ok "the release builds the image the chart runs by default"
else fail "release.yml builds another image than chart/values.yaml names"; fi

echo "=== The daily CVE scan"
SCAN="$ROOT/.github/workflows/cve-scan.yml"
if grep -qxF '  IMAGE: ghcr.io/ioanalytica/nginx-static:latest' "$SCAN"; then ok "the scan covers the base image at :latest"
else fail "cve-scan.yml does not scan ghcr.io/ioanalytica/nginx-static:latest"; fi
if grep -q 'trivyignores: .github/cve-scan-accepted.yaml' "$SCAN" && grep -q 'ignore-unfixed: true' "$SCAN"; then
    ok "the scan's failing step reads the accepted findings and skips what has no fix"
else
    fail "cve-scan.yml no longer reads .github/cve-scan-accepted.yaml in a step with ignore-unfixed"
fi
# The scan sees the linked libraries only through the entries the image
# carries: the Dockerfile writes them, the scan and the smoke test insist on
# the same three.
linked='musl pcre2-static zlib-static '
if grep -qF "\"$linked\"" "$SCAN" && grep -qF "\"$linked\"" "$ROOT/docker/tests/smoke-test.sh" \
   && grep -qF 'P:(musl|zlib-static|pcre2-static)' "$ROOT/docker/Dockerfile"; then
    ok "the Dockerfile, the smoke test and the scan name the same linked libraries"
else
    fail "the linked libraries differ between docker/Dockerfile, the smoke test and cve-scan.yml"
fi
# Each accepted finding: the vulnerability, where it applies, why it waits,
# and an expiry date at most three months out.
if out="$(python3 - "$ROOT/.github/cve-scan-accepted.yaml" <<'PY' 2>&1
import datetime, re, sys, yaml
entries = (yaml.safe_load(open(sys.argv[1])) or {}).get("vulnerabilities") or []
limit = datetime.date.today() + datetime.timedelta(days=93)
problems = []
seen = set()
for entry in entries:
    name = entry.get("id", "an entry without id")
    if not re.fullmatch(r"(CVE-\d{4}-\d+|GHSA(-[0-9a-z]{4}){3})", str(entry.get("id", ""))):
        problems.append(f"{name}: not a CVE or GHSA id")
    if name in seen:
        problems.append(f"{name}: listed twice")
    seen.add(name)
    if not (entry.get("paths") or entry.get("purls")):
        problems.append(f"{name}: neither paths nor purls, so it would apply to every package")
    if len(str(entry.get("statement", "")).split()) < 8:
        problems.append(f"{name}: no statement that says why it waits and on what")
    expiry = entry.get("expired_at")
    if not isinstance(expiry, datetime.date):
        problems.append(f"{name}: no expired_at date")
    elif expiry > limit:
        problems.append(f"{name}: expires {expiry}, more than three months out")
    unknown = set(entry) - {"id", "paths", "purls", "statement", "expired_at"}
    if unknown:
        problems.append(f"{name}: unknown keys {sorted(unknown)}")
print("\n".join(problems) if problems else f"{len(entries)} entries")
sys.exit(1 if problems else 0)
PY
)"; then
    ok "every accepted finding has a place, a reason and an expiry date ($out)"
else
    fail "accepted findings"
    printf '%s\n' "$out" | sed 's/^/      /'
fi

echo "=== Latest is the release with the highest version"
IS_LATEST="$ROOT/scripts/release-is-latest.sh"
# latest <desc> <expected> <version> <published versions, one a line>
latest() {
    local got
    got="$("$IS_LATEST" "$3" <<<"$4" 2>&1)" || true
    if [ "$got" = "$2" ]; then ok "$1"; else fail "$1 — expected $2, got '$got'"; fi
}
latest "the first release of all"                 true  0.3.0 ""
latest "a release above the tags with a v"        true  0.3.0 "v0.2.2${nl}v0.2.1${nl}v0.1.0"
latest "a re-run of the newest release"           true  0.3.0 "0.3.0${nl}v0.2.2"
latest "a late re-run of an older release"        false 0.3.0 "0.3.1${nl}0.3.0${nl}v0.2.2"
latest "a two-digit minor above a one-digit one"  true  0.10.0 "0.9.0${nl}0.3.0"
latest "a release candidate"                      false 0.4.0-rc.1 "0.3.0"

echo "=== The page Try it locally and its workflow name the same versions"
PAGE="$ROOT/examples/k3d/README.md"
TRY="$ROOT/.github/workflows/try-locally.yml"
k3d_pin="$(sed -n 's/^ *K3D_VERSION: *//p' "$TRY")"
k3s_pin="$(sed -n 's/.*--image rancher\/k3s:v\([0-9]*\.[0-9]*\)\..*/\1/p' "$PAGE")"
tested="$(grep -o 'Tested with k3d [0-9.]* and$' "$PAGE" || true)"
tested_k3s="$(grep -o '^k3s [0-9.]*\.$' "$PAGE" || true)"
if [ -n "$k3d_pin" ] && [ "$tested" = "Tested with k3d ${k3d_pin%.*} and" ]; then
    ok "the page is tested with the k3d the workflow installs, ${k3d_pin%.*}"
else fail "the page says '$tested', the workflow installs k3d $k3d_pin"; fi
if [ -n "$k3s_pin" ] && [ "$tested_k3s" = "k3s $k3s_pin." ]; then
    ok "the page is tested with the k3s its cluster runs, $k3s_pin"
else fail "the page says '$tested_k3s', its cluster runs k3s $k3s_pin"; fi
# The runner replaces the page's values URL and chart address; a page that
# words them differently would install the released chart in a pull request.
RUNNER="$ROOT/tests/try-locally/run.sh"
page_url="$(sed -n 's/^PAGE_URL="\(.*\)"$/\1/p' "$RUNNER")"
page_chart="$(sed -n 's/^PAGE_CHART="\(.*\)"$/\1/p' "$RUNNER")"
if [ -n "$page_url" ] && grep -qxF "url=$page_url" "$PAGE" && grep -qF -- "-f \$url/values.yaml" "$PAGE"; then
    ok "the page takes its values from the address the runner replaces"
else fail "examples/k3d/README.md does not set url=$page_url and install with -f \$url/values.yaml"; fi
if [ -n "$page_chart" ] && grep -qF "helm install demo $page_chart " "$PAGE"; then
    ok "the page installs the chart the runner replaces"
else fail "examples/k3d/README.md does not install $page_chart"; fi
# shellcheck disable=SC2016 # the workflow's own variable
if grep -qF 'tests/try-locally/run.sh --import "$IMAGE" ./chart' "$TRY" && grep -qF "run.sh $page_chart --version" "$TRY"; then
    ok "the workflow runs the page with the checkout's chart and image, and with a published version"
else fail "try-locally.yml does not run tests/try-locally/run.sh with ./chart and with a version"; fi
# The page names no image: it runs the chart's default, the base image.
if grep -qE '^image:' "$ROOT/examples/k3d/values.yaml"; then fail "examples/k3d/values.yaml names an image"
else ok "the page runs the chart's default image"; fi

echo "=== Renovate configuration"
RENOVATE="$ROOT/.github/renovate.json"
# has <desc> <jq filter that is true>
has() {
    if jq -e "$2" "$RENOVATE" >/dev/null 2>&1; then ok "$1"; else fail "$1"; fi
}
has "the file is JSON with the Renovate schema"  '."$schema" == "https://docs.renovatebot.com/renovate-schema.json"'
has "actions are pinned by digest"               '.extends | index("helpers:pinGitHubActionDigestsToSemver")'
has "its commits are signed off"                 '.commitBody == "Signed-off-by: {{{gitAuthor}}}"'
has "the common chart dependency stays manual"   '.helmv3.enabled == false'
has "no values file is read for image pins"      '."helm-values".enabled == false'
has "NGINX moves in the Dockerfile and in appVersion together" 'any(.customManagers[]; .depNameTemplate == "nginx/nginx" and (.managerFilePatterns | length) == 2)'
has "a new NGINX branch waits for approval"      'any(.packageRules[]; .matchDepNames == ["nginx/nginx"] and .dependencyDashboardApproval == true)'
has "a moved action tag waits for approval"      'any(.packageRules[]; .matchUpdateTypes == ["digest"] and .dependencyDashboardApproval == true)'
has "the tests' fixtures are left alone"         '.ignorePaths | index("tests/**") and index("chart/tests/**") and index("docker/tests/**")'
# Every *_VERSION the workflows pin is one the custom manager's pattern reads.
pins="$(grep -rhc '# renovate: datasource=' "$ROOT/.github/workflows" "$ROOT/.github/actions" | paste -sd+ - | bc)"
if [ "$pins" -ge 3 ]; then ok "$pins tool versions carry a renovate line"
else fail "only $pins tool versions with a renovate line found"; fi

echo
if [ "$FAILURES" -gt 0 ]; then
    echo "=== $FAILURES check(s) FAILED"
    exit 1
fi
echo "=== All checks passed"
