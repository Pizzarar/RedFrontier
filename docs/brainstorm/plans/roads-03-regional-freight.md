# Plan roads-03 · Regional freight network + T3 contracts

Lane: @roads · Lead: Roa3 (`vs who lead`) · Buddy: Roads · 2026-11-25

## Idea
After roads-02, freight only runs between heartlands and scarlett_meadows (fh_trade/config.lua:91 `destinations`),
even though fh_trade has 16 posts across the map (config.lua:40-56) and fh_progression now tiers 4 regions
(G1 ae3f6a2). Every freight unlock is heartlands-only, so rep earned elsewhere doesn't open contracts there, and
`contracts_t3` has no consumer. roads-03 makes freight a map-wide network that rep in each region opens up.

## Owner's words (verbatim)
"build everything autonomously, Aub tests only at the end." Overlord Red3: "no parking without a real blocker …
Buddy picks the next plan."

## Decided
- Destinations resolve from fh_core `FhRegions` (posts/towns, same as the posts table does at load,
  world-02 block F) instead of a hand list. Only regions with at least one fh_trade post get offers. Config keeps
  per-region overrides and an `exclude` list. Root cause: one source of truth for places.
- Contract tier gate = **regional**: an offer's origin region decides it. T2 needs
  `fh_progression:getTier(src, origin_region) >= 2`, T3 `>= 3` (README:6). The global `contracts_t2/t3`
  canUnlock ids stay as an extra kill switch (both must pass). Rep in a region opens that region's board, which
  matches the spec's "Regional rep unlocks". Wagon tiers stay on the global wagon_t2/t3 canUnlock (roads-02).
  Checked: fh_progression README (getTier, canUnlock), no new primitive, no new flag.
- T3 contracts: minWagonTier 3, minDistance larger than T2, pay = 2x T2 (6x T1), with a spec bound (T3 pay <= 7x
  the matching T1). Same fh_quests `freight` job type with offer `tier = 3`.
- Fail closed: fh_progression down or erroring → only T1 offers can be accepted.
- Positions from FhRegions are `verified = false` for most posts: the R15 card lists which destinations to
  eyeball; no in-game claims.

## Plan
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| R12 destinations from FhRegions posts: generator builds region→destination from fh_trade posts + FhRegions coords; overrides/exclude in config; T1/T2 offers between any two post regions with distance ≥ tier minDistance; specs (pairs, exclusion, distance filter, missing coords skipped) | `[fh]/fh_trade` shared/server freight, config, spec | none (fh_trade roads-only) | Root cause |
| R13 regional tier gate: accept checks getTier(src, origin) for T2/T3 plus global canUnlock; offers carry `region_id` + `tier`; specs (tier 1/2/3 per region, progression down, throws) | fh_trade freight server/shared, spec | R12 (same files: R13 rebases on R12) | Root cause |
| R14 T3 freight: `freight.t3` config (minWagonTier 3, minDistance, pay 2x T2), contracts_t3 gate, spec pay bound | fh_trade config + shared freight, spec | R12/R13 (same files) | Root cause |
| R15 OWNER-TESTS `## Roads` steps: freight to Saint Denis/Blackwater; tier gate per region (set rep in bayou_nwa only → T2 there, still T1 in heartlands); T3 with a t3 wagon. Update `docs/lanes/roads/SPEC.md` + TASKS | OWNER-TESTS `## Roads`, docs/lanes/roads | other sections (append-only) | Root cause |

Order: R12 → R13 → R14 (same resource, stacked, one worker or sequential) → R15. Specs on
`~/.venvs/rf/bin/python tools/run-specs.py`, Gemini review PASS (tierA review for R13, since it gates pay), merge via the
Red3 slot, then `vs log decision "roads-03 playtest-ready <hash>"`.

## Done-check
- Venv specs green; freight spec proves offers exist for ≥ 3 region pairs incl. bayou_nwa and great_plains.
- `git grep contracts_t3` shows an fh_trade consumer.
- Roads card has the R15 steps; roads-03 playtest-ready logged.

## Out of scope
Ungated chase/ambush (@spikes S2/S3), off-road wheel natives, supplies shortage pricing, @quests per-player board
display (idea-873), new regions or post positions (world lane), illicit-cargo heat on freight.

Credits: original design, no plugin parity.
