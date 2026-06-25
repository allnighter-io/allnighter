#!/usr/bin/env bash
# Detached lab loop — survives IDE session end. Resumes partial manifests.
set -euo pipefail
cd "$(dirname "$0")/../.."

export WRITER_SKILL="${WRITER_SKILL:-bug_packet_writer_v4}"
export WRITER_TAG="${WRITER_TAG:-writer_v4}"

exec python3 scripts/team_lab/spawn_lab_daemon.py
