#!/usr/bin/env bash
set -euo pipefail

# Config
LOGFILE="${LOGFILE:-$HOME/Library/Logs/cloudspace-evict.log}"
# Directories to scan for eviction candidates (edit as needed)
SCAN_DIRS=(
  "$HOME/Library/Mobile Documents/com~apple~CloudDocs"
  "$HOME/Library/CloudStorage"
)
# Skip these (patterns). Add project dirs you never want evicted.
SKIP_PATTERNS=(
  "/Library/CloudStorage/.*Caches"
  "/Library/Mobile Documents/com~apple~CloudDocs/Important"
)

# Candidate size threshold (bytes) — consider eviction if >= 200 MB
MIN_SIZE_BYTES=$((200 * 1024 * 1024))
# Max files to evict per run
MAX_EVICT=50

APPLY=0
if [[ "${1:-}" == "--apply" ]]; then
  APPLY=1
fi

# Logging is best-effort: LOGFILE and stdout usually sit on the volume this
# script is trying to free, so a failed write must never stop eviction.
log() {
  local line
  line="$(date '+%Y-%m-%d %H:%M:%S') $*"
  printf "%s\n" "$line" || true
  printf "%s\n" "$line" 2> /dev/null >> "$LOGFILE" || true
}

require() {
  command -v "$1" > /dev/null 2>&1 || {
    log "Missing dependency: $1"
    exit 1
  }
}

require fileproviderctl
require find
require stat

log "Starting eviction scan (min-size: $((MIN_SIZE_BYTES / 1024 / 1024))MB, max: $MAX_EVICT, apply:$APPLY)"

# Build find predicates
skip_expr=()
for pat in "${SKIP_PATTERNS[@]}"; do
  skip_expr+=(-not -path "$HOME$pat")
done

# Gather candidates (Bash 3.2-compatible null-delimited read)
CANDIDATES=()
while IFS= read -r -d '' entry; do
  CANDIDATES+=("$entry")
done < <(
  for root in "${SCAN_DIRS[@]}"; do
    [[ -d "$root" ]] || continue
    find "$root" -xdev -type f "${skip_expr[@]}" -size +"$((MIN_SIZE_BYTES / 1024))"k -print0 2> /dev/null
  done
)

if [[ ${#CANDIDATES[@]} -eq 0 ]]; then
  log "No candidates found."
  exit 0
fi

# Keep the largest MAX_EVICT candidates, sorted by size desc, in memory.
# No temp files: the volume may have no free blocks left.
TOP_SIZES=()
TOP_FILES=()
for f in "${CANDIDATES[@]}"; do
  # size in bytes (GNU/BSD stat compatibility)
  if stat -f '%z' "$f" > /dev/null 2>&1; then
    sz=$(stat -f '%z' "$f" 2> /dev/null) || continue
  else
    sz=$(stat -c '%s' "$f" 2> /dev/null) || continue
  fi
  n=${#TOP_SIZES[@]}
  if [[ $n -ge $MAX_EVICT && $sz -le ${TOP_SIZES[$((n - 1))]} ]]; then
    continue
  fi
  j=$n
  while [[ $j -gt 0 && ${TOP_SIZES[$((j - 1))]} -lt $sz ]]; do
    TOP_SIZES[j]=${TOP_SIZES[$((j - 1))]}
    TOP_FILES[j]=${TOP_FILES[$((j - 1))]}
    j=$((j - 1))
  done
  TOP_SIZES[j]=$sz
  TOP_FILES[j]=$f
  if [[ ${#TOP_SIZES[@]} -gt $MAX_EVICT ]]; then
    unset "TOP_SIZES[$MAX_EVICT]" "TOP_FILES[$MAX_EVICT]"
  fi
done

TOTAL=0
COUNT=0
i=0
while [[ $i -lt ${#TOP_SIZES[@]} ]]; do
  sz="${TOP_SIZES[$i]}"
  f="${TOP_FILES[$i]}"
  i=$((i + 1))

  # Heuristic: only attempt to evict if file seems materialized (has data fork)
  # If it's already online-only, evict will just be a no-op.
  mb=$((sz / 1024 / 1024))
  log "Candidate: ${mb}MB — $f"
  if [[ "$APPLY" -eq 1 ]]; then
    if fileproviderctl evict "$f" > /dev/null 2>&1; then
      log "  Evicted."
      TOTAL=$((TOTAL + sz))
      COUNT=$((COUNT + 1))
    else
      log "  Evict failed (maybe not a FileProvider file)."
    fi
  fi
done

if [[ "$APPLY" -eq 1 ]]; then
  log "Evicted $COUNT files, ~$((TOTAL / 1024 / 1024))MB freed (will finalize as macOS reclaims)."
else
  log "Dry-run complete. Use --apply to perform eviction."
fi

exit 0
