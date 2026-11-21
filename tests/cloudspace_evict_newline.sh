#!/usr/bin/env bash
# Regression test: cloudspace_evict.sh must keep each candidate file path whole.
# Candidates are streamed and kept in memory (the top 50), not written out as
# size<TAB>path lines. A newline in a synced file name must still be one path
# passed to fileproviderctl, and must not be evaluated by $(( )).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/cloudspace_evict.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fake_home="$tmp/home"
cloud="$fake_home/Library/CloudStorage/OneDrive-Acme"
evicted="$tmp/evicted"
mkdir -p "$tmp/bin" "$cloud"
: > "$evicted"

cat > "$tmp/bin/fileproviderctl" << EOF
#!/usr/bin/env bash
if [[ "\$1" == "evict" ]]; then printf '%s\0' "\$2" >> "$evicted"; fi
exit 0
EOF
chmod +x "$tmp/bin/fileproviderctl"

# shellcheck disable=SC2016
names=(
  "plain.bin"
  $'split\n+i[$(touch${IFS}PWNED)]'
  $'other\n12345\tplain.bin'
)
for n in "${names[@]}"; do
  # 210 MiB, above the 200 MiB eviction threshold. dd is on macOS and Linux;
  # truncate is not part of stock macOS.
  dd if=/dev/zero of="$cloud/$n" bs=1 count=0 seek=220200960 2> /dev/null
done

failures=0
(
  cd "$tmp"
  HOME="$fake_home" LOGFILE="$tmp/evict.log" PATH="$tmp/bin:$PATH" \
    bash "$SCRIPT" --apply > /dev/null 2>&1
) || {
  echo "FAIL: cloudspace_evict.sh exited non-zero"
  failures=$((failures + 1))
}

if [[ -e "$tmp/PWNED" ]]; then
  echo "FAIL: file name text was executed as a command"
  failures=$((failures + 1))
fi

got=()
while IFS= read -r -d '' p; do
  got+=("$p")
done < "$evicted"

for p in "${got[@]}"; do
  ok=0
  for n in "${names[@]}"; do
    [[ "$p" == "$cloud/$n" ]] && ok=1
  done
  if [[ "$ok" -eq 0 ]]; then
    echo "FAIL: evicted a path that is not a candidate: $(printf '%q' "$p")"
    failures=$((failures + 1))
  fi
done

for n in "${names[@]}"; do
  count=0
  for p in "${got[@]}"; do
    [[ "$p" == "$cloud/$n" ]] && count=$((count + 1))
  done
  if [[ "$count" -ne 1 ]]; then
    echo "FAIL: expected one eviction of $(printf '%q' "$cloud/$n"), got $count"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
