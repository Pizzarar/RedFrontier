# fh_anim

Cosmetic, named action animations (plan animations-01). Client-only; on by default (`Config.Enabled = true`);
entries in `shared/anims.lua` are still candidates until A7 swaps in the S8-confirmed ones.

- `exports.fh_anim:play(key)`: instant clip, auto-ends after `ms`.
- `exports.fh_anim:start(key)` / `:stop(key)`: wrap a progress bar; `stop` clears only if our anim is still active.
- `TriggerClientEvent('fh:anim:play', src, key)`: fire-and-forget from server success paths. No-op if fh_anim is stopped.
- Unknown key or flag off returns `false`, no error. Skipped when mounted, in a vehicle, swimming, dead, ragdolling
  or already in a scenario.
- Scenarios start via `TaskStartScenarioInPlaceHash(joaat(name))` (not ox_lib `anim.scenario`).
- Pure logic: `shared/anim_logic.lua`, spec `spec/anim_spec.lua`.

Keys: skin, gather, eat, drink, craft, cook, chest_open, trough, plant, harvest, refill, wash.
