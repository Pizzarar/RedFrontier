# fh_economy

Money & rep ledger (spec 4.6). All payouts and rep changes go through here; every call appends a `fh_ledger` row.

## Exports (server)
- `exports.fh_economy:pay(src, amount, reason, region_id)` -> `ok, err, ledgerId`
  Credits `config.moneyType` (`cash`) via RSGCore `Player.Functions.AddMoney`.
- `exports.fh_economy:rep(src, region_id, delta, reason)` -> `ok, err`
  Atomic: clamped `value = value + delta` upsert and the ledger insert share one transaction.
- `exports.fh_economy:charge(src, amount, reason, region_id)` -> `ok, err, ledgerId` (B7)
  Debit, the mirror of `pay`: balance check, ledger row `kind='charge'` (amount = the positive sum taken) FIRST, then
  RSGCore `Player.Functions.RemoveMoney` on a Player looked up again after the insert. Never takes the balance
  below 0. Short at the first check -> `fh_insufficient_funds`, nothing written; short at the re-check after the
  insert (money spent meanwhile) -> `fh_insufficient_funds` and the just-inserted row is deleted again, as for a
  refused RemoveMoney. Emits `fh:economy:charged` on success.
  **One at a time per character:** while a charge for a citizenid is in flight, another charge for the same
  character returns `false, 'fh_charge_busy'` at once (no row, no money). It does not queue; retry if you need to.
- `exports.fh_economy:getRep(who, region_id)` -> `rep` or `nil, err` (B7)
  Integer rep, 0 when there is no row. `who` = a player server id (number, character loaded) or a citizenid string
  for offline reads: 1-50 letters, digits, `_` or `-`. An all-digit string (a mistyped server id), a blank, padded
  or otherwise malformed string, and any other type are refused with `no_player` instead of reading 0.

`pay` and `charge` write the ledger row first, then move the money; if that fails the row is deleted again
(the only DELETE, on its own just-inserted row), so there is never money without a row or a row without money. If
that DELETE itself fails, the server console logs `[fh_economy] WARNING: could not void ledger row <id> ...`
(audit that row by hand). `src` must be a number and a character must be loaded in rsg-core.
The ledger insert yields: after it, both re-fetch the player by `src` and check it is still the same citizenid.
If the player dropped -> `no_player`; if another character is now loaded on `src` -> `player_changed`. Either way
the row is deleted again and no money moves (the Player object from before the insert is never used).

Refused (returns `false, code`): `invalid_amount`, `amount_too_large`, `invalid_delta`, `delta_too_large`,
`invalid_reason` (empty or longer than `maxReason`), `unknown_region`, `no_player`, `ledger_failed`. Validation lives
in `shared/ledger_logic.lua` (pure, tested).
`pay` adds: `player_changed`, `addmoney_refused`.
`charge` adds: `amount_too_large` (over `maxCharge`), `fh_insufficient_funds`, `fh_charge_busy`, `player_changed`,
`removemoney_refused`.
`getRep` returns `nil` with `unknown_region`, `no_player` or `ledger_failed` (DB read failed).

## Events
- Emits: `fh:economy:paid`, `fh:economy:rep_changed`, `fh:economy:charged` (payloads in `fh_core/docs/events.md`).
- Consumes: none.

## Config keys (`config.lua`)
`moneyType`, `maxPay`, `maxCharge` (cap on one charge, default 100000), `maxRepDelta`, `maxReason`, `repMin`, `repMax`.

## DB tables (`server/migrations/0002_fh_ledger.sql`)
- `fh_ledger` (id, citizenid, kind pay|rep|charge, amount, reason, region_id, created_at): append-only.
  `server/migrations/0006_fh_ledger_charge.sql` widens the `kind` enum with `charge` (B7); existing rows untouched.
- `fh_rep` (citizenid, region_id, value), PK (citizenid, region_id).

Region ids: fh_economy loads `@fh_core/shared/regions.lua` itself in its manifest (`shared_scripts`), so it
does not depend on fh_core's manifest listing it (B4a's `shared/*.lua` glob covers fh_core's own use).

## Tests
`lua spec/ledger_logic_spec.lua` from the repo root, or busted. (Not yet run: no Lua interpreter on the build machine.)

## In-game test checklist
- [ ] Server console `fh_pay <id> 5` -> cash +$5, one `fh_ledger` row kind=pay.
- [ ] `fh_pay <id> 0` and `fh_pay <id> -5` -> refused, no row, no cash change.
- [ ] `fh_rep <id> 10` twice -> `fh_rep.value` = 20, two ledger rows kind=rep.
- [ ] Unknown region / empty reason via an exports call from another resource -> refused.
- [ ] Migration 0005 applied; server console `fh_charge <id> 5` with >= $5 -> cash -$5, one `fh_ledger` row
      kind=charge amount=5; with less cash than asked -> `fh_insufficient_funds`, no row, no cash change.
- [ ] `exports.fh_economy:getRep(<id>, 'heartlands')` after the `fh_rep` step -> 20; same with the citizenid -> 20;
      `getRep('12', 'heartlands')` -> `nil, 'no_player'`.
