# mac-diskspace-guard

> 🖥️ macOS LaunchAgent + script to keep an eye on free disk space and trigger cleanup before things grind to a halt.  
> No `sudo` required — everything runs as your user.

---

## ✨ Features
- 🚨 Warns when free disk space drops below a threshold (GB or %).  
- 🗑️ Optionally runs cleanup steps (Time Machine thinning, CleanMyMac X, etc.).  
- 🔔 macOS notifications + log file at `~/Library/Logs/diskspace-guard.log`.  
- ⚙️ Configurable via environment variables and LaunchAgent arguments.  

---

## 📜 Script: `diskspace-guard.sh`
Save this file to:  
```bash
~/bin/diskspace_guard.sh
````

*(or another path you prefer; just keep it consistent with the plist)*

---

## ⚙️ LaunchAgent: `com.craig.diskspace-guard.plist`

Save this file to:

```bash
~/Library/LaunchAgents/com.craig.diskspace-guard.plist
```

If you saved the script somewhere else, update the `ProgramArguments` path accordingly.

---

## 🚀 Install & Load

1. **Put the files in place**

   ```bash
   mkdir -p ~/Library/LaunchAgents
   # Save the plist to ~/Library/LaunchAgents
   # Save the script to ~/bin
   ```

2. **Load the agent**

   ```bash
   launchctl unload ~/Library/LaunchAgents/com.craig.diskspace-guard.plist 2>/dev/null || true
   launchctl load ~/Library/LaunchAgents/com.craig.diskspace-guard.plist
   ```

3. **(Optional) Kick it right now for a test**

   ```bash
   bash -lc '~/bin/diskspace_guard.sh --threshold-gb 9999 --percent-free 101'
   ```

   You should see:

   * a macOS notification, and
   * a log entry in `~/Library/Logs/diskspace-guard.log`.

   Afterwards, revert your thresholds in the plist (or wait for the next scheduled run).

---

## 🔧 Configuration & Tuning

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

## 📄 License

MIT — use, modify, and share freely.
Contributions welcome! 🎉

<!-- repository-guidance:begin -->
## Contributing and agent guidance

- [Contributor guide](CONTRIBUTING.md): development workflow and validation.
- [Agent instructions](AGENTS.md): shared guidance for Codex and other coding agents.
- [Security policy](SECURITY.md): private vulnerability reporting.

## Repository license

MIT licensed; see [LICENCE](LICENCE). Preserve third-party notices.
<!-- repository-guidance:end -->
