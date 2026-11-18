#!/usr/bin/env bash
# A log path that cannot be written must not abort the report. Stdout still
# receives the header and provider rows.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/cloudspace_report.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

root="$tmp/root"
fake_home="$root/Users/craig"
provider="$fake_home/Library/CloudStorage/OneDrive-Acme"
stdout="$tmp/stdout"
stderr="$tmp/stderr"
mkdir -p "$provider" "$tmp/logdir"
: > "$provider/file.txt"

status=0
(
  cd "$root"
  HOME="$fake_home" LOGFILE="$tmp/logdir" \
    bash "$SCRIPT" > "$stdout" 2> "$stderr"
) || status=$?

failures=0
if [[ "$status" -ne 0 ]]; then
  echo "FAIL: cloudspace_report.sh exited $status"
  failures=$((failures + 1))
fi
if [[ -s "$stderr" ]]; then
  echo "FAIL: log open error was not discarded"
  cat "$stderr"
  failures=$((failures + 1))
fi
if ! grep -qxF "Provider,Path,On-Disk (GB),Items" "$stdout"; then
  echo "FAIL: missing header on stdout"
  failures=$((failures + 1))
fi
if ! grep -qxF "OneDrive,$provider,0,1" "$stdout"; then
  echo "FAIL: missing OneDrive row on stdout"
  echo "---- stdout ----"
  cat "$stdout"
  failures=$((failures + 1))
fi

if [[ "$failures" -ne 0 ]]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
