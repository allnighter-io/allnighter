<p align="center">
  <img src="Apps/AllnighterMac/Resources/Assets.xcassets/AppIcon.appiconset/icon_256.png" width="128" height="128" alt="Allnighter">
</p>

<h1 align="center">Allnighter</h1>

<p align="center">
  <strong>You already pay for the AI team.<br>Make it show up to work.</strong>
</p>

<p align="center">
  Local CLI for macOS · source-available · not a model provider
</p>

<p align="center">
  <a href="https://allnighter.io">allnighter.io</a>
  ·
  <a href="https://get.allnighter.io">install</a>
  ·
  <a href="LICENSE.md">licence</a>
</p>

---

You already pay for Claude Code. Maybe Codex, Cursor, Grok, Gemini, OpenCode, or a local model. They have never met each other. You are the copy-paste layer between them.

Allnighter is the bench. One prompt. Your own CLIs, in parallel. Named Teams for judgment — Spec Review, Bug Hunt, Growth, Research — and Loop when a strong lead should steer while one worker mutates the tree. No API keys. No cloud proxy. No markup on tokens you already bought.

The `alln` CLI is the product. The Mac app is the same bench with a floor. You can use Allnighter without the DMG.

```bash
curl -fsSL https://get.allnighter.io | sh
```

macOS. Signed and notarized. Current floor: CLI **1.1.17** + Mac app **1.1.5**.

Then, from the repo you actually work in:

```bash
alln menu --json
```

That catalog is live. Do not paste an old one into the next session.

---

## What it does

Allnighter starts **your** tools, under **your** logins, on **your** Mac.

```text
you / your agent
        │
        ▼
      alln
        │  local stdin / stdout
        ├──── claude      → Anthropic   (your session)
        ├──── codex       → OpenAI      (your session)
        ├──── cursor-agent
        ├──── grok
        └──── ollama      → localhost
```

It does not include Claude, Codex, or anyone else. It does not see those credentials. It does not swap your model. It will not let two writers edit the same root at once.

| You send | What happens |
| --- | --- |
| **Team** | Parallel judgment. Spec Review, Bug Hunt, Growth, Research, and others. Observational until you execute. |
| **Loop** | A durable PM chair. You kick off once; it drives rounds. One mutating worker per repo root. |

Discovery is free forever: `menu`, `help`, `doctor`, `capacity`, `billing`. A run is what counts.

---

## Privacy

This is how it is built, not a promise bolted on later.

1. We never see your prompts, your code, or your files.
2. We never see your provider credentials. Allnighter starts the vendor CLI; that CLI logs itself in.
3. We never see model output. It is written to your disk.
4. We do not sell data, run ads, or train on anything you produce.

What leaves the machine toward us: an irreversible machine hash for trial, Stripe email if you pay, an update check, and — only if you send it — an `alln feedback` note (your words, CLI version, OS). Full text: [Privacy Policy](docs/legal/Privacy_Policy.md).

---

## Source available

The source is public so you can read what `alln` does before you run it.

This is **not** open source. You may view, modify, and compile for your own use. You may not redistribute binaries, re-host the build, or call a fork Allnighter / `alln`. The official signed binary is the supported product.

[Licence (EULA)](LICENSE.md) · [Terms](docs/legal/Terms_of_Service.md)

```bash
# Official install — this is the product
curl -fsSL https://get.allnighter.io | sh

# Confirm the binary you ran matches a published tree
alln version
```

---

## Pricing

No Buy button on the website. Install, then pay from the Mac or from `alln billing checkout` if you want to.

| | |
| --- | --- |
| **Free** | 3 runs/day, full product. Capacity, doctor, help: always free. |
| **Trial** | 14 days unlimited, starting at first run — not at install. |
| **Builder** | $8/mo or $80/yr. Unlimited orchestration within *your* provider limits. |
| **Founding** | $160 once, first 100. Then it is gone. |

USD. Stripe Checkout with email. We never see your card number. Offer details: [allnighter.io](https://allnighter.io).

---

## For agents

You are in a session that already has Claude, Codex, Cursor, or similar. Allnighter is how that session uses the rest of the bench.

```bash
# Every new session
alln menu --json

# After --no-wait, run the returned nextAction.command once. Do not poll.
# running ≠ progress. Read observation on:
alln show <id> --json
```

Cold machine, no `alln` on PATH:

```bash
curl -fsSL https://get.allnighter.io | sh
alln bootstrap
```

`alln install-cli` only repairs PATH. It is not the install.

Canonical ids only. `--dry-run` before a worker you have not used. Do not trust a catalog you pasted yesterday.

---

## Mac app

Same product as the CLI. Same run contract. Dark-mode native macOS.

[Download the DMG](https://get.allnighter.io/Allnighter.dmg)

iPhone companion is not the v1 floor.

---

## Docs

| | |
| --- | --- |
| Product / agents | [`AGENTS.md`](AGENTS.md) — start here if you are changing this repo |
| Legal | [`docs/legal/`](docs/legal/) |
| Privacy | [`docs/legal/Privacy_Policy.md`](docs/legal/Privacy_Policy.md) |
| Support | support@allnighter.io |

---

© 2026 Happy Moose Apps Inc. Allnighter and alln are trademarks.
Not affiliated with Anthropic, OpenAI, xAI, Google, or Cursor.
