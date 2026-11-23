# fh_quests: quest engine, jobs board, family questlines (plan quests-01)

One data-driven engine for repeatable **jobs** (board), one-time **family questlines** and the intro **tutorial**
(@guide's `fh_tutorial` registers its quest through this API). Steps advance only on existing `fh:*` server events;
other lanes never call into fh_quests to make progress, it only listens. Rewards go only through fh_economy.

This README is the API contract @guide (fh_tutorial), @ui (board/journal/dialogue screens) and @roads (freight job
type) build against now. Every export and event lives here; anything not listed is internal.

## Status

| Part | Block | State |
|---|---|---|
| Definition shape, `where` grammar, state machine, reward-once rule, board rotation (pure `shared/`) | Q1 | **built**, specced |
| This contract (exports, events, sync schema, table) | Q1 | **published** (signatures frozen; additive changes only) |
| Server: migration, event intake, exports, payouts via fh_economy, `fh:quests:*` events, `fh:quests:sync` | Q2 | coming |
| Jobs board: `registerJobType` registry, `hunt_request`, `camp_clear`, `bounty`, rotation timer, ox_lib `/jobs` fallback | Q3 | coming |
| 3 family questlines (data files, giver NPCs, ox_lib text dialogue fallback) | Q4 | coming |
| OWNER-TESTS section, `ensure fh_quests` in server.cfg | Q5 | coming |

Today the resource loads only the pure modules: `server_exports` is declared in `fxmanifest.lua` but calling an
export before Q2 lands errors. Do not `ensure` it yet (Q5 adds it).

## Quest definition shape

```lua
{
  id        = 'family_hale_1',          -- [A-Za-z0-9_.:-], max 64 chars; unique; ledger reason is 'quest:<id>'
  kind      = 'line',                   -- 'job' | 'line' | 'tutorial'
  title     = 'A Roof Over Your Head',
  giver     = 'npc_hale',               -- optional: npc id whose talk() offers this quest
  region_id = 'heartlands',             -- fh_core regions id
  prereq    = { 'tutorial_intro' },     -- optional: quest ids that must have been completed at least once
  ['repeat'] = { cooldown_min = 60 },   -- optional: repeatable, cooldown after each completion; nil = one-time
  steps = {                             -- 1..32 steps, done in order
    { on = 'fh:homestead:claimed', text = 'Claim a homestead plot.' },
    { on = 'fh:hunting:pelt_sold', where = { quality = { min = 2 } }, count = 3, text = 'Sell three good pelts.' },
    { talk = { npc = 'npc_hale', lines = { 'You did it.', 'Here, take this.' } }, text = 'Report back to Hale.' },
  },
  rewards = {                           -- all optional
    money = 25,                                   -- whole dollars, fh_economy.pay
    rep   = { region_id = 'heartlands', delta = 5 }, -- fh_economy.rep (non-zero integer)
    items = { { name = 'bread', amount = 2, info = nil } }, -- player inventory via fh_core addItem
  },
}
```

- `repeat` is a Lua keyword: write it as `['repeat']` in Lua source.
- `step.count` defaults to 1: the step needs that many matching events.
- `step.talk = { npc, lines? }`: the step listens on `fh:quests:talked` (default `on`) with `npc_id = talk.npc`
  added to its `where`. `lines` is the text dialogue shown when the step advances (no cutscenes or voice).
- `engine.validate(def, { regions = FhRegions.regions })` rejects malformed defs with a code (`fh_bad_id`,
  `fh_bad_kind`, `fh_bad_region`, `fh_no_steps`, `fh_bad_step_event@step2`, `fh_bad_min@quality@step2`,
  `fh_bad_money`, ...). `registerQuest` returns that code as `err`.

## `where` grammar (step predicates)

`where` maps payload fields to predicates. All fields must pass (AND). No `where` = any payload of that event.

| Form | Passes when |
|---|---|
| `animal = 'bear'` (string, number or boolean) | payload value `==` it (no coercion: `3 ~= '3'`) |
| `animal = { eq = 'bear' }` | same, table form (combines with `optional`) |
| `quality = { min = 2 }` | value is a number `>= 2` |
| `price = { max = 50 }` | value is a number `<= 50` |
| `quality = { min = 2, max = 3 }` | both bounds |
| `animal = { any = { 'wolf', 'coyote' } }` | value equals one of them |
| `animal = { optional = true, eq = 'bear' }` (also with `min`/`max`/`any`) | field **absent (nil) passes**; present must match |

A non-optional predicate fails when the field is absent. `eq` cannot combine with `min`/`max`/`any`, nor `any` with
`min`/`max`; `{ optional = true }` alone and unknown keys are rejected by `validate`.

Why `optional`: @hunting's `fh:hunting:pelt_sold` payload is `{ citizenid, item_id, animal, size_class, quality,
price, region_id }`, but `animal` and `size_class` land with Hunting H3. A `hunt_request` step written as
`where = { animal = { optional = true, eq = 'wolf' }, quality = { min = 2 } }` matches on quality alone until H3
ships, then also on animal, with no def change.

## Event intake (server events only)

The engine listens to this whitelist; anything else is ignored. The payload must carry `citizenid`, or `src`
(resolved to the character's citizenid server-side). An event credits a quest only if its citizenid equals the
quest holder's, or the holder is listed in `payload.participants` (array of citizenids). Wrong citizenid never
advances anything.

| Event | Owner | Payload used |
|---|---|---|
| `fh:zones:camp_cleared` | @core (fh_zones) | `{ camp_id, region_id, loot }` today, **no player**: credits nobody until Q0a adds `participants = { citizenid... }` |
| `fh:hunting:pelt_skinned` | @hunting (H2) | `{ citizenid, item_id, animal, quality, size_class }` |
| `fh:hunting:pelt_sold` | @hunting (H3) | `{ citizenid, item_id, animal, size_class, quality, price, region_id }` |
| `fh:hunting:chain_complete` | @hunting (H4) | `{ citizenid, chain_id }` |
| `fh:homestead:claimed` | @homestead | `{ src, citizenid, plot_id, region_id }` |
| `fh:economy:paid`, `fh:economy:rep_changed` | fh_economy | see `fh_core/docs/events.md` (reasons `quest:*` are ignored so a reward never advances a quest) |
| `fh:death:dropped`, `fh:death:recovered`, `fh:death:expired` | fh_death | see `fh_core/docs/events.md` |
| `fh:quests:talked` | fh_quests | `{ src, citizenid, npc_id }` (fired by the `talk` export) |

A registered job type may add its own event names via `hooks.events` (below); they join the intake while the
job type is registered. New whitelist entries are additive changes to this table.

## Server exports

All take `src` (player server id) and resolve the citizenid themselves. Errors are string codes.

| Export | Returns | Block |
|---|---|---|
| `registerQuest(def)` | `ok, err` | Q2 |
| `registerJobType(name, hooks)` | `ok, err` | Q3 |
| `start(src, quest_id)` | `ok, err` (`fh_quest_active`, `fh_quest_done`, `fh_quest_cooldown`, `fh_quest_prereq:<id>`, `fh_reward_pending`, `fh_unknown_quest`, `fh_no_player`) | Q2 |
| `abandon(src, quest_id)` | `ok, err` (`fh_not_active`) | Q2 |
| `getActive(src)` | array of journal entries (sync schema below), active only | Q2 |
| `getBoard(src, region_id)` | board object (sync schema below) | Q3 |
| `acceptOffer(src, offer_id)` | `ok, err, quest_id` (`fh_offer_gone` once the board rotated) | Q3 |
| `talk(src, npc_id)` | `ok, err, dialogue` where `dialogue = { { quest_id, step, lines }... }` for steps that advanced, plus `offers = { quest_id... }` this npc gives that the player can start | Q2 |

`registerQuest` replaces an existing def with the same id (so a restarting content resource re-registers cleanly).
Registrations live in memory: re-register on fh_quests (re)start, exactly as below.

### registerJobType(name, hooks)

`name` matches `[a-z0-9_]+`. Hooks (all functions; cross-resource function refs are fine):

- `offers(region_id) -> { offer... }`: candidate offers for that region. Each offer needs a stable `key` (same
  template = same key) and a `title`; anything else rides along to `accept` and to the sync payload.
- `accept(src, offer) -> ok, err`: the job type's own checks/setup (spawn cargo, etc.). Refusal aborts the accept.
- `onEvent(name, payload, state) -> 'progress' | 'complete' | 'fail' | nil`: called for intake events while the
  player has this job active; the verdict goes through `engine.apply`, so rewards still pay exactly once.
- `abandon(src, state)`: clean up when the player abandons.
- optional `events = { 'fh:roads:delivered', ... }`: extra intake events for this job type.

The accepted job is stored as quest id `job:<name>:<offer key>` (one `fh_quest_state` row per player and key).

**Soft dependency (@roads freight):** do not list fh_quests in your `dependencies`. Register only when it runs,
and again whenever it restarts:

```lua
local function registerFreight()
    if GetResourceState('fh_quests') ~= 'started' then return end
    exports.fh_quests:registerJobType('freight', { offers = ..., accept = ..., onEvent = ..., abandon = ... })
end
AddEventHandler('onResourceStart', function(res)
    if res == 'fh_quests' or res == GetCurrentResourceName() then registerFreight() end
end)
```

fh_quests drops a job type when its owning resource stops.

## Emitted events (server, `TriggerEvent`, one table argument)

| Event | Payload |
|---|---|
| `fh:quests:started` | `{ citizenid, quest_id, kind, step }` |
| `fh:quests:step` | `{ citizenid, quest_id, kind, step }` (`step` = the new current step; also per counted event) |
| `fh:quests:completed` | `{ citizenid, quest_id, kind, step }` |
| `fh:quests:failed` | `{ citizenid, quest_id, kind, step }` |
| `fh:quests:abandoned` | `{ citizenid, quest_id, kind, step }` |
| `fh:quests:board_changed` | `{ region_id }` (the region's offers rotated or one was taken) |
| `fh:quests:talked` | `{ src, citizenid, npc_id }` (also intake) |

## Client sync: `fh:quests:sync` (server -> one client), for @ui

Full snapshot (no diffs in v1), sent on character load, on any change to that player's quests, and on
`getBoard`. One table argument:

```json
{
  "v": 1,
  "journal": [
    {
      "quest_id": "family_hale_1",
      "kind": "line",
      "title": "A Roof Over Your Head",
      "giver": "npc_hale",
      "region_id": "heartlands",
      "status": "active",
      "step": 2,
      "steps_total": 3,
      "step_text": "Sell three good pelts.",
      "count": 1,
      "need": 3,
      "rewards": { "money": 25, "rep": { "region_id": "heartlands", "delta": 5 }, "items": [ { "name": "bread", "amount": 2 } ] },
      "cooldown_until": null,
      "updated_at": 1795651200
    }
  ],
  "board": {
    "region_id": "heartlands",
    "epoch": 498792,
    "expires_at": 1795654800,
    "offers": [
      {
        "id": "heartlands:498792:hunt_request:wolf_2",
        "job_type": "hunt_request",
        "title": "Two-star wolf pelt",
        "text": "Sell a 2-star or better wolf pelt.",
        "rewards": { "money": 12 },
        "accepted": false
      }
    ]
  }
}
```

- `journal`: active quests plus done/failed one-time quests (history). `status` is `active|done|failed|abandoned`.
  `giver`, `cooldown_until` may be null. Times are unix seconds.
- `board`: null unless the player is at a board (or asked via `getBoard`). 3-5 offers; `id` is what
  `acceptOffer` takes and stays valid until `expires_at`.
- Dialogue lines arrive in `talk`'s return value (the ox_lib fallback shows them until @ui's dialogue screen lands).

## Persistence (Q2 migration)

```sql
CREATE TABLE IF NOT EXISTS `fh_quest_state` (
  `citizenid` varchar(50) NOT NULL,
  `quest_id` varchar(64) NOT NULL,
  `status` varchar(16) NOT NULL,          -- active | done | failed | abandoned
  `step` int(11) NOT NULL DEFAULT 1,
  `progress` longtext NOT NULL,           -- JSON: { count, completions, reward_pending? }
  `cooldown_until` bigint(20) DEFAULT NULL, -- unix seconds; repeatables only
  `updated_at` bigint(20) NOT NULL,       -- unix seconds
  PRIMARY KEY (`citizenid`, `quest_id`)
);
```

Completed one-time quests stay as `status='done'` (that is the prereq and "already done" record). Repeatables keep
one row; `cooldown_until` is set on each completion and `progress.completions` counts them.

## Rewards (exactly once)

- Money and rep only via `exports.fh_economy:pay(src, money, 'quest:<id>', region_id)` and
  `exports.fh_economy:rep(src, rep.region_id, rep.delta, 'quest:<id>')`; items via fh_core addItem into the
  player inventory ref. No reward without a ledger row.
- The engine emits the `reward` effect only on the active -> done transition. Re-fired events after completion, a
  second `complete` verdict, or a duplicate step event produce no second reward (specced).
- Server order (Q2): persist `done` with `progress.reward_pending = true`, pay, then persist `rewardPaid`. On load,
  `engine.pendingReward` re-offers an unpaid reward; `start` refuses while one is pending (`fh_reward_pending`).

## Pure modules (`shared/`, specced by `python tools/run-specs.py`, `spec/quests_*_spec.lua`)

- `FhQuestsMatch` (`match.lua`): `validate(where)`, `validatePredicate(pred)`, `test(pred, value)`,
  `where(where, payload) -> ok, failingField`, `credits(payload, citizenid)`.
- `FhQuestsEngine` (`engine.lua`): `INTAKE`, `isIntake(name)`, `validate(def, opts)`, `stepOf(def, i)`,
  `canStart(def, stateByQuest, now)`, `start(def, stateByQuest, citizenid, now)`,
  `onEvent(def, state, eventName, payload, now)`, `apply(def, state, verdict, now)`, `abandon(def, state, now)`,
  `fail(def, state, now, reason)`, `pendingReward(def, state)`, `rewardPaid(state, now)`.
  All return a new state plus an effects list `{ type = started|step|completed|failed|abandoned|reward, citizenid,
  quest_id, kind, step, ... }`; inputs are never mutated; an ignored event returns the same state and `{}`.
  `now` is injected (unix seconds or a function returning them).
- `FhQuestsBoard` (`board.lua`): `rotate(region_id, epoch, offerLists, opts) -> offers`, `epoch(now, rotate_min)`,
  `find(board, offer_id)`, `hash`, `rng`. Same (region, epoch, offers) always gives the same 3-5 offers, ids
  `<region_id>:<epoch>:<job_type>:<key>`; job types are interleaved so one type cannot fill the board. Offers live
  in memory and are regenerated after a restart (same epoch -> same board).

## In-game test card

(Filled in by Q2-Q5; the lane's in-game checks go in `OWNER-TESTS.md`, section `## Quests`.)
