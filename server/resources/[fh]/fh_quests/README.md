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
| Server: migration, event intake, all 8 exports, payouts via fh_economy, `fh:quests:*` events, `fh:quests:sync` | Q2 | **built**, pure parts specced |
| Jobs board plumbing: generic `registerJobType` registry, `getBoard`, `acceptOffer`, board sync, rotation timer | Q2 | **built** |
| Built-in job types `hunt_request`, `camp_clear`, `bounty`; `/jobs` jobs board and `/journal` on the fh_ui screens (the ox_lib fallback menu is removed) | Q3 | **built**, pure parts specced; in-game unverified |
| 3 family questlines (data files, giver NPCs, ox_lib text dialogue **workaround**) | Q4 | **built**, defs and walk-throughs specced; in-game unverified |
| OWNER-TESTS section, `ensure fh_quests` in server.cfg | Q5 | coming |

The server side is in (`server/main.lua`: state cache, per-character lock, persistence, payouts, sync;
`server/api.lua`: exports and event intake). It is not `ensure`d yet (Q5 adds it). It needs the `fh_quest_state`
migration (`server/migrations/0007_quest_state.sql`) applied by
`tools/setup-server.ps1`. Without the table it logs once and every export returns `fh_not_ready`.

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
| `fh:zones:camp_cleared` | @core (fh_zones) | `{ camp_id, region_id, loot, participants }`: `participants` = citizenids of the players within `activationRadius` at clear (empty table if none, or if the lookup failed) |
| `fh:hunting:pelt_skinned` | @hunting (H2) | `{ citizenid, item_id, animal, quality, size_class }` |
| `fh:hunting:pelt_sold` | @hunting (H3) | `{ citizenid, item_id, animal, size_class, quality, price, region_id }` |
| `fh:hunting:chain_complete` | @hunting (H4) | `{ citizenid, chain_id }` |
| `fh:homestead:claimed` | @homestead | `{ src, citizenid, plot_id, region_id }` |
| `fh:economy:paid`, `fh:economy:rep_changed` | fh_economy | see `fh_core/docs/events.md` (reasons `quest:*` are ignored so a reward never advances a quest) |
| `fh:death:dropped`, `fh:death:recovered`, `fh:death:expired` | fh_death | see `fh_core/docs/events.md` |

Only local server events are taken: an event that arrives with a client source is dropped, so a client can never
feed the intake. Each credited character is processed under its own lock (see "Concurrency").

**`fh:quests:talked` is emitted only, not intake.** It is listed in `engine.INTAKE` so `talk` steps validate
against it, but nothing listens to it: the `talk` export feeds the talking player's own quests directly and then
emits `fh:quests:talked` for observers. A re-fired or foreign `fh:quests:talked` therefore never advances a quest.

A registered job type may add its own event names via `hooks.events` (below); they join the intake while the
job type is registered and stop counting when it is dropped. New whitelist entries are additive changes to this
table.

## Server exports

All player exports take `src` (player server id) and resolve the citizenid themselves. Errors are string codes
(full list under "Error codes"). Every player export can also return the common codes `fh_not_ready`,
`fh_no_player`, `fh_busy`, `fh_db` and `fh_internal`.

| Export | Returns | Specific errors | Block |
|---|---|---|---|
| `registerQuest(def)` | `ok, err` | `fh_bad_def`, `fh_reserved_id`, any `engine.validate` code | Q2 |
| `registerJobType(name, hooks)` | `ok, err` | `fh_bad_job_name`, `fh_bad_hooks`, `fh_bad_hook:<hook>`, `fh_bad_job_events`, `fh_bad_job_event:<name>` | Q2 |
| `start(src, quest_id)` | `ok, err` | `fh_unknown_quest`, `fh_quest_active`, `fh_quest_done`, `fh_quest_cooldown`, `fh_quest_prereq:<id>`, `fh_reward_pending` | Q2 |
| `abandon(src, quest_id)` | `ok, err` | `fh_not_active` | Q2 |
| `getActive(src)` | array of journal entries (sync schema below), active only; `{}, err` on error | common codes only | Q2 |
| `getBoard(src, region_id)` | board object (sync schema below), or `nil, err` | `fh_bad_region` | Q2 |
| `acceptOffer(src, offer_id)` | `ok, err, quest_id` | `fh_offer_gone`, `fh_bad_offer`, `fh_offer_no_event`, `fh_bad_job_snapshot`, any `engine.validate` code, `start`'s codes, `fh_accept_failed`, `fh_accept_refused` or the job type's own refusal string | Q2 |
| `talk(src, npc_id)` | `ok, err, dialogue` | `fh_bad_npc` | Q2 |

- `start` only starts registered quests (`registerQuest`); job quests start through `acceptOffer`. If an earlier
  completion still owes a reward, `start` / `acceptOffer` try to pay it first and refuse with `fh_reward_pending`
  while it stays owed.
- `talk` returns `dialogue = { { quest_id, step, lines }... }` for talk steps that advanced (or finished their
  quest), plus `dialogue.offers = { quest_id... }`: quests whose `giver` is this npc that the player can start now
  (sorted). After the change is saved it emits `fh:quests:talked`.
- `acceptOffer` takes the offer `id` from `getBoard` / the sync payload. `fh_offer_gone` = the board rotated, the
  region is unknown, or the job type is no longer registered.
- `registerQuest` replaces an existing def with the same id (so a restarting content resource re-registers cleanly).
  Ids starting with `job:` belong to job types (`fh_reserved_id`). Registrations live in memory: re-register on
  fh_quests (re)start, exactly as below.

### Error codes

| Code | From | Meaning |
|---|---|---|
| `fh_not_ready` | every player export | `fh_quest_state` is missing (migration not applied); quests are disabled |
| `fh_no_player` | every player export | `src` has no loaded character |
| `fh_busy` | every player export | this character's quest lock stayed taken for 5 s (another change in flight); retry |
| `fh_db` | every player export | loading or saving `fh_quest_state` failed; nothing was emitted or paid |
| `fh_internal` | every player export | a Lua error inside the locked section (logged); state is as last saved |
| `fh_bad_def`, `fh_bad_id`, `fh_bad_kind`, `fh_bad_title`, `fh_bad_giver`, `fh_bad_region`, `fh_bad_prereq`, `fh_prereq_self`, `fh_bad_repeat`, `fh_no_steps`, `fh_too_many_steps` | `registerQuest`, `acceptOffer` | `engine.validate`: the def's own fields |
| `fh_bad_steps` | `registerQuest`, `acceptOffer` | `steps` is not a dense 1..n list (holes or non-integer keys) |
| `fh_bad_step@stepN`, `fh_bad_step_text@stepN`, `fh_bad_step_count@stepN`, `fh_bad_talk@stepN`, `fh_bad_talk_lines@stepN`, `fh_bad_step_event@stepN`, `fh_bad_<pred>@<field>@stepN` | `registerQuest`, `acceptOffer` | a step, its talk block, its event (not on the intake / job events) or a `where` predicate |
| `fh_bad_rewards`, `fh_unknown_reward:<k>`, `fh_bad_money`, `fh_bad_rep_region`, `fh_bad_rep_delta`, `fh_bad_items`, `fh_bad_item`, `fh_bad_item_amount`, `fh_bad_item_info` | `registerQuest`, `acceptOffer` | the rewards block |
| `fh_reserved_id` | `registerQuest` | ids starting with `job:` are reserved for accepted jobs |
| `fh_bad_job_name`, `fh_bad_hooks`, `fh_bad_hook:<hook>`, `fh_bad_job_events`, `fh_bad_job_event:<name>` | `registerJobType` | name not `[a-z0-9_]+` (max 32), hooks not a table, `offers` missing or a hook not callable, `events` not a list of `fh:*` names (never `fh:quests:talked`) |
| `fh_unknown_quest` | `start` | no registered quest with that id |
| `fh_quest_active`, `fh_quest_done`, `fh_quest_cooldown`, `fh_quest_prereq:<id>` | `start`, `acceptOffer` | already active; one-time quest already done; repeatable still cooling down; a prereq never completed |
| `fh_reward_pending` | `start`, `acceptOffer` | the previous completion of this quest still owes part of its reward |
| `fh_not_active` | `abandon` | the player has no active quest with that id |
| `fh_bad_region` | `getBoard` | unknown region id (`FhRegions`) |
| `fh_offer_gone` | `acceptOffer` | the offer id is not on the current board (rotated, unknown region, job type gone) |
| `fh_bad_offer` | `acceptOffer` | the job type's offer has no `key` / `title` |
| `fh_offer_no_event` | `acceptOffer` | the offer has no `on` and its job type has no `onEvent` hook (nothing could ever advance it) |
| `fh_bad_job_snapshot` | `acceptOffer`, load (log only) | a job snapshot without `job_type` / `key`; on load such a job row is ignored (kept in the table, logged) |
| `fh_accept_failed` | `acceptOffer` | the job type's `accept` hook threw (logged) |
| `fh_accept_refused` | `acceptOffer` | the `accept` hook returned falsy without a string reason (a string reason is returned as-is) |
| `fh_bad_npc` | `talk` | `npc_id` is not a non-empty string |

Internal codes that only reach the server log: `fh_bad_row`, `fh_bad_row_citizenid`, `fh_bad_row_quest`,
`fh_bad_row_status` (an unusable `fh_quest_state` row, skipped on load) and the reward protocol's
`fh_no_reward`, `fh_reward_inflight`, `fh_reward_not_owed`, `fh_reward_not_inflight`, `fh_bad_outcome`.

### registerJobType(name, hooks)

`name` matches `[a-z0-9_]+` (max 32 chars). Hooks (functions; cross-resource function refs are fine). Only
`offers` is required:

- `offers(region_id) -> { offer... }`: candidate offers for that region (called once per region per rotation).
- `accept(src, offer) -> ok, err` (optional): the job type's own checks/setup (spawn cargo, etc.), with the offer
  table as `offers` returned it. Refusal aborts the accept; a string `err` is returned to the caller.
- `onEvent(name, payload, state) -> 'progress' | 'complete' | 'fail' | nil` (optional): if present, it decides
  every verdict for this type's active jobs: it is called for each intake event that credits the job's holder
  (quest payout echoes excluded), with a copy of the state; the verdict goes through `engine.apply`, so rewards
  still pay exactly once. Without it the engine matches the offer's `on` / `where` / `count` itself.
- `abandon(src, state)` (optional): clean up when the player abandons (also called if the accept could not be
  saved, to undo `accept`'s setup).
- optional `events = { 'fh:roads:delivered', ... }`: extra intake events for this job type (`fh:*`, not
  `fh:quests:talked`).

**Offer fields** (what `offers` returns; everything not listed rides along to `accept` only and is not stored):

| Field | Required | Meaning |
|---|---|---|
| `key` | yes | stable template key (same template = same key; one row per player and key) |
| `title` | yes | board and journal title |
| `on` | unless `onEvent` | the step event (intake whitelist or this type's `events`) |
| `where` | no | step predicates (`where` grammar above) |
| `count` | no | matching events needed (default 1) |
| `cooldown_min` | no | minutes before the same offer can be taken again after completion (default **60**, one board rotation; `0` allowed) |
| `text` | no | step / board text (defaults to `title`) |
| `rewards` | no | the reward shape of quest defs (`money`, `rep`, `items`) |

**Accepted jobs.** An accepted offer becomes a one-step repeatable quest with id `job:<name>:<offer key>`, kind
`job`. Its snapshot (`job_type`, `key`, `region_id`, `title`, `text`, `on`, `where`, `count`, `rewards`,
`cooldown_min`, `hook`) is stored in the row as `progress.job`, and the def is rebuilt and re-validated from it on
load. So an active job and an unpaid job reward survive a restart even after the board rotated or the offer
template changed.

**Jobs pause while their type is unregistered.** Until the owning resource (re)registers the type, its active jobs
ignore every event (no progress, no fail) and keep their row; they resume once it registers again. They can
still be abandoned, except a job whose step event is one of the type's own `events`: its def cannot be rebuilt
(nor shown in the journal) until the type registers again.

**Hooks run inside fh_quests' per-character lock.** A hook must not call back into fh_quests exports that change
the same player's quests (`start`, `abandon`, `acceptOffer`, `talk`): return a verdict instead. Hooks should be
quick; a hook that throws is logged and treated as "no change" (`accept`: `fh_accept_failed`).

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

## Built-in job types (Q3)

Registered at start through the public `registerJobType` export, the same path @roads' `freight` uses
(`server/jobtypes.lua`; the data and every verdict are pure, in `shared/jobtypes.lua`, specced in
`quests_jobtypes`). Each decides its verdicts in `hooks.onEvent` from the accepted-offer snapshot
(`progress.job`). Region templates are in `FhQuestsJobTypes.DATA`; only `heartlands` has any today. All coordinates,
models and camp ids are guesses (TODO-verify-in-game). Default cooldown 60 min (one rotation).

| Type | Offer `on` / `where` | Advances when | Offer-only fields |
|---|---|---|---|
| `hunt_request` | `fh:hunting:pelt_sold`, `where = { quality = { min = N }, animal = { optional = true, eq = X } }` | a pelt of quality >= N is sold (and of animal X when the payload carries `animal`) by the job holder | `animal`, `stars` |
| `camp_clear` | `fh:zones:camp_cleared`, `where = { camp_id = X }` | the camp is cleared and the holder is in `payload.participants` | `camp_id` |
| `bounty` | `fh:quests:bounty_down` (a type event, local server only) | the watched wanted NPC dies; completes the job | `name`, `model`, `coords`, `heading` |

- **`hunt_request`:** `animal` is optional on purpose: until Hunting H3 (Q0b) puts `animal` in the `pelt_sold`
  payload it matches on quality only, afterwards on animal too, with no change here.
- **`camp_clear`:** credit comes from the `participants` list (core idea-614, landed): fh_zones sends the citizenids
  of the players within `activationRadius` when the camp clears (an empty table when there are none), and each of them
  is credited. An empty list credits nobody.
- **`bounty`:** `accept` asks fh_core for a ped (`exports.fh_core:requestSpawn`, `kind = 'ped'`, tag
  `fh_quests:bounty:<region_id>:<offer key>`). The server polls the adopted netId's health
  (`GetEntityHealth(NetworkGetEntityFromNetworkId(netId)) <= 0`, the same check fh_zones uses for camp peds) and then
  fires the local event `fh:quests:bounty_down { citizenid = <acceptor>, offer_key, region_id }`. The verdict
  completes only when `payload.citizenid` is the job holder and `offer_key` is the job's own offer: other players
  (and `participants`) are never paid, and whoever lands the kill, the acceptor is credited. One live bounty per
  offer: a second accepter gets `fh_bounty_taken`. Abandoning despawns the ped. The ped is made hostile by the
  client (`client/bounty.lua`, on `fh:spawn:adopted`, same natives as the camp peds).
- **Not spike-gated.** Death detection is the same server-side health check `fh_zones` already ships ungated for
  `camp_clear`, so a bounty can be no less reliable than a camp; gating it would also leave the default
  (`fh_spike_gated true`) board without a bounty and `spike-gated.md` untouched. Still **unverified in-game**.
- **Owner leaves (drop or character unload):** the ped is despawned and the offer freed at once (no stuck
  `fh_bounty_taken`, no ped left to be killed by a bystander), and nobody is credited: the death event fires only while
  the acceptor's character is still online. The **job row stays `active`** (nothing persisted changes). When that
  character loads again, or fh_quests restarts with them online, the server **re-arms** it: a fresh ped for each
  of their active bounty jobs (spawn setup rebuilt from the template by region + key). If the template is gone or the
  offer is taken by someone else, the job stays open and can be abandoned.
- **Limitations:** watchers are in memory (re-armed as above). A ped that fh_core cannot spawn leaves the job open until
  relog or abandon.

**Rotation.** Each region's board holds 3-5 offers, picked by `board.rotate` from the offers of every registered
type (types are interleaved, so every type is on the board while templates last), re-picked every 60 minutes
(`fh:quests:board_changed`). The pick is a pure function of (region, epoch, templates), kept in memory and
regenerated on restart: the same epoch gives the same board and the same offer ids.

**Entry points.** `/jobs` and an rsg-target sphere zone (plus a client-local notice-board prop) at the board spot
(`client/board.lua`) fire `fh:quests:ui_open`, which opens the fh_ui jobs screen (`server/ui.lua`). The `/jobs`
command works anywhere (no proximity check). The old ox_lib fallback menu and its lib callbacks are gone.

## Emitted events (server, `TriggerEvent`, one table argument)

| Event | Payload |
|---|---|
| `fh:quests:started` | `{ citizenid, quest_id, kind, step }` |
| `fh:quests:step` | `{ citizenid, quest_id, kind, step }` (`step` = the new current step; also per counted event) |
| `fh:quests:completed` | `{ citizenid, quest_id, kind, step }` |
| `fh:quests:failed` | `{ citizenid, quest_id, kind, step }` |
| `fh:quests:abandoned` | `{ citizenid, quest_id, kind, step }` |
| `fh:quests:board_changed` | `{ region_id }` (the region's board rotated, an offer there was accepted, or a job type registered/dropped while the board was cached) |
| `fh:quests:talked` | `{ src, citizenid, npc_id }` (after a successful `talk`; emitted only, not intake) |

Events are emitted only after the new state was saved, in effect order (`started`/`step`/`completed`/...). The
reward payout follows the save and the events.

## Concurrency

All reads and writes of one character's quest state (exports, intake events, payouts on load) run under a
per-character lock, so two events can never both see the same `active` state. An export that cannot get the lock
within 5 s returns `fh_busy`; an intake event waits up to 30 s and is then dropped (logged).

## Client sync: `fh:quests:sync` (server -> one client), for @ui

Full snapshot (no diffs in v1), sent on character load (and for online players when fh_quests restarts), on any
change to that player's quests (start, abandon, accept, talk, a counted intake event), and on `getBoard`. One
table argument:

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
- `board`: null until the player's `getBoard(src, region_id)` is called. From then on **every** sync to that player
  includes that region's current board (the last region asked for), until they drop or unload. 3-5 offers (the built-in
  job types below; fewer only if a region has fewer templates); `id` is what `acceptOffer` takes and stays valid until
  `expires_at` (unix seconds, end of the rotation epoch; boards rotate every 60 minutes). `accepted` is true when
  this player has the job of that offer active. `text` and `rewards` come from the offer (`rewards` shows
  `money`, `rep`, item `name`/`amount` only). On rotation the server emits `fh:quests:board_changed` and the next
  `getBoard` / sync shows the new offers.
- Journal rows whose quest has no registered def (content resource not started) are left out until it registers.
- Dialogue lines arrive in `talk`'s return value (the ox_lib fallback shows them until @ui's dialogue screen lands).

## Persistence (Q2 migration)

```sql
CREATE TABLE IF NOT EXISTS `fh_quest_state` (
  `citizenid` varchar(50) NOT NULL,
  `quest_id` varchar(64) NOT NULL,
  `status` varchar(16) NOT NULL,          -- active | done | failed | abandoned
  `step` int(11) NOT NULL DEFAULT 1,
  `progress` longtext NOT NULL,           -- JSON, see below
  `cooldown_until` bigint(20) DEFAULT NULL, -- unix seconds; repeatables only
  `updated_at` bigint(20) NOT NULL,       -- unix seconds
  PRIMARY KEY (`citizenid`, `quest_id`)
);
```

Completed one-time quests stay as `status='done'` (that is the prereq and "already done" record). Repeatables keep
one row; `cooldown_until` is set on each completion and `progress.completions` counts them.

`progress` JSON keys (anything else is dropped on save and on load; `shared/store.lua`):

| Key | Meaning |
|---|---|
| `count`, `completions` | events counted toward the current step; completions so far |
| `reward_pending` | `true` while any reward part is still owed |
| `reward_paid` | `{ [part key] = true }` parts already delivered (`money`, `rep`, `item:<i>`) |
| `reward_inflight` | `{ key, at }` the part being paid right now (crash recovery) |
| `job` | accepted job offer snapshot (see registerJobType "Accepted jobs") |

Storage notes:

- **`cooldown_until` goes through `NULLIF(?, 0)`.** The UPSERT always sends 7 non-nil positional parameters (a
  `nil` inside a Lua array does not cross to oxmysql reliably), so "no cooldown" is sent as `0` and stored as
  `NULL`. A real cooldown is never `0` (unix seconds).
- On load, whole numbers that come back as floats (JSON / driver) are turned back into integers; a row with an
  unknown `status`, or an empty `citizenid` / `quest_id`, is skipped and logged; unreadable `progress` JSON loads
  as empty progress.
- Every write is an UPSERT on (`citizenid`, `quest_id`); only a successful write updates the server's cache.

## Rewards (exactly once)

- Money and rep only via `exports.fh_economy:pay(src, money, 'quest:<id>', region_id)` and
  `exports.fh_economy:rep(src, rep.region_id, rep.delta, 'quest:<id>')`; items via
  `exports.fh_core:addItem({ type = 'backpack', id = src }, name, amount, info)`. No money/rep without a ledger row.
- Parts are paid in order `money`, `rep`, `item:<i>`, each exactly once (`shared/rewards.lua`): mark the part
  in flight and save, call the payer, then save it paid. A crash in between is settled on the next run from
  `fh_ledger` (money/rep) or assumed delivered (items). A refusal (player offline, fh_economy down, refused)
  stops the run; the rest stays owed and is retried on the next character load and before the next `start` /
  `acceptOffer` of that quest. Payouts only happen while the player is online.
- The engine emits the `reward` effect only on the active -> done transition. Re-fired events after completion, a
  second `complete` verdict, or a duplicate step event produce no second reward (specced).
- Server order: persist `done` with `progress.reward_pending = true`, emit the events, then pay part by part as
  above. `start` / `acceptOffer` refuse while a reward is still owed (`fh_reward_pending`).

### Known limitations

- **Item rewards are not delivered yet.** fh_core `addItem` refuses `backpack` / `equipped` refs
  (`fh_core/server/inventory.lua:232`); fixing that is queued to @core as idea-643. Until it lands, money and rep
  still pay exactly once, but the item part stays owed: the quest keeps `reward_pending`, the server retries on
  each character load, and a **repeatable** quest or job with item rewards cannot be started again
  (`fh_reward_pending`). Content should avoid item rewards on repeatables until idea-643 ships.
- **`cooldown_min = 0` can underpay, never double-pay.** If the same repeatable is completed twice within
  `LEDGER_SLACK_S` (5 s) and the second payout's outcome is unknown (crash, or the fh_economy export threw), the
  ledger lookup finds the first completion's row and counts the second as paid. Any cooldown of 1 minute or more
  avoids it; the default for jobs is 60.

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
- `FhQuestsJobs` (`jobs.lua`): `validateType(name, hooks)`, `parseId`, `questId(job_type, key)`,
  `snapshot(job_type, offer, region_id, hasHook)`, `def(snapshot, opts)`, `normalize(v)`, `DEFAULT_COOLDOWN_MIN`.
- `FhQuestsJobTypes` (`jobtypes.lua`): `TYPES`, `DATA`, `offers(job_type, region_id)`, `verdict(job_type, eventName, payload, state)`,
  `bountyTag(region_id, key)`, `BOUNTY_EVENT`.
- `FhQuestsIntake` (`intake.lua`): `accepts(name, extraEvents)`, `srcToResolve(payload)`, `targets(payload, cid)`,
  `payloadFor(payload, cid)`, `feed(defs, states, eventName, payload, now, hookFor)`, `emits(effects)`,
  `dialogue(def, before, after)`, `offers(defs, states, npc_id, now)`,
  `fresh(defs, states, change, eventName, payload, now, hookFor)` (drops or recomputes a stale change at commit time).
- `FhQuestsRewards` (`rewards.lua`): the exactly-once payout protocol, `run(def, state, io)` with the I/O injected.
- `FhQuestsStore` (`store.lua`): `SELECT`, `UPSERT`, `params(state, encode)`, `fromRow(row, decode)`.
- `FhQuestsJournal` (`journal.lua`): `entry`, `shown`, `journal(defs, states, activeOnly)`, `boardView`,
  `snapshot` (the `fh:quests:sync` payload).

Specs: `quests_match`, `quests_engine`, `quests_board`, `quests_intake`, `quests_rewards`, `quests_store`,
`quests_journal`, `quests_jobs`, `quests_jobtypes`. `server/main.lua` and `server/api.lua` are thin I/O glue over these.

## In-game test card

The ordered quests checklist is `OWNER-TESTS.md`, section `## Q5: quests (fh_quests)`. Smoke test once per build:

1. Boot with `ensure fh_quests` after `fh_hunting`: no `[fh_quests]` error lines and no `fh_quest_state missing`.
2. `/jobs` opens the board with 3-5 Heartlands offers (hunt requests, the camp, wanted NPCs).
3. Accept a hunt request, sell a pelt of its quality: it completes and pays once (ledger `quest:job:hunt_request:<key>`).
4. Accept a bounty: the wanted NPC spawns; relog and a fresh one spawns; disconnect and it despawns, freeing the offer.
5. Talk to Hale, Marrow and Whitlock from within 5 m (further is `fh_too_far`); givers stay frozen, cannot be killed and do not flee.

## Family questlines (Q4)

Three one-time `kind = 'line'` quests in `data/families/<family>.lua` (region `heartlands`, text dialogue only, no
cutscenes or voice). `server/families.lua` loads them with `LoadResourceFile` and calls `registerQuest` at start.
Families are independent (no `prereq`); the steps inside a line run in order. Rewards are money + rep only (item
rewards stay owed until core idea-643 lands). The giver NPC id is the def's `giver`; the giver's intro lines
(shown before the start offer) and fixed spawn point live in `shared/givers.lua`.

| Family | Quest id / giver | Steps (events) | Reward |
|---|---|---|---|
| Hale & Daughters: A Roof Over Your Head | `family_hale` / `npc_hale` | claim a plot (`fh:homestead:claimed`), earn $15+ in one payment (`fh:economy:paid`, `amount.min 15`), report back (talk) | $40, +5 rep |
| Marrow's Debt: Smoke on the Ridge | `family_marrow` / `npc_marrow` | clear an outlaw camp (`fh:zones:camp_cleared`), sell 2 pelts (`fh:hunting:pelt_sold`), report back (talk) | $60, +8 rep |
| Whitlock's Ghost: The Bear of Bear Hollow | `family_whitlock` / `npc_whitlock` | sell a quality 2+ pelt (`fh:hunting:pelt_sold`), finish the Legendary Bear hunt (`fh:hunting:chain_complete`, `chain_id = 'legendary_bear'`), report back (talk) | $120, +12 rep |

**Depends on other lanes (the lines park on that step until then):**
- `family_whitlock` step 2 depends on **@hunting** (H4, plan hunting-01-l8): `fh:hunting:chain_complete` with
  `chain_id = 'legendary_bear'`. It is already in the intake whitelist; fh_hunting needs no code from this lane.

### Giver dialogue (WORKAROUND)

`client/givers.lua` + the callbacks at the end of `server/families.lua` are a **workaround**, replaced by the @ui
quest journal/dialogue screen (delete them and the fxmanifest lines then). The givers are spawned by the server
via `exports.fh_core:requestSpawn` at fixed points; the client puts an rsg-target sphere zone on each. Opening it
calls the server `talk` export (so a finished talk step advances and its `talk.lines` are shown as ox_lib alert
dialogs, one per line). If the line is not started, the giver's intro lines are shown and the player is offered
to start it (`start`). No NUI. Coordinates, headings and ped models are guesses: TODO-verify-in-game.

### Giver proximity (server-checked)

The two net callbacks (`fh:quests:giver:talk`, `fh:quests:giver:start`) compare the player's server-side ped position
with the giver's fixed point (`FhQuestsGivers.within`, radius `REACH` = 5 m) and refuse with **`fh_too_far`** beyond
it, so a modified client cannot start a line or advance a talk step from across the map. The check lives in the net
handlers, not in the `talk` export: the exports are server-only (no client can call them) and also serve callers
whose npc has no fixed point, so only the handler knows the position. Any future client path (the @ui dialogue
screen's handler) must run the same check. Other codes: `fh_bad_npc` (not a giver), `fh_unknown_quest`.
Giver peds are frozen, invincible and ignore events on the client that spawned them (`client/givers.lua`).
