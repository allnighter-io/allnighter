#!/usr/bin/env bash
# Kill stale AllnighterCore test runners only — never alln serve or unrelated work.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAX_AGE_MINUTES=30
DRY_RUN=false

usage() {
  echo "usage: $0 [--dry-run] [--max-age-minutes N]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --max-age-minutes)
      [[ $# -ge 2 ]] || usage
      MAX_AGE_MINUTES="$2"
      shift 2
      ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

if ! [[ "$MAX_AGE_MINUTES" =~ ^[0-9]+$ ]] || [[ "$MAX_AGE_MINUTES" -lt 1 ]]; then
  echo "kill-stale-tests: --max-age-minutes must be a positive integer" >&2
  exit 1
fi

# Seconds since process start (macOS ps etime is awkward; use lstart + python).
age_seconds() {
  local pid="$1"
  python3 - "$pid" <<'PY'
import sys, time, subprocess
pid = int(sys.argv[1])
out = subprocess.check_output(["ps", "-p", str(pid), "-o", "lstart="], text=True).strip()
# Example: "Fri Jul 31 06:30:00 2026"
started = time.mktime(time.strptime(out, "%a %b %d %H:%M:%S %Y"))
print(int(time.time() - started))
PY
}

matches_pattern() {
  local cmdline="$1"
  if [[ "$cmdline" == *"alln serve"* ]] || [[ "$cmdline" == *"allnighter serve"* ]]; then
    return 1
  fi
  if [[ "$cmdline" == *"AllnighterCorePackageTests"* ]]; then
    return 0
  fi
  if [[ "$cmdline" == *"swift-test"* ]] && [[ "$cmdline" == *"AllnighterCore"* ]]; then
    return 0
  fi
  return 1
}

max_age_seconds=$((MAX_AGE_MINUTES * 60))
found=0
killed=0

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  pid="${line%% *}"
  cmdline="${line#* }"
  [[ "$pid" =~ ^[0-9]+$ ]] || continue
  [[ "$pid" -eq "$$" ]] && continue

  if ! matches_pattern "$cmdline"; then
    continue
  fi

  if ! kill -0 "$pid" 2>/dev/null; then
    continue
  fi

  age="$(age_seconds "$pid" 2>/dev/null || echo 0)"
  if [[ "$age" -lt "$max_age_seconds" ]]; then
    continue
  fi

  found=$((found + 1))
  if [[ "$DRY_RUN" == true ]]; then
    echo "stale pid=$pid age=${age}s: $cmdline"
  else
    echo "killing stale pid=$pid age=${age}s: $cmdline"
    kill -TERM "$pid" 2>/dev/null || true
    killed=$((killed + 1))
  fi
done < <(ps -axo pid=,command= 2>/dev/null || true)

if [[ "$DRY_RUN" == true ]]; then
  echo "kill-stale-tests: listed $found stale runner(s) (dry-run)"
else
  echo "kill-stale-tests: sent TERM to $killed stale runner(s)"
fi

exit 0
