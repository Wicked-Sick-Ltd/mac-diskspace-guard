#!/usr/bin/env bash
# Spec for cloudspace_evict.sh on a volume that cannot absorb its bookkeeping.
#
# While the bug is present these tests fail: a full data volume makes the
# script exit before fileproviderctl evicts anything. After the fix they pass:
# the largest candidates are still evicted when the log, the temp list, or a
# later size lookup cannot be written or completed.
#
# cloudspace_report.sh is not covered. It only reports footprint; it does not
# build an eviction list or call fileproviderctl.
#
# Run from anywhere:
#   bash tests/full_volume_evicts_largest.sh

set -u

main() {
  REPO=$(cd "$(dirname "$0")/.." && pwd)
  EVICT="$REPO/cloudspace_evict.sh"
  GUARD="$REPO/diskspace_guard.sh"
  MIN_SIZE_K=$((200 * 1024))
  BASE_SIZE=$((200 * 1024 * 1024 + 1))
  PAGE=4096
  failures=0

  avail_bytes() {
    df -B1 "$1" | awk 'NR==2 { print $4 }'
  }

  # Fill the volume, then free exactly `want` bytes (a multiple of the page size,
  # or zero). Sparse candidates do not consume this budget; only real writes do.
  leave_free_bytes() {
    local vol="$1"
    local want="$2"
    local filler="$vol/filler"
    local size avail

    python3 - "$filler" "$PAGE" << 'PY'
import os
import sys

path, page = sys.argv[1], int(sys.argv[2])
block = b"\0" * page
with open(path, "wb", buffering=0) as handle:
    while True:
        try:
            handle.write(block)
        except OSError:
            break
PY
    size=$(stat -c '%s' "$filler")
    while [[ "$(avail_bytes "$vol")" -lt "$want" ]]; do
      size=$((size - PAGE))
      if [[ "$size" -lt 0 ]]; then
        echo "could not free ${want} bytes on $vol" >&2
        return 1
      fi
      truncate -s "$size" "$filler"
    done
    avail=$(avail_bytes "$vol")
    if [[ "$avail" -ne "$want" ]]; then
      echo "left ${avail} bytes free on $vol, wanted ${want}" >&2
      return 1
    fi
  }

  install_fileproviderctl() {
    local bin_dir="$1"
    local calls="$2"
    mkdir -p "$bin_dir"
    cat > "$bin_dir/fileproviderctl" << EOF
#!/bin/bash
printf '%s\n' "\$*" >> $(printf '%q' "$calls")
exit 0
EOF
    chmod +x "$bin_dir/fileproviderctl"
  }

  # Mirror of the predicates in cloudspace_evict.sh. Sizes are assigned so the
  # files find returns last are the largest: a partial prefix of the walk is
  # not the top 50.
  plant_sized_candidates() {
    local home="$1"
    local count="$2"
    local dir="$home/Library/CloudStorage/Dropbox/shared"
    local -n _expect="$3"
    local -a _order
    local i path pos line

    mkdir -p "$dir" "$home/Library/Logs" "$home/Library/Mobile Documents/com~apple~CloudDocs"
    i=0
    while [[ "$i" -lt "$count" ]]; do
      truncate -s "$BASE_SIZE" "$(printf '%s/plant-%03d.bin' "$dir" "$i")"
      i=$((i + 1))
    done
    # Below the script's -size +204800k cutoff. Must never be evicted.
    truncate -s $((100 * 1024 * 1024)) "$dir/small.bin"

    mapfile -d '' _order < <(find "$dir" -xdev -type f \
      -not -path "$home/Library/CloudStorage/.*Caches" \
      -not -path "$home/Library/Mobile Documents/com~apple~CloudDocs/Important" \
      -size +"${MIN_SIZE_K}"k -print0)
    if [[ "${#_order[@]}" -gt 0 && -z "${_order[-1]}" ]]; then
      unset '_order[-1]'
    fi

    if [[ "${#_order[@]}" -ne "$count" ]]; then
      echo "find selected ${#_order[@]} candidates, wanted $count" >&2
      return 1
    fi

    pos=0
    for path in "${_order[@]}"; do
      truncate -s $((BASE_SIZE + pos * PAGE)) "$path"
      pos=$((pos + 1))
    done

    _expect=()
    while IFS= read -r line; do
      _expect+=("${line#* }")
    done < <(
      for path in "${_order[@]}"; do
        stat -c '%s %n' "$path"
      done | sort -n | tail -n 50
    )
    if [[ "${#_expect[@]}" -ne 50 ]]; then
      echo "oracle produced ${#_expect[@]} paths" >&2
      return 1
    fi
  }

  assert_evicted() {
    local calls="$1"
    local stdout="$2"
    local stderr="$3"
    local status="$4"
    shift 4
    local -a expect=("$@")
    local got_n expect_n

    if [[ "$status" -ne 0 ]]; then
      echo "exit status $status" >&2
      echo "--- stdout ---" >&2
      cat "$stdout" >&2 || true
      echo "--- stderr ---" >&2
      cat "$stderr" >&2 || true
      return 1
    fi

    expect_n=${#expect[@]}
    got_n=$(grep -c . "$calls" 2> /dev/null || true)
    if [[ "$got_n" -ne "$expect_n" ]]; then
      echo "fileproviderctl calls: $got_n, want $expect_n" >&2
      echo "--- calls ---" >&2
      cat "$calls" >&2 || true
      echo "--- stderr ---" >&2
      cat "$stderr" >&2 || true
      return 1
    fi

    local path
    : > "$calls.want"
    for path in "${expect[@]}"; do
      printf 'evict %s\n' "$path" >> "$calls.want"
    done
    if ! sort "$calls" > "$calls.got.sorted"; then
      return 1
    fi
    if ! sort "$calls.want" > "$calls.want.sorted"; then
      return 1
    fi
    if ! diff -u "$calls.want.sorted" "$calls.got.sorted"; then
      echo "--- stderr ---" >&2
      cat "$stderr" >&2 || true
      return 1
    fi
  }

  new_volume() {
    local vol
    vol=$(mktemp -d /tmp/evict-vol.XXXXXX)
    mount -t tmpfs -o size=32m tmpfs "$vol"
    printf '%s\n' "$vol"
  }

  run_case() {
    local name="$1"
    shift
    echo "== $name =="
    # Subshell so a RETURN trap and its mounts stay inside the case.
    if (
      "$@"
    ); then
      echo "PASS $name"
    else
      echo "FAIL $name" >&2
      failures=$((failures + 1))
    fi
  }

  # Opening log fits; the candidate-list append does not. The largest files are
  # last in find order, so keeping only a prefix of the walk evicts the wrong set.
  test_candidate_list_enospc() {
    local vol home record calls stdout stderr bin_dir
    local -a expect
    vol=$(new_volume) || return 1
    trap 'umount "$vol" 2>/dev/null || true; rm -rf "$vol"' RETURN
    home="$vol/home"
    record=$(mktemp -d /tmp/evict-record.XXXXXX)
    calls="$record/calls"
    stdout="$record/stdout"
    stderr="$record/stderr"
    bin_dir="$record/bin"
    : > "$calls"
    plant_sized_candidates "$home" 80 expect || return 1
    install_fileproviderctl "$bin_dir" "$calls"
    mkdir -p "$home/tmp"
    leave_free_bytes "$vol" "$PAGE" || return 1
    local status=0
    env HOME="$home" TMPDIR="$home/tmp" PATH="$bin_dir:/usr/bin:/bin" \
      bash "$EVICT" --apply > "$stdout" 2> "$stderr" || status=$?
    assert_evicted "$calls" "$stdout" "$stderr" "$status" "${expect[@]}" || return 1
  }

  # No free bytes at all: the log tee fails before find. Eviction must still run.
  test_log_enospc() {
    local vol home record calls stdout stderr bin_dir
    local -a expect
    vol=$(new_volume) || return 1
    trap 'umount "$vol" 2>/dev/null || true; rm -rf "$vol"' RETURN
    home="$vol/home"
    record=$(mktemp -d /tmp/evict-record.XXXXXX)
    calls="$record/calls"
    stdout="$record/stdout"
    stderr="$record/stderr"
    bin_dir="$record/bin"
    : > "$calls"
    plant_sized_candidates "$home" 80 expect || return 1
    install_fileproviderctl "$bin_dir" "$calls"
    mkdir -p "$home/tmp"
    leave_free_bytes "$vol" 0 || return 1
    local status=0
    env HOME="$home" TMPDIR="$home/tmp" PATH="$bin_dir:/usr/bin:/bin" \
      bash "$EVICT" --apply > "$stdout" 2> "$stderr" || status=$?
    assert_evicted "$calls" "$stdout" "$stderr" "$status" "${expect[@]}" || return 1
  }

  # A later size lookup failing must not discard the largest candidates already
  # found. The stand-in calls /usr/bin/stat for every other path.
  test_stat_error() {
    local vol home record calls stdout stderr bin_dir dir
    local -a expect
    vol=$(new_volume) || return 1
    trap 'umount "$vol" 2>/dev/null || true; rm -rf "$vol"' RETURN
    home="$vol/home"
    record=$(mktemp -d /tmp/evict-record.XXXXXX)
    calls="$record/calls"
    stdout="$record/stdout"
    stderr="$record/stderr"
    bin_dir="$record/bin"
    : > "$calls"
    plant_sized_candidates "$home" 60 expect || return 1
    dir="$home/Library/CloudStorage/Dropbox/shared"
    # Smallest candidate: in the walk, not in the top 50.
    truncate -s $((200 * 1024 * 1024 + 1)) "$dir/stat-fail.bin"
    install_fileproviderctl "$bin_dir" "$calls"
    cat > "$bin_dir/stat" << 'EOF'
#!/bin/bash
for arg in "$@"; do
  if [[ "$arg" == *"/stat-fail.bin" ]]; then
    exit 1
  fi
done
exec /usr/bin/stat "$@"
EOF
    chmod +x "$bin_dir/stat"
    mkdir -p "$home/tmp"
    local status=0
    env HOME="$home" TMPDIR="$home/tmp" PATH="$bin_dir:/usr/bin:/bin" \
      bash "$EVICT" --apply > "$stdout" 2> "$stderr" || status=$?
    assert_evicted "$calls" "$stdout" "$stderr" "$status" "${expect[@]}" || return 1
  }

  # diskspace_guard.sh reaches eviction only by executing cloudspace_evict.sh.
  # Its "|| true" must not be the only thing that runs: the largest files are
  # still handed to fileproviderctl when the data volume is full.
  test_guard_launches_evict() {
    local vol home record calls stdout stderr bin_dir
    local -a expect
    vol=$(new_volume) || return 1
    trap 'umount "$vol" 2>/dev/null || true; rm -rf "$vol"' RETURN
    home="$vol/home"
    record=$(mktemp -d /tmp/evict-record.XXXXXX)
    calls="$record/calls"
    stdout="$record/stdout"
    stderr="$record/stderr"
    bin_dir="$record/bin"
    : > "$calls"
    plant_sized_candidates "$home" 80 expect || return 1
    install_fileproviderctl "$bin_dir" "$calls"
    mkdir -p "$home/tmp" "$home/bin"
    cp "$EVICT" "$home/bin/cloudspace_evict.sh"
    chmod +x "$home/bin/cloudspace_evict.sh"
    leave_free_bytes "$vol" "$PAGE" || return 1
    local status=0
    env HOME="$home" TMPDIR="$home/tmp" PATH="$bin_dir:/usr/bin:/bin" \
      bash "$GUARD" \
      --threshold-gb 1000000 \
      --percent-free 101 \
      --no-cleanmymac --no-tm --no-caches --no-trash --no-xcode \
      --logfile "$record/guard.log" \
      > "$stdout" 2> "$stderr" || status=$?
    if [[ "$status" -ne 0 ]]; then
      echo "diskspace_guard.sh exit status $status" >&2
      cat "$stderr" >&2 || true
      return 1
    fi
    # The guard swallows the evict script's status. The calls file is the signal.
    assert_evicted "$calls" "$stdout" "$stderr" 0 "${expect[@]}" || return 1
  }

  run_case candidate_list_write_error_still_evicts_largest test_candidate_list_enospc
  run_case log_write_error_still_evicts_largest test_log_enospc
  run_case stat_error_still_evicts_largest test_stat_error
  run_case diskspace_guard_still_evicts_largest_when_volume_is_full test_guard_launches_evict

  if [[ "$failures" -ne 0 ]]; then
    echo "$failures test(s) failed" >&2
    exit 1
  fi
  echo "all tests passed"
}

if [[ "${EVICT_TEST_INNER:-}" != 1 ]]; then
  exec unshare --mount --user --map-root-user \
    env EVICT_TEST_INNER=1 bash "$0"
else
  main
fi
