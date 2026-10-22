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
make install
# Optional: install cloud eviction & hourly cloud footprint report
make install-cloud
```

Or manually:

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
```

---

## Configuration & Tuning

* **Change thresholds**
  Edit the plist line with `--threshold-gb` and/or `--percent-free`, then reload:

  ```bash
  launchctl unload ~/Library/LaunchAgents/com.craig.diskspace-guard.plist
  launchctl load ~/Library/LaunchAgents/com.craig.diskspace-guard.plist
  ```

* **Disable any cleanup step**
  Set the corresponding `RUN_…=0` env var at the top of the script,
  or add it into the `ProgramArguments` command, e.g.:

  ```bash
  RUN_CLEANMYMAC=0 ~/bin/diskspace_guard.sh …
  ```

* **No sudo prompts**
  LaunchAgents can’t use `sudo`. Everything runs safely as your user.

* **Time Machine thinning**
  Only happens if `tmutil` is available.
  It won’t touch your external backup drive — only trims local snapshots.

* **CleanMyMac X run**
  The `--scan --clean` args are best-effort.
  If unsupported, the app is still opened to let its background agent do its job.
  *(Optional: swap this to an AppleScript that tells CleanMyMac X to run Smart Scan directly.)*

---

<!-- repository-guidance:begin -->
## Contributing and agent guidance

- [Contributor guide](CONTRIBUTING.md): development workflow and validation.
- [Agent instructions](AGENTS.md): shared guidance for Codex and other coding agents.
- [Security policy](SECURITY.md): private vulnerability reporting.

## Repository license

MIT licensed; see [LICENCE](LICENCE). Preserve third-party notices.
<!-- repository-guidance:end -->
