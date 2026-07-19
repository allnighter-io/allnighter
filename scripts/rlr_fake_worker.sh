#!/bin/bash
# rlr_fake_worker.sh — deterministic fake worker CLI for Run Lifecycle
# Reliability (RLR-S00). A drop-in `claude`-shaped stub the AllnighterCLI
# `claude_code` driver can invoke on a curated PATH: no real model, no quota,
# fully controllable via ENVIRONMENT variables (the driver owns argv, so the
# harness cannot configure behaviour through arguments — only env).
#
# The `alln team start`/`team status`/`kill` two-process tests copy this file to
# `<fakebin>/claude`, chmod +x, and put `<fakebin>` first on PATH. It reproduces
# the field hang pattern from docs/phases/Run_Lifecycle_Reliability.md:
# a live worker child whose run status/journal disagree, and a kill that stamps
# a terminal `killed` while the worker is still alive.
#
# ---------------------------------------------------------------------------
# INTERFACE (all env vars optional; safe defaults = "block silently forever")
# ---------------------------------------------------------------------------
#   RLR_FAKE_LOG=<path>        Append one `pwd=<cwd> args=<argv>` line per
#                              invocation (worker-spawn proof; mirrors the
#                              existing ConcurrentInvocationTwoProcess fixture).
#   RLR_FAKE_EMIT=<string>     Print <string> + newline to stdout, then continue
#                              (emit a line of output on demand). Empty = silent.
#   RLR_FAKE_MARKER=<token>    Unique token embedded in this process's own argv
#                              (via `-`-prefixed no-op args) AND in the child
#                              sleep command lines, so the test can pgrep/pkill
#                              exactly its own descendants. Defaults to the pid.
#   RLR_FAKE_IGNORE_SIGTERM=1  Trap and IGNORE SIGTERM (survive a plain TERM;
#                              only SIGKILL can reap this process).
#   RLR_FAKE_SPAWN_GRANDCHILD=1  Spawn a grandchild via `setsid` so it becomes
#                              its own session/process-group leader and ESCAPES
#                              any process-group kill aimed at this worker.
#   RLR_FAKE_HANG=1            (default when RLR_FAKE_EXIT_CODE is unset) Block
#                              indefinitely (sleep + wait) — the hang pattern.
#   RLR_FAKE_SLEEP_SECONDS=<n> Duration of this worker's own blocking sleep
#                              (default 3600). Give each test a unique value so
#                              `pgrep -f "sleep <n>"` is unambiguous.
#   RLR_FAKE_GRANDCHILD_SLEEP=<n>  Grandchild sleep duration (default 3601).
#   RLR_FAKE_EXIT_CODE=<n>     When set AND RLR_FAKE_HANG!=1, exit immediately
#                              with code <n> (chosen exit code; no blocking).
#
# `--version` always short-circuits to a version banner + exit 0 so the driver's
# readiness probe succeeds without any of the above behaviour.
# ---------------------------------------------------------------------------

if [ "${1:-}" = "--version" ]; then
    echo "claude-rlr-fake 0.0.1"
    exit 0
fi

marker="${RLR_FAKE_MARKER:-$$}"

# Record the invocation (cwd + flattened argv) exactly like the existing
# two-process fixture so tests can wait for the worker to actually spawn.
if [ -n "${RLR_FAKE_LOG:-}" ]; then
    flat=$(printf '%s' "$*" | tr '\n' ' ')
    printf 'pwd=%s marker=%s args=%s\n' "$PWD" "$marker" "$flat" >> "$RLR_FAKE_LOG"
fi

# Emit a line on demand (kept off by default so a silent worker reproduces the
# "stuck at accepted / frozen heartbeat" signature).
if [ -n "${RLR_FAKE_EMIT:-}" ]; then
    printf '%s\n' "$RLR_FAKE_EMIT"
fi

# Fast-exit path: chosen exit code, no blocking.
if [ -n "${RLR_FAKE_EXIT_CODE:-}" ] && [ "${RLR_FAKE_HANG:-}" != "1" ]; then
    exit "$RLR_FAKE_EXIT_CODE"
fi

# Ignore SIGTERM if asked: a plain TERM to this process (or its group) is
# swallowed; only SIGKILL reaps it.
if [ "${RLR_FAKE_IGNORE_SIGTERM:-}" = "1" ]; then
    trap '' TERM
fi

# Spawn a grandchild in its OWN session (setsid) so a process-group kill of this
# worker never reaches it — the "live descendant survives kill" leg.
if [ "${RLR_FAKE_SPAWN_GRANDCHILD:-}" = "1" ]; then
    gc_sleep="${RLR_FAKE_GRANDCHILD_SLEEP:-3601}"
    # `setsid` detaches into a new session; the marker rides in the argv of a
    # short-lived labeller so the test can pgrep the grandchild by marker.
    setsid /bin/sh -c "exec sleep ${gc_sleep}" >/dev/null 2>&1 &
fi

# Block indefinitely on our own marked sleep. `& wait` (rather than `exec`)
# keeps the SIGTERM trap installed above in force.
worker_sleep="${RLR_FAKE_SLEEP_SECONDS:-3600}"
sleep "${worker_sleep}" &
child_pid=$!
wait "${child_pid}"
