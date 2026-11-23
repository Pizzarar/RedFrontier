# Quests plan 01: fh_quests engine, jobs board, family questlines (`@quests`)

## Idea
One data-driven quest/job engine (`[fh]/fh_quests`). Steps advance on existing `fh:*` server events. Rewards are paid only through `fh_economy.pay`/`rep`. State is persisted. On top of it: a repeatable **jobs board** (camp clears, bounties, hunting requests, plus @roads freight as a registered job type) and 3 one-time **family questlines** (text dialogue). @guide's `fh_tutorial` is built on the same API.

## Owner's words (verbatim, via Overlord 2026-11-23)
"wiki + quests (repeatable jobs board + one-time family questlines) + optional intro tutorial." Spec amendment: "optional one-time family questlines and an intro tutorial are in scope; text dialogue only, no cutscenes or voice acting." Lane brief: "Non-linear sandbox ... theme-park style, 3-5 families, text dialogue ... Use only other lanes' exports/events; requests go to their Buddy. No push."

## Decided
- **Checked primitives:** `vs --help` (no quest primitive); fh_economy `pay`/`rep` (fh_economy/README.md:6-8), plus `charge`/`getRep` coming in core-02; `exports.fh_core:requestSpawn` (fh_core/server/spawn.lua:257) and `getSpawn` (:273); `addItem` on container refs (fh_zones/server/main.lua:124); emitted events: `fh:zones:camp_cleared` (fh_zones/server/main.lua:137), `fh:economy:*`, `fh:homestead:claimed`, `fh:death:*`, `fh:hunting:*` (hunting-01-l8.md:22); ox_lib is in [rsg] for the fallback menu; `fh_spike_gated` is the single flag (reused, no new flag). Nothing existing covers quests, so this is a new resource.
- **Architecture:** same as other lanes. Pure shared Lua modules hold the logic (`engine.lua` state machine, `match.lua` step predicates, `board.lua` offer rotation) and are tested by `tools/run-specs.py`. Server files stay thin. No NUI here: the board, journal and dialogue screens belong to @ui. This lane ships a documented sync schema plus an ox_lib menu/chat fallback.
- **Definition shape (data):** `{ id, kind = 'job'|'line'|'tutorial', title, giver?, region_id, prereq = {quest ids}, repeat = {cooldown_min}|nil, steps = { { on = '<fh event>', where = { field = value | {min=}|{max=}|{any={}} }, count = n, text = '...', talk? = {npc, lines} } }, rewards = { money, rep = {region_id, delta}, items } }`. `talk` steps advance on the engine's own `fh:quests:talked`.
- **Event intake:** a whitelist of `fh:*` server events. The payload must carry `citizenid`, or `src`, which is resolved to a citizenid. Unknown events are ignored. Other lanes never call into fh_quests to make progress; it only listens.
- **API contract (publish first, Q1):** these are server exports.
  - `registerQuest(def)` -> `ok, err`. Used by fh_tutorial and by content packs.
  - `registerJobType(name, hooks)`. Hooks are `offers(region_id) -> {offer}`, `accept(src, offer) -> ok, err`, `onEvent(name, payload, state) -> 'progress'|'complete'|'fail'|nil`, `abandon(src, state)`. @roads freight registers through this as a soft dependency, i.e. when fh_quests is started.
  - `start(src, quest_id)`, `abandon(src, quest_id)`, `getActive(src)`, `getBoard(src, region_id)`, `acceptOffer(src, offer_id)`, `talk(src, npc_id)`.
  - Emitted events: `fh:quests:started|step|completed|failed|abandoned {citizenid, quest_id, kind, step}` and `fh:quests:board_changed {region_id}`.
  - Client sync: `fh:quests:sync` (journal + board payload). The schema lives in the README for @ui.
- **Persistence:** a migration with `fh_quest_state (citizenid, quest_id, status, step, progress JSON, updated_at)`, PK (citizenid, quest_id). Completed one-time quests stay in it as `status='done'`; repeatables store `cooldown_until`.
- **Rewards:** money and rep go only through fh_economy (ledger reason `quest:<id>`). Items go through fh_core addItem into the player inventory ref. No reward is paid without a ledger row.
- **Job types v1:**
  - `hunt_request`: deliver an N-star pelt of animal X. It advances on `fh:hunting:pelt_sold` with `quality>=N` and `animal` match. This needs `animal` in the pelt_sold payload; see Q0b.
  - `camp_clear`: clear camp X. It advances on `fh:zones:camp_cleared`; see Q0a for credit.
  - `bounty`: a wanted NPC spawned via `requestSpawn` (tag `fh_quests:bounty:<offer>`). The server watches the adopted netId for death, and the acceptor gets credit. If server-side death detection proves unreliable, it falls back behind `fh_spike_gated` (one row in fh_core/docs/spike-gated.md).
  - `freight`: owned by @roads (roads-01 R4) and registered via `registerJobType`.
  - The board rotates 3-5 offers per region on a timer and keeps them persisted in memory only. Offers are regenerated on restart.
- **Families v1: 3 families**, 3-5 steps each, one-time, text dialogue only. Each one uses only events that exist today (homestead claim, camp clear, pelt sold, economy paid, the legendary bear `chain_complete`). The Legendary Bear chain stays owned by @hunting; one family line requires its `chain_complete` as a step. Giver NPCs are placed via `requestSpawn` at fixed points and opened through rsg-target or ox_lib.
- **Credit:** solo (1-4 players). V1 has no party sharing beyond what an event payload credits.

## Plan

| Block | Touches | Clashes with | Type |
|---|---|---|---|
| Q0a request to @core: `fh:zones:camp_cleared` adds `participants = {citizenid...}` (players inside the camp radius at clear) | fh_zones (core-owned) | @core | Root cause (inbox to @core; quests does not edit fh_zones) |
| Q0b request to @hunting: `fh:hunting:pelt_sold` adds `animal` (and `size_class`) | fh_hunting | @hunting | Root cause (send to Hunting Buddy) |
| Q1 API contract README + pure modules `engine.lua`, `match.lua`, `board.lua` + specs. Send the README path to @guide, @ui, @roads as soon as it lands | new `[fh]/fh_quests` shared + README | none | Root cause |
| Q2 server: migration, event whitelist intake, exports, reward payout via fh_economy, `fh:quests:*` events, `fh:quests:sync` | fh_quests server, server/migrations | migration numbering (check main before naming) | Root cause |
| Q3 jobs board: registry + `hunt_request`, `camp_clear`, `bounty` types + region rotation + ox_lib fallback menu (`/jobs` dev + board prop/NPC via rsg-target) | fh_quests | @ui jobs-board fixture (schema in the README is the contract) | ox_lib menu = Workaround → replaced by @ui jobs-board real wiring (ui.md Open "jobs board") |
| Q4 3 family questlines: data files, giver NPCs, text dialogue via ox_lib fallback | fh_quests `data/families/*.lua` | @ui (dialogue/journal screen later) | ox_lib dialogue = Workaround → replaced by the @ui quest journal/dialogue screen (ui.md Open "quest journal") |
| Q5 OWNER-TESTS.md quests section + README test card; `ensure fh_quests` in server.cfg after fh_economy/fh_zones/fh_hunting | OWNER-TESTS.md (own section), server.cfg (one line) | other lanes appending to the same files: rebase carefully | Root cause |

Order: Q0a/Q0b are sent at once and do not block. Then Q1 → Q2 → Q3 → Q4 → Q5. Until Q0a lands, `camp_clear` credits nobody (spec'd as such). Until Q0b lands, `hunt_request` matches on quality only.

**Done-check per block:** `python tools/run-specs.py` green. Specs cover:
- step matching (eq/min/any, wrong citizen ignored)
- state machine (start/advance/complete/fail/abandon, prereq gate, one-time vs cooldown)
- reward calc (no double pay on re-fired events)
- board rotation determinism

Syntax clean. Every export and event is in the README. Review PASS, then rebase, merge to local main, and log the hash. At the end, log `decision quests playtest-ready <hash>`.

**Lead:** new Quests Lead (Lead - Claude profile), spawned by the Buddy.

## Out of scope
- NUI screens (@ui)
- the tutorial script itself (@guide, fh_tutorial)
- freight logic (@roads)
- the Legendary Bear chain logic (@hunting)
- cutscenes/VO
- party/shared credit beyond event payloads
- push/release
- edits to other lanes' resources (requests only)

## Credits
Original design; no plugin parity. The theme-park questline structure is a general genre convention, so no attribution is needed.
