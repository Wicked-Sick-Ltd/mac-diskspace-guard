# Repository Guidelines

## Project Structure

A launchagent and script to check for disk space running out and take remedial action.

- Key files: `cloudspace_evict.sh`, `cloudspace_report.sh`, `diskspace_guard.sh`.

## Development and Validation

Run commands from the repository root unless the component documentation says otherwise. Configure local dependencies and test services before application tests.

- `bash -n cloudspace_evict.sh` — check shell syntax without running operational actions.

## Cloud agent environment

Cloud Agent VMs are Linux. `.cursor/install.sh` installs `shellcheck`, `shfmt`, `bats`, and `plistutil` for editing, linting, and syntax checks.

`make install`, `make install-cloud`, and `make uninstall` call `launchctl` and write into `~/bin` and `~/Library/LaunchAgents`. Those steps are macOS-only and cannot run on the Linux VM. Do not execute `diskspace_guard.sh`, `cloudspace_evict.sh`, or `cloudspace_report.sh` there: they can delete files or evict cloud data. Use `bash -n`, `shellcheck -x`, and `shfmt -d -i 2 -ci -sr -bn .` only. No secret environment variables are required.

## Coding and Testing

Match the indentation and naming of neighboring files; avoid unrelated reformatting. Use the checks documented in the README and component directories; do not claim an automated suite exists without verifying it. Keep changes focused and follow existing test filenames. Add regression coverage for behavior changes, using isolated fixtures instead of live customer data. For documentation-only edits, verify commands, local links, and `git diff --check`.

## Working Agreement

Read `CONTRIBUTING.md` and `SECURITY.md` before contributing. Honor directory-specific agent instructions. Preserve existing local changes and use a separate branch or worktree when other work is in progress. Keep credentials, private datasets, and generated artifacts out of commits. Deployment, publishing, and live service changes require authorization for that environment.

Use concise commit subjects consistent with recent history (for example, `docs: clarify setup`). Pull requests should explain the change, link relevant issues, and record validation results and any skipped checks. Include screenshots when user-visible behavior changes.

## Licensing

MIT licensed; see [LICENCE](LICENCE). Preserve third-party notices.
