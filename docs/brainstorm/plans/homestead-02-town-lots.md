# Plan homestead-02 · two home classes: town lot + wilderness claim (`fh_homestead`, lane @homestead)

## Idea
idea-801 (hub decision, made): each character may hold ONE town lot AND ONE wilderness claim.
- TOWN LOT: bought, ~12-15 m radius, lawman-safe, town rep bump on purchase.
- WILDERNESS CLAIM: free, large, raid-exposed (today's plots).
Today `fh_plots.citizenid` is UNIQUE (`server/migrations/0003_homestead.sql:8`) and `claims.byOwner[citizenid]` holds one plot id
(`server/main.lua:7`), so both need to become per-class.

## Owner words (verbatim, idea-801)
> - Two home classes (hub decision, @world): TOWN LOT (bought, ~12-15m, lawman-safe, town rep bump) + WILDERNESS CLAIM (free, large, raid-exposed); one of each per character. fh_plots.citizenid is UNIQUE today -> schema change. @world world-01 ships plot data with class='claim'|'town_lot', town lots claimable=false until this lands.
> - world-01 out-of-scope: town-lot purchase + one town_lot AND one claim per character (fh_plots.citizenid UNIQUE -> schema change). @world ships town_lot plot data with claimable=false; flip when schema lands. Plan docs/brainstorm/plans/world-01-regions.md

## Goal
A character can buy a town lot and also claim a wilderness plot, independently. The lot is a small, safe, paid home in town;
the claim stays the big free, raidable one. Existing claims keep working untouched.

## Done-when
- H6-H10 merged to local main (review PASS, `~/.venvs/rf/bin/python tools/run-specs.py` all green), world-01 block B already on main.
- Owner can: buy a lot (cash drops, rep rises, chest works) AND claim a plot on the same character; a second lot or second claim is refused.
- OWNER-TESTS homestead card has the town-lot steps. `vs log decision "homestead town-lots playtest-ready <hash>"`.

## Decided
- Class lives in data: `plots[id].class = 'claim' | 'town_lot'` (a missing class = `'claim'`). world-01 block B already adds lots as
  entries of `FhHomesteadConfig.plots` with `class='town_lot'`, `claimable=false` (world-01-regions.md:23-28, 45-51). H6+ **consumes that
  shape**: key on `class`, flip `claimable` to true. No second lot table. Plots stay owned by fh_homestead/config.lua; towns/regions
  stay in fh_core `shared/regions.lua`.
- Uniqueness per class: `UNIQUE(citizenid, class)`; `plot_id` stays PK. Memory: `claims.byOwner[class][citizenid]`.
- Backward compatible API: `claim`, `unclaim`, `getPlot`, `claimedPlots`, `isInSafeZone` keep their signatures; `getPlot(citizenid)` returns the
  **claim**-class plot (default class `'claim'`). New optional arg `class`. Callers by grep (all keep the default, no edit needed):
  `fh_hands/server/main.lua:85` (`getPlot`), `fh_ui/server/main.lua:28` (`claimedPlots`), `fh_survival/server/homestead_adapter.lua`
  (`isNearStation`, `getComfort`), `fh_crafting/server/stations.lua` (stations), plus homestead-internal `plotOf` users:
  `slots.lua:106,187,204`, `build.lua:213,260`, `comfort.lua:35,98,194,210,304,343`. Those internals keep `plotOf(cid)` = claim class in v1
  (a lot has no slots/comfort until H9).
- Purchase = `exports.fh_economy:charge(src, amount, reason, region_id)` -> `ok, err, ledgerId`, then claim; if the claim fails after the
  charge, `exports.fh_economy:credit(citizenid, amount, reason, region_id)` (offline-safe, queues). Same pattern as build refund (d19146d).
  Memory reservation happens BEFORE the charge so two concurrent buys cannot both pass; `fh_charge_busy` is retryable.
- Rep bump: `exports.fh_economy:rep(src, region_id, delta, reason)` with the lot's `region` (rep is per region in `fh_rep`; there is no
  separate "town" rep key). Cap `maxRepDelta = 1000` (`fh_economy/config.lua:6`), our delta is far below.
- Checked existing primitives: fh_economy `charge`/`credit`/`pay`/`rep`/`getRep` (README:8-26, all present); fh_core regions registry
  (`getRegion`, `isKnownRegion`, `territoryAt`, towns list planned by world A; no rep or safe-zone export); fh_homestead `isInSafeZone`
  (query only, "nothing enforces it yet", server/main.lua:128-143, README:37); fh_zones `getCamp` (camps only, no town-law concept);
  fh_alife `getOwner(campId)` (planned in a-life-01, camps only, not on main; not usable for lots); fh_heat `get/set/add/level/payoff`
  (no safe-area concept). Gap: **no enforcement of "safe" anywhere** (no law-AI or PvP rule reads `isInSafeZone`).
- Migration number: written here as `0099`; renumbered to main's highest+1 at merge during the pre-merge rebase (never pre-claim a real
  number). Highest on main now: 0017.

## Blocks
Stakes: **tierA-invariant** = schema, claim uniqueness, purchase (money). Others normal.

| Block | What | Files touched | Done-check (spec names) | Stakes | Root cause / Workaround |
|---|---|---|---|---|---|
| H6 schema + per-class uniqueness | Migration `0018_homestead_plot_class.sql`: `ALTER TABLE fh_plots ADD COLUMN IF NOT EXISTS class varchar(16) NOT NULL DEFAULT 'claim'`; `DROP INDEX IF EXISTS citizenid`; `ADD UNIQUE KEY citizenid_class (citizenid, class)`. Existing rows become `'claim'`. `shared/plot_rules.lua`: `canClaim(plot, coords, cid, claims)` reads `plot.class` and checks `claims.byOwner[class][cid]`; new reason `fh_already_has_lot`; `classOf(plot)`; `claimable` check (`fh_not_claimable`). | `server/migrations/0018_homestead_plot_class.sql`, `fh_homestead/shared/plot_rules.lua`, `spec/plot_rules_spec.lua` | `plot_rules_spec`: claim+lot for one cid both allowed; two claims refused (`fh_already_has_plot`); two lots refused; `claimable=false` refused; missing class = claim; old `byOwner` flat shape still accepted. Migration read check: file re-runnable (IF EXISTS guards) | tierA-invariant (schema, uniqueness) | Root cause |
| H7 claim/unclaim/getPlot per class | `server/main.lua`: `claims.byOwner[class]`, `loadClaims` reads `class` (fall back `'claim'` if column absent), `claim(src, class?)`, `unclaim(src, plotId)` (owner/admin, class from plot), `getPlot(citizenid, class?)`, `claimedPlots()` unchanged (both classes), `FhHomesteadClaims.plotOf(cid, class?)` default `'claim'`. INSERT writes `class`. `/fh_claim` stays claim-only (plot containing you must be class claim). `fxmanifest.lua` unchanged exports list. | `fh_homestead/server/main.lua`, `fh_homestead/README.md` (API table only), new `spec/fh_homestead_claims_spec.lua` (stubbed server, like fh_economy_server_spec) | spec: existing callers (`getPlot(cid)`) return the claim plot even when the cid also owns a lot; lot-only owner gets `nil` from `getPlot(cid)`; `getPlot(cid,'town_lot')` returns the lot; unclaim of the lot leaves the claim; DB insert/rollback keeps both maps consistent; no-class rows load as claim | tierA-invariant (claim uniqueness) | Root cause |
| H8 town-lot purchase | `/fh_buylot` (+ export `buyLot(src)`): in a lot's radius, `class='town_lot'`, `claimable=true`; reserve memory; `charge(src, plot.price, 'town_lot:'..id, plot.region)`; insert row + chest row + register chest (reuse claim path); on any failure after charge: `credit(cid, price, 'town_lot_refund:'..id, region)` and un-reserve; on success `rep(src, region, cfg.townLotRep, 'town_lot')`, event `fh:homestead:claimed` (payload gets `class`) plus `fh:homestead:lot_bought`. On lot unclaim (abandon or admin): `rep(-cfg.townLotRep)` in the lot region for the owner (same call shape as the bump; if rep needs an online src and the owner is offline, record it per fh_economy README or refuse abandon while offline; pick one and spec it), so abandon+rebuy never nets more than one bump. Config: `townLot = { price, rep }` defaults + per-plot `price` override. | `fh_homestead/server/main.lua` (or new `server/lots.lua`), `fh_homestead/config.lua` (defaults only, see Clashes), `fh_homestead/fxmanifest.lua` (+`buyLot`), `fh_core/docs/events.md` (payload note) | `spec/fh_homestead_lots_spec.lua`: success path = 1 charge, 1 rep, 1 row; `fh_insufficient_funds` = no row, no rep; `fh_charge_busy` = no row; DB insert fails after charge = 1 credit of the same amount, no rep; second lot = refused BEFORE any charge; two buys in the same tick = one charge; claim-owner can still buy a lot; rep loop: buy, abandon, buy = net +25 rep (one bump) | tierA-invariant (money, purchase) | Root cause |
| H9 town-lot slots + safety | Per-class slot template: `slotTemplate()` becomes `slotTemplates.claim` / `.town_lot` (lot default: `chest_2` and `station_1` workbench only, no cabin/fence/trophy; see Open Q3). `plotOf` for slots/comfort/build becomes class-aware via `plot.class`; `/fh_build` builds on the plot you stand in that you own. `isInSafeZone`: lot counts when owned; radius = `plot.radius` (no fence bonus); `lawSafe=true` field per class; new export `plotInfo(plotId)` -> `{class, raidable, lawSafe, owner}` for @alife (raidable = class=='claim'). | `fh_homestead/config.lua` (templates), `shared/build_rules.lua`, `server/slots.lua`, `server/build.lua`, `server/comfort.lua`, `server/main.lua`, specs `build_rules_spec`, `plot_rules_spec` | specs: lot template has no cabin/fence slot; `/fh_build cabin` on a lot = `fh_slot_unknown`; claim templates unchanged (existing build_rules_spec green untouched); `isInSafeZone` true at lot edge, false just outside; `plotInfo` claim = raidable, lot = not | normal | Workaround: lawman-safe has nothing enforcing it (isInSafeZone/plotInfo only report); follow-up idea-803 @a-life enforces no raids/law aggro inside owned lots |
| H10 flip claimable + docs | Flip `claimable=true` on the lot entries world-01 B added (after B is on main); README (exports/events/config/tables, `class` column, Open: nothing enforces safe); homestead section in OWNER-TESTS.md; a fh_ui `/where` hint is a request to @ui/@world, not built here. | `fh_homestead/config.lua`, `fh_homestead/README.md`, `OWNER-TESTS.md` | spec: every `class='town_lot'` entry in config has `price`, `region`, `radius` 12-15, and no overlap with other plots; OWNER-TESTS steps below | normal | Root cause |

OWNER-TESTS steps (H10): (1) stand in a lot, `/fh_buylot`: cash -price, `fh_rep` +rep in that region, chest opens; (2) `/fh_buylot` again in another lot: `fh_already_has_lot`, cash unchanged; (3) walk to a claim, `/fh_claim`: works (one of each); (4) `/fh_unclaim` on each class separately; (5) with <price cash: `fh_insufficient_funds`, no row.

## Parallel table
| block | touches | clashes with |
|---|---|---|
| H6 | migrations/0099, plot_rules.lua, plot_rules_spec | any lane adding a migration (renumber at merge to main highest+1); none on source |
| H7 | server/main.lua, README API table, new claims spec | H8, H9 (same file; serial after H7); fh_hands/fh_ui callers need no edit |
| H8 | server/main.lua (or lots.lua), config.lua defaults, fxmanifest, events.md | H7 (needs it), **@world block B on fh_homestead/config.lua**: config.lua edits here merge AFTER world B, not alongside; fh_core/docs/events.md (other lanes append) |
| H9 | config.lua templates, build_rules, slots, build, comfort | **@world block B (config.lua)**: merge after B; H7 (plotOf shape); @survival/@crafting readers (API unchanged) |
| H10 | config.lua, README, OWNER-TESTS.md | **@world block B (config.lua, lot entries)**: must be on main first; other lanes' OWNER-TESTS sections (own section only) |

Order: world B on main (outside this plan) -> H6 -> H7 -> H8 -> H9 -> H10. H6 and the pure-rule half of H7 can start before world B (no config.lua edit);
anything that touches config.lua waits. One migration only (H6); H7-H10 add none.

## Open questions for the owner (proposed default each)
1. **Price**: default $300 per lot (one config value `townLot.price`, per-plot override). Cabin tier 1 costs $150 for scale.
2. **Rep amount**: default +25 rep in the lot's region, once per purchase (no re-farming: refund-free sell then rebuy is blocked by Q5).
3. **Build slots for a lot**: default `chest_2` + `station_1` (workbench) only; no cabin, fence, trophy wall (it is a small safe shop-home, the claim is for building out).
   Comfort from a lot-only character: default none in v1 (comfort stays claim-based); say if you want the best home to count.
4. **"Lawman-safe" concretely**: default = (a) `isInSafeZone` true over the owned lot (radius = lot radius), (b) lots are never raid targets (`plotInfo.raidable=false`
   for @alife), (c) no heat decay or arrest immunity (nothing enforces safe zones yet: README Open). Real law-AI behaviour is a follow-up for fh_zones/@alife.
5. **Sell / abandon / refund**: default = `/fh_unclaim` works on a lot (abandon), **no refund**, and abandoning takes the +rep back (`rep(-townLotRep)`), so buy/abandon/rebuy cannot farm rep; an admin can unclaim. Chest
   contents stay in the stash (existing spill gap). Alternative: 50% refund via `credit` if you want it.
6. **Existing claims in the migration**: default = every existing `fh_plots` row becomes class `'claim'`, nobody loses a plot, and `getPlot` is unchanged.
7. **Lot already owned by someone** is simply taken (same as claims); no rent, no expiry in v1.

## Out of scope
Raids on claims (@alife), law-AI enforcement of safe zones (@zones/@alife), lot-to-lot transfer or trading, rent/upkeep, spill-on-unclaim, new region/town data (world A), claim coords (world B), pushing.

## Lead
- Lead rn-115ea34769e8 (@homestead). Plan drafted by Hom17 rn-feab374a532e; Buddy-checked 2026-11-24 (index name `citizenid` matches 0003, unclaim(src, plotId) is current, DROP INDEX IF EXISTS ok on MariaDB).
- Dispatch order: H6 now; H7 after H6; H8-H10 after @world block B is on main. Owner defaults logged as needs-you (non-blocking); build on the defaults until the owner says otherwise.
- Migration placeholder 0099 renumbered at merge to main highest+1; dedupe check before merge. Specs only via `~/.venvs/rf/bin/python tools/run-specs.py`.
- Reviews: Claude work -> Review - Gemini; tierA waits for Gemini.
