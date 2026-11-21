#!/usr/bin/env bash
# A failing df on a /Volumes entry must not abort the report under set -e.
# The script looks at the real /Volumes path, which exists on macOS. On a
# machine without it, create that directory if permitted.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/cloudspace_report.sh"

made_volumes=0
if [[ ! -d /Volumes ]]; then
  if mkdir /Volumes 2> /dev/null; then
    made_volumes=1
  elif sudo -n mkdir /Volumes; then
    made_volumes=1
  else
    echo "FAIL: /Volumes is missing and cannot be created"
    exit 1
  fi
fi

tmp="$(mktemp -d)"
vol="/Volumes/diskspace-guard-df-$$"
sudo_vol=0
cleanup() {
  if [[ "$sudo_vol" -eq 1 ]]; then
    sudo -n rm -rf "$vol"
  else
    rm -rf "$vol"
  fi
  rm -rf "$tmp"
  if [[ "$made_volumes" -eq 1 ]]; then
    rmdir /Volumes 2> /dev/null || sudo -n rmdir /Volumes 2> /dev/null || true
  fi
}
trap cleanup EXIT

if ! mkdir "$vol" 2> /dev/null; then
  sudo -n mkdir "$vol"
  sudo_vol=1
fi
mkdir -p "$tmp/bin" "$tmp/home"
cat > "$tmp/bin/df" << EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$tmp/df-args"
exit 1
EOF
chmod +x "$tmp/bin/df"

stdout="$tmp/stdout"
stderr="$tmp/stderr"
status=0
HOME="$tmp/home" LOGFILE="$tmp/report.log" PATH="$tmp/bin:$PATH" \
  bash "$SCRIPT" > "$stdout" 2> "$stderr" || status=$?

failures=0
if [[ "$status" -ne 0 ]]; then
  echo "FAIL: cloudspace_report.sh exited $status"
  cat "$stderr"
  failures=$((failures + 1))
fi
if ! grep -qxF "Provider,Path,On-Disk (GB),Items" "$stdout"; then
  echo "FAIL: missing header on stdout"
  failures=$((failures + 1))
fi
if ! grep -Fxq -- "-H $vol" "$tmp/df-args"; then
  echo "FAIL: df was not asked for $vol"
  cat "$tmp/df-args" 2> /dev/null || true
  failures=$((failures + 1))
fi
if grep -F -- "$vol" "$stdout" "$tmp/report.log"; then
  echo "FAIL: a failed df still produced a volume line"
  failures=$((failures + 1))
fi

if [[ "$failures" -ne 0 ]]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
