# fh_economy

Money & rep ledger (spec 4.6). All payouts and rep changes go through here; every call appends a `fh_ledger` row.

## Exports (server)
- `exports.fh_economy:pay(src, amount, reason, region_id)` -> `ok, err, ledgerId`
  Credits `config.moneyType` (`cash`) via RSGCore `Player.Functions.AddMoney`.
- `exports.fh_economy:rep(src, region_id, delta, reason)` -> `ok, err`
  Atomic: clamped `value = value + delta` upsert and the ledger insert share one transaction.

`pay` writes the ledger row first, then `AddMoney`; if `AddMoney` fails the row is deleted again
(the only DELETE, on its own just-inserted row), so there is never money without a row or a row without money.
`src` must be a number and a character must be loaded in rsg-core.

Refused (returns `false, code`): `invalid_amount`, `amount_too_large`, `invalid_delta`, `delta_too_large`,
`invalid_reason` (empty or longer than `maxReason`), `unknown_region`, `no_player`, `ledger_failed`, `addmoney_refused`. Validation lives in `shared/ledger_logic.lua` (pure, tested).

## Events
- Emits: `fh:economy:paid`, `fh:economy:rep_changed` (payloads in `fh_core/docs/events.md`).
- Consumes: none.

## Config keys (`config.lua`)
`moneyType`, `maxPay`, `maxRepDelta`, `maxReason`, `repMin`, `repMax`.

## DB tables (`server/migrations/0002_fh_ledger.sql`)
- `fh_ledger` (id, citizenid, kind pay|rep, amount, reason, region_id, created_at): append-only.
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
