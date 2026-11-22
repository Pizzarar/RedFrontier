# fh_buffs

Buff interface (spec 4.5). Server state only; the client side is a stub (no effects yet).

## Exports (server)
- `exports.fh_buffs:apply(src, buff_id, magnitude, duration)` -> `ok, result|err`
  `result = { magnitude, expires_at, refreshed }`; duration in seconds.
- `exports.fh_buffs:get(src)` -> `{ [buff_id] = { magnitude, expires_at } }` (active only).

## Stacking rules (single source: `shared/buff_logic.lua`)
- Different buffs stack.
- Same buff (still active) refreshes: expiry = now + duration, magnitude = max(old, new).
- Magnitude is capped per buff (`config.caps`). Unknown buff ids are refused (`unknown_buff`).
- Invalid magnitude/duration (<= 0, NaN, infinite, non-number) refused.
- `src` must be a number with a loaded rsg-core character (`no_player` otherwise); nothing is allocated before validation.

## Events
- Emits: `fh:buffs:applied`; client sync `fh:buffs:sync` (server -> client, snapshot table).
- Consumes: none.

## Config keys (`config.lua`)
`tickMs`, `caps` (per-buff magnitude cap; add new buff ids here).

## DB tables
None (buffs are in-memory; lost on restart/relog by design for M1).

## Tests
`lua spec/buff_logic_spec.lua` from the repo root, or busted. (Not yet run: no Lua interpreter on the build machine.)

## In-game test checklist
- [ ] Console `fh_buff <id> well_fed 1.1 60` -> prints ok and `get` shows the buff.
- [ ] Repeat with magnitude 1.0 -> magnitude stays 1.1, expiry refreshed.
- [ ] Apply `rested` -> both buffs listed.
- [ ] Magnitude 9 -> capped at the config value. Unknown id -> refused.
- [ ] After the duration, `get` no longer lists the buff.
