#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Live mode is manual by design: CI does not possess the founder's authenticated
# vendor sessions, and Code Red never accepts a mock as live proof.
# See docs/phases/CODE_RED_Core_Infrastructure_Repair.md.
CODE_RED_TEAM_ID="${CODE_RED_TEAM_ID:-code_red_two_source}"
CODE_RED_CREW_MODEL="${CODE_RED_CREW_MODEL:-model_chatgpt}"   # codex
CODE_RED_LEAD_MODEL="${CODE_RED_LEAD_MODEL:-model_opus}"      # claude_code
CODE_RED_EXEC_TEAM_ID="${CODE_RED_EXEC_TEAM_ID:-code_red_execution}"
CODE_RED_EXEC_MODEL="${CODE_RED_EXEC_MODEL:-model_opus}"      # claude_code
CODE_RED_EXEC_SOURCE="${CODE_RED_EXEC_SOURCE:-claude_code}"
CODE_RED_EXEC_LINE="CODE_RED_EXECUTION_PROOF"
CODE_RED_SCRATCH="${CODE_RED_SCRATCH:-$HOME/Library/Developer/Allnighter/CLI}"

fail() { echo "code-red: $*" >&2; exit 1; }

# Builds `alln` from the committed checkout, OUTSIDE the protected repo (the
# checkout lives under ~/Documents; building there re-opens the TCC code red).
build_alln() {
  swift build --disable-sandbox --package-path "$ROOT/Packages/AllnighterCore" \
    --scratch-path "$CODE_RED_SCRATCH" --product alln >&2
  local bin
  bin="$(swift build --disable-sandbox --package-path "$ROOT/Packages/AllnighterCore" \
    --scratch-path "$CODE_RED_SCRATCH" --show-bin-path)"
  [[ -x "$bin/alln" ]] || fail "no alln binary at $bin"
  echo "$bin/alln"
}

# A disposable clean Git fixture — never the product checkout. Its cleanliness is
# what makes the pre/post Git observation assertion exact.
make_fixture() {
  local dir
  dir="$(mktemp -d "${TMPDIR:-/tmp}/code-red-fixture.XXXXXX")"
  git -C "$dir" init -q
  git -C "$dir" config user.email "code-red@allnighter.test"
  git -C "$dir" config user.name "Code Red"
  git -C "$dir" config commit.gpgsign false
  printf 'CODE_RED_SENTINEL_%s\n' "$(date +%s)" > "$dir/sentinel.txt"
  printf '# Code Red fixture\n\nDisposable repository for the live works test.\n' > "$dir/README.md"
  git -C "$dir" add . >/dev/null
  git -C "$dir" commit -q -m "code red fixture"
  echo "$dir"
}

# The two-source research team: one crew seat and the Lead pinned to two
# DIFFERENT authenticated vendors, each locked to its own model so the roster
# cannot be substituted away.
write_team_preset() {
  local file="$1"
  cat > "$file" <<JSON
{
  "id" : "$CODE_RED_TEAM_ID",
  "displayName" : "Code Red Two Source",
  "description" : "CR-S03 works test: two distinct authenticated vendor CLIs, research only.",
  "lane" : "code",
  "outputKind" : "bugPacket",
  "mutating" : false,
  "defaultEffort" : "high",
  "isDefaultForLane" : false,
  "builtIn" : false,
  "version" : 1,
  "typeTags" : [ "code-red-works" ],
  "purposeTags" : [ ],
  "starterPrompts" : [ ],
  "workerSpecs" : [
    {
      "id" : "bug_reproducer",
      "skillId" : "bug_reproducer",
      "purpose" : "answer",
      "preferredModelId" : "$CODE_RED_CREW_MODEL",
      "allowedModelIds" : [ "$CODE_RED_CREW_MODEL" ],
      "requiredCapabilityTags" : [ ],
      "preferredCapabilityTags" : [ ],
      "count" : 1,
      "fallbackPolicy" : "anyReady",
      "required" : true,
      "triangulate" : false,
      "triangulatePreferenceIds" : [ ]
    }
  ],
  "lead" : {
    "skillId" : "bug_packet_writer",
    "preferredModelId" : "$CODE_RED_LEAD_MODEL",
    "fallbackModelIds" : [ ],
    "requiredCapabilityTags" : [ ],
    "fallbackPolicy" : "anyReady",
    "dissentPolicy" : "preserveDissent"
  }
}
JSON
}

# The execution Team: one source-scoped mutating seat. Execution resolves to
# exactly one worker, so this team's proof is that it edits the real repository.
write_execution_preset() {
  local file="$1"
  cat > "$file" <<JSON
{
  "id" : "$CODE_RED_EXEC_TEAM_ID",
  "displayName" : "Code Red Execution",
  "description" : "CR-S04 works test: one authenticated vendor CLI edits the registered repository.",
  "lane" : "code",
  "outputKind" : "plan",
  "mutating" : true,
  "executionSourceId" : "$CODE_RED_EXEC_SOURCE",
  "defaultEffort" : "high",
  "isDefaultForLane" : false,
  "builtIn" : false,
  "version" : 1,
  "typeTags" : [ "code-red-works" ],
  "purposeTags" : [ ],
  "starterPrompts" : [ ],
  "workerSpecs" : [
    {
      "id" : "execution_playbook",
      "skillId" : "execution_playbook",
      "purpose" : "answer",
      "preferredModelId" : "$CODE_RED_EXEC_MODEL",
      "allowedModelIds" : [ "$CODE_RED_EXEC_MODEL" ],
      "requiredCapabilityTags" : [ ],
      "preferredCapabilityTags" : [ ],
      "count" : 1,
      "fallbackPolicy" : "anyReady",
      "required" : true,
      "triangulate" : false,
      "triangulatePreferenceIds" : [ ]
    }
  ],
  "lead" : {
    "skillId" : "plan_writer_build",
    "preferredModelId" : "$CODE_RED_EXEC_MODEL",
    "fallbackModelIds" : [ ],
    "requiredCapabilityTags" : [ ],
    "fallbackPolicy" : "anyReady",
    "dissentPolicy" : "preserveDissent"
  }
}
JSON
}

# Dispatches one gesture and samples the REAL vendor process tree while it runs,
# so both gestures report observed processes instead of journal inference.
# usage: dispatch_and_sample <out.json> <err.txt> <observed.txt> <alln args...>
dispatch_and_sample() {
  local out="$1" err="$2" observed="$3"; shift 3
  : > "$observed"
  "$ALLN" "$@" > "$out" 2> "$err" &
  local pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    ps -eo pid=,ppid=,comm= 2>/dev/null \
      | awk -v top="$pid" '
          { pid[$1]=$1; parent[$1]=$2; cmd[$1]=$3 }
          END {
            for (p in pid) {
              a = p; hops = 0
              while (a != "" && a != "1" && hops < 12) {
                if (a == top) { print pid[p] "\t" cmd[p]; break }
                a = parent[a]; hops++
              }
            }
          }' >> "$observed" || true
    sleep 0.25
  done
  local status=0
  wait "$pid" || status=$?
  sort -u "$observed" -o "$observed"
  return "$status"
}

# Creates a works-test team once. A matching team is reused; a DIFFERENT team
# with the same id is a hard stop — never silently run someone else's roster.
ensure_team() {
  local team_id="$1" preset="$2" checker="$3"
  if "$ALLN" teams definition "$team_id" --json > "$WORK/existing-$team_id.json" 2>/dev/null; then
    python3 -c "$checker" "$WORK/existing-$team_id.json" \
      || fail "team $team_id exists with a different roster — inspect it with 'alln teams definition $team_id'"
    echo "code-red: reusing team $team_id"
  else
    "$ALLN" teams new "$team_id" --file "$preset" --json > "$WORK/team-created-$team_id.json"
    echo "code-red: created team $team_id"
  fi
}

case "${1:-}" in
  structural)
    bash "$ROOT/scripts/check_architecture_policy.sh" --self-test
    bash "$ROOT/scripts/check_architecture_policy.sh"
    [[ ! -e "$ROOT/Packages/AllnighterCore/Sources/AllnighterCore/ProjectMirror.swift" ]]
    [[ ! -e "$ROOT/Packages/AllnighterCore/Sources/AllnighterEngine/PanelSeatIsolation.swift" ]]
    rg -q -F 'let service = RunService(' "$ROOT/Packages/AllnighterCore/Sources/AllnighterCLI/RunCLI.swift"
    rg -q -F 'await service.run(request' "$ROOT/Packages/AllnighterCore/Sources/AllnighterCLI/RunCLI.swift"
    ! rg -q -F 'ResidentExecutionOperation' "$ROOT/Packages/AllnighterCore/Sources/AllnighterCLI/RunCLI.swift"
    rg -q -F 'code: "CODE_RED_UNSUPPORTED"' "$ROOT/Packages/AllnighterCore/Sources/AllnighterCLI/PanelCLI.swift"
    swift test --disable-sandbox --package-path "$ROOT/Packages/AllnighterCore" --filter RunCLIStreamAdapterTests
    swift test --disable-sandbox --package-path "$ROOT/Packages/AllnighterCore" --filter TwoSourceResearchTeamTests
    echo "code-red structural: direct CLI adapter, policy, alternate-root deletion, two-source roster verified"
    ;;

  live-direct)
    # CR-S03 research gesture: two explicitly configured, distinct, authenticated
    # vendor CLIs, in one canonical registered repository, returning separately
    # attributed answers, with the fixture's Git state unchanged.
    command -v python3 >/dev/null || fail "python3 is required to check the receipt"

    [[ -z "$(git -C "$ROOT" status --porcelain)" ]] \
      || fail "refusing to run: the product checkout is dirty — live proof must come from committed HEAD"
    HEAD_SHA="$(git -C "$ROOT" rev-parse HEAD)"

    ALLN="${CODE_RED_ALLN:-$(build_alln)}"
    IDENTITY="$("$ALLN" --version)"
    BIN_SHA256="$(shasum -a 256 "$ALLN" | cut -d' ' -f1)"
    echo "code-red: client $IDENTITY"
    echo "code-red: binary $ALLN sha256 $BIN_SHA256 (checkout HEAD $HEAD_SHA)"

    FIXTURE="$(make_fixture)"
    FIXTURE_HEAD="$(git -C "$FIXTURE" rev-parse HEAD)"
    SENTINEL="$(head -n1 "$FIXTURE/sentinel.txt")"
    echo "code-red: fixture $FIXTURE at $FIXTURE_HEAD ($SENTINEL)"

    WORK="$(mktemp -d "${TMPDIR:-/tmp}/code-red-run.XXXXXX")"
    PROJECT_JSON="$WORK/project.json"
    "$ALLN" project add "$FIXTURE" --name "Code Red Fixture" --json > "$PROJECT_JSON"
    PROJECT_ID="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("project",d).get("id",""))' "$PROJECT_JSON")"
    [[ -n "$PROJECT_ID" ]] || fail "could not register the fixture project (see $PROJECT_JSON)"
    echo "code-red: project $PROJECT_ID"

    write_team_preset "$WORK/team.json"
    ensure_team "$CODE_RED_TEAM_ID" "$WORK/team.json" "
import json, sys
d = json.load(open(sys.argv[1]))
ok = (d.get('id') == '$CODE_RED_TEAM_ID'
      and d.get('mutating') is False
      and [w.get('preferredModelId') for w in d.get('workerSpecs', [])] == ['$CODE_RED_CREW_MODEL']
      and d.get('lead', {}).get('preferredModelId') == '$CODE_RED_LEAD_MODEL')
sys.exit(0 if ok else 1)
"

    PROMPT='Research only, do not modify any files. Independently name this repository'"'"'s most important infrastructure risk, and cite as evidence: (1) the output of pwd, (2) the output of git rev-parse HEAD, (3) the first line of sentinel.txt.'
    RUN_JSON="$WORK/run.json"
    RUN_ERR="$WORK/run.err"
    OBSERVED="$WORK/observed-pids.txt"

    echo "code-red: dispatching the research gesture (two distinct authenticated CLIs)"
    RUN_EXIT=0
    dispatch_and_sample "$RUN_JSON" "$RUN_ERR" "$OBSERVED" \
      run "$PROMPT" --project "$PROJECT_ID" --team "$CODE_RED_TEAM_ID" --json || RUN_EXIT=$?

    echo "code-red: observed live descendant processes:"
    sed 's/^/    /' "$OBSERVED" || true

    AFTER_HEAD="$(git -C "$FIXTURE" rev-parse HEAD)"
    AFTER_PORCELAIN="$(git -C "$FIXTURE" status --porcelain)"

    python3 - "$RUN_JSON" "$RUN_EXIT" "$FIXTURE_HEAD" "$AFTER_HEAD" "$FIXTURE" "$OBSERVED" <<'PY'
import json, os, sys

run_json, run_exit, before_head, after_head, fixture, observed = sys.argv[1:7]
missing = []

def check(ok, why):
    if not ok:
        missing.append(why)

if int(run_exit) != 0:
    missing.append(f"alln run exited {run_exit}")

try:
    d = json.load(open(run_json))
except Exception as exc:                       # noqa: BLE001 - report, never guess
    print(f"code-red: LIVE PROOF RED — unreadable run JSON: {exc}", file=sys.stderr)
    sys.exit(1)

team_run = d.get("teamRun", {})
workers = d.get("workers", [])
answers = d.get("workerAnswers", [])
obs = d.get("researchGitObservation")

check(team_run.get("status") in ("done", "complete"), f"run status {team_run.get('status')}")
check(team_run.get("writePolicy") == "readOnly", f"writePolicy {team_run.get('writePolicy')}")

# Exactly two selected, DISTINCT source CLIs — no substitution, duplication, or collapse.
sources = sorted(w.get("sourceId", "") for w in workers)
check(len(workers) == 2, f"expected 2 workers, got {len(workers)}: {sources}")
check(len(set(sources)) == 2, f"expected 2 DISTINCT sources, got {sources}")
check(d.get("usage", {}).get("cliCalls") == 2, f"cliCalls {d.get('usage', {}).get('cliCalls')}")
subs = [w.get("message", "") for w in d.get("warnings", []) if "substitut" in w.get("message", "").lower()]
check(not subs, f"substitution warning(s): {subs}")

# Separately attributed, non-empty answers: the crew seat as its own answer, the
# Lead as the run's answer. Each must be real text from its own source.
crew_workers = [w for w in workers if w.get("purpose") == "answer"]
check(len(crew_workers) >= 1, "no crew answer seat in the roster")
for w in crew_workers:
    mine = [a for a in answers if a.get("workerId") == w.get("id")]
    check(bool(mine), f"no answer attributed to {w.get('id')} ({w.get('sourceId')})")
    for a in mine:
        check(a.get("status") == "done", f"{w.get('sourceId')} answer status {a.get('status')}")
        check(bool((a.get("markdown") or "").strip()), f"{w.get('sourceId')} returned an empty answer")

lead_text = ((d.get("answer") or {}).get("markdown") or "")
check(bool(lead_text.strip()), "the Lead seat returned no output")

# The two seats must be the two distinct CLIs the team selected.
by_purpose = {w.get("purpose"): w.get("sourceId") for w in workers}
check(len(set(by_purpose.values())) == 2,
      f"the seats collapsed onto one CLI: {by_purpose}")

# Bounded pre/post Git observation over the clean fixture.
check(obs is not None, "no researchGitObservation recorded")
if obs is not None:
    check(obs.get("changed") is False, f"research-write violation: {obs.get('changedPaths')}")
    check(obs.get("baselineHead", "").startswith(before_head[:12]), f"baselineHead {obs.get('baselineHead')}")
    check(obs.get("head", "").startswith(after_head[:12]), f"observed head {obs.get('head')}")
check(before_head == after_head, "the fixture HEAD moved during a research run")

# One canonical root: the journal the run wrote must name the registered fixture.
journal = (d.get("audit") or {}).get("runJournalPath")
check(bool(journal) and os.path.exists(journal), f"run journal missing: {journal}")
if journal and os.path.exists(journal):
    jd = json.load(open(journal))
    check(os.path.realpath(jd.get("repoRoot") or "") == os.path.realpath(fixture),
          f"journal repoRoot {jd.get('repoRoot')} != fixture {fixture}")

# Live process evidence for BOTH selected vendors.
seen = open(observed).read()
for source in set(sources):
    vendor = {"claude_code": "claude", "codex": "codex", "cursor_agent": "cursor",
              "grok": "grok", "antigravity": "agy"}.get(source, source)
    check(vendor in seen, f"no live process observed for {source} (expected '{vendor}')")

print(json.dumps({
    "status": "GREEN" if not missing else "RED",
    "runId": team_run.get("id"),
    "runStatus": team_run.get("status"),
    "writePolicy": team_run.get("writePolicy"),
    "sources": sources,
    "cliCalls": d.get("usage", {}).get("cliCalls"),
    "answerChars": {w.get("sourceId"): len(
        next((a.get("markdown") or "") for a in answers if a.get("workerId") == w.get("id")), )
        for w in crew_workers if any(a.get("workerId") == w.get("id") for a in answers)},
    "leadChars": len(lead_text),
    "gitObservation": obs,
    "runJournalPath": journal,
    "missing": missing,
}, indent=2))

if missing:
    print("code-red: LIVE PROOF RED — " + "; ".join(missing), file=sys.stderr)
    sys.exit(1)
PY

    [[ -z "$AFTER_PORCELAIN" ]] || fail "the fixture working tree changed during a research run:\n$AFTER_PORCELAIN"
    echo "code-red: research gesture GREEN"

    # ---- CR-S04 execution gesture -------------------------------------------
    # Same canonical fixture, now under a mutating Team: exactly one selected
    # worker makes one bounded real edit, and the returned change must be the
    # fixture's actual Git truth.
    write_execution_preset "$WORK/exec-team.json"
    ensure_team "$CODE_RED_EXEC_TEAM_ID" "$WORK/exec-team.json" "
import json, sys
d = json.load(open(sys.argv[1]))
ok = (d.get('id') == '$CODE_RED_EXEC_TEAM_ID'
      and d.get('mutating') is True
      and d.get('executionSourceId') == '$CODE_RED_EXEC_SOURCE'
      and [w.get('preferredModelId') for w in d.get('workerSpecs', [])] == ['$CODE_RED_EXEC_MODEL'])
sys.exit(0 if ok else 1)
"

    EXEC_BASE_HEAD="$(git -C "$FIXTURE" rev-parse HEAD)"
    EXEC_PROMPT="Append the exact line $CODE_RED_EXEC_LINE to sentinel.txt, then show the git diff. Change nothing else."
    EXEC_JSON="$WORK/exec-run.json"
    EXEC_ERR="$WORK/exec-run.err"
    EXEC_OBSERVED="$WORK/exec-observed-pids.txt"

    echo "code-red: dispatching the execution gesture (one selected authenticated CLI)"
    EXEC_EXIT=0
    dispatch_and_sample "$EXEC_JSON" "$EXEC_ERR" "$EXEC_OBSERVED" \
      run "$EXEC_PROMPT" --project "$PROJECT_ID" --team "$CODE_RED_EXEC_TEAM_ID" --json || EXEC_EXIT=$?

    echo "code-red: observed live descendant processes:"
    sed 's/^/    /' "$EXEC_OBSERVED" || true

    # Every path this run touched, whether the worker committed it or left it in
    # the working tree. "A change anywhere else fails."
    EXEC_HEAD="$(git -C "$FIXTURE" rev-parse HEAD)"
    {
      git -C "$FIXTURE" status --porcelain | awk '{ print $NF }'
      if [[ "$EXEC_HEAD" != "$EXEC_BASE_HEAD" ]]; then
        git -C "$FIXTURE" diff --name-only "$EXEC_BASE_HEAD..$EXEC_HEAD"
      fi
    } | sed '/^$/d' | sort -u > "$WORK/exec-changed-paths.txt"
    SENTINEL_HITS="$(grep -c -F "$CODE_RED_EXEC_LINE" "$FIXTURE/sentinel.txt" || true)"

    python3 - "$EXEC_JSON" "$EXEC_EXIT" "$EXEC_BASE_HEAD" "$EXEC_HEAD" "$FIXTURE" \
      "$EXEC_OBSERVED" "$WORK/exec-changed-paths.txt" "$SENTINEL_HITS" "$CODE_RED_EXEC_SOURCE" <<'PY'
import json, os, sys

(run_json, run_exit, base_head, head, fixture, observed,
 changed_paths_file, sentinel_hits, exec_source) = sys.argv[1:10]
missing = []

def check(ok, why):
    if not ok:
        missing.append(why)

if int(run_exit) != 0:
    missing.append(f"alln run exited {run_exit}")

try:
    d = json.load(open(run_json))
except Exception as exc:                       # noqa: BLE001 - report, never guess
    print(f"code-red: EXECUTION PROOF RED — unreadable run JSON: {exc}", file=sys.stderr)
    sys.exit(1)

team_run = d.get("teamRun", {})
workers = d.get("workers", [])
delta = d.get("repoDelta")

check(team_run.get("status") in ("done", "complete"), f"run status {team_run.get('status')}")
# Execution is never downgraded to research or a dry run.
check(team_run.get("writePolicy") == "mutating", f"writePolicy {team_run.get('writePolicy')}")
check(d.get("researchGitObservation") is None,
      "an execution run must report repoDelta, not the research observation")

# Exactly one selected worker.
check(len(workers) == 1, f"expected exactly 1 worker, got {[w.get('sourceId') for w in workers]}")
check(d.get("usage", {}).get("cliCalls") == 1, f"cliCalls {d.get('usage', {}).get('cliCalls')}")
if workers:
    check(workers[0].get("sourceId") == exec_source,
          f"execution ran on {workers[0].get('sourceId')}, not the selected {exec_source}")

# The change exists exactly once, in the fixture's real working tree, and nowhere else.
check(int(sentinel_hits) == 1, f"sentinel.txt contains the proof line {sentinel_hits} times, expected exactly 1")
changed = [p for p in open(changed_paths_file).read().split() if p]
check(changed == ["sentinel.txt"], f"changed paths in the fixture: {changed}")

# The returned diff is the fixture's real Git truth.
check(delta is not None, "no repoDelta returned for a mutating run")
if delta is not None:
    check(delta.get("changed") is True, "repoDelta reports no change after a real edit")
    check(delta.get("baseline", "").startswith(base_head[:12]), f"repoDelta baseline {delta.get('baseline')}")
    if head != base_head:
        check((delta.get("head") or "").startswith(head[:12]),
              f"repoDelta head {delta.get('head')} != fixture HEAD {head[:12]}")
    files = delta.get("files") or []
    check(files in ([], ["sentinel.txt"]), f"repoDelta files {files}")

# Live process evidence for the one selected vendor.
vendor = {"claude_code": "claude", "codex": "codex", "cursor_agent": "cursor",
          "grok": "grok", "antigravity": "agy"}.get(exec_source, exec_source)
check(vendor in open(observed).read(), f"no live process observed for {exec_source} (expected '{vendor}')")

print(json.dumps({
    "status": "GREEN" if not missing else "RED",
    "runId": team_run.get("id"),
    "runStatus": team_run.get("status"),
    "writePolicy": team_run.get("writePolicy"),
    "workers": [w.get("sourceId") for w in workers],
    "cliCalls": d.get("usage", {}).get("cliCalls"),
    "sentinelHits": int(sentinel_hits),
    "changedPaths": changed,
    "repoDelta": delta,
    "runJournalPath": (d.get("audit") or {}).get("runJournalPath"),
    "missing": missing,
}, indent=2))

if missing:
    print("code-red: EXECUTION PROOF RED — " + "; ".join(missing), file=sys.stderr)
    sys.exit(1)
PY

    echo "code-red live-direct: GREEN — two distinct authenticated CLIs answered from the canonical"
    echo "  fixture unchanged, then one selected CLI made exactly the requested real edit there"
    echo "code-red: artifacts in $WORK (fixture $FIXTURE)"
    ;;

  live-resident)
    echo "code-red: resident transport is unproven and unused before CR-S05; there is nothing to run" >&2
    exit 2
    ;;
  *)
    echo "usage: $0 structural|live-direct|live-resident" >&2
    exit 2
    ;;
esac
