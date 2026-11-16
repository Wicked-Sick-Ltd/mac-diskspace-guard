#!/usr/bin/env bash
set -euo pipefail

LOGFILE="${LOGFILE:-$HOME/Library/Logs/cloudspace-report.log}"
TS="$(date '+%Y-%m-%d %H:%M:%S')"
# Log appends are best-effort: LOGFILE usually sits on the volume being
# reported on, which may have no free blocks left.
append_log() { printf "%s" "$1" 2> /dev/null >> "$LOGFILE" || true; }
emit() {
  printf "%s\n" "$1" || true
  append_log "$1"$'\n'
}
log() { emit "$TS $*"; }

# Common cloud locations on modern macOS (File Provider)
ICLOUD="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
CLOUDSTORAGE="$HOME/Library/CloudStorage" # Dropbox, Google Drive, OneDrive (new)
DROPBOX_GUESS="$HOME/Library/CloudStorage/Dropbox"
GDRIVE_GUESS=$(find "$HOME/Library/CloudStorage" -mindepth 1 -maxdepth 1 -iname '*GoogleDrive*' 2> /dev/null || true)
ONEDRIVE_GUESS=$(find "$HOME/Library/CloudStorage" -mindepth 1 -maxdepth 1 -iname '*OneDrive*' 2> /dev/null || true)

HDR="Provider,Path,On-Disk (GB),Items"
emit "$HDR"

report_dir() {
  local name="$1"
  local path="$2"
  if [[ -d "$path" ]]; then
    # On-disk footprint (materialized bytes). Fast estimate: du -sk
    local kb items
    kb=$(du -sk "$path" 2> /dev/null | awk '{print $1}')
    items=$(find "$path" -xdev -type f -print 2> /dev/null | wc -l | tr -d ' ')
    local gb=$((kb / 1024 / 1024))
    emit "$name,$path,$gb,$items"
  fi
}

report_dir "iCloud" "$ICLOUD"
report_dir "Dropbox" "$DROPBOX_GUESS"
for p in $GDRIVE_GUESS; do report_dir "GoogleDrive" "$p"; done
for p in $ONEDRIVE_GUESS; do report_dir "OneDrive" "$p"; done

# Also enumerate all providers under CloudStorage (covers any additional accounts)
if [[ -d "$CLOUDSTORAGE" ]]; then
  while IFS= read -r -d '' d; do
    [[ "$d" == "$DROPBOX_GUESS" ]] && continue
    [[ "$d" == "$ICLOUD" ]] && continue
    append_log "FileProvider,$d,"
    kb=$(du -sk "$d" 2> /dev/null | awk '{print $1}')
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
  # Try df on the mount
  vol_line=$(df -H "$vol" 2> /dev/null | awk 'NR==2{printf "  %s — Used:%s Free:%s Use%%:%s\n",$6,$3,$4,$5}')
  if [[ -n "$vol_line" ]]; then
    emit "$vol_line"
  fi
done < <(find /Volumes -mindepth 1 -maxdepth 1 -type d -print0 2> /dev/null)

exit 0
