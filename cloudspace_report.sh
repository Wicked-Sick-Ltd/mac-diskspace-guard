#!/usr/bin/env bash
set -euo pipefail

LOGFILE="${LOGFILE:-$HOME/Library/Logs/cloudspace-report.log}"
TS="$(date '+%Y-%m-%d %H:%M:%S')"
# Log appends are best-effort: LOGFILE usually sits on the volume being
# reported on, which may have no free blocks left. A failed open must not
# abort the report.
append_log() {
  { printf '%s' "$1" >> "$LOGFILE"; } 2> /dev/null || true
}
emit() {
  printf '%s\n' "$1" || true
  append_log "$1"$'\n'
}
log() { emit "$TS $*"; }

# Common cloud locations on modern macOS (File Provider)
ICLOUD="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
CLOUDSTORAGE="$HOME/Library/CloudStorage" # Dropbox, Google Drive, OneDrive (new)
DROPBOX_GUESS="$HOME/Library/CloudStorage/Dropbox"

HDR="Provider,Path,On-Disk (GB),Items"
emit "$HDR"

# du echoes the path, which may span several lines, and exits non-zero when a
# subdirectory is unreadable. Keep only a leading numeric size: an empty or
# non-numeric result must not abort the report or be evaluated by $(( )).
du_kb() {
  local kb=""
  kb=$(du -sk "$1" 2> /dev/null | awk 'NR == 1 { print $1 }') || true
  [[ $kb =~ ^[0-9]+$ ]] || kb=0
  printf '%s\n' "$kb"
}

report_dir() {
  local name="$1"
  local path="$2"
  if [[ -d "$path" ]]; then
    # On-disk footprint (materialized bytes). Fast estimate: du -sk
    local kb items
    kb=$(du_kb "$path")
    items=$(find "$path" -xdev -type f -print 2> /dev/null | wc -l | tr -d ' ')
    local gb=$((kb / 1024 / 1024))
    emit "$name,$path,$gb,$items"
  fi
}

report_dir "iCloud" "$ICLOUD"
report_dir "Dropbox" "$DROPBOX_GUESS"
# Provider folder names come from account/organization names and may contain
# spaces, glob characters or newlines: keep each path whole (NUL-delimited).
while IFS= read -r -d '' p; do
  report_dir "GoogleDrive" "$p"
done < <(find "$CLOUDSTORAGE" -mindepth 1 -maxdepth 1 -type d -iname '*GoogleDrive*' -print0 2> /dev/null)
while IFS= read -r -d '' p; do
  report_dir "OneDrive" "$p"
done < <(find "$CLOUDSTORAGE" -mindepth 1 -maxdepth 1 -type d -iname '*OneDrive*' -print0 2> /dev/null)

# Also enumerate all providers under CloudStorage (covers any additional accounts)
if [[ -d "$CLOUDSTORAGE" ]]; then
  while IFS= read -r -d '' d; do
    [[ "$d" == "$DROPBOX_GUESS" ]] && continue
    [[ "$d" == "$ICLOUD" ]] && continue
    append_log "FileProvider,$d,"
    kb=$(du_kb "$d")
    gb=$((kb / 1024 / 1024))
    items=$(find "$d" -xdev -type f -print 2> /dev/null | wc -l | tr -d ' ')
    emit "$gb,$items"
  done < <(find "$CLOUDSTORAGE" -mindepth 1 -maxdepth 1 -type d -print0 2> /dev/null)
fi

# Mountain Duck mounts typically appear in /Volumes/<Name>
if mount | grep -qi "mountainduck"; then
  log "Mountain Duck mounts detected:"
fi

while IFS= read -r -d '' vol; do
  # A stale or disconnected mount makes df fail. That must not abort the report.
  vol_line=$(df -H "$vol" 2> /dev/null | awk 'NR==2{printf "  %s — Used:%s Free:%s Use%%:%s\n",$6,$3,$4,$5}') || true
  if [[ -n "$vol_line" ]]; then
    emit "$vol_line"
  fi
done < <(find /Volumes -mindepth 1 -maxdepth 1 -type d -print0 2> /dev/null)

exit 0
