#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
case "${1:-}" in
  structural)
    bash "$ROOT/scripts/check_architecture_policy.sh"
    [[ ! -e "$ROOT/Packages/AllnighterCore/Sources/AllnighterCore/ProjectMirror.swift" ]]
    [[ ! -e "$ROOT/Packages/AllnighterCore/Sources/AllnighterEngine/PanelSeatIsolation.swift" ]]
    rg -q -F 'let service = RunService(' "$ROOT/Packages/AllnighterCore/Sources/AllnighterCLI/RunCLI.swift"
    rg -q -F 'await service.run(request' "$ROOT/Packages/AllnighterCore/Sources/AllnighterCLI/RunCLI.swift"
    ! rg -q -F 'ResidentExecutionOperation' "$ROOT/Packages/AllnighterCore/Sources/AllnighterCLI/RunCLI.swift"
    echo "code-red structural: direct RunService route and alternate-root deletion verified"
    ;;
  live-direct|live-resident)
    echo "code-red: live vendor proof is not available in CR-S01; run structural mode only" >&2
    exit 2
    ;;
  *)
    echo "usage: $0 structural|live-direct|live-resident" >&2
    exit 2
    ;;
esac
