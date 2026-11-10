#!/usr/bin/env bash
#
# Run shellcheck over every shell script of the repository. CI and a local
# run find the same files and use the same flags.
#
# Scripts are found by their shebang, not by an extension, among the tracked
# files and the new ones git does not ignore: a script is checked before its
# first commit.
#
# -S warning keeps the check to real problems. The notes below it are mostly
# SC2016, single quotes around a $ that sed, awk or a remote shell is meant
# to see, which the tests do on purpose throughout.
#
#   tests/ci/shellcheck.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

# exceptions <file>: the findings that stay for one file, as a list of codes.
# None at present; an entry names its file and says why the finding stays.
exceptions() {
  case "$1" in
    *) ;;
  esac
}

# No mapfile: this also runs on the bash 3.2 of macOS.
files=()
while IFS= read -r f; do
  [ -f "$f" ] || continue
  if head -n 1 "$f" | grep -qE '^#!.*[/ ](ba|da|a)?sh([[:space:]]|$)'; then
    files+=("$f")
  fi
done < <(git ls-files -co --exclude-standard)

[ "${#files[@]}" -gt 0 ] || { echo "shellcheck: no scripts found, the discovery is broken" >&2; exit 1; }

echo "shellcheck: ${#files[@]} scripts"
status=0
plain=()
for f in "${files[@]}"; do
  codes="$(exceptions "$f")"
  if [ -n "$codes" ]; then
    shellcheck -x -S warning -e "$codes" "$f" || status=1
  else
    plain+=("$f")
  fi
done
shellcheck -x -S warning "${plain[@]}" || status=1
[ "$status" -eq 0 ] || exit 1
echo "shellcheck: OK"
