# fh_anim

Cosmetic, named action animations (plan animations-01). Client-only; off by default (`Config.Enabled = false`)
until the P0 probe (`spk_anim`) confirms which clips play in RedM. Table entries in `shared/anims.lua` are
**candidate, unproven**.

- `exports.fh_anim:play(key)`: instant clip, auto-ends after `ms`.
- `exports.fh_anim:start(key)` / `:stop(key)`: wrap a progress bar; `stop` clears only if our anim is still active.
- `TriggerClientEvent('fh:anim:play', src, key)`: fire-and-forget from server success paths. No-op if fh_anim is stopped.
- Unknown key or flag off returns `false`, no error. Skipped when mounted, in a vehicle, swimming, dead, ragdolling
  or already in a scenario.
- Scenarios start via `TaskStartScenarioInPlaceHash(joaat(name))` (not ox_lib `anim.scenario`).
- Pure logic: `shared/anim_logic.lua`, spec `spec/anim_spec.lua`.

Keys: skin, gather, eat, drink, craft, cook, chest_open, trough, plant, harvest, refill, wash.
