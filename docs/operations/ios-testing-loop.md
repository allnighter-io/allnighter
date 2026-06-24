# iOS testing loop

**Repo:** `/Users/mike/Documents/GitHub/Allnighter-iOS`

This is the SSOT for how humans and agents run the iOS app. If testing feels
hard, the process is wrong — fix the process, not the human.

## Agent rule (non-negotiable)

When the user asks how to test **anything** on iOS:

1. **Agents verify UI themselves** — run `allios proof` (PNG capture, same contract as Mac
   `gui_proof.sh`) and **read the image**. Optional `allios uitest` for tap flows. **Never
   ask the founder to manually eyeball the simulator** for Tier 0 work.
2. Give the **simplest path** only when the founder explicitly wants to look — one
   command block, not a menu.
3. **Every shell command** starts with:
   ```bash
   cd /Users/mike/Documents/GitHub/Allnighter-iOS &&
   ```
4. No bare `allios`, `scripts/foo.sh`, or multi-terminal live setup without the `cd`.
5. Default to **preview** (no Mac, no Supabase). Only mention **live** when the
   task explicitly needs phone → Mac relay.
6. Mac GUI uses `scripts/gui_proof.sh` + layout-watcher; iOS uses `allios proof`
   (PNG under `docs/qa/ios/_captures/`) — same contract: **the agent looks, not the user.**

## One-time setup

```bash
cd /Users/mike/Documents/GitHub/Allnighter-iOS &&
grep -q 'allios()' ~/.zshrc || cat >> ~/.zshrc <<'EOF'
allios() { "$HOME/Documents/GitHub/Allnighter-iOS/scripts/ios_dev.sh" "$@"; }
EOF
```

```bash
source ~/.zshrc
```

Live relay credentials (only if you ever run `allios live` — skip for preview):

You don't need a separate step. `allios live` runs bootstrap automatically when `.env`
is missing. Manual refresh only:

```bash
cd /Users/mike/Documents/GitHub/Allnighter-iOS && allios live setup --refresh
```

---

## Three tiers — pick one

| Tier | When | Time | What it proves |
| --- | --- | --- | --- |
| **0 — UI dev** | Every SwiftUI / chat tweak | ~1 min first run; ~5 s relaunch | Preview data: home, threads, send, reply, composer |
| **1 — Unit tests** | Before commit / after logic change | ~4–5 min | `AllnighteriOSTests` green |
| **2 — Live Mac** | Relay, pairing, real Mac threads | ~15 min setup + slow builds | Phone talks to your Mac over Supabase |

**90% of work is Tier 0.** If you are not explicitly testing relay or pairing,
do not use Tier 2.

---

## Tier 0 — UI dev (default)

### Agent visual proof (required at slice close)

```bash
cd /Users/mike/Documents/GitHub/Allnighter-iOS && allios proof
```

- Launches preview, writes `docs/qa/ios/_captures/home.png`, `thread.png`, `pending.png`, and `model-picker.png`.
- **Agents run this and read the PNG** — same as Mac `gui_proof.sh`. Do not hand off to the founder.

Optional XCTest tap flows (supplemental; simulator cold-boot can flake):

```bash
cd /Users/mike/Documents/GitHub/Allnighter-iOS && allios uitest
```

- Single combined case: preview home + model picker fixture. **Tier 0 closeout uses `allios proof` (PNG), not uitest.**

Extra capture name (same harness):

```bash
cd /Users/mike/Documents/GitHub/Allnighter-iOS && allios screenshot
```

- Alias for `allios proof` with an optional capture name.

### Founder fast loop (only when they want to click around)

```bash
cd /Users/mike/Documents/GitHub/Allnighter-iOS && allios
```

- Builds if needed, launches **DEBUG preview** on the simulator.
- Banner: *“Preview data — configure Supabase to connect live.”*
- **Success:** home shows conversations; open a thread; send from composer.

### Every edit after that (fast)

```bash
cd /Users/mike/Documents/GitHub/Allnighter-iOS && allios launch
```

- **No rebuild.** Install + relaunch only (~seconds if simulator is already open).
- If you changed Swift, run `allios` once, then go back to `allios launch`.

### Fastest path (Xcode)

1. Open `Apps/AllnighteriOS/AllnighteriOS.xcodeproj`
2. Pick a simulator, press **⌘R**
3. Leave the simulator running between runs

Optional: Xcode → Settings → Locations → Derived Data → Custom →
`~/Library/Developer/Allnighter/iOS-Build` (same cache as `allios`).

### What to test in preview

| Goal | Simplest path |
| --- | --- |
| **Inbox** — see threads, unread, active runs | `allios proof` → read `home.png` |
| Open a thread | Tap any conversation (or `allios proof` → `thread.png`) |
| **Reply** in thread | Type in bottom composer → send → agent reply (~2.5s preview) |
| **New message** from home | Type in home composer → send → auto-opens thread |
| New chat (clear composer) | Tap ✎ top-right |
| Model / team / effort chips | Tap chips on composer before send |
| Agent labels in transcript | Open thread with worker turns |

Preview polls home every 8s (live + preview) so the inbox stays fresh when connected.

Preview does **not** prove Mac execution — only UI + local send plumbing.

---

## Tier 1 — Unit tests

```bash
cd /Users/mike/Documents/GitHub/Allnighter-iOS && allios test
```

- Log: `/tmp/allnighter-ios-unit-tests.log`
- Run at slice close, not on every save.

Build only (no simulator):

```bash
cd /Users/mike/Documents/GitHub/Allnighter-iOS && allios build
```

---

## Tier 2 — Live Mac (only when you need real relay)

**One command.** It bootstraps `.env` the first time, starts the Mac relay agent in the
background, builds, and launches the simulator. No second terminal. No `serve_remote`.

```bash
cd /Users/mike/Documents/GitHub/Allnighter-iOS && allios live
```

- First run may take ~2–3 min (credentials + build + agent warmup).
- After that: `allios live launch` for a fast relaunch (~10s).
- **Success:** banner shows your Mac name — not *“Preview data…”*.
- First connect may need **pairing approval on the Mac** (one-time).

Stop the background Mac agent when you're done:

```bash
cd /Users/mike/Documents/GitHub/Allnighter-iOS && allios live stop
```

JWTs expire (~1 hour). Re-run `allios live` (it refreshes on bootstrap if needed), or:

```bash
cd /Users/mike/Documents/GitHub/Allnighter-iOS && allios live setup --refresh
```

**You do not need Tier 2 for daily UI work.** Preview (`allios launch`) is enough.

---

## Command reference

| Command | Does |
| --- | --- |
| `allios` | Preview: build (if needed) + launch |
| `allios launch` | Preview: relaunch only |
| `allios build` | Build only |
| `allios proof` | UI tests — **agents verify here** |
| `allios screenshot` | PNG capture → `docs/qa/ios/_captures/` |
| `allios live` | Live: auto-start Mac relay + build + launch |
| `allios live launch` | Live: relaunch only (relay auto-started) |
| `allios live stop` | Stop background Mac relay agent |
| `allios live setup` | Manual credential bootstrap / `--refresh` |
| `allios clean` | Wipe DerivedData, then preview build + launch |

`.env` presence does **not** change default `allios` behavior — preview is always
the default dev path.

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `allios` takes forever | Use `allios launch` after first build; or Xcode ⌘R |
| “Could not send work request” in preview | Old build — `cd … && allios` once |
| Live: “Could not connect” | Run `allios live` again (restarts agent). Log: `~/Library/Developer/Allnighter/ios-live-serve.log` |
| Simulator install failed | Quit Simulator, `cd … && allios` |
| Wrong data (preview vs live) | Preview = amber “Preview data” banner; live = Mac name |

---

## Friction we removed (policy)

- **`allios` never auto-switches to live** just because `.env` exists.
- **Live is opt-in** (`allios live`) so daily UI work stays one command.
- **Agents must not** mention `serve_remote`, a second terminal, or bootstrap steps
  when the user is doing UI work — point to Tier 0 only. For live, give **only**
  `allios live`.
