# fh_economy

Money & rep ledger (spec 4.6). All payouts and rep changes go through here; every call appends a `fh_ledger` row.

## Exports (server)
- `exports.fh_economy:pay(src, amount, reason, region_id)` -> `ok, err, ledgerId`
  Credits `config.moneyType` (`cash`) via RSGCore `Player.Functions.AddMoney`.
- `exports.fh_economy:rep(src, region_id, delta, reason)` -> `ok, err`
  Atomic: clamped `value = value + delta` upsert and the ledger insert share one transaction.
- `exports.fh_economy:repByCitizenid(citizenid, region_id, delta, reason)` -> `ok, err` (idea-804)
  Same write as `rep` (shared inner function: clamp, upsert, `kind='rep'` ledger row, `fh:economy:rep_changed`) keyed
  by citizenid, so it works for an offline character (rep lives in `fh_rep`, which rsg-core holds no copy of).
  The event's `src` is the online server id if that citizenid is loaded, else `nil`. Refused: `invalid_citizenid`
  (same rules as `getRep` strings), `unknown_citizenid` (no `players` row), and `rep`'s delta / reason / region errors.
  Server export only.
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
- `exports.fh_economy:credit(citizenid, amount, reason, region_id)` -> `ok, err, mode` (core-04 E2, idea-700)
  Payout to a character by **citizenid**, online or offline, that never loses money (refunds etc.). `amount` must be a
  positive integer (`5.0` is taken as 5; `5.5`, strings, NaN/inf refused) up to `maxCredit`; same reason / region rules
  as `pay`. On success `err` is nil and `mode` is:
  - `'paid'`: the character is online; the `pay` path ran (ledger row `kind='credit'` first, fresh lookup after the
    insert, `AddMoney`, row voided on failure). Emits `fh:economy:credited` (`queued = false`).
  - `'pending'`: queued. One transaction inserts a `fh_pending_credit` row and a ledger row `kind='credit_pending'`
    (no money moved yet). Also used when the online attempt failed with nothing moved (player left / switched during
    the insert, `AddMoney` refused): the credit is queued instead. It is **never** written to the `players.money`
    column (rsg-core keeps a loaded player's money in memory and saves it over such a write).
  **Claim on load** (`RSGCore:Server:PlayerLoaded`): `UPDATE fh_pending_credit SET claimed_by = <fresh token> WHERE
  citizenid = ? AND claimed_by IS NULL`, `SELECT` by that token, look the character up again, `AddMoney` per row (no
  yield in between), then one transaction writes a `kind='credit'` ledger row per paid row and deletes it (by id AND
  token). Emits `fh:economy:credited` (`queued = true`) per row. A double / concurrent load claims nothing already
  claimed, so a row is paid once. If the character loaded while a queue insert was in flight, `credit` claims at once
  after the insert (mode is still `'pending'`).
  **Failures after the claim:** character gone, or `AddMoney` refused (money verifiably not added: if `AddMoney`
  throws, the balance delta decides) -> those rows are released (`claimed_by = NULL`) and paid on the next load.
  The clearing transaction fails after `AddMoney` succeeded -> the money stays on the character and the rows stay
  **claimed** (never released, so never paid again) with a console
  `[fh_economy] WARNING: pending credits <ids> for <cid> were PAID but not cleared ...`: audit by hand (delete them,
  add their `credit` ledger rows). At resource start, any row still claimed (from an earlier run: crash mid-claim or
  a failed clear) is counted in a WARNING; it may or may not have been paid, so it is never released automatically.
  Credits queued for a character who is online across an fh_economy restart wait for their next load (or next credit).
  Refused: `invalid_citizenid` (not `getRep`'s citizenid shape), `unknown_citizenid` (offline and no `players` row:
  nobody could ever claim it), `invalid_amount`, `amount_too_large`, `invalid_reason`, `unknown_region`,
  `ledger_failed` (DB error; nothing queued, nothing paid).

`pay` and `charge` write the ledger row first, then move the money; if that fails the row is deleted again
(the only DELETE, on its own just-inserted row), so there is never money without a row or a row without money. If
that DELETE itself fails, the server console logs `[fh_economy] WARNING: could not void ledger row <id> ...`
(audit that row by hand). `src` must be a number and a character must be loaded in rsg-core.
The ledger insert yields: after it, both re-fetch the player by `src` and check it is still the same citizenid.
If the player dropped -> `no_player`; if another character is now loaded on `src` -> `player_changed`. Either way
the row is deleted again and no money moves (the Player object from before the insert is never used).
**Logout window (core-07 A1):** rsg-core saves a character on `RSGCore:Server:OnPlayerUnload` / `PlayerDropped` and
keeps it in `RSGCore.Players` for a moment after; money moved then is never saved. From either event until a
character loads on that `src` again, `pay` / `charge` refuse with `no_player` (row voided if one was in flight),
`credit` queues (`'pending'`) and the load claim pays nothing (rows released, paid on the next load). After the
`playerDropped` native the entry is cleared (re-checked every 5 s) once rsg-core no longer has that character on the src.
**Amounts** (`pay`, `charge`): rounded to whole cents (`FhLedgerLogic.toCents`, the same rounding as rsg-core's money
items), and that rounded amount is what moves, what the ledger row and the event carry; a whole amount stays a Lua
integer. One that rounds to 0 (e.g. `0.004`) -> `invalid_amount`. The cap is checked on the amount as given.
**AddMoney / RemoveMoney throwing** after the balance moved counts as moved, so the row is kept and the call succeeds;
a throw before anything moved fails as refused. pay, charge, credit and the claim decide this in integer cents
(`FhLedgerLogic.movedBy`), never as floats: the money-item sync re-reads cash via `%.2f`, and `0.14 + 1 ~= 1.14`.

Refused (returns `false, code`): `invalid_amount`, `amount_too_large`, `invalid_delta`, `delta_too_large`,
`invalid_reason` (empty or longer than `maxReason`), `unknown_region`, `no_player`, `ledger_failed`. Validation lives
in `shared/ledger_logic.lua` (pure, tested).
`pay` adds: `player_changed`, `addmoney_refused`.
`charge` adds: `amount_too_large` (over `maxCharge`), `fh_insufficient_funds`, `fh_charge_busy`, `player_changed`,
`removemoney_refused`.
`getRep` returns `nil` with `unknown_region`, `no_player` or `ledger_failed` (DB read failed).

## Events
- Emits: `fh:economy:paid`, `fh:economy:rep_changed`, `fh:economy:charged`, `fh:economy:credited` (payloads in `fh_core/docs/events.md`).
- Consumes: `RSGCore:Server:PlayerLoaded` (claims the character's pending credits).

## Config keys (`config.lua`)
`moneyType`, `maxPay`, `maxCharge` (cap on one charge, default 100000), `maxCredit` (cap on one credit, default
100000), `maxRepDelta`, `maxReason`, `repMin`, `repMax`.

## DB tables (`server/migrations/0002_fh_ledger.sql`)
- `fh_ledger` (id, citizenid, kind pay|rep|charge, amount, reason, region_id, created_at): append-only.
  `server/migrations/0006_fh_ledger_charge.sql` widens the `kind` enum with `charge` (B7); existing rows untouched.
- `fh_rep` (citizenid, region_id, value), PK (citizenid, region_id).
- `fh_pending_credit` (id, citizenid, amount int unsigned, reason, region_id, claimed_by NULL|token, created_at):
  queued offline credits (`server/migrations/0015_fh_pending_credit.sql`, which also widens `fh_ledger.kind` with
  `credit` and `credit_pending`). `credit_pending` = queued, no money moved; `credit` = money added.

Region ids: fh_economy loads `@fh_core/shared/regions.lua` itself in its manifest (`shared_scripts`), so it
does not depend on fh_core's manifest listing it (B4a's `shared/*.lua` glob covers fh_core's own use).

## Tests
From the repo root: `~/.venvs/rf/bin/python tools/run-specs.py spec/ledger_logic_spec.lua spec/fh_economy_server_spec.lua spec/fh_economy_credit_spec.lua spec/fh_economy_rep_spec.lua`
- `spec/ledger_logic_spec.lua`: pure validation and the pay / charge sequences.
- `spec/fh_economy_server_spec.lua`: the real `server/main.lua` on a stubbed server: `charge`, `pay`, `getRep`,
  including drop / character switch across the insert yield.
- `spec/fh_economy_rep_spec.lua`: `repByCitizenid` offline (row + ledger, clamp), online (event carries `src`), refusals.
- `spec/fh_economy_credit_spec.lua`: `credit` online / offline, claim on load (double and concurrent claims pay once),
  `AddMoney` refused / throwing after the claim, a failed clear, the start-up audit warning.

## In-game test checklist
- [ ] Server console `fh_pay <id> 5` -> cash +$5, one `fh_ledger` row kind=pay.
- [ ] `fh_pay <id> 0` and `fh_pay <id> -5` -> refused, no row, no cash change.
- [ ] `fh_rep <id> 10` twice -> `fh_rep.value` = 20, two ledger rows kind=rep.
- [ ] Unknown region / empty reason via an exports call from another resource -> refused.
- [ ] Migration 0005 applied; server console `fh_charge <id> 5` with >= $5 -> cash -$5, one `fh_ledger` row
      kind=charge amount=5; with less cash than asked -> `fh_insufficient_funds`, no row, no cash change.
- [ ] Migration 0015 applied; `fh_credit <online citizenid> 5` -> cash +$5, ledger row kind=credit. Log the
      character out, `fh_credit <its citizenid> 7` -> `[true, null, "pending"]`, one `fh_pending_credit` row + ledger
      row kind=credit_pending, `players.money` untouched; log back in -> cash +$7 once, the pending row is gone, a
      kind=credit row is added. Relog again -> no further cash.
- [ ] `exports.fh_economy:getRep(<id>, 'heartlands')` after the `fh_rep` step -> 20; same with the citizenid -> 20;
      `getRep('12', 'heartlands')` -> `nil, 'no_player'`.
