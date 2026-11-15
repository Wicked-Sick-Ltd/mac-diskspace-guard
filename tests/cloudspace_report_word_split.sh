#!/usr/bin/env bash
# Regression test: cloudspace_report.sh must treat each provider folder found
# under ~/Library/CloudStorage as one path, never word-split or glob it into
# other directories (relative to the launchd working directory "/", or
# absolute prefixes created by a space in $HOME).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/cloudspace_report.sh"

REAL_DU="$(command -v du)"
REAL_FIND="$(command -v find)"

failures=0

# run_case NAME HOME_SUBPATH PROVIDER_DIR...
# Builds a fake filesystem root whose top level mirrors the macOS directories
# an attacker would target, runs the report from that root (as launchd does
# from "/"), and records every directory du or find was asked to walk.
run_case() {
  local name="$1" home_sub="$2"
  shift 2

  local tmp
  tmp="$(mktemp -d)"
  local root="$tmp/root"
  local fake_home="$root/$home_sub"
  local cloud="$fake_home/Library/CloudStorage"
  local walked="$tmp/walked"
  local logfile="$tmp/report.log"

  mkdir -p "$tmp/bin" "$cloud"
  : > "$walked"

  local d
  for d in Library Users System Applications private Volumes home; do
    mkdir -p "$root/$d"
    : > "$root/$d/canary"
  done
  # Another account whose name is the first word of a home folder with a space.
  mkdir -p "$root/Users/Ann"
  : > "$root/Users/Ann/canary"

  local provider
  for provider in "$@"; do
    mkdir -p "$cloud/$provider"
    : > "$cloud/$provider/file.txt"
  done

  cat > "$tmp/bin/du" << EOF
#!/usr/bin/env bash
for a in "\$@"; do :; done
printf '%s\0' "\$a" >> "$walked"
exec "$REAL_DU" "\$@"
EOF
  cat > "$tmp/bin/find" << EOF
#!/usr/bin/env bash
for a in "\$@"; do
  if [[ "\$a" == "-xdev" ]]; then printf '%s\0' "\$1" >> "$walked"; break; fi
done
exec "$REAL_FIND" "\$@"
EOF
  chmod +x "$tmp/bin/du" "$tmp/bin/find"

  (
    cd "$root"
    HOME="$fake_home" LOGFILE="$logfile" PATH="$tmp/bin:$PATH" \
      bash "$SCRIPT" > /dev/null 2>&1
  ) || {
    echo "FAIL [$name]: cloudspace_report.sh exited non-zero"
    failures=$((failures + 1))
  }

  local case_failed=0 w
  while IFS= read -r -d '' w; do
    case "$w" in
      "$cloud"/*) ;;
      *)
        echo "FAIL [$name]: walked directory outside CloudStorage: $w"
        case_failed=1
        ;;
    esac
  done < "$walked"

  for provider in "$@"; do
    [[ "$provider" == *$'\n'* ]] && continue
    local label="OneDrive"
    [[ "$provider" == GoogleDrive* ]] && label="GoogleDrive"
    if ! grep -qxF "$label,$cloud/$provider,0,1" "$logfile"; then
      echo "FAIL [$name]: missing report row for $label folder: $cloud/$provider"
      case_failed=1
    fi
  done

  if [[ "$case_failed" -eq 0 ]]; then
    echo "ok   [$name]"
  else
    failures=$((failures + 1))
  fi
  rm -rf "$tmp"
}

run_case "onedrive org name with space" "Users/craig" "OneDrive-Public Library"
run_case "onedrive org name, other top-level dirs" "Users/craig" \
  "OneDrive-Acme Users System Applications private Volumes home"
run_case "google drive folder with space" "Users/craig" "GoogleDrive-me@example.com Library"
run_case "home folder with space" "Users/Ann Smith" "OneDrive-Acme"
run_case "glob characters in folder name" "Users/craig" "OneDrive-Acme * ????????????"
run_case "newline in folder name" "Users/craig" $'OneDrive-Acme\nSystem'

if [[ "$failures" -ne 0 ]]; then
  echo "$failures case(s) failed"
  exit 1
fi
echo "all cases passed"
