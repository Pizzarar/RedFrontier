# fh_hands

Hired hands (L9 / M7): an owner hires a hand, the hand bills a wage every tick and, on a paid tick, runs its task.
State lives in `fh_hands` (migration `0009_hands`, PK `(citizenid, hand_kind)`: one row per hand kind per owner).

## Exports (server)
- `exports.fh_hands:hire(src, kind)` -> `ok, err`. Errors: `unknown_hand`, `no_player`, `locked`, `max_hands`,
  `already_hired`, `db_failed`, `busy`, `not_ready`.
- `exports.fh_hands:fire(src, kind)` -> `ok, err` (`no_player`, `not_hired`, `db_failed`, `busy`, `not_ready`).
- `exports.fh_hands:getHands(src)` -> `{ [kind] = { unpaid, status, last_tick } }` (copy; `{}` when unavailable).
- `exports.fh_hands:registerTask(kind, fn)` -> `ok, err`; `fn(ctx) -> ok, info`, `ctx = { src, citizenid, hand_kind }`.

## Hands and tasks (`config.lua`, `FhHandsConfig`)
| kind | wage / tick | task | adds to plot chest `fh:chest:<plot>:1` |
|---|---|---|---|
| `ranch_hand` | `hands.ranch_hand.wage` | `feed_topup` | `feed` up to `feed.cap`, at most `feed.perTick` per paid tick |
| `woodcutter` | `hands.woodcutter.wage` | `lumber_topup` | `lumber` up to `lumber.cap`, at most `lumber.perTick` per paid tick |

All hands share `tickSeconds` (one wage per interval), `maxCatchupTicks` (offline catch-up cap) and `quitAfterUnpaid`.
`feed` is registered by fh_hands (fh_core `registerItems`); `lumber` is fh_homestead's build item and is never
registered here. Both tasks share `FhHandsLogic.chestTopup`: never past the cap, never reduce a chest the owner filled
above it.

## Hire gate
- First hand: fh_progression `canUnlock(src, unlockId)` (`hire_hand`).
- Second hand: also `canUnlock(src, extraHandUnlocks[2])` (`hire_hand_2`, heartlands t3, added by fh_progression).
  Fail closed: anything but `true` (`unknown_unlock` before the unlock exists, `tier_too_low`, a throw) is `locked`.
- More hands than `#extraHandUnlocks + 1`: `max_hands`. The count is read under the owner's lock, so concurrent hires
  cannot both pass as the first hand. Firing back to one hand means the next hire needs `hire_hand_2` again.

## Wage ticks (invariants)
Every load / poll tick / hire / fire / admin tick for a citizenid runs under that citizenid's lock (`withLock`). Each
hand's ticks are processed separately (`runOwner`, kinds sorted): per tick the row's `last_tick` is claimed by a SQL
CAS **before** the charge (`exports.fh_economy:charge`, core B7), so two hands bill two wages and no tick is ever
charged twice. Charge outcomes (`FhHandsLogic.chargeOutcome`): paid -> task runs; `fh_charge_busy` / `ledger_failed`
-> tick handed back, no strike; `no_player` / `player_changed` -> handed back, owner stops; `charge_unavailable` ->
claim kept, no strike, no task; anything else -> unpaid strike, **no task**, quit after `quitAfterUnpaid`.

## Events
Emits `fh:hands:hired`, `fh:hands:fired`, `fh:hands:unpaid`, `fh:hands:quit`, `fh:hands:task_failed`.

## Admin (console or ACE `command.<name>`)
`fh_hand_tick <serverId>`, `fh_hand_hire <serverId> <kind>`, `fh_hand_fire <serverId> <kind>`.

Logic is pure (`shared/hands_logic.lua`) and covered by `spec/hands_spec.lua`.
