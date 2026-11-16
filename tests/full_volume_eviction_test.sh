#!/usr/bin/env bash
# Spec for cloud eviction when the data volume cannot accept another write.
#
# These checks fail while cloudspace_evict.sh and cloudspace_report.sh abort
# on the first auxiliary write (set -euo pipefail plus tee / mktemp output).
# They pass once a failed log append or candidate-list write cannot stop
# fileproviderctl evict, and once the report still prints provider rows.
#
# Run from anywhere:
#   bash tests/full_volume_eviction_test.sh
#
# Needs passwordless sudo to mount a loopback ext4 image. The filler file is
# written only after the mount's block device is confirmed to be different
# from the root filesystem.
#
# Not covered here:
#   sort's own temporary files. With no free blocks the size-list write in
#   cloudspace_evict.sh fails first, so sort is never started. GNU sort also
#   keeps a two-line list in memory, so a short run would not spill anyway.
#   diskspace_guard.sh's own log and tmutil pipelines already ignore write
#   errors. tmutil is not invoked; it is absent here and would edit host
#   snapshots.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
failures=0
MOUNTS=()
WORKDIRS=()

pass() { printf 'PASS: %s\n' "$1"; }

fail() {
  printf 'FAIL: %s\n' "$1"
  failures=$((failures + 1))
}

note() { printf '  %s\n' "$1"; }

cleanup_all() {
  local mnt
  for mnt in "${MOUNTS[@]+"${MOUNTS[@]}"}"; do
    if mountpoint -q "$mnt"; then
      sudo -n umount "$mnt" || sudo -n umount -l "$mnt" || true
    fi
  done
  local dir
  for dir in "${WORKDIRS[@]+"${WORKDIRS[@]}"}"; do
    rm -rf "$dir"
  done
}
trap cleanup_all EXIT

require_tools() {
  local missing=0
  local tool
  for tool in mkfs.ext4 mountpoint sudo truncate dd df awk; do
    if ! command -v "$tool" > /dev/null 2>&1; then
      note "missing tool: $tool"
      missing=1
    fi
  done
  if ! sudo -n true; then
    note "sudo -n is required to mount the fixture volume"
    missing=1
  fi
  if [[ "$missing" -ne 0 ]]; then
    printf 'fixture setup failed\n'
    exit 2
  fi
}

# Create an empty ext4 mount owned by the current user.
# Sets VOL_WORKDIR, VOL_MNT, HOME_DIR, STUB_DIR, FP_LOG.
new_volume() {
  VOL_WORKDIR=$(mktemp -d /tmp/evict-vol.XXXXXX)
  WORKDIRS+=("$VOL_WORKDIR")
  VOL_MNT="$VOL_WORKDIR/mnt"
  mkdir -p "$VOL_MNT"
  truncate -s 32M "$VOL_WORKDIR/vol.img"
  mkfs.ext4 -F -q -b 4096 "$VOL_WORKDIR/vol.img"
  sudo -n mount -o loop "$VOL_WORKDIR/vol.img" "$VOL_MNT"
  MOUNTS+=("$VOL_MNT")
  sudo -n chown "$(id -u):$(id -g)" "$VOL_MNT"
  if ! mountpoint -q "$VOL_MNT"; then
    note "loop image did not mount at $VOL_MNT"
    exit 2
  fi
  local root_src mnt_src
  root_src=$(df -kP / | awk 'NR==2 {print $1}')
  mnt_src=$(df -kP "$VOL_MNT" | awk 'NR==2 {print $1}')
  if [[ "$VOL_MNT" != /tmp/* || "$root_src" == "$mnt_src" ]]; then
    note "refusing to use $VOL_MNT (source $mnt_src, root $root_src)"
    exit 2
  fi
  HOME_DIR="$VOL_MNT/home"
  mkdir -p \
    "$HOME_DIR/Library/Logs" \
    "$HOME_DIR/Library/CloudStorage/TestProvider" \
    "$HOME_DIR/Library/Mobile Documents/com~apple~CloudDocs" \
    "$HOME_DIR/Library/Caches" \
    "$HOME_DIR/.Trash" \
    "$HOME_DIR/bin" \
    "$VOL_MNT/tmp"
  # Apparent size must be strictly above find's +204800k threshold.
  truncate -s $((210 * 1024 * 1024)) \
    "$HOME_DIR/Library/CloudStorage/TestProvider/bigfile.bin"
  truncate -s $((205 * 1024 * 1024)) \
    "$HOME_DIR/Library/Mobile Documents/com~apple~CloudDocs/notes.bin"
  STUB_DIR="$VOL_WORKDIR/stub"
  mkdir -p "$STUB_DIR"
  FP_LOG="$VOL_WORKDIR/fileproviderctl.log"
  : > "$FP_LOG"
  cat > "$STUB_DIR/fileproviderctl" << 'EOF'
#!/bin/sh
log=${FILEPROVIDERCTL_LOG:?}
printf '%s\n' "$#" >> "$log"
for arg in "$@"; do
  printf '%s\n' "$arg" >> "$log"
done
exit 0
EOF
  chmod +x "$STUB_DIR/fileproviderctl"
}

fill_volume() {
  local root_src mnt_src avail root_avail
  if ! mountpoint -q "$VOL_MNT"; then
    note "refusing to fill a path that is not a mount: $VOL_MNT"
    exit 2
  fi
  root_src=$(df -kP / | awk 'NR==2 {print $1}')
  mnt_src=$(df -kP "$VOL_MNT" | awk 'NR==2 {print $1}')
  if [[ "$root_src" == "$mnt_src" ]]; then
    note "refusing to fill the root filesystem"
    exit 2
  fi
  dd if=/dev/zero of="$VOL_MNT/.filler" bs=4096 status=none || true
  avail=$(df -kP "$VOL_MNT" | awk 'NR==2 {print $4}')
  root_avail=$(df -kP / | awk 'NR==2 {print $4}')
  if [[ "$avail" -ne 0 ]]; then
    note "fixture volume still has ${avail}K free"
    exit 2
  fi
  if [[ "$root_avail" -lt 1048576 ]]; then
    note "root filesystem dropped below 1G free after fill"
    exit 2
  fi
  if echo probe > "$VOL_MNT/.probe" 2> /dev/null; then
    note "a new file write succeeded on the full fixture"
    exit 2
  fi
}

candidate_cloud() {
  printf '%s\n' "$HOME_DIR/Library/CloudStorage/TestProvider/bigfile.bin"
}

candidate_icloud() {
  printf '%s\n' "$HOME_DIR/Library/Mobile Documents/com~apple~CloudDocs/notes.bin"
}

# fileproviderctl invocations are stored as: argc, then that many argument lines.
evict_recorded() {
  local want="$1"
  local count arg i hit=1
  [[ -s "$FP_LOG" ]] || return 1
  while IFS= read -r count || [[ -n "${count:-}" ]]; do
    [[ -n "${count:-}" ]] || continue
    local -a args=()
    for ((i = 0; i < count; i++)); do
      IFS= read -r arg || return 1
      args+=("$arg")
    done
    if [[ "${args[0]:-}" == "evict" && "${args[1]:-}" == "$want" && "${#args[@]}" -eq 2 ]]; then
      hit=0
    fi
  done < "$FP_LOG"
  return "$hit"
}

show_capture() {
  local err_file="$1"
  note "exit status: $RUN_STATUS"
  if [[ -s "$err_file" ]]; then
    note "stderr:"
    sed 's/^/    /' "$err_file" | head -n 40
  fi
  if [[ -s "$FP_LOG" ]]; then
    note "fileproviderctl log:"
    sed 's/^/    /' "$FP_LOG" | head -n 40
  else
    note "fileproviderctl was not invoked"
  fi
}

run_evict() {
  local out_file="$VOL_WORKDIR/evict.out"
  local err_file="$VOL_WORKDIR/evict.err"
  env -u LOGFILE \
    HOME="$HOME_DIR" \
    TMPDIR="$VOL_MNT/tmp" \
    PATH="$STUB_DIR:/usr/bin:/bin" \
    FILEPROVIDERCTL_LOG="$FP_LOG" \
    bash "$ROOT/cloudspace_evict.sh" --apply > "$out_file" 2> "$err_file"
  RUN_STATUS=$?
  RUN_ERR="$err_file"
  RUN_OUT="$out_file"
}

expect_both_evicted() {
  local label="$1"
  local ok=0
  if [[ "$RUN_STATUS" -ne 0 ]]; then
    note "$label: script exited $RUN_STATUS, expected 0"
    ok=1
  fi
  if ! evict_recorded "$(candidate_cloud)"; then
    note "$label: fileproviderctl evict was not called for the CloudStorage file"
    ok=1
  fi
  if ! evict_recorded "$(candidate_icloud)"; then
    note "$label: fileproviderctl evict was not called for the iCloud file"
    ok=1
  fi
  if [[ -f "$(candidate_cloud)" && -f "$(candidate_icloud)" ]]; then
    :
  else
    note "$label: a candidate file disappeared"
    ok=1
  fi
  if [[ "$ok" -eq 0 ]]; then
    pass "$label"
  else
    show_capture "$RUN_ERR"
    fail "$label"
  fi
}

test_happy_path_evicts() {
  new_volume
  run_evict
  expect_both_evicted "free volume: --apply evicts both materialized candidates"
}

test_opening_log_enospc_still_evicts() {
  new_volume
  fill_volume
  if [[ -e "$HOME_DIR/Library/Logs/cloudspace-evict.log" ]]; then
    note "precondition failed: log file already exists"
    exit 2
  fi
  run_evict
  expect_both_evicted "full volume: opening log write cannot skip eviction"
}

test_log_slack_list_write_enospc_still_evicts() {
  new_volume
  local log="$HOME_DIR/Library/Logs/cloudspace-evict.log"
  printf 'seed\n' > "$log"
  local size
  size=$(stat -c '%s' "$log")
  if ((size % 4096 == 0)); then
    note "precondition failed: seed log consumes a whole block"
    exit 2
  fi
  fill_volume
  if ! printf '%0200d\n' 1 >> "$log"; then
    note "precondition failed: short append did not fit in the log's last block"
    exit 2
  fi
  run_evict
  expect_both_evicted "full volume: eviction continues when the size list cannot be written"
}

test_guard_reaches_evict_on_full_home() {
  new_volume
  cp "$ROOT/diskspace_guard.sh" "$ROOT/cloudspace_evict.sh" "$HOME_DIR/bin/"
  chmod +x "$HOME_DIR/bin/diskspace_guard.sh" "$HOME_DIR/bin/cloudspace_evict.sh"
  fill_volume
  local out_file="$VOL_WORKDIR/guard.out"
  local err_file="$VOL_WORKDIR/guard.err"
  # This host has far more than 60GB free on /, so the threshold is raised to
  # force the same branch the LaunchAgent takes when free space is below 60GB.
  # Trash and caches exist and are empty. tmutil and osascript are absent, so
  # those steps skip. The two sleeps in the guard make this case take ~10s.
  env -u LOGFILE \
    HOME="$HOME_DIR" \
    TMPDIR="$VOL_MNT/tmp" \
    PATH="$STUB_DIR:/usr/bin:/bin" \
    FILEPROVIDERCTL_LOG="$FP_LOG" \
    bash "$HOME_DIR/bin/diskspace_guard.sh" \
    --threshold-gb 999999 \
    --percent-free 101 \
    > "$out_file" 2> "$err_file"
  RUN_STATUS=$?
  RUN_ERR="$err_file"
  # The guard already ignores its own log failures. The requirement is that
  # the eviction it starts still calls fileproviderctl.
  local child_status="$RUN_STATUS"
  RUN_STATUS=0
  if [[ "$child_status" -ne 0 ]]; then
    note "diskspace_guard.sh exited $child_status"
    show_capture "$RUN_ERR"
    fail "guard on a full home volume still evicts materialized cloud files"
    return
  fi
  expect_both_evicted "guard on a full home volume still evicts materialized cloud files"
}

test_report_survives_log_enospc() {
  new_volume
  mkdir -p "$HOME_DIR/Library/CloudStorage/Dropbox/docs"
  printf 'synced\n' > "$HOME_DIR/Library/CloudStorage/Dropbox/docs/a.txt"
  fill_volume
  local out_file="$VOL_WORKDIR/report.out"
  local err_file="$VOL_WORKDIR/report.err"
  env -u LOGFILE \
    HOME="$HOME_DIR" \
    PATH="/usr/bin:/bin" \
    bash "$ROOT/cloudspace_report.sh" > "$out_file" 2> "$err_file"
  RUN_STATUS=$?
  RUN_ERR="$err_file"
  local ok=0
  local row="Dropbox,$HOME_DIR/Library/CloudStorage/Dropbox,"
  if [[ "$RUN_STATUS" -ne 0 ]]; then
    note "report exited $RUN_STATUS, expected 0"
    ok=1
  fi
  if ! grep -F -q -- "$row" "$out_file"; then
    note "report stdout is missing $row"
    ok=1
  fi
  if [[ "$ok" -eq 0 ]]; then
    pass "full volume: cloud footprint report still lists Dropbox"
  else
    show_capture "$RUN_ERR"
    if [[ -s "$out_file" ]]; then
      note "stdout:"
      sed 's/^/    /' "$out_file" | head -n 20
    fi
    fail "full volume: cloud footprint report still lists Dropbox"
  fi
}

require_tools
test_happy_path_evicts
test_opening_log_enospc_still_evicts
test_log_slack_list_write_enospc_still_evicts
test_guard_reaches_evict_on_full_home
test_report_survives_log_enospc

if [[ "$failures" -eq 0 ]]; then
  printf 'all checks passed\n'
  exit 0
fi
printf '%s check(s) failed\n' "$failures"
exit 1
