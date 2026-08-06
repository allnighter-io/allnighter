# Mac Studio LAN Bench Node & Remote Multi-Seat Offloading

Status: **SHELVED / NO BUILD (2026-08-06)** — founder agreed after review.
Do not resume this packet or authorize slices from it without a new founder
ruling. Historical brainstorm only; no product law was promoted.

**Why shelved:** The pain (multi-account quota, remote local-GPU inference) is
real; the proposed architecture is not. Streamed prompt/context → diffs onto the
laptop working tree fights how agent CLIs actually work (iterative FS + tools +
tests) and collides with one-mutator-per-root. Reusing the iOS Tailscale pairing
spine for a Mac execution plane confuses control plane with worker offload.
“Remote Bench Node” + 5–10× leverage framing selects Mac Studio vanity over the
real ICP (multi-CLI power user, one floor, agent-native). Bundle of three
different problems (local inference URL, second-identity ops, multi-host
mutators) into one phase would become a home-cluster product by accident.

**If anything returns later (separate packets only):** (1) optional remote
inference `baseURL` / Ollama host for local-model seats; (2) research-only remote
seats (snapshot in → text out); (3) explicit session host ownership — never
silent cross-host mutator failover or PeerTransport-as-execution fabric.
Priority stays single-Mac capacity truth, park/substitute, and agent teaching.

Owner: unassigned (shelved)
Created: 2026-08-06
Archived: 2026-08-06
Origin: Founder input / ICP First Principles brainstorm. High-frequency vibe coders frequently own dedicated Mac Studio / local hardware (128GB+ RAM) and multiple CLI subscriptions, but suffer from single-machine thermal load and mid-session quota exhaustion.

---

## 1. Executive Summary & Core Concept

Allnighter’s primary promise is: **"You already pay for the team. Allnighter makes it show up to work."**

Vibe coders and power builders often own:
1. **Multiple subscriptions** (e.g., primary Claude Pro/Team, secondary ChatGPT/OpenCode-Go accounts).
2. **Dedicated local hardware** (e.g., an M2/M3/M4 Ultra Mac Studio sitting on their local network with 128GB–192GB Unified Memory).

Today, utilizing that Mac Studio requires high-friction setup: manually setting up SSH tunnels, managing separate git clones/branches, or manually copy-pasting code between local and remote windows.

### The Solution Framing: Remote Bench Node
By re-purposing Allnighter's **iOS pairing protocol** (zero-cloud, direct peer-to-peer over Tailscale / Local Network), a Mac Studio on the LAN registers as a **Remote Bench Node**. It exposes a catalog of seats (`studio:ollama-32b`, `studio:opencode-go-sub2`, `studio:claude-code-sub2`) to the main workstation.

---

## 2. Core Architectural Invariant: Single Repository / Single Working Tree

**Crucial Invariant:** Work is **NEVER** split across separate git branches or remote clones on the Mac Studio.

```
┌────────────────────────────────────────────────────────┐
│  YOUR MAIN WORKSTATION (e.g. MacBook Pro)              │
│  • Single Source of Truth (SSOT) for code & git state  │
│  • Allnighter Master App / CLI                         │
│  • Diffs applied directly to local working tree         │
└──────────────────────────┬─────────────────────────────┘
                           │ 
             Tailscale / Local Network (iOS Transport)
             Prompts/Context In ──► Diffs Out
                           │
┌──────────────────────────▼─────────────────────────────┐
│  MAC STUDIO — Remote Bench Node                        │
│  • Runs local LLMs (Qwen 32B, DeepSeek R1 70B)         │
│  • Holds Secondary Credentials (Account #2)            │
└────────────────────────────────────────────────────────┘
```

* **No Git Sync Overhead:** No `git pull`, `git push`, branch switching, or merge conflicts.
* **Streamed Diffs:** The Mac Studio acts purely as an execution engine. Prompt and file contexts stream over the encrypted LAN transport; generated diffs are applied directly to the user's active local workspace on their primary Mac.

---

## 3. ICP Problem Rankings (First Principles 0–10 Scale)

Evaluating potential problem spaces for high-frequency vibe coders:

| Problem Space | Rating (0–10) | Rationale |
| :--- | :---: | :--- |
| **Heterogeneous Tiered Dispatch (Frontier Lead + Zero-Cost LAN Execution Bench)** | **9.8 / 10** | **Hero Capability.** Uses Claude/GPT-4o for pilot reasoning, but delegates mechanical deslop, log parsing, and initial research to zero-cost local 32B/70B models on the Mac Studio. |
| **Quota Harvesting & Multi-Account Subscription Stacking** | **9.5 / 10** | **Unsolved Friction.** Allows running a second OpenCode-Go / Claude subscription on the Mac Studio to automatically harvest double daily quota without keychain/login collisions on the main Mac. |
| **Mac Studio LAN Node Offload** | **7.5 / 10** | Unlocks idle $5k Mac Studio hardware without thermal load on the main laptop, using existing iOS Tailscale pairing. |
| **Local Ollama on Primary Machine** | **5.0 / 10** | Useful, but running 32B+ models locally bogs down the primary MacBook Pro during active compilation/IDE work. |

---

## 4. Net Value Boost: How Much Better is ALLN for Vibe Coders?

Comparing standard multi-subscription / Mac Studio workflows vs. Allnighter with Remote Bench Nodes:

### Status Quo (Today)
- **Manual context switching:** Copy-pasting prompts to web UI or separate SSH terminals when local CLI hits a rate limit.
- **Laptop fan noise & lag:** Running local 32B models bogs down the primary dev machine.
- **Wasted hardware:** The $5,000 Mac Studio sits idle 90% of the day because wiring it into daily CLI workflows is tedious.
- **Quota walls:** Hitting a 5-hour limit stops work cold or requires switching tools manually.

### With ALLN Remote Bench Nodes (~5x to 10x Workload Leverage)
1. **Un-throttled Continuity (2x–3x Quota Ceiling):** Seamless fallback across local and remote secondary subscriptions. When Seat 1 hits a rate limit, Allnighter shifts execution turns to Seat 2 on the Mac Studio instantly.
2. **Zero-Cost Mechanical Iterations:** Initial deslop, boilerplate generation, and search turns run on the Mac Studio's local GPU at 70+ tokens/sec for $0 token cost.
3. **Zero Thermal Footprint:** The primary MacBook Pro stays completely silent, cold, and fast while heavy agent work executes on the Studio.
4. **Zero Git Friction:** Single-repo invariant preserves total flow state—no branch management across machines.

---

## 5. Next Steps & Open Questions

- **Spike Candidates:** Can the iOS network handshake (`Tailscale / LAN peer discovery`) be abstracted into a shared `PeerTransport` usable by both iOS and macOS secondary hosts?
- **Credential Storage:** How are secondary subscription credentials securely isolated on the remote Mac Studio host?
- **Status:** Ephemeral brainstorm doc. No code slice authorized.
