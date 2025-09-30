# mac-diskspace-guard

Early warning + auto-cleanup for macOS so you **don’t** hit zero free disk space.

- Warn with iStat Menus (recommended) or just use this agent’s thresholds
- Auto-tidy **Trash, caches, Xcode DerivedData**
- Thin **Time Machine local snapshots**
- Optionally trigger **CleanMyMac X** Smart Cleanup
- (When still tight) **Evict** largest *materialized* cloud files (iCloud, Dropbox, Google Drive, OneDrive) via `fileproviderctl`
- Optional hourly **cloud footprint report** (iCloud/Dropbox/GDrive/OneDrive + `/Volumes` mounts like Mountain Duck)

---

## Quick Start

**Requirements**
- macOS 12+ (for `fileproviderctl`-based eviction)
- Optional: iStat Menus for nice UI alerts
- Optional: CleanMyMac X (the guard will try to run Smart Cleanup)

**Permissions**
- No `sudo` required. The scripts run as your user.
- First run from Terminal may prompt access; granting Terminal **Full Disk Access** helps on some setups.

**Apple Silicon**
- Homebrew is usually `/opt/homebrew`. The LaunchAgent sets PATH accordingly.

---

## Install

```bash
mkdir -p ~/bin ~/Library/LaunchAgents ~/Library/Logs
cp diskspace_guard.sh ~/bin/
chmod +x ~/bin/diskspace_guard.sh
cp com.craig.diskspace-guard.plist ~/Library/LaunchAgents/

# load / reload
launchctl unload ~/Library/LaunchAgents/com.craig.diskspace-guard.plist 2>/dev/null || true
launchctl load  ~/Library/LaunchAgents/com.craig.diskspace-guard.plist

# (optional) force a test run
bash -lc '~/bin/diskspace_guard.sh --threshold-gb 9999 --percent-free 101'

