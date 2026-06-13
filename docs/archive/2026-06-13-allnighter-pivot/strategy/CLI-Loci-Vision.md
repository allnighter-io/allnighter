**CLI Loci**  
**Functional Requirements Document — First Draft**  
**Version 0.1 | June 12, 2026**

---

### 1. Vision Statement

**CLI Loci** is the native command center that turns a developer’s Mac into a powerful, always-on multi-agent orchestration hub and their iPhone into the perfect, always-available remote control surface — for **any** terminal-based AI coding agent they choose to run.

It delivers one beautiful, unified experience across macOS and iOS so that developers no longer have to:
- Switch between the official Claude app, Telegram bots, raw Terminal windows, or half-baked browser wrappers.
- Be desk-bound while long-running agents work.
- Accept cloud coordination layers or vendor lock-in just to get a decent mobile handoff.
- Juggle multiple fragmented tools when they naturally use Claude Code + Grok Build + Aider + Codex CLI (and whatever comes next) in the same week.

**Core promise**:  
“One native app on your Mac. One delightful companion on your iPhone. Every local CLI agent you run. Real parallel execution. Radical privacy. Zero mandatory cloud. Zero server costs for the developer building it.”

CLI Loci is **not** “another AI agent app.” It is the **universal remote and mission-control layer** that sits above the agents developers already love and trust.

---

### 2. Core Idea & Positioning

**The Mac app is the powerful heart.**  
It is a native, **unsandboxed** SwiftUI macOS application (distributed directly via DMG/PKG + notarization) that:
- Spawns, manages, and orchestrates multiple headless/background PTY sessions for any supported CLI agent.
- Provides a rich, native dashboard with live status, progress, cost estimates, parsed diffs, and quick actions.
- Runs as a menu-bar / status-item app with optional persistent window so it can stay alive in the background.
- Exposes a clean, documented local WebSocket API (SwiftNIO) that the iOS app (and future clients) connect to over Tailscale or local network.

**The iOS app is the elegant remote.**  
It connects directly to the user’s own Mac app over their private Tailscale network and delivers first-class native mobile experiences that no web UI or vendor app can match:
- Live Activities + Dynamic Island
- Context-aware haptics
- Swipeable, tactile diff approval cards
- Rich actionable push notifications (optional self-hosted relay)
- Voice dictation, Shortcuts/Siri integration, widgets, Share Sheet, camera input

**The combination solves the real pain**:
- “Opening new terminal windows is annoying” → The Mac app manages everything cleanly.
- “I want to walk away and still steer” → True parallel headless sessions + beautiful iOS remote.
- “I hate vendor clouds and $100–200/month subscriptions just for mobile control” → Tailscale P2P + BYOK (Bring Your Own Keys).
- “I use multiple agents and hate switching apps” → One universal interface.

**Positioning statement for mentors**:
CLI Loci is the power-user, local-first, multi-agent “mission control” that Claude’s official remote and the current fragmented indie tools have left on the table. It is platform-neutral by design and deliberately stays out of the model/agent wars.

---

### 3. Problem Statement (Why This Exists)

Serious AI developers in 2026 routinely use 2–4 different CLI coding agents depending on task, model strengths, cost, and speed. Each agent has its own interface:
- Claude Code → Official remote requires high-tier subscription + routes through Anthropic coordination layer.
- Grok Build → Strong Telegram remote, no polished native iOS experience yet.
- Aider, Codex CLI, Cline, Kilo, Goose, etc. → Mostly raw terminal or basic browser wrappers (itwillsync, etc.).

**Resulting pain**:
- Context switching and lost flow.
- Inability to easily run multiple agents in parallel on the same or different codebases.
- Poor or non-existent mobile experiences for long-running work.
- Privacy concerns when session state or diffs travel through third-party clouds.
- Subscription fatigue and vendor lock-in.
- The simple annoyance of managing many terminal windows and background processes.

CLI Loci exists to eliminate that fragmentation and friction with a single, delightful, local-first native layer.

---

### 4. Target Users & Personas

**Primary Persona: “Power Solo Dev” (Mike archetype)**  
- iOS developer who also builds with AI agents daily.
- Uses Grok Build + Claude Code + Aider regularly.
- Wants to start heavy work on Mac Mini from desk, then monitor/steer/approve from iPhone while walking the dog or at a coffee shop.
- Values privacy, speed, and native feel over everything.
- Happy to pay $9.99–$19.99 one-time (or small pro unlock) for a tool that saves hours every week and feels premium.

**Secondary Personas**:
- Privacy-conscious enterprise or finance engineers who refuse to route code through Anthropic/OpenAI coordination servers.
- Multi-machine power users (desktop + Mac Mini + laptop).
- Early adopters who like to run the latest agents and want one place to control them all.

---

### 5. Key Differentiators (The 10x Hooks)

1. **True Universality** — One app controls Claude Code, Grok Build, Aider, Codex CLI, and future agents via an extensible bridge layer. No app switching.
2. **Real Parallel “Walk-Away” Execution** — Spawn and manage multiple headless/background sessions simultaneously (different worktrees, different agents). Monitor all of them from the couch.
3. **Radical Local-First Privacy + BYOK** — Everything stays on the user’s machines and private Tailscale network by default. No mandatory third-party coordination servers. Users paste their own API keys once.
4. **Native Mac Dashboard + iOS Superpowers** — Beautiful SwiftUI on both platforms. Live Activities, haptics, swipe-to-approve diffs, voice, Shortcuts, widgets — the micro-wow moments that make people tweet about it.
5. **Zero Server Costs for the Builder** — Direct distribution. No backend to run or maintain.

---

### 6. High-Level Architecture (Mac + iOS Combo)

**macOS App (Primary — Unsandboxed)**
- Swift 6 + SwiftUI (main UI) + targeted AppKit where needed.
- PTY / Process management layer (Foundation.Process + C interop or tmux-backed for reliable background sessions).
- Session orchestration engine (parallel headless sessions, worktree isolation, state persistence).
- Output parser + diff engine (one place that turns raw CLI output into structured events and beautiful SwiftUI diff cards).
- Local WebSocket server (SwiftNIO + NIOWebSocket) exposing clean JSON protocol.
- Tailscale detection + direct P2P connection handling.
- Menu-bar / status item + background mode.
- Keychain for API keys.
- First-run permission wizard (Full Disk Access, etc.) with clear explanations.
- Optional lightweight daemon mode for headless Mac Minis.

**iOS App (Companion Remote)**
- Swift + SwiftUI.
- `URLSessionWebSocketTask` connecting to the Mac app’s WebSocket server over Tailscale/local network.
- Rich session view with streaming, collapsible tool steps, and swipeable parsed diff cards + Core Haptics.
- Dashboard mirroring + mobile-optimized list/grid.
- Live Activities + Dynamic Island.
- WidgetKit, App Intents + Shortcuts + Siri.
- Optional self-hosted push relay (ntfy or tiny companion binary the user can run).
- Voice dictation, Share Sheet, camera input.

**Shared Swift Package (Maximum Code Reuse)**
- All data models (`Session`, `AgentType`, `Diff`, `Event`, `Machine`, etc.).
- Output parsers and diff rendering logic.
- WebSocket protocol definitions (message types for chat, approvals, status, diffs, etc.).
- Common utilities.

**Communication & Security**
- Preferred: Direct encrypted Tailscale P2P.
- Fallback: Local network.
- Auth: Short-lived pairing tokens + device identity (QR code or Tailscale device picker flow).
- Everything stays on user’s hardware/network by default.

**Distribution**
- macOS: Direct notarized DMG/PKG (Developer ID). Sparkle (or similar) for updates.
- iOS: App Store (or TestFlight initially).
- No mandatory cloud services. Optional self-hosted relay for push only.

---

### 7. MVP Scope (First Shipable Version)

**Must-have for v1 (Personal tool → early testers in 4–8 weeks of focused work)**:
- Tailscale-first onboarding + QR/Tailscale device pairing.
- Support for 3 agents initially: Claude Code, Grok Build, Aider (via config/plugin layer so new ones are easy to add).
- Mac app: Dashboard showing machines + active sessions. Ability to launch new session or attach to running one. Basic rich session view with streaming output and simple approvals.
- iOS app: Connect to Mac, see dashboard, open one rich session view with streaming + basic approvals.
- Simple parsed diff cards (at least basic approve/reject).
- Context-aware haptics on key events.
- BYOK flow (paste keys in Mac app, stored in Keychain).
- Background session persistence (sessions keep running if Mac app is closed or Mac sleeps — using tmux or native PTY management).

**Phase 2 (The “wow” release)**:
- True parallel headless session spawning and management from phone or Mac.
- Beautiful swipeable diff cards with success/reject haptics.
- Live Activities + Dynamic Island + rich actionable notifications.
- Multi-machine support.
- Voice input + Shortcuts deep integration.
- Cost tracking across sessions.
- Session history + searchable diffs.

**Out of MVP (v2+)**:
- Android companion.
- Collaborative session sharing.
- Advanced git/PR helpers.
- Plugin marketplace for new agents.
- Windows/Linux desktop companion (possible Tauri later).

---

### 8. Monetization (People Will Pay)

- One-time purchase: **$9.99 – $19.99** (or $4.99 launch price).
- Optional freemium: Free for 1 machine + 1 active session. Paid unlocks unlimited parallel agents, multi-machine, advanced features, and priority updates.
- Small optional subscription tier for power users who want early access to new agent integrations and pro support.
- Zero server costs → high margin even at small volume.

Power users who save hours per week and get native delight are very willing to pay a one-time or low recurring fee for this class of tool.

---

### 9. Open Questions for Mentors (Feedback Requested)

1. **Architecture choice**: Do you agree that the Mac app (unsandboxed) + iOS companion is meaningfully better than a pure headless daemon + web/iOS remote? Where would you cut scope first?
2. **PTY strategy**: Start with tmux-backed sessions for reliability, or go straight to native PTY management? Any strong opinions on the technical approach?
3. **MVP cut**: Is supporting 3 agents (Claude + Grok + Aider) in v1 too ambitious or about right? Would you launch with just 2?
4. **Name & positioning**: CLI Loci vs Cli Cortex vs something else? Does the “universal remote for CLIs” framing land cleanly with power users?
5. **Pricing & packaging**: One-time vs freemium vs small sub? Any red flags?
6. **Distribution & permissions**: Any concerns with the direct DMG + Full Disk Access flow for the target audience?
7. **Open-sourcing the bridge/protocol**: Worth doing early to create a standard and drive adoption, or keep closed longer?
8. **Biggest risk**: What do you see as the highest-risk part of this (technical, market, or execution) and how would you de-risk it?

---

### 10. Next Steps (After Feedback)

- Lock name, domains, and basic branding.
- Define the exact WebSocket protocol (message types, auth handshake, session lifecycle, diff events).
- Build the shared Swift Package models + parsers first.
- Prototype Mac PTY layer + simple dashboard.
- Prototype iOS WebSocket connection + basic session view.
- Dogfood daily while iterating.

---

This is the first draft. It captures the full vision we’ve been building together while staying focused enough to share with mentors.

I kept it detailed on vision, core idea, architecture, and differentiators (as requested) while leaving room for expansion on exact UI flows, data models, and protocol spec in later versions.

Would you like me to:
- Expand any specific section right now (e.g., detailed user stories, full WebSocket protocol sketch, onboarding flow, or UI screen descriptions)?
- Adjust tone, length, or add/remove anything before you share it?
- Create a clean Markdown/PDF version saved to the artifacts folder?

Just say the word and I’ll refine it instantly. This feels like a strong, mentor-ready starting point.