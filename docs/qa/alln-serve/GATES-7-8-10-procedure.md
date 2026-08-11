# Gates 7, 8, 10 — founder procedure (second Mac)

Run on the **other** Mac, not the dev host. That machine is a better test than
this one: §9's precondition is a clean host with no `Allnighter.app`, which is
exactly what it is.

Budget: ~15 minutes, two logout/login cycles and one lid close.

Everything below is copy-paste. After each block, send me the output — I record
and sign the QA files.

---

## Setup (once)

**Pin the build first.** A gate that cannot name the commit it tested is not
evidence. On **this** Mac, with a clean tree:

```bash
git status --short          # must be empty. If not, stop -- do not test a half state.
git rev-parse --short HEAD  # write this down; it is the gate's build identity
bash scripts/rebuild_cli.sh # the binary must be built FROM that commit
alln version --json         # record; must agree with the sha above
```

Then send that exact binary over:

```bash
scp ~/.local/share/allnighter/bin/alln <othermac>:~/alln-new
```

The other Mac must run the binary built from the recorded commit, and every
JSON file you send back carries `binaryGitSha` so I can prove it did. If the
tree was dirty, or the binary predates the commit, the gate records a build that
never existed and the result means nothing.

On the **other** Mac:

```bash
# confirm the precondition: nothing Allnighter is installed or running
ls /Applications/Allnighter.app 2>&1
launchctl list | grep -i allnighter
which alln

mkdir -p ~/.local/bin && mv ~/alln-new ~/.local/bin/alln && chmod +x ~/.local/bin/alln
export PATH="$HOME/.local/bin:$PATH"
alln install-cli --json
alln serve status --json; echo "EXIT=$?"
```

**Expect:** `state: "healthy"`, `EXIT=0`, `supervisor.loaded: true`, and every
scheduler id present. If it is not healthy here, stop and send me the output —
the rest of the gates are meaningless until this is green.

---

## Gate 7 — serve returns after logout/login

```bash
# 1. record before
alln serve status --json > ~/gate7-before.json; echo "EXIT=$?"

# 2. log out (Apple menu -> Log Out). Log back in.
# 3. open Terminal ONLY. Do not open any app, do not run any other alln command.

export PATH="$HOME/.local/bin:$PATH"
alln serve status --json > ~/gate7-after.json; echo "EXIT=$?"
```

**Pass:** `after` is `healthy`, exit 0, with a **new** daemon pid, without you
launching anything. The point of "Terminal only" is that no command of yours
started it — launchd did.

---

## Gate 8 — disable survives login, and install does not re-enable it

```bash
alln serve disable --json
alln serve status --json > ~/gate8-before.json; echo "EXIT=$?"   # expect disabled, exit 0

# log out, log back in, open Terminal only

export PATH="$HOME/.local/bin:$PATH"
alln serve status --json > ~/gate8-after.json; echo "EXIT=$?"    # expect STILL disabled

# and an install must not silently re-enable it
alln install-cli --json
alln serve status --json > ~/gate8-after-install.json; echo "EXIT=$?"  # expect STILL disabled

# restore
alln serve enable --json
```

**Pass:** disabled survives both the login and the reinstall. A disable you did
not undo must never be undone for you.

---

## Gate 10 — a deadline that came due while asleep

This is the one gate today's work actually earned: scheduler receipts now carry
`nextWakeAt` and `lastSuccessAt`, so this is directly measurable instead of
inferred.

```bash
# 1. read the next due deadline
alln serve status --json | python3 -c "
import json,sys
d=json.load(sys.stdin)
for s in d['schedulers']:
    print(s['id'], 'next:', s.get('nextWakeAt'), 'lastSuccess:', s.get('lastSuccessAt'))
"
```

Pick the row with the soonest `nextWakeAt` (`capacityRefresh` is usually a few
minutes out). Note its `lastSuccessAt`.

```bash
# 2. close the lid and leave it asleep until PAST that nextWakeAt -- give it
#    10 minutes to be safe.
# 3. open the lid, wait 2 minutes, then:

alln serve status --json | python3 -c "
import json,sys
d=json.load(sys.stdin)
for s in d['schedulers']:
    print(s['id'], 'next:', s.get('nextWakeAt'), 'lastSuccess:', s.get('lastSuccessAt'))
"
```

**Pass:** that scheduler's `lastSuccessAt` advanced to a time after the wake,
within 2 minutes of opening the lid (§4.4).

**Fail looks like:** `lastSuccessAt` unchanged, or `nextWakeAt` still the old
pre-sleep deadline — meaning the loop slept through and is waiting out the
original interval. That is the failure §10.1 R2 says is the least-designed part
of the packet, and it is worth finding.

---

## What I do with the output

Send me the six JSON files and the two scheduler listings. I write one record
per gate under `docs/qa/alln-serve/`, with date, build identity, before/after,
and pass/fail. Per §8 you are the signer — I record, you sign.

An unrecorded gate is an unrun gate, so nothing counts until the files exist.
