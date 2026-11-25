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
| 3 family questlines (data files, giver NPCs, fh_ui `dialogue` screen) | Q4 | **built**, defs and walk-throughs specced; in-game unverified |
| OWNER-TESTS section, `ensure fh_quests` in server.cfg | Q5 | coming |
| Content-ladder job types `supply_run`, `survey`, `escort`, `rescue` + reach-watcher | quests-02 C1-C4 | **built**; heartlands data only; in-game unverified |
| Contract tiers (tier gating, scaling, ladder content) | quests-03 T1-T4 | **built**; heartlands, scarlett_meadows, bayou_nwa, great_plains |

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
    { id = 'claim', on = 'fh:homestead:claimed', text = 'Claim a homestead plot.' }, -- id is optional
    { id = 'sell', on = 'fh:hunting:pelt_sold', where = { quality = { min = 2 } }, count = 3, text = 'Sell three good pelts.' },
    { id = 'report', talk = { npc = 'npc_hale', lines = { 'You did it.', 'Here, take this.' } }, text = 'Report back to Hale.' },
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
- `step.id` is an optional stable id (non-empty string, unique in the def). Progress is saved by id as well as
  index, so a registered def can be reordered or gain steps without moving an in-flight character. A row saved
  before the def had ids falls back to its index.
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

Use `optional` only for a field an emitter may leave out. `fh:hunting:pelt_sold` always carries `animal` and
`size_class` (Q0b, fh_hunting `shared/sell.lua`), so match them plainly: `where = { animal = 'wolf', quality = { min = 2 } }`.

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
  region is unknown or not enabled (`FhRegions.isEnabled`), or the job type is no longer registered.
- Region gate: a region that is not enabled has an empty board (`getBoard` still answers, with 0 offers) and no job
  type's `offers` hook is called for it; accepting one of its offer ids is `fh_offer_gone`. Turning a region on in
  fh_core is the only change needed to show its offers (`board.collect` / `board.offerRegion`).
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
| `fh_bad_step@stepN`, `fh_bad_step_id@stepN`, `fh_duplicate_step_id@stepN`, `fh_bad_step_text@stepN`, `fh_bad_step_count@stepN`, `fh_bad_talk@stepN`, `fh_bad_talk_lines@stepN`, `fh_bad_step_event@stepN`, `fh_bad_<pred>@<field>@stepN` | `registerQuest`, `acceptOffer` | a step, its id, its talk block, its event (not on the intake / job events) or a `where` predicate |
| `fh_bad_rewards`, `fh_unknown_reward:<k>`, `fh_bad_money`, `fh_bad_rep_region`, `fh_bad_rep_delta`, `fh_bad_items`, `fh_bad_item`, `fh_bad_item_amount`, `fh_bad_item_info` | `registerQuest`, `acceptOffer` | the rewards block |
| `fh_reserved_id` | `registerQuest` | ids starting with `job:` are reserved for accepted jobs |
| `fh_bad_job_name`, `fh_bad_hooks`, `fh_bad_hook:<hook>`, `fh_bad_job_events`, `fh_bad_job_event:<name>` | `registerJobType` | name not `[a-z0-9_]+` (max 32), hooks not a table, `offers` missing or a hook not callable, `events` not a list of `fh:*` names (never `fh:quests:talked`) |
| `fh_unknown_quest` | `start` | no registered quest with that id |
| `fh_quest_active`, `fh_quest_done`, `fh_quest_cooldown`, `fh_quest_prereq:<id>` | `start`, `acceptOffer` | already active; one-time quest already done; repeatable still cooling down; a prereq never completed |
| `fh_reward_pending` | `start`, `acceptOffer` | the previous completion of this quest still owes part of its reward |
| `fh_offer_locked` | `acceptOffer` | player's progression tier in the offer's region is below offer `min_tier` |
| `fh_not_active` | `abandon` | the player has no active quest with that id |
| `fh_bad_region` | `getBoard` | unknown region id (`FhRegions`) |
| `fh_offer_gone` | `acceptOffer` | the offer id is not on the current board (rotated, unknown or disabled region, job type gone) |
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
| `min_tier` | no | minimum progression tier required to see or accept the offer; floors any number ≥1 with no upper cap (default `1`; content uses 1–3) |

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
(`server/jobtypes.lua`; every verdict is pure, in `shared/jobtypes.lua`, specced in `quests_jobtypes`; each offer
builder is in `shared/jobtypes/<type>.lua`). Each decides its verdicts in `hooks.onEvent` from the accepted-offer
snapshot (`progress.job`). Region templates are in `data/regions/<region_id>.lua` (one per FhRegions id, read as
`FhQuestsJobTypes.DATA`); only `heartlands` has any today. All coordinates,
models and camp ids are guesses (TODO-verify-in-game). Default cooldown 60 min (one rotation).

| Type | Offer `on` / `where` | Advances when | Offer-only fields |
|---|---|---|---|
| `hunt_request` | `fh:hunting:pelt_sold`, `where = { quality = { min = N }, animal = { eq = X }, region_id = { eq = <offer region> } }` | a pelt of animal X and quality >= N is sold by the job holder at a trapper in the offer's region | `animal`, `stars` |
| `camp_clear` | `fh:zones:camp_cleared`, `where = { camp_id = X }` | the camp is cleared and the holder is in `payload.participants` | `camp_id` |
| `bounty` | `fh:quests:bounty_down` (a type event, local server only) | the watched wanted NPC dies; completes the job | `name`, `model`, `coords`, `heading` |

- **`hunt_request`:** `animal` is required: fh_hunting's `pelt_sold` always carries it (Q0b), so a pelt of another
  animal, or a payload without `animal`, never credits the job. The offer key is region-scoped,
  `hunt_<region_id>_<animal>_<N>star` (idea-902; quest id `job:hunt_request:hunt_heartlands_wolf_2star`), so two
  regions offering the same animal/stars never share a quest id, cooldown or ledger reason. **Matching is
  region-scoped** (idea-902b): `where.region_id = { eq = <offer region> }`, and fh_hunting's `pelt_sold.region_id` is
  the region of the trapper the pelt was sold at (one trapper per region, `fh_hunting/data/legendaries/<region>.lua`
  `trapper`; emit at `fh_hunting/shared/sell.lua:218-221`; a disabled region's trapper refuses `fh_region_closed`).
  So a sale completes only the hunt jobs of its own region, and a `pelt_sold` without `region_id` never credits one.
  Within a region one sale still credits every held job it matches (`deer_1star` / `deer_2star`). Every region with
  hunt data has a trapper (guard: `quests_content` "every region with hunt offers has an fh_hunting trapper").
  A job whose region is later disabled cannot be completed until it is re-enabled (abandon it). Rows saved under the
  old key `<animal>_<N>star` are re-keyed on load (Persistence, "Legacy job ids"); their stored `where`, like that of
  any job accepted before idea-902b, stays unscoped until the job is accepted again (it completes once, on a matching
  sale in any region).
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

### Content-ladder job types (quests-02 C1-C4)

Same registration path and region gate as above (`server/jobtypes.lua` registers all seven; builders in
`shared/jobtypes/<type>.lua`, verdicts decided there through `JT.registerVerdict`, read by `JT.verdict` in
`shared/jobtypes.lua`). `FhQuestsJobTypes` (and `FhQuestsWatchRules`) are read as **globals** in these files, never
from the chunk argument `...`: under FXServer `...` is a number, not nil.

| Type | Offer `on` | Advances / ends when | DATA key in `data/regions/<id>.lua` |
|---|---|---|---|
| `supply_run` | `fh:trade:sold`, `where = { post = { eq }, item = { eq }, amount = { min } }` | the holder sells at least `amount` of `item` at that fh_trade `post` in ONE sale; completes (count 1) | `supply = { { post, item, amount, money, rep }, ... }` |
| `survey` | `fh:quests:point_reached` (count = number of points) | the reach-watcher reports the holder at a point; each valid point counts one; completes at the last | `surveys = { { key, name, points = { {x,y,z}... }, ordered = true (default), money, rep }, ... }` |
| `escort` | `fh:quests:escort_arrived` | the escortee reaches `destination` -> complete; `fh:quests:escort_lost` (escortee dead or despawned) -> **fail** | `escorts = { { key, name, model, start = {x,y,z}, heading, destination = {x,y,z}, money, rep }, ... }` |
| `rescue` | `fh:quests:captive_freed` | the holder is within 10 m of the live captive AFTER the linked camp was cleared with the holder in `participants` -> complete; `fh:quests:captive_lost` (captive dead or despawned) -> **fail** | `rescues = { { key, name, camp = '<fh_zones camp id>', model, coords = {x,y,z}, heading, money, rep }, ... }` |

- **`supply_run`:** `fh:trade:sold` payload is `{ src, region, post, item, amount, total }` (fh_trade
  `server/main.lua:144`); the intake resolves `src` to the citizenid. The key is `region` (not `region_id`). `post`
  and `item` must match exactly; `amount` is the single sale's quantity, so two smaller sales never add up. Offer key
  `supply_<post>_<item>`.
- **`survey`:** ordered by default (point `count + 1` only; `ordered = false` accepts any unvisited point). Radius
  is 25 m horizontal (`WR.DEFAULT_RADIUS`), checked server-side on a 3 s tick (`WR.TICK_MS`) against the holder's
  ped coords; a point out of order never counts. Offer key `survey_<key>`.
- **`escort`:** on accept the escortee ped spawns at `start` (fh_core `requestSpawn`, tag
  `fh_quests:escort:<region>:<key>:<cid>`) and the client tasks it to follow the holder (`client/escort.lua`,
  `fh:quests:escort_follow` / `escort_stop`). Arrival = the escortee's position (not the holder's) within the
  watcher radius of `destination`. Lost = dead, spawn request failed/gone, or entity missing 2 checks in a row.
  Offer key `escort_<key>`.
- **`rescue`:** on accept the captive spawns at `coords` (tag `fh_quests:rescue:<region>:<key>:<cid>`). A local
  `fh:zones:camp_cleared { camp_id, ... participants }` for the offer's `camp` unlocks the job only if the holder is
  listed and the job was already accepted (armed). Reaching the captive before the unlock does nothing and is not
  remembered; the unlock is in memory, so after a relog or restart a fresh clear is needed. Lost rule is escort's.
  Offer key `rescue_<key>`.
- **Quest-owned events** (`fh:quests:point_reached`, `escort_arrived`, `escort_lost`, `captive_freed`,
  `captive_lost`) are LOCAL server events (`TriggerEvent`), payload `{ citizenid, offer_key, region_id }`
  (`point_reached` adds `point`). Each verdict checks that `citizenid`, `offer_key` and `region_id` match the held
  job, so only the holder's own job moves.
- **Region gate:** unchanged: a region that is not enabled has no offers for any type (`FhRegions.isEnabled`, see
  Server exports). Today only `data/regions/heartlands.lua` has `supply`/`surveys`/`escorts`/`rescues`; every
  coordinate, model and camp id there is TODO-verify-in-game.

#### Reach-watcher hook (for future "be somewhere" types)

`server/watch.lua` runs one coarse tick (`WR.TICK_MS`) over every held watched job and emits the kind's event when
a target is reached. A new type needs no edit to the rules:

1. `FhQuestsWatchRules.registerKind(job_type, def)` (`shared/watch_rules.lua`): `points(offer)` (required, the
   targets), optional `ordered`, `radius`, `event`, `payload(entry, point)`, and server-only `posOf(entry)` (whose
   position counts, default the holder's ped), `onArm(entry, offer)` (extra setup, e.g. spawn an NPC; return
   `ok, err`) and `onDisarm(entry, why)`.
2. Register hooks with `FhQuestsWatch.jobHooks(job_type)` (`W.jobHooks`, `server/watch.lua`): returns
   `{ accept, abandon, events }` (arm on accept, disarm on abandon, the kind's event added to the intake); merge it
   into the type's `registerJobType` hooks (as `survey` does; `escortHooks()` / `rescueHooks()` add their lost event).
3. Register a verdict with `FhQuestsJobTypes.registerVerdict(job_type, fn)` and an offer builder with `registerBuilder`.

Active watched jobs are re-armed from the template plus the persisted progress count on character load and on
fh_quests restart.

**Rotation.** Each region's board holds 3-5 offers, picked by `board.rotate` from the offers of every registered
type (types are interleaved, so every type is on the board while templates last), re-picked every 60 minutes
(`fh:quests:board_changed`). The pick is a pure function of (region, epoch, templates), kept in memory and
regenerated on restart: the same epoch gives the same board and the same offer ids.

**Entry points.** `/jobs` and an rsg-target sphere zone (plus a client-local notice-board prop) at each board spot
(`shared/board_spots.lua`, consumed by `client/board.lua`) fire `fh:quests:ui_open`, which opens the fh_ui jobs
screen (`server/ui.lua`). There is one board spot per region (Heartlands and Scarlett Meadows); `/jobs` opens the
board for the **nearest** spot (`FhQuestsBoardSpots.regionFor`, no proximity check — it just picks the closest).
The old ox_lib fallback menu and its lib callbacks are gone.

## Tiers (quests-03)

Repeatable contracts on the jobs board support tier progression aligned with regional reputation (`fh_progression`). Higher tiers unlock more challenging contracts with scaled payouts.

### Offer `min_tier` and default

Every offer template accepted by `registerJobType` / `JT.registerBuilder` supports an optional `min_tier` field:
- Normalization: `JT.minTier(v)` (`shared/jobtypes.lua:33`) floors any number `≥ 1`; there is no upper cap in the schema. Content currently uses tiers 1–3.
- Default: `1` when omitted or invalid in region data (`data/regions/<region_id>.lua`) or builder returns (normalized via `FhQuestsJobTypes.minTier`).
- Tier 1 contracts are available to all players; tier 2 requires progression tier 2 (100 rep); tier 3 requires progression tier 3 (400 rep).

### Progression tier gating

Gating is evaluated strictly per region against the player's progression tier:
- **`tierOf(src, region_id)`** (`server/main.lua`): Queries `exports.fh_progression:getTier(src, region_id)`. If `fh_progression` is not started, the player/region is missing, or `getTier` throws or returns non-number, it safely falls back to tier `1`.
- **At the board** (`Q.boardView`): The server rotates offers per region deterministically, then filters the view using pure `FhQuestsBoard.visible(offers, playerTier)` (`shared/board.lua`). Offers where `offerMinTier(offer) > playerTier` are excluded from the client's board by default.
- **At accept** (`acceptOffer` in `server/api.lua`): The server performs an authoritative check against the offer's region (`offerRegionOf(offer, region_id)`). If `offerMinTier(offer) > tierOf(src, region)`, accept is refused with error code **`fh_offer_locked`** (`server/ui_text.lua:7` maps this verbatim to "Your standing in this region is not high enough for that job."). The client never decides eligibility.
- **Dynamic board refresh on tier crossing**: `server/api.lua` listens for `fh:progression:tier_changed` (`{ src, citizenid, region_id, old, new }`, ignored if client-sourced). When a player's tier changes in a region, the server fires `fh:quests:board_changed` for `(region_id, src)` and re-syncs the board snapshot (`fh:quests:sync`) to that player if they are currently viewing that region's board, updating the visible offers in real time.

### `locked = { min_tier }` and `FhQuestsConfig.showLockedOffers`

For development and UI preview:
- `FhQuestsConfig.showLockedOffers` (`config.lua`, default `false`): When `false`, locked offers (`min_tier > playerTier`) are omitted from the board sync payload.
- When set to `true`, locked offers remain in `board.offers` but have a `locked = { min_tier = N }` table attached (`FhQuestsJournal.boardView`). This allows UI work to display the contract greyed out or show "Requires Tier N" badges.
- Even when previewed with `showLockedOffers = true`, server-side `acceptOffer` strictly enforces the tier gate and refuses locked contracts with `fh_offer_locked`.

### Reward scaling by offer tier

Reward scaling is implemented in pure module `FhQuestsRewards.scaleByTier(rewards, tier, multipliers)` (`shared/rewards.lua`):
- **Offer tier, not player tier**: Payouts scale by the **OFFER's** `min_tier`, snapshotted at `acceptOffer`. A tier-3 player taking a tier-1 contract receives base tier-1 pay (1.0x); a tier-2 contract pays 1.5x; a tier-3 contract pays 2.25x.
- **Config multipliers**: Defined in `FhQuestsConfig.tierRewardMultipliers` (`config.lua`):
  ```lua
  FhQuestsConfig.tierRewardMultipliers = {
      [1] = 1.0,
      [2] = 1.5,
      [3] = 2.25,
  }
  ```
  Unknown, nil, non-integer, or invalid tiers fall back to multiplier `1.0`.
- **Rounding and types**: Scaled `money` and `rep.delta` are rounded half-up (`math.floor(val * mult + 0.5)`) to non-negative whole integers. This matches the engine's whole-number integer contract and `fh_economy` whole-dollar payouts. Items in `rewards.items` are copied unchanged without scaling.
- **Frozen at accept**: Scaled rewards are frozen into `progress.job.rewards` in `fh_quest_state` at accept. Later progression tier changes or config multiplier edits do not alter running jobs, and payouts remain delivered strictly via `fh_economy`.

### Tier 2 and Tier 3 content

Four enabled regions have tier 2 and tier 3 content templates (`data/regions/<region_id>.lua`): `heartlands`, `scarlett_meadows`, `bayou_nwa`, and `great_plains`. Each enabled region provides at least one offer at tier 1, tier 2, and tier 3 across built-in job types:
- **`heartlands`**:
  - Tier 2 (`min_tier = 2`): `heartlands_t2_01` Dakota South camp ($52, rep 4 -> $78, +6 rep), Harlan Voss bounty ($44, rep 3 -> $66, +5 rep), 3-star elk hunt ($42, rep 1 -> $63, +2 rep), valentine_post whiskey supply run (3x trade_whiskey, $26, rep 2 -> $39, +3 rep).
  - Tier 3 (`min_tier = 3`): Calvin Dredge bounty ($58, rep 4 -> $131, +9 rep), Nora Whitfield rescue at `heartlands_t2_01` ($46, rep 4 -> $104, +9 rep).
- **`scarlett_meadows`**:
  - Tier 2 (`min_tier = 2`): `scarlett_meadows_t2_01` Catfish Bottom camp ($52, rep 4 -> $78, +6 rep), Graham Lockett bounty ($44, rep 3 -> $66, +5 rep), 3-star boar hunt ($22, rep 1 -> $33, +2 rep), rhodes_post whiskey supply run (3x trade_whiskey, $28, rep 2 -> $42, +3 rep).
  - Tier 3 (`min_tier = 3`): Celeste Kane bounty ($58, rep 4 -> $131, +9 rep), Otis Brent rescue at `scarlett_meadows_t2_01` ($46, rep 4 -> $104, +9 rep).
- **`bayou_nwa`**:
  - Tier 2 (`min_tier = 2`): `bayou_nwa_t2_01` Cypress Hollow camp ($52, rep 4 -> $78, +6 rep), Lucien Broussard bounty ($44, rep 3 -> $66, +5 rep), 3-star fox hunt ($18, rep 1 -> $27, +2 rep), saint_denis_post cloth supply run (5x trade_cloth, $24, rep 2 -> $36, +3 rep).
  - Tier 3 (`min_tier = 3`): Sabine Fontenot bounty ($58, rep 4 -> $131, +9 rep), Celine Arceneaux rescue at `bayou_nwa_t2_01` ($46, rep 4 -> $104, +9 rep).
- **`great_plains`**:
  - Tier 2 (`min_tier = 2`): `great_plains_t2_01` Great Plains East camp ($52, rep 4 -> $78, +6 rep), Roland Stroud bounty ($44, rep 3 -> $66, +5 rep), 3-star coyote hunt ($20, rep 1 -> $30, +2 rep), blackwater_post whiskey supply run (3x trade_whiskey, $28, rep 2 -> $42, +3 rep).
  - Tier 3 (`min_tier = 3`): Maren Keller bounty ($58, rep 4 -> $131, +9 rep), Tobias Renshaw rescue at `great_plains_t2_01` ($46, rep 4 -> $104, +9 rep).

## Emitted events (server, `TriggerEvent`, one table argument)

| Event | Payload |
|---|---|
| `fh:quests:started` | `{ citizenid, quest_id, kind, step }` |
| `fh:quests:step` | `{ citizenid, quest_id, kind, step }` (`step` = the new current step; also per counted event) |
| `fh:quests:completed` | `{ citizenid, quest_id, kind, step }` |
| `fh:quests:failed` | `{ citizenid, quest_id, kind, step }` |
| `fh:quests:abandoned` | `{ citizenid, quest_id, kind, step }` |
| `fh:quests:board_changed` | `{ region_id [, src] }` (the region's board rotated, an offer there was accepted, a player crossed a tier boundary, or a job type registered/dropped while the board was cached) |
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
        "id": "heartlands:498792:hunt_request:hunt_heartlands_wolf_2star",
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
- Dialogue lines arrive in `talk`'s return value (the fh_ui `dialogue` screen pages through them).

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
| `step_id` | the current step's stable `id` when the def gives steps ids; resolved before `step` on load |
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
- **Legacy job ids (idea-902).** `hunt_request` keys were `<animal>_<N>star` (not region-scoped) before idea-902. No
  SQL migration: `Q.load` re-keys such a row (`jobs.migrateLegacy`) before anything else reads it, and persists the
  move as one transaction (UPSERT `job:hunt_request:hunt_<region>_<old key>` + DELETE the old row). Status, step,
  counts, completions, `cooldown_until` and every reward marker carry over, so an active job stays completable, a
  cooldown keeps blocking the live offer and an owed reward is paid once. The region is the row's own accepted-offer
  snapshot (`progress.job.region_id`, the board it was accepted on); only a row without one falls back to the current
  data, and only for an old key exactly one region builds. A row whose region is unknown, or whose new id already
  exists, is left as is and logged. A failed transaction fails the load (`fh_db`) instead of running with both ids.
  The re-keyed snapshot keeps `legacy_key`: until that job is accepted again its ledger reason stays
  `quest:job:hunt_request:<old key>` (an in-flight payout is reconciled against rows written under that reason), and
  `abandon` accepts the old id from a journal synced before the re-key.

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
  `find(board, offer_id)`, `visible(offers, tier)`, `offerMinTier(offer)`, `hash`, `rng`. Same (region, epoch, offers) always gives the same 3-5 offers, ids
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
- `FhQuestsRewards` (`rewards.lua`): the exactly-once payout protocol, `run(def, state, io)` with the I/O injected,
  `scaleByTier(rewards, tier, multipliers)`, `tierMultiplier(tier, multipliers)`.
- `FhQuestsStore` (`store.lua`): `SELECT`, `UPSERT`, `params(state, encode)`, `fromRow(row, decode)`.
- `FhQuestsJournal` (`journal.lua`): `entry`, `shown`, `journal(defs, states, activeOnly)`, `boardView`,
  `snapshot` (the `fh:quests:sync` payload).

Specs: `quests_match`, `quests_engine`, `quests_board`, `quests_intake`, `quests_rewards`, `quests_store`,
`quests_journal`, `quests_jobs`, `quests_jobtypes`, `quests_tiers`, `quests_hunt_rekey` (idea-902 keys + legacy re-key, incl. the
server load path). `server/main.lua` and `server/api.lua` are thin I/O glue over these.

## In-game test card

The ordered quests checklist is `OWNER-TESTS.md`, section `## Q5: quests (fh_quests)`. Smoke test once per build:

1. Boot with `ensure fh_quests` after `fh_hunting`: no `[fh_quests]` error lines and no `fh_quest_state missing`.
2. `/jobs` opens the board with 3-5 Heartlands offers (hunt requests, the camp, wanted NPCs).
3. Accept a hunt request, sell a pelt of its quality at that region's trapper: it completes and pays once (ledger `quest:job:hunt_request:<key>`).
4. Accept a bounty: the wanted NPC spawns; relog and a fresh one spawns; disconnect and it despawns, freeing the offer.
5. Talk to Hale, Marrow and Whitlock from within 5 m (further is `fh_too_far`); givers stay frozen, cannot be killed and do not flee.

## Family questlines (Q4)

Five one-time `kind = 'line'` quests in `data/families/<family>.lua` (Hale/Marrow/Whitlock: region `heartlands`; Cormier and Ashby, added in C6: see the table; text dialogue only, no
cutscenes or voice). `server/families.lua` loads them with `LoadResourceFile` and calls `registerQuest` at start.
Families are independent (no `prereq`); the steps inside a line run in order. Rewards are money + rep only (item
rewards stay owed until core idea-643 lands). The giver NPC id is the def's `giver`; the giver's intro lines
(shown before the start offer) and fixed spawn point live in `shared/givers.lua`.

| Family | Quest id / giver | Steps (events) | Reward |
|---|---|---|---|
| Hale & Daughters: A Roof Over Your Head | `family_hale` / `npc_hale` | claim a plot (`fh:homestead:claimed`), earn $15+ in one payment (`fh:economy:paid`, `amount.min 15`), report back (talk) | $40, +5 rep |
| Marrow's Debt: Smoke on the Ridge | `family_marrow` / `npc_marrow` | clear an outlaw camp (`fh:zones:camp_cleared`), sell 2 pelts (`fh:hunting:pelt_sold`), report back (talk) | $60, +8 rep |
| Whitlock's Ghost: The Bear of Bear Hollow | `family_whitlock` / `npc_whitlock` | sell a quality 2+ pelt (`fh:hunting:pelt_sold`), finish the Legendary Bear hunt (`fh:hunting:chain_complete`, `chain_id = 'legendary_bear'`), report back (talk) | $120, +12 rep |
| Cormier Landing: High Water (C6) | `family_cormier` / `npc_cormier` (Odile Cormier, near Lagras; region `bayou_nwa`, Lemoyne) | skin an alligator (`fh:hunting:pelt_skinned`, `animal = 'alligator'`), clear a Swamp Gang camp (`fh:zones:camp_cleared`, `region_id = 'bayou_nwa'`), sell 2 pelts (`fh:hunting:pelt_sold`, `count = 2`), report back (talk) | $70, +8 rep (`bayou_nwa`) |
| Ashby Range: The Long Grass (C6) | `family_ashby` / `npc_ashby` (June Ashby, near Blackwater; region `great_plains`, West Elizabeth) | skin a wolf or coyote (`fh:hunting:pelt_skinned`, `animal` any of wolf/coyote), clear a camp (`fh:zones:camp_cleared`, `region_id = 'great_plains'`), sell a quality 2+ pelt (`fh:hunting:pelt_sold`, `quality.min 2`), report back (talk) | $75, +8 rep (`great_plains`) |

**Depends on other lanes (the lines park on that step until then):**
- `family_whitlock` step 2 depends on **@hunting** (H4, plan hunting-01-l8): `fh:hunting:chain_complete` with
  `chain_id = 'legendary_bear'`. It is already in the intake whitelist; fh_hunting needs no code from this lane.

### Giver dialogue

`client/givers.lua` puts an rsg-target sphere zone on each giver (spawned by the server via `exports.fh_core:requestSpawn`
at fixed points); selecting it fires `fh:quests:ui_talk`. The server calls the `talk` export (a finished talk step
advances), builds the page list (talk lines, then the giver's intro when a start offer follows) and opens the fh_ui
`dialogue` screen. "I will" relays `fh:quests:ui_start`. Coordinates, headings and ped models are guesses:
TODO-verify-in-game.

### Giver proximity (server-checked)

The two net handlers (`fh:quests:ui_talk`, `fh:quests:ui_start`) compare the player's server-side ped position
with the giver's fixed point (`FhQuestsGivers.within`, radius `REACH` = 5 m) and refuse with **`fh_too_far`** beyond
it, so a modified client cannot start a line or advance a talk step from across the map. The check lives in the net
handlers, not in the `talk` export: the exports are server-only (no client can call them) and also serve callers
whose npc has no fixed point, so only the handler knows the position. Any future client path must run the same check. Other codes: `fh_bad_npc` (not a giver), `fh_unknown_quest`.
Giver peds are frozen, invincible and ignore events on the client that spawned them (`client/givers.lua`).
