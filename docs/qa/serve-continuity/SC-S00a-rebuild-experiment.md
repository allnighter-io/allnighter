# SC-S00a Rebuild Experiment
Date: 2026-08-09T22:42:26Z

## 0. Pre-state
### codesign (before)
Identifier=alln-55554944120f9e82794f3e398ffb41c119082d78
Format=Mach-O thin (arm64)
CodeDirectory v=20400 size=361094 flags=0x2(adhoc) hashes=11273+7 location=embedded
Signature=adhoc
TeamIdentifier=not set

### alln binary
lrwxr-xr-x@ 1 mike  staff  74 Aug  6 05:47 /Users/mike/.local/bin/alln -> /Users/mike/Library/Developer/Allnighter/CLI/arm64-apple-macosx/debug/alln
/Users/mike/Library/Developer/Allnighter/CLI/arm64-apple-macosx/debug/alln

### serve health
{
  "activeObligationCount" : 0,
  "binaryGitSha" : "4c03d6bf6f0a1f32a54e0eb197169ae743f69941",
  "binaryVersion" : "1.0.0",
  "contractVersion" : "9.14.0",
  "daemonId" : "5c8c2686-3c3b-4b87-b161-e4f262360bbf",
  "journal" : {
    "incrementalDurable" : true,
    "orphanRecovery" : true,
    "runsDirWritable" : true
  },
  "loopback" : {
    "host" : "127.0.0.1",
    "listening" : true,
    "port" : 53975
  },
  "pid" : 34158,
  "schemaVersion" : 1,
  "startedAt" : "2026-08-09T22:21:28Z",
  "state" : "available"
}

### launchctl print (key fields)
	active count = 1
	state = running
	program = /Users/mike/.local/bin/alln
	runs = 1
	pid = 34158
	last exit code = (never exited)
	jetsamproperties category = daemon
	job state = running
	properties = keepalive | runatload | inferred program
## 1. Rebuild
before_id=Identifier=alln-55554944120f9e82794f3e398ffb41c119082d78
before_cdhash=

## 2. Codesign after rebuild
after_id=Identifier=alln-55554944760d815861953338ae6e50241b4c7ad3
after_cdhash=
Identifier=alln-55554944760d815861953338ae6e50241b4c7ad3
Format=Mach-O thin (arm64)
CodeDirectory v=20400 size=361094 flags=0x2(adhoc) hashes=11273+7 location=embedded
Signature=adhoc
TeamIdentifier=not set
identity_changed=YES
serve_pid_before_kill=34158

## 3. Kill launchd-owned serve and observe
killing pid=34158
### launchctl after kill (t+3s)
	active count = 1
	state = running
	runs = 2
	pid = 75453
	last exit code = 0
	jetsamproperties category = daemon
	job state = running
	properties = keepalive | runatload | inferred program

### health
{
  "activeObligationCount" : 0,
  "binaryGitSha" : "699a8e09a11601dc986291955afb187b6a522128",
  "binaryVersion" : "1.0.0",
  "contractVersion" : "9.14.0",
  "daemonId" : "85116d23-0622-46e5-a80f-45becc363c48",
  "journal" : {
    "incrementalDurable" : true,
    "orphanRecovery" : true,
    "runsDirWritable" : true
  },
  "loopback" : {
    "host" : "127.0.0.1",
    "listening" : true,
    "port" : 58729
  },
  "pid" : 75453,
  "schemaVersion" : 1,
  "startedAt" : "2026-08-09T22:42:56Z",
  "state" : "available"
}

### ps alln serve
mike             75420   0.4  0.0 410638432   8544   ??  Ss    3:42PM   0:00.09 /bin/zsh -c builtin export PATH="/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"; snap=$(command cat <&3); builtin unsetopt aliases 2>/dev/null; builtin unalias -m '*' 2>/dev/null || true; builtin eval "$snap" && { builtin unsetopt nounset 2>/dev/null || true; builtin eval "${__CURSOR_SANDBOX_ENV_RESTORE:-}" 2>/dev/null; builtin export PWD="$(builtin pwd)"; builtin setopt aliases 2>/dev/null; builtin eval "$1" < /dev/null; }; COMMAND_EXIT_CODE=$?; dump_zsh_state >&4; builtin exit $COMMAND_EXIT_CODE -- set -e\012LOG=/tmp/sc-s00a-rebuild-experiment.md\012SERVE_PID=$(launchctl print gui/$(id -u)/com.allnighter.resident-coordinator 2>&1 | rg -o 'pid = [0-9]+' | head -1 | awk '{print $3}')\012echo "serve_pid_before_kill=$SERVE_PID" | tee -a "$LOG"\012\012{\012  echo\012  echo "## 3. Kill launchd-owned serve and observe"\012  echo "killing pid=$SERVE_PID"\012} | tee -a "$LOG"\012\012if [[ -n "$SERVE_PID" ]]; then\012  kill -TERM "$SERVE_PID" 2>/dev/null || true\012  sleep 2\012  kill -KILL "$SERVE_PID" 2>/dev/null || true\012fi\012sleep 3\012\012{\012  echo '### launchctl after kill (t+3s)'\012  launchctl print gui/$(id -u)/com.allnighter.resident-coordinator 2>&1 | rg -i 'pid |state |last exit|runs |active count|properties|job state' | head -25\012  echo\012  echo '### health'\012  alln serve --health --json 2>&1\012  echo\012  echo '### ps alln serve'\012  ps aux | rg '[a]lln serve' || echo '(none)'\012} | tee -a "$LOG"\012\012# wait for KeepAlive respawn attempt\012sleep 12\012{\012  echo\012  echo '### launchctl after wait (t+15s)'\012  launchctl print gui/$(id -u)/com.allnighter.resident-coordinator 2>&1 | rg -i 'pid |state |last exit|runs |active count|properties|job state' | head -25\012  echo\012  echo '### recent LWCR log (last 2m)'\012  /usr/bin/log show --last 2m --style compact --predicate 'eventMessage CONTAINS "resident-coordinator" AND (eventMessage CONTAINS "LWCR" OR eventMessage CONTAINS "EX_CONFIG" OR eventMessage CONTAINS "could not initialize")' 2>&1 | tail -15\012} | tee -a "$LOG"\012
mike             75618   0.4  0.0 410647392   1744   ??  S     3:43PM   0:00.00 /bin/zsh -c builtin export PATH="/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"; snap=$(command cat <&3); builtin unsetopt aliases 2>/dev/null; builtin unalias -m '*' 2>/dev/null || true; builtin eval "$snap" && { builtin unsetopt nounset 2>/dev/null || true; builtin eval "${__CURSOR_SANDBOX_ENV_RESTORE:-}" 2>/dev/null; builtin export PWD="$(builtin pwd)"; builtin setopt aliases 2>/dev/null; builtin eval "$1" < /dev/null; }; COMMAND_EXIT_CODE=$?; dump_zsh_state >&4; builtin exit $COMMAND_EXIT_CODE -- set -e\012LOG=/tmp/sc-s00a-rebuild-experiment.md\012SERVE_PID=$(launchctl print gui/$(id -u)/com.allnighter.resident-coordinator 2>&1 | rg -o 'pid = [0-9]+' | head -1 | awk '{print $3}')\012echo "serve_pid_before_kill=$SERVE_PID" | tee -a "$LOG"\012\012{\012  echo\012  echo "## 3. Kill launchd-owned serve and observe"\012  echo "killing pid=$SERVE_PID"\012} | tee -a "$LOG"\012\012if [[ -n "$SERVE_PID" ]]; then\012  kill -TERM "$SERVE_PID" 2>/dev/null || true\012  sleep 2\012  kill -KILL "$SERVE_PID" 2>/dev/null || true\012fi\012sleep 3\012\012{\012  echo '### launchctl after kill (t+3s)'\012  launchctl print gui/$(id -u)/com.allnighter.resident-coordinator 2>&1 | rg -i 'pid |state |last exit|runs |active count|properties|job state' | head -25\012  echo\012  echo '### health'\012  alln serve --health --json 2>&1\012  echo\012  echo '### ps alln serve'\012  ps aux | rg '[a]lln serve' || echo '(none)'\012} | tee -a "$LOG"\012\012# wait for KeepAlive respawn attempt\012sleep 12\012{\012  echo\012  echo '### launchctl after wait (t+15s)'\012  launchctl print gui/$(id -u)/com.allnighter.resident-coordinator 2>&1 | rg -i 'pid |state |last exit|runs |active count|properties|job state' | head -25\012  echo\012  echo '### recent LWCR log (last 2m)'\012  /usr/bin/log show --last 2m --style compact --predicate 'eventMessage CONTAINS "resident-coordinator" AND (eventMessage CONTAINS "LWCR" OR eventMessage CONTAINS "EX_CONFIG" OR eventMessage CONTAINS "could not initialize")' 2>&1 | tail -15\012} | tee -a "$LOG"\012
mike             75453   0.0  0.1 411510752  43200   ??  S     3:42PM   0:00.77 /Users/mike/.local/bin/alln serve

### launchctl after wait (t+15s)
	active count = 1
	state = running
	runs = 2
	pid = 75453
	last exit code = 0
	jetsamproperties category = daemon
	job state = running
	properties = keepalive | runatload | inferred program

### recent LWCR log (last 2m)
Timestamp               Ty Process[PID:TID]
2026-08-09 15:43:13.166 Df log[76004:43bb018] [com.apple.log:] log run noninteractively, parent: 75998 (zsh), args: '/usr/bin/log' 'show' '--last' '2m' '--style' 'compact' '--predicate' 'eventMessage CONTAINS "resident-coordinator" AND (eventMessage CONTAINS "LWCR" OR eventMessage CONTAINS "EX_CONFIG" OR eventMessage

## 4. Verdict

**H1 (rebuild-retired identity → EX_CONFIG on this registration): REFUTED** for the
current post-`bootout`+`bootstrap` agent (no `needs LWCR update | managed LWCR` flags).

- Codesign Identifier **did** change across rebuild (adhoc identity rotates).
- After kill, KeepAlive restarted `alln serve` successfully (pid 34158 → 75453),
  health `available`, new gitSha `699a8e09`, no LWCR refuse in the 2m window.
- Matches Bug Hunt fallthrough: fresh plain-bootstrap may tolerate rebuilds until
  BTM re-adopts managed LWCR at login — that re-adoption path remains unproven
  (no reboot performed).

**Still required (packet does not shrink away):**
1. Doctor / `--health` fail-closed on orphan or wedged LA (SC-S00).
2. Product-owned lifecycle + migrate orphan (SC-S01+).
3. Demand heal on real fronts (SC-S03).
4. Founder ruling on login-item ownership; logout/login Works Test before claiming
   reboot continuity.

**Landmine retained:** pointing any future managed agent at an adhoc debug symlink
that rotates Identifier on every rebuild remains structurally unsafe once BTM
pins an LWCR — do not treat this REFUTE as permission to keep that target.
