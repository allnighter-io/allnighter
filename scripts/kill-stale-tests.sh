#!/usr/bin/env bash
# Kill stale AllnighterCore test runners only — never alln serve or unrelated work.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/test-guard-lib.sh disable=SC1091
source "$ROOT/scripts/lib/test-guard-lib.sh"

MAX_AGE_MINUTES=30
MAX_AGE_SECONDS_OVERRIDE=""
DRY_RUN=false

usage() {
  echo "usage: $0 [--dry-run] [--max-age-minutes N] [--max-age-seconds N]" >&2
  echo "  --max-age-seconds is a test-only override for fast Works Test iteration." >&2
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
    --max-age-seconds)
      [[ $# -ge 2 ]] || usage
      MAX_AGE_SECONDS_OVERRIDE="$2"
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
if [[ -n "$MAX_AGE_SECONDS_OVERRIDE" ]] && { ! [[ "$MAX_AGE_SECONDS_OVERRIDE" =~ ^[0-9]+$ ]] || [[ "$MAX_AGE_SECONDS_OVERRIDE" -lt 0 ]]; }; then
  echo "kill-stale-tests: --max-age-seconds must be a non-negative integer" >&2
  exit 1
fi

if [[ -n "$MAX_AGE_SECONDS_OVERRIDE" ]]; then
  max_age_seconds="$MAX_AGE_SECONDS_OVERRIDE"
else
  max_age_seconds=$((MAX_AGE_MINUTES * 60))
fi

found=0
killed=0
survived=0

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  pid="${line%% *}"
  cmdline="${line#* }"

  age=""
  if age="$(age_seconds "$pid" 2>/dev/null)"; then
    :
  else
    # Probe failed (defect E was: this silently became 0 and every process
    # looked brand new). Never do that again — an unreadable age means we
    # cannot prove the process is young, so treat it as stale-eligible.
    echo "kill-stale-tests: WARNING — could not determine age for pid=$pid; treating as stale-eligible" >&2
    age="$max_age_seconds"
  fi

  if [[ "$age" -lt "$max_age_seconds" ]]; then
    continue
  fi

  found=$((found + 1))
  if [[ "$DRY_RUN" == true ]]; then
    echo "stale pid=$pid age=${age}s: $cmdline"
    continue
  fi

  echo "killing stale pid=$pid age=${age}s: $cmdline"
  result="$(kill_pid_escalate "$pid")"
  if [[ "$result" == "survived" ]]; then
    echo "kill-stale-tests: WARNING — pid=$pid survived SIGKILL" >&2
    survived=$((survived + 1))
  else
    killed=$((killed + 1))
  fi
done < <(list_matching_pids "$$")

if [[ "$DRY_RUN" == true ]]; then
  echo "kill-stale-tests: listed $found stale runner(s) (dry-run)"
else
  echo "kill-stale-tests: killed $killed of $found stale runner(s)$( [[ "$survived" -gt 0 ]] && echo ", $survived survived SIGKILL" )"
fi

if [[ "$survived" -gt 0 ]]; then
  exit 1
fi
exit 0
