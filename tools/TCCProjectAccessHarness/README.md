# TCC Project-Access Harness

This is a disposable native harness for the resident Team Documents-prompt
regression. It has no Allnighter package imports and never launches a vendor
CLI. It models only the disputed primitive: a short-lived helper launched by
`launchd` changes to one directory and enumerates it once.

Run it from a normal macOS terminal, never from Codex or another restricted
host:

```bash
cd /Users/mike/Documents/GitHub/Allnighter
bash tools/TCCProjectAccessHarness/run.sh --mode scratch
bash tools/TCCProjectAccessHarness/run.sh --mode project \
  --project /Users/mike/Documents/GitHub/XTerminal
bash tools/TCCProjectAccessHarness/run.sh --mode snapshot \
  --project /Users/mike/Documents/GitHub/XTerminal
```

The `scratch` action should never cause a protected-folder request. The
`project` action is the current resident-run shape: it receives only the real
project CWD. The `snapshot` action is the candidate read-only design: the
normal-terminal client uses `git archive HEAD`, removes every `.env*` entry,
and the launchd helper sees only that owned copy under `~/Library`.

For each invocation, record whether a dialog appeared before opening any other
app. The JSON receipt records PID, requested/effective CWD, entry count, and
any filesystem error; it is saved below
`~/Library/Developer/Allnighter/TCCProjectAccessHarness/logs/`.

The script bootstraps and removes only
`com.allnighter.tcc-project-access-harness`. It does not call `tccutil`, change
the project, copy credentials, or start a model. Do not reset TCC as part of
routine development. If a clean permission-state experiment is later required,
that is a separate explicit founder decision because it changes macOS privacy
state.

This is not yet a release proof: it establishes the launchd/CWD primitive and
the snapshot candidate. The product acceptance test is a real read-only Team
review from that snapshot, with no Documents prompt and no untracked or dotenv
content transferred.
