#!/usr/bin/env bash
set -euo pipefail

LOGFILE="${LOGFILE:-$HOME/Library/Logs/cloudspace-report.log}"
TS="$(date '+%Y-%m-%d %H:%M:%S')"
log() { printf "%s %s\n" "$TS" "$*" | tee -a "$LOGFILE"; }

# Common cloud locations on modern macOS (File Provider)
ICLOUD="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
CLOUDSTORAGE="$HOME/Library/CloudStorage" # Dropbox, Google Drive, OneDrive (new)
DROPBOX_GUESS="$HOME/Library/CloudStorage/Dropbox"

HDR="Provider,Path,On-Disk (GB),Items"
printf "%s\n" "$HDR" | tee -a "$LOGFILE"

# du echoes the path, which may span several lines. Keep only the leading size:
# any path text reaching $(( )) would be evaluated as code.
du_kb() {
  local kb
  kb=$(du -sk "$1" 2> /dev/null | awk 'NR == 1 { print $1 }')
  [[ "$kb" =~ ^[0-9]+$ ]] || kb=0
  printf "%s\n" "$kb"
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
    printf "%s,%s,%s,%s\n" "$name" "$path" "$gb" "$items" | tee -a "$LOGFILE"
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
    printf "FileProvider,%s," "$d" | tee -a "$LOGFILE" > /dev/null
    kb=$(du_kb "$d")
    gb=$((kb / 1024 / 1024))
    items=$(find "$d" -xdev -type f -print 2> /dev/null | wc -l | tr -d ' ')
    printf "%s,%s\n" "$gb" "$items" | tee -a "$LOGFILE"
  done < <(find "$CLOUDSTORAGE" -mindepth 1 -maxdepth 1 -type d -print0 2> /dev/null)
fi

# Mountain Duck mounts typically appear in /Volumes/<Name>
if mount | grep -qi "mountainduck"; then
  log "Mountain Duck mounts detected:"
fi

while IFS= read -r -d '' vol; do
  # Try df on the mount
  df -H "$vol" 2> /dev/null | awk 'NR==2{printf "  %s — Used:%s Free:%s Use%%:%s\n",$6,$3,$4,$5}' | tee -a "$LOGFILE"
done < <(find /Volumes -mindepth 1 -maxdepth 1 -type d -print0 2> /dev/null)

exit 0
