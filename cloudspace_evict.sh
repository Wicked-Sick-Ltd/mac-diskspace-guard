#!/usr/bin/env bash
set -euo pipefail

# This runs when the data volume is nearly full. Nothing it writes for
# bookkeeping (log, stdout) may abort eviction, including a vanished reader.
trap '' PIPE

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
# Paths sized per stat invocation
STAT_BATCH=256

APPLY=0
if [[ "${1:-}" == "--apply" ]]; then
  APPLY=1
fi

log() {
  local line
  line="$(date '+%Y-%m-%d %H:%M:%S') $*"
  printf '%s\n' "$line" 2> /dev/null || true
  { printf '%s\n' "$line" >> "$LOGFILE"; } 2> /dev/null || true
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

# Size in bytes (GNU/BSD stat compatibility)
if stat -f '%z' / > /dev/null 2>&1; then
  SIZE_FMT=(-f '%z')
else
  SIZE_FMT=(-c '%s')
fi

# Build find predicates
skip_expr=()
for pat in "${SKIP_PATTERNS[@]}"; do
  skip_expr+=(-not -path "$HOME$pat")
done

# Largest MAX_EVICT candidates seen so far; nothing else from the walk is kept.
TOP_SIZES=()
TOP_PATHS=()
MIN_IDX=0

consider() {
  local sz="$1" f="$2" n=${#TOP_SIZES[@]} j
  if [[ $n -lt $MAX_EVICT ]]; then
    TOP_SIZES+=("$sz")
    TOP_PATHS+=("$f")
    if [[ $n -eq 0 || $sz -lt ${TOP_SIZES[MIN_IDX]} ]]; then
      MIN_IDX=$n
    fi
    return 0
  fi
  [[ $sz -gt ${TOP_SIZES[MIN_IDX]} ]] || return 0
  TOP_SIZES[MIN_IDX]=$sz
  TOP_PATHS[MIN_IDX]=$f
  MIN_IDX=0
  for ((j = 1; j < n; j++)); do
    if [[ ${TOP_SIZES[j]} -lt ${TOP_SIZES[MIN_IDX]} ]]; then
      MIN_IDX=$j
    fi
  done
}

# Sizes one batch with a single stat; if any path in it fails, sizes them one
# at a time so a single unreadable file only drops itself.
BATCH=()
flush_batch() {
  local n=${#BATCH[@]} out sz f i
  local -a sizes=()
  [[ $n -gt 0 ]] || return 0
  if out=$(stat "${SIZE_FMT[@]}" "${BATCH[@]}" 2> /dev/null); then
    while [[ -n "$out" ]]; do
      case "$out" in
        *$'\n'*)
          sizes+=("${out%%$'\n'*}")
          out=${out#*$'\n'}
          ;;
        *)
          sizes+=("$out")
          out=
          ;;
      esac
    done
  fi
  if [[ ${#sizes[@]} -eq $n ]]; then
    for ((i = 0; i < n; i++)); do
      [[ ${sizes[i]} =~ ^[0-9]+$ ]] && consider "${sizes[i]}" "${BATCH[i]}"
    done
  else
    for f in "${BATCH[@]}"; do
      sz=$(stat "${SIZE_FMT[@]}" "$f" 2> /dev/null) || continue
      [[ $sz =~ ^[0-9]+$ ]] && consider "$sz" "$f"
    done
  fi
  BATCH=()
}

# Stream candidates (Bash 3.2-compatible null-delimited read)
while IFS= read -r -d '' entry; do
  BATCH+=("$entry")
  if [[ ${#BATCH[@]} -ge $STAT_BATCH ]]; then
    flush_batch
  fi
done < <(
  for root in "${SCAN_DIRS[@]}"; do
    [[ -d "$root" ]] || continue
    find "$root" -xdev -type f "${skip_expr[@]}" -size +"$((MIN_SIZE_BYTES / 1024))"k -print0 2> /dev/null
  done
)
flush_batch

N=${#TOP_SIZES[@]}
if [[ $N -eq 0 ]]; then
  log "No candidates found."
  exit 0
fi

# Sort the kept candidates by size desc
for ((i = 0; i < N; i++)); do
  max=$i
  for ((j = i + 1; j < N; j++)); do
    if [[ ${TOP_SIZES[j]} -gt ${TOP_SIZES[max]} ]]; then
      max=$j
    fi
  done
  if [[ $max -ne $i ]]; then
    sz=${TOP_SIZES[i]}
    f=${TOP_PATHS[i]}
    TOP_SIZES[i]=${TOP_SIZES[max]}
    TOP_PATHS[i]=${TOP_PATHS[max]}
    TOP_SIZES[max]=$sz
    TOP_PATHS[max]=$f
  fi
done

TOTAL=0
COUNT=0
for ((i = 0; i < N; i++)); do
  sz=${TOP_SIZES[i]}
  f=${TOP_PATHS[i]}

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
