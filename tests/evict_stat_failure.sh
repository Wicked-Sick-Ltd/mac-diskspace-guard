#!/usr/bin/env bash
# One candidate that cannot be stat'd must not stop eviction of the others.
# cloudspace_evict.sh --apply has to exit 0 and invoke fileproviderctl evict
# for every remaining over-threshold file. These checks fail while a stat
# error aborts the script.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$ROOT/cloudspace_evict.sh"
HELPER_SRC="$ROOT/tests/macos_stat_f.c"
ORIG_PATH=$PATH

if [[ ! -f "$SCRIPT" ]]; then
  printf 'missing %s\n' "$SCRIPT" >&2
  exit 1
fi

failures=0

note() { printf '%s\n' "$*"; }

fail_case() {
  printf 'FAIL %s: %s\n' "$CASE_NAME" "$*" >&2
  failures=$((failures + 1))
}

show_case_logs() {
  local work=$1
  printf '%s\n' '--- stdout ---' >&2
  cat "$work/stdout" >&2 || true
  printf '%s\n' '--- stderr ---' >&2
  cat "$work/stderr" >&2 || true
  printf '%s\n' '--- evict calls ---' >&2
  cat "$work/evict-calls" >&2 || true
}

write_stub() {
  local path=$1
  local body=$2
  printf '%s\n' "$body" > "$path"
  chmod 755 "$path"
}

prepare_home() {
  local home=$1
  mkdir -p \
    "$home/Library/Mobile Documents/com~apple~CloudDocs/shared" \
    "$home/Library/CloudStorage/Dropbox/keep" \
    "$home/Library/CloudStorage/Dropbox/blocked" \
    "$home/Library/Logs"
  # Strictly above the script's 200MB candidate threshold.
  truncate -s 220M "$home/Library/Mobile Documents/com~apple~CloudDocs/shared/early large.bin"
  truncate -s 340M "$home/Library/CloudStorage/Dropbox/keep/later large.bin"
  truncate -s 260M "$home/Library/CloudStorage/Dropbox/blocked/unstable.bin"
  SURVIVOR_EARLY="$home/Library/Mobile Documents/com~apple~CloudDocs/shared/early large.bin"
  SURVIVOR_LATER="$home/Library/CloudStorage/Dropbox/keep/later large.bin"
  UNSTABLE="$home/Library/CloudStorage/Dropbox/blocked/unstable.bin"
  BLOCK_DIR="$home/Library/CloudStorage/Dropbox/blocked"
}

install_fileproviderctl() {
  local bin=$1
  local work=$2
  write_stub "$bin/fileproviderctl" "#!/usr/bin/env bash
printf '%s\n' \"\$*\" >> \"\$EVICT_CALLS\"
exit 0"
  export EVICT_CALLS="$work/evict-calls"
  : > "$EVICT_CALLS"
}

run_evict() {
  local home=$1
  local bin=$2
  local work=$3
  export HOME="$home"
  export LOGFILE="$work/evict.log"
  export PATH="$bin:$ORIG_PATH"
  set +e
  "$BASH" "$SCRIPT" --apply > "$work/stdout" 2> "$work/stderr"
  CASE_RC=$?
  set -e
}

expect_survivors_evicted() {
  local work=$1
  if [[ "$CASE_RC" -ne 0 ]]; then
    show_case_logs "$work"
    fail_case "exited $CASE_RC; a stat failure must not abort eviction"
    return
  fi
  local survivor
  for survivor in "$SURVIVOR_EARLY" "$SURVIVOR_LATER"; do
    if ! grep -F -x "evict $survivor" "$work/evict-calls" > /dev/null; then
      show_case_logs "$work"
      fail_case "fileproviderctl evict did not run for $survivor"
      return
    fi
  done
  note "PASS $CASE_NAME"
}

case_deleted_before_stat() {
  CASE_NAME=deleted_before_stat
  local work home bin
  work=$(mktemp -d)
  home=$work/home
  bin=$work/bin
  mkdir -p "$bin"
  prepare_home "$home"
  install_fileproviderctl "$bin" "$work"
  # mktemp runs only after find has recorded candidates and before stat.
  REMOVE_FILE=$UNSTABLE
  export REMOVE_FILE
  write_stub "$bin/mktemp" "#!/usr/bin/env bash
p=\$(/usr/bin/mktemp \"\$@\")
rm -f -- \"\$REMOVE_FILE\"
printf '%s\n' \"\$p\""
  run_evict "$home" "$bin" "$work"
  expect_survivors_evicted "$work"
  rm -rf "$work"
}

case_unstatable_directory() {
  CASE_NAME=unstatable_directory
  local work home bin
  work=$(mktemp -d)
  home=$work/home
  bin=$work/bin
  mkdir -p "$bin"
  prepare_home "$home"
  install_fileproviderctl "$bin" "$work"
  BLOCK_DIR_FOR_STAT=$BLOCK_DIR
  export BLOCK_DIR_FOR_STAT
  write_stub "$bin/mktemp" "#!/usr/bin/env bash
p=\$(/usr/bin/mktemp \"\$@\")
chmod a-x -- \"\$BLOCK_DIR_FOR_STAT\"
printf '%s\n' \"\$p\""
  run_evict "$home" "$bin" "$work"
  chmod u+x "$BLOCK_DIR" 2> /dev/null || true
  expect_survivors_evicted "$work"
  chmod u+x "$BLOCK_DIR" 2> /dev/null || true
  rm -rf "$work"
}

case_restat_loses_path() {
  CASE_NAME=restat_loses_path
  local work home bin
  work=$(mktemp -d)
  home=$work/home
  bin=$work/bin
  mkdir -p "$bin"
  prepare_home "$home"
  install_fileproviderctl "$bin" "$work"
  gcc -O2 -o "$bin/macos_stat_f" "$HELPER_SRC"
  # First successful BSD-style stat of the unstable path removes it, so a
  # second stat of that same path (the script's check, then its use) fails.
  DOOMED_ON_NEXT_STAT=$UNSTABLE
  DOOMED_MARK=$work/doomed-marked
  export DOOMED_ON_NEXT_STAT DOOMED_MARK
  write_stub "$bin/stat" "#!/usr/bin/env bash
helper=\$(dirname \"\$0\")/macos_stat_f
if [[ \"\${1:-}\" == -f && \"\${2:-}\" == %z && -n \"\${3:-}\" ]]; then
  if \"\$helper\" -f %z \"\$3\"; then
    if [[ \"\$3\" == \"\$DOOMED_ON_NEXT_STAT\" && ! -e \"\$DOOMED_MARK\" ]]; then
      : > \"\$DOOMED_MARK\"
      rm -f -- \"\$3\"
    fi
    exit 0
  fi
  exit 1
fi
printf '%s\n' 'usage: stat [-FLnq] [-f format | -l | -r | -s | -x] [-t timefmt] [file ...]' >&2
exit 1"
  run_evict "$home" "$bin" "$work"
  expect_survivors_evicted "$work"
  rm -rf "$work"
}

note "interpreter: $BASH $BASH_VERSION"
case_deleted_before_stat
case_unstatable_directory
case_restat_loses_path

if [[ "$failures" -ne 0 ]]; then
  printf '%s case(s) failed\n' "$failures" >&2
  exit 1
fi
note "all eviction stat-failure cases passed"
