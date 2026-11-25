# hunting-03 · Regional trappers + legendary coats (idea-1016, idea-1004)

## Idea
1. **idea-1016 (@quests ask):** one trapper per region instead of one in heartlands, so `pelt_sold.region_id` varies and @quests' hunt_request works everywhere. Only enabled regions show a trapper.
2. **idea-1004 (progression-03 T5):** finishing a legendary chain grants that legendary's coat through `exports.fh_tailor:grant`.

## Words (verbatim)
- Hun2 (2026-11-25): "idea-1016 (@quests: per-region trappers/sale points so pelt_sold.region_id varies; today one trapper in heartlands, config.lua:36-42 — coords are owner TODO-verify, so maybe region-enabled-only) and idea-1004 (progression-03 T5: legendary pelt coats via exports.fh_tailor:grant; catalog ids come from progression T3, coordinate with Pro2). Your lean on order/scope".
- progression-03 T5: "@hunting (legendary pelt coats) and @quests (questline rewards) call `exports.fh_tailor:grant`."

## Decided
- **Primitives checked:** `exports.fh_tailor:grant(citizenid, entryId, source) -> ok, 'granted'|'already_owned'|err` (fh_tailor/server/tailor.lua:202, exported main.lua:314). It is idempotent, works offline, accepts any catalog id, returns `wrong_sex` for the other sex's entry and `unknown_entry` for ids not in the catalog. `source` must match `^[%w_:%-%.]+$`. Also checked: `FhRegions.isEnabled`, the per-region legendary files `data/legendaries/<region>.lua` (hunting-02), shared/sell.lua (single `cfg.Trapper`, sell.lua:88), and the chain-complete handler (server/main.lua:406). No new command, rule or cross-lane API.
- **Order (Buddy lean):** C1 ∥ C2, then C3. They touch different code paths. Both edit server/main.lua in separate sections, so the second to merge rebases.
- **C1 trappers: data, not config.** Each `data/legendaries/<region>.lua` gets `trapper = { label, coords }`. The legendary's rumour is bought from that trapper, so the rumour point moves to it (heartlands already works this way). `cfg.Trapper` becomes the fallback for heartlands only. A trapper shows and sells **only in enabled regions** (Hun2's lean): no prompt, no blip, and sell refuses with `fh_region_closed`. Sell, pay and `pelt_sold.region_id` all use the trapper the player is standing at. Coords are `TODO-verify-in-game`, and enabled regions' coords go on the owner card.
- **C2 coats: grant on `chain_complete`** (Buddy lean, R13). The pelt stays sellable. No commission step, no item consumption, no removeItem dependency. If you'd rather "bring the pelt + fee to the trapper", that's a later block.
- **Coat ids (hunting proposes, @progression owns the catalog):** `coat_<legendary_id>_male` and `coat_<legendary_id>_female` (e.g. `coat_legendary_bear_male`), 15 × 2 = 30 earned_only outfit entries. Hunting calls grant for both. One returns `wrong_sex`, which is expected and ignored. Source tag: `hunting:legendary:<legendary_id>`.
- **No ordering dependency on progression T3 (Root cause, not a workaround):** grant is idempotent, so hunting also **backfills on player load**. For every completed chain it calls grant for both coat ids. Before T3 adds the ids, grant returns `unknown_entry`, which is logged once per id and harmless. Once T3 merges, every character who already finished a chain gets their coat on next login. All calls go through pcall, and a missing fh_tailor is a no-op.
- Original content, no plugin inspiration on hunting's side. The tailor credit line already lives in progression-03.
- Rules: specs-first; `~/.venvs/rf/bin/python tools/run-specs.py` only. Builders/reviewers per current Red3 rule. No push; Red3 merge slots. Never write the owner's name.

## Plan
| Block | Touches | Clashes with | Kind | Stakes |
|---|---|---|---|---|
| C1 Regional trappers: `trapper` field in the 15 legendary data files; `sell.lua` uses a trapper list, picks the nearest one in range in an enabled region, and pays + emits with its region_id; rumour action uses the region's trapper; client loops prompts/blips over enabled trappers. Specs: sell at a scarlett_meadows trapper emits `region_id='scarlett_meadows'`; a disabled region's trapper refuses `fh_region_closed`; out-of-range refuses; heartlands unchanged (regression); rumour at the right trapper only | shared/sell.lua, shared/chain.lua (rumour position), data/legendaries/*.lua, client/main.lua, server/main.lua (sell/rumour wiring), spec/* | C2 in server/main.lua (separate sections; rebase) | Root cause | Medium (money path + an event @quests reads) |
| C2 Legendary coats: on chain complete, pcall grant `coat_<id>_male` + `_female` with source `hunting:legendary:<id>`; a backfill on player load for completed chains; log `unknown_entry` once per id. Specs (fake grant): complete → 2 calls with the right ids/source; wrong_sex ignored; unknown_entry doesn't break completion; backfill grants only completed chains; fh_tailor missing → no error | server/main.lua (complete handler + player-loaded), shared/coats.lua (new, pure id/backfill logic), spec/* | C1 in server/main.lua | Root cause | Low |
| C3 Docs: README trapper table (region → label, enabled) + coats section (id convention, backfill); OWNER-TESTS `## Hunting`: sell at a non-heartlands enabled trapper (check the region in the quest/ledger), finish a legendary → coat in wardrobe (after T3) | README.md, OWNER-TESTS.md | other lanes' OWNER-TESTS sections | Root cause | Low |

**Done-check per block:** venv specs green, reviewer PASS, merged in a Red3 slot, hash logged.
**Done when:** trappers in all 4 enabled regions sell and emit their own region_id; disabled regions show none; finishing a legendary calls grant for its coat (and backfills); OWNER-TESTS updated; `decision hunting trappers-coats-ready <hash>`.

## Cross-lane (sent)
- @progression inbox: add 30 earned_only outfit entries `coat_<legendary_id>_male|female` to the T3 catalog (ids listed in the inbox item). Presets are their call (`TODO-verify` like the rest of T3).
- @quests: FYI when C1 merges. `pelt_sold.region_id` now varies, with no payload change.

## Open
- Coat looks: T3/S1 picks the presets. Until then a coat is a catalog row with a placeholder preset.
- Trapper coords for enabled regions need an in-game check by the owner (card in C3).

## Out of scope
- Regional pelt price differences. A commission/craft step for coats. fh_tailor catalog edits (that's @progression). Trappers in disabled regions going live (they turn on with the region).

## Lead
Hun2.
