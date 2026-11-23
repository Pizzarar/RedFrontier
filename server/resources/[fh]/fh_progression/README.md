# fh_progression

Regional rep tiers and unlocks (M7). Read-only: it never writes rep; fh_economy owns that.

## Exports (server)
- `exports.fh_progression:getTier(src, region_id)` -> `1..3` (1 for unknown region / no character)
- `exports.fh_progression:canUnlock(src, unlock_id)` -> `ok, reason`
  Reasons: `no_player` (no character loaded on `src`), `unknown_unlock`, `unknown_region`, `bad_value`, `tier_too_low`.
- `exports.fh_progression:getRep(src, region_id)` -> number (0 if unknown)

## Events
- Emits `fh:progression:tier_changed` `{ src, citizenid, region_id, old, new }` when a tier crosses.
  Never emitted on a cold cache (first load / resource restart), only between two known values.
- Consumes `fh:economy:rep_changed` (`value` may be nil: re-read), `RSGCore:Server:PlayerLoaded`,
  `RSGCore:Server:OnPlayerUnload`, `playerDropped`, `onResourceStart` (preloads online players).

## Config (`config.lua`, `FhProgressionConfig`)
- `tiers[region_id] = { t2 = n, t3 = n }`: minimum rep per tier; region ids come from `fh_core/shared/regions.lua`.
- `unlocks[unlock_id] = { region_id, min_tier }`.

## Cache
`server/progression_cache.lua` (pure, injected deps, covered by `spec/progression_cache_spec.lua`). Per player (keyed by
`src`, validated against `citizenid`), all configured regions loaded together. Rep reads yield, so: a load commits only if
no newer load / `rep_changed` / unload / drop for that `src` happened meanwhile and the character is unchanged; a
`rep_changed` re-read applies only if no newer change for that region arrived (no stale overwrite, no double emit).
A read error keeps the old value, emits nothing and marks the entry for reload on next access.

## Rep read
`server/compat_rep.lua` is the only reader: `exports.fh_economy:getRep(citizenid, region_id)` -> `integer|nil, err`
(@core B7). A nil+err from the export stays an error (never 0). Only when the call itself fails (no export yet) it falls
back to a read-only `SELECT` on `fh_rep`. Workaround: remove the fallback when fh_economy exports getRep (idea-600).

Logic is pure (`shared/progression_logic.lua`) and covered by `spec/progression_spec.lua`.
