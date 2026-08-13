# Second Mac Bench — the two-machine problem

Status: **V2 / NOT STARTED / NO CODE AUTHORIZED.** Packet **3 of 3** in the
local-work split. Opened 2026-08-09 by founder ruling as a *placeholder with a
scope fence*, not a plan. Do not start slices; do not resurrect the shelved
architecture (§2).
Revised: 2026-08-09 (v1 — stub)
Owner: unassigned
Created: 2026-08-09
Origin: The 2026-08-09 segment read for
[`OpenCode_Local_Ollama_Seats.md`](OpenCode_Local_Ollama_Seats.md) found that
**every** local-model segment has the same shape — *the big-memory Mac is rarely
the machine you type on.* Studio in the office, laptop on the couch. That put
real pressure on a non-goal, so it gets a packet rather than silence.

**Sequencing (founder, 2026-08-09):** (1) nail Ollama seats →
(2) [`Context_Firewall.md`](Context_Firewall.md) → **(3) this.**

---

## 1. Why this exists as a document at all

Because the tension is real and the previous answer was silence.

- Large-memory Macs are where the interesting local models actually run.
- That machine is usually **not** the machine the developer types on.
- Multi-host execution is shelved, for good reasons that still hold (§2).

Leaving that unwritten means every future agent rediscovers the tension and
proposes the shelved architecture again. This packet exists to **hold the fence
and record the narrow doors**, not to open them.

## 2. What is shelved and stays shelved

[`Mac_Studio_LAN_Bench.md`](../archive/phases/Mac_Studio_LAN_Bench.md) —
shelved 2026-08-06 after founder review. Its reasoning is binding input here,
not history to be re-argued:

- Streaming prompt/context → diffs onto a laptop working tree **fights how agent
  CLIs actually work** (iterative FS + tools + tests) and collides with
  one-mutator-per-root.
- Reusing the iOS Tailscale pairing spine as a Mac execution plane **confuses
  the control plane with worker offload**.
- "Remote Bench Node" + leverage framing **selects Studio vanity over the real
  ICP**.
- Bundling three different problems into one phase becomes a home-cluster
  product by accident.

**Do not resume that packet.** Read it before proposing anything here.

## 3. The three narrow doors (from the archive, unchanged)

The shelved doc already decomposed what could legitimately return, **as separate
packets only**. That decomposition is adopted verbatim as this packet's scope
fence, ordered by risk:

| Door | What | Risk |
| --- | --- | --- |
| **D1 — remote inference URL** | A remote `OLLAMA_HOST` as an *inference base URL only*. The agent body, the tools, the filesystem, and the write lock all stay on the local machine. Nothing executes remotely. | **Lowest.** This is a model endpoint, not a bench node. It is arguably packet 1's shape with a different URL. |
| **D2 — research-only remote seats** | Snapshot in → text out. Observational only. No mutation, no working tree, no lock held across a network. | **Medium.** Needs host identity and honest failure attribution. |
| **D3 — explicit session host ownership** | A run names its host, explicitly, once. | **Highest.** Never silent cross-host mutator failover; never PeerTransport-as-execution-fabric. |

**D1 is the only door worth opening first**, and it may be small enough that it
never needs slices of its own.

## 4. Ironclad non-goals (inherited)

- Silent cross-host mutator failover.
- A multi-host execution fabric, cluster, or bench-node pool.
- Holding a per-root write lock across a network.
- Reusing the iOS pairing/control spine as a worker execution plane.
- A mandatory third-party coordination cloud.
- Anything that makes a second machine a *requirement* rather than an option.

## 5. Preconditions before this packet may open

1. Packet 1 shipped: an honest single-machine local seat exists (a remote
   inference URL is meaningless before a local one is trustworthy).
2. Packet 2 settled: if a remote host is involved, **the egress question is
   already answered** — a remote inference URL is a crossing, and it must appear
   in the ledger like any other ([`Context_Firewall.md`](Context_Firewall.md)
   §4.3).
3. A founder ruling naming **which door** (§3) opens, and why now.

Until all three hold, the correct response to "can I use my Studio from my
laptop?" is: **not yet, and here is why** — not a design.

## 6. Open questions (do not answer speculatively)

1. Is D1 a packet at all, or a two-line configuration note inside packet 1?
2. Does a remote inference URL change provenance? A model running on *your other
   Mac* is still local-provenance in the wallet sense and **not** local in the
   egress sense. Those two meanings diverge here for the first time — packet 2
   §4 owns the resolution.
3. What does capacity/readiness mean when the host is not this machine?
   (Packet 1's `Available | Unavailable` per seat assumes `127.0.0.1`.)

## 7. Done when

Not applicable — this packet has no authorized work. It exits by either being
opened with a founder ruling (§5) or archived as permanently fenced.

---

## AGENTS.md routing

| Task | Read first |
| --- | --- |
| Second Mac, Studio in the office, LAN bench, remote `OLLAMA_HOST` | This packet §2–§5 — **fence first**; the shelved architecture stays shelved |
| Anyone proposing multi-host execution or cross-host failover | §2 + §4 — refuse, and point at [`Mac_Studio_LAN_Bench.md`](../archive/phases/Mac_Studio_LAN_Bench.md) |
| Local seats on this machine | [`OpenCode_Local_Ollama_Seats.md`](OpenCode_Local_Ollama_Seats.md) — packet 1 |
| Whether a remote host is an egress crossing | [`Context_Firewall.md`](Context_Firewall.md) §4.3 — packet 2 owns it |
