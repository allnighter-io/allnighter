# OCL-S00 dogfood target

STATUS: BEFORE

## Notes
Pipe probe file. Agents may change STATUS only.

## Ops
- Never kill `alln serve` (long-lived daemon). `identityAlive` on a terminal
  run can point at that daemon — check `ps` before any kill.
- Leftover `opencode serve` on :4096 blocks the next `alln run` with
  `opencode serve busy` until cleared or attach is implemented.
