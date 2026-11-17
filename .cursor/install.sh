#!/usr/bin/env bash
# Linux Cloud Agent bootstrap for mac-diskspace-guard.
# Installs lint and syntax tools only. Does not copy scripts into $HOME,
# call launchctl, or run diskspace_guard.sh, cloudspace_evict.sh, or
# cloudspace_report.sh (those can delete files or evict cloud data).
set -euo pipefail

warn() {
  printf 'WARNING: %s\n' "$*" >&2
}

if ! command -v apt-get > /dev/null 2>&1; then
  warn "apt-get is not available; shellcheck, shfmt, bats, and plistutil were not installed"
  exit 1
fi

if ! command -v sudo > /dev/null 2>&1 || ! sudo -n true > /dev/null 2>&1; then
  warn "passwordless sudo is not available; cannot install packages"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends shellcheck shfmt

install_optional() {
  local pkg="$1"
  local cmd="$2"
  if ! sudo apt-get install -y --no-install-recommends "$pkg"; then
    warn "optional package failed to install: ${pkg} (${cmd})"
    return 0
  fi
  if ! command -v "$cmd" > /dev/null 2>&1; then
    warn "optional tool not on PATH: ${cmd} (package ${pkg})"
  fi
}

# bats: no test suite in the repo yet (CI does not run it).
# plistutil / xmllint: XML plist checks. plutil is macOS-only.
install_optional bats bats
install_optional libplist-utils plistutil
install_optional libxml2-utils xmllint

# No secret environment variables are required. THRESHOLD_GB,
# THRESHOLD_FREE_PCT, LOGFILE, CLEANMYMAC_APP, and the RUN_* knobs have
# defaults in the scripts and are not read here.

if ! command -v bats > /dev/null 2>&1; then
  warn "optional tool not available: bats (no bats tests in this repo)"
fi
if ! command -v plistutil > /dev/null 2>&1; then
  warn "optional tool not available: plistutil (Linux plist check skipped)"
fi
if ! command -v xmllint > /dev/null 2>&1; then
  warn "optional tool not available: xmllint"
fi

shellcheck_version="$(shellcheck --version | awk '/^version:/ { print $2; exit }')"
shfmt_version="$(shfmt --version)"
printf 'install ok: shellcheck %s; shfmt %s\n' "$shellcheck_version" "$shfmt_version"
if command -v bats > /dev/null 2>&1; then
  printf 'bats %s\n' "$(bats --version)"
fi
if command -v plistutil > /dev/null 2>&1; then
  plist_version="$(dpkg-query -W -f='${Version}' libplist-utils 2> /dev/null || true)"
  printf 'plistutil %s\n' "${plist_version:-present}"
fi
