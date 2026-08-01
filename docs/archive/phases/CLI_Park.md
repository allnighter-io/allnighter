# CLI Park (On bench / Parked)

Status: **Complete — 2026-07-29** (code SSOT `SetupStore.parkedDriverIds`, `DriversCLI`,
`DriverParkTests`; contract examples in `ContractRegistry`)
Owner: Shared Core + CLI + Mac
Updated: 2026-07-29

Ephemeral build packet. Runtime SSOT is code (`SetupStore.parkedDriverIds`,
`DriverPark`, `alln drivers`). Archived 2026-08-01 after `073522c7` shipped
park/unpark + Mac setup UI. Vocabulary in `Product_Vocabulary.md`.

## Claim

A user can **park** a CLI they are not using. Parked CLIs are grayed out, skipped
on re-check, absent from Ready / Needs attention / model pickers, and listed
**last** in `alln drivers --json` (hook for future `alln capacity` / status).

## CLI surface

```text
alln drivers [--json]
alln drivers park <driver-id> [--json]
alln drivers unpark <driver-id> [--json]
```

## Truth owner

`SetupStore.State.parkedDriverIds` in `cli_setup.json`.

## Works Test

```text
alln drivers park opencode --json
# → that row status=parked, listed last; models for opencode ready=false / status=parked
alln drivers unpark opencode --json
# → no longer parked
```

GUI: CLI setup detail → On bench | Parked control; Parked section last in list.

## Proof (this slice)

- Unit: `DriverParkTests` (persist, legacy decode, ready exclusion, list order).
- Contract/help: `ContractRegistryTests`, `HelpTopicRegistryTests`.
- Live: `alln drivers park|unpark` exercised on a built `alln` binary.
