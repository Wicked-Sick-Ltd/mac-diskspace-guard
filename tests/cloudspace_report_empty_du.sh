#!/usr/bin/env bash
# An empty or non-numeric `du` result must not abort cloudspace_report.sh
# under set -euo pipefail, and the value used in $(( )) must stay a plain
# integer. A failing `du` that still printed a leading size keeps that size.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/cloudspace_report.sh"

failures=0

setup_tree() {
  tmp="$(mktemp -d)"
  root="$tmp/root"
  fake_home="$root/Users/craig"
  cloud="$fake_home/Library/CloudStorage"
  provider="$cloud/OneDrive-Acme"
  logfile="$tmp/report.log"
  stdout="$tmp/stdout"
  stderr="$tmp/stderr"
  mkdir -p "$tmp/bin" "$provider"
  : > "$provider/file.txt"
}

finish_case() {
  local name="$1" status="$2"
  if [[ "$status" -ne 0 ]]; then
    echo "FAIL [$name]: cloudspace_report.sh exited $status"
    failures=$((failures + 1))
    rm -rf "$tmp"
    return
  fi
  if [[ -e "$root/PWNED" ]]; then
    echo "FAIL [$name]: du output was executed as a command"
    failures=$((failures + 1))
    rm -rf "$tmp"
    return
  fi
  local case_failed=0
  if ! grep -qxF "Provider,Path,On-Disk (GB),Items" "$stdout"; then
    echo "FAIL [$name]: missing header on stdout"
    case_failed=1
  fi
  if ! grep -qxF "OneDrive,$provider,$expect_gb,1" "$logfile"; then
    echo "FAIL [$name]: missing OneDrive row with size $expect_gb"
    case_failed=1
    echo "---- log ----"
    cat "$logfile" || true
  fi
  if [[ "$case_failed" -eq 0 ]]; then
    echo "ok   [$name]"
  else
    failures=$((failures + 1))
  fi
  rm -rf "$tmp"
}

run_report() {
  local status=0
  (
    cd "$root"
    HOME="$fake_home" LOGFILE="$logfile" PATH="$tmp/bin:$PATH" \
      bash "$SCRIPT" > "$stdout" 2> "$stderr"
  ) || status=$?
  printf '%s' "$status"
}

# du prints nothing and fails. The assignment would abort under pipefail
# before any size check; the report must finish and record 0.
setup_tree
cat > "$tmp/bin/du" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$tmp/bin/du"
expect_gb=0
finish_case "empty du exits non-zero" "$(run_report)"

# du fails after printing a real size (unreadable subdirectory). Keep the
# size, and do not abort.
setup_tree
cat > "$tmp/bin/du" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' 1048576
exit 1
EOF
chmod +x "$tmp/bin/du"
expect_gb=1
finish_case "failed du keeps a leading size" "$(run_report)"

# Non-numeric du output must not reach $(( )).
setup_tree
# shellcheck disable=SC2016
cat > "$tmp/bin/du" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' '+i[$(touch${IFS}PWNED)]'
exit 0
EOF
chmod +x "$tmp/bin/du"
expect_gb=0
finish_case "non-numeric du is not evaluated" "$(run_report)"

if [[ "$failures" -ne 0 ]]; then
  echo "$failures case(s) failed"
  exit 1
fi
echo "all cases passed"
