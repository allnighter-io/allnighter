# SC-S04b — Product-owned serve enable / disable (LaunchAgent → staged binary)

Run: `90FEB7F3-6FEB-4951-83C7-C13FBE18031F` (Kimi K3; shortRemaining≈31%)  
Status: **done** (2026-08-09) — commit `b7eecd78`; Works Test 11/11  
Slice: SC-S04b (small)  
SSOT: [`docs/phases/Serve_Continuity.md`](../../Serve_Continuity.md) §6 + §4 SC-S04b  
Executor: Kimi K3 if 5h remaining ≥15%; else DeepSeek V4 Pro

## Goal

`alln serve enable` / `alln serve disable`: product-owned LaunchAgent for
`com.allnighter.resident-coordinator` that runs the **staged** stable binary
(`ServeStableBinary` destination). Migrate/replace any leftover CODE_RED plist.
Default remains **opt-in** (enable is explicit). No install-cli wiring yet (S02).

## Shipped

- `ServeLifecycle.enable` / `disable`; CLI `serve enable|disable [--json]`
- Contract 9.16.0; never supervises `/.local/bin/`
- Filtered proof: `scripts/swift-test.sh --filter ServeLifecycleEnableTests`
