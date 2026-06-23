# iOS testing loop

**Repo:** `/Users/mike/Documents/GitHub/Allnighter-iOS`

This is the SSOT for how humans and agents run the iOS app. If testing feels
hard, the process is wrong — fix the process, not the human.

## Agent rule (non-negotiable)

When the user asks how to test **anything** on iOS:

1. Give the **simplest path** that actually proves the thing — one command block,
   not a menu of options.
2. **Every shell command** starts with:
   ```bash
   cd /Users/mike/Documents/GitHub/Allnighter-iOS &&
   ```
3. No bare `allios`, `scripts/foo.sh`, or “run serve_remote” without the `cd`.
4. Default to **preview** (no Mac, no Supabase). Only mention **live** when the
   task explicitly needs phone → Mac relay.
5. Say how long it roughly takes and what “success” looks like in the UI.

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

Live relay credentials (only for Tier 2):

```bash
cd /Users/mike/Documents/GitHub/Allnighter-iOS && scripts/bootstrap_remote_env.sh
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

### First run of the day (or after clean)

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
| Home list / search / filters | `allios launch` → scroll home |
| Open a thread | Tap any conversation |
| Reply in thread | Type in bottom composer → send |
| New chat from home | Type in home composer → send → auto-opens thread |
| Model / team / effort chips | Tap chips on composer before send |
| Agent labels in transcript | Open thread with worker turns |

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

## Tier 2 — Live Mac (integration only)

Use when you must prove **real** phone → Supabase → Mac agent.

**Terminal 1 — Mac agent (keep running):**

```bash
cd /Users/mike/Documents/GitHub/Allnighter-iOS && scripts/serve_remote.sh
```

**Terminal 2 — iOS with relay env:**

```bash
cd /Users/mike/Documents/GitHub/Allnighter-iOS && allios live
```

- Requires `.env` (from bootstrap).
- First connect may require **pairing approval on the Mac**.
- **Success:** connection banner shows your Mac name (not preview banner).

Relaunch live app without rebuild:

```bash
cd /Users/mike/Documents/GitHub/Allnighter-iOS && allios live launch
```

JWTs expire (~1 hour). Refresh:

```bash
cd /Users/mike/Documents/GitHub/Allnighter-iOS && scripts/bootstrap_remote_env.sh --refresh
```

---

## Command reference

| Command | Does |
| --- | --- |
| `allios` | Preview: build (if needed) + launch |
| `allios launch` | Preview: relaunch only |
| `allios build` | Build only |
| `allios test` | Unit tests |
| `allios live` | Live: build + launch with `.env` |
| `allios live launch` | Live: relaunch only with `.env` |
| `allios clean` | Wipe DerivedData, then preview build + launch |

`.env` presence does **not** change default `allios` behavior — preview is always
the default dev path.

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `allios` takes forever | Use `allios launch` after first build; or Xcode ⌘R |
| “Could not send work request” in preview | Old build — `cd … && allios` once |
| Live: “Could not connect” | Terminal 1: `serve_remote.sh` running? JWT fresh? |
| Simulator install failed | Quit Simulator, `cd … && allios` |
| Wrong data (preview vs live) | Preview = amber “Preview data” banner; live = Mac name |

---

## Friction we removed (policy)

- **`allios` never auto-switches to live** just because `.env` exists.
- **Live is opt-in** (`allios live`) so daily UI work stays one command.
- **Agents must not** dump bootstrap / Supabase / pairing steps when the user is
  doing UI work — point to Tier 0 only.
