#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
sources="$ROOT/Packages/AllnighterCore/Sources"

count_hits() { rg -l -F -- "$1" "$sources" 2>/dev/null | wc -l | tr -d ' '; }

printf 'alternate_repository_implementation_hits=%s\n' "$(count_hits ProjectMirror)"
printf 'foreground_resident_operation_hits=%s\n' "$(count_hits foregroundTeamRun)"
printf 'run_service_owner_mentions=%s\n' "$(count_hits RunService.run)"
printf 'forbidden_production_concept_hits=%s\n' "$(( $(count_hits projectMirrorId) + $(count_hits PanelSeatIsolation) + $(count_hits PanelReadOnlyArgs) ))"
