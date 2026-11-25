# Plan · @a-life 03 · wilderness-claim raids

Implemented A-Life — Thanks to S.T.A.L.K.E.R. A-Life by GSC Game World.

Lead: AL2 (rn-700965813307), or whoever `vs who lead` returns. Buddy: A-Life (rn-2589bd3f3837). Cross-lane: @homestead (one small export extension, C0).

## Ask (verbatim)
- Hub: "TOWN LOTS (bought, lawman-protected) are never raid targets. WILDERNESS CLAIMS (free) are raid-exposed. That is the core risk/reward."
- Red3: "Keep your lane working its goals ... riff the next one from your SPEC Done-when gaps and hand it over this hour."

## Goal (what Aub sees)
Aub lives on a wilderness claim in a region where outlaws hold a camp. While Aub is online, a warning sometimes comes: "Riders from <camp> are heading for your claim (~5 min)". If Aub is home when they arrive, a gang on foot attacks the claim. Beating them weakens those outlaws. If Aub is away, the raiders steal a few stacks from the claim chest and carry them to their camp's stash, so clearing that camp gets the goods back. A town lot is never raided, and a built fence lowers the odds. `/alife raid <plotId>` forces a raid for testing.

## Decided (leans, owner away, R13)
- Primitives checked:
  - fh_homestead `plotInfo(plotId)` returns `{class, raidable, lawSafe, owner}`. It was built for "@alife raids" (`fh_homestead/server/main.lua:577`).
  - `claimedPlots()` (:571); chest ref `{type='chest', id=rules.chestStashId(plotId, 1)}` (:96); the fence slot's `safeRadiusBonus` (config.lua:26).
  - fh_alife squads, `regionPressure`, and the materialise/despawn/death-watch code in `fh_alife/server/squads.lua` (a-life-02).
  - fh_core `requestSpawn`/`despawn` and container APIs.
  - No new vs command or core API.
- **Targets:** only plots where `plotInfo.raidable` is true and that have an owner. Town lots never are, which the hub requires.
- **Online only:** a raid is scheduled only while the claim owner is online, so nothing is lost while Aub is logged off. If the owner logs off mid-raid, the raid is cancelled and the squad goes home.
- **Odds:** checked each tick per eligible claim: `baseChance × (outlaw-held camps in the claim's region) × (1 − fenceMitigation if a fence is built)`. Each claim has a cooldown (3 h) and there's a global cap on live raids. A region with no outlaw-held camp never raids, so clearing camps protects your claim.
- **Warning first:** the owner gets a notice when the squad sets out. Arrival is `warnTicks` later (about 5 min).
- **Owner home at arrival** (within the raid radius): the squad spawns at the claim on foot through the a-life-02 squad code (owner tag `alife_raid`). Wiping it fires `fh:alife:raid_repelled {plot_id, region_id, faction, participants = citizenids}` and adds `regionPressure`.
- **Owner away at arrival:** the raiders steal up to `stealStacks` (2) random stacks from **chest 1 only**, never more than `stealMaxFraction` of any stack. The goods move into the raiding camp's fh_zones stash, so clearing the camp recovers them. If the camp respawns, its stash resets and the goods are gone, which is the risk. The owner gets an itemised notice.
- **Heat:** none added (idea-899/807 covers squad heat).
- **C0, @homestead:** extend `plotInfo` with `coords`, `region` and `fenceBuilt` (read-only), so fh_alife never copies homestead config or rules. Ask the @homestead lead first. If they'd rather not, they add a read-only export `raidFacts(plotId)` instead. fh_alife does not edit homestead files itself unless the homestead lead agrees.

## Plan
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| C0 `plotInfo` gains `coords`, `region`, `fenceBuilt` + spec | `fh_homestead/server/main.lua` (plotInfo only), homestead spec | @homestead (coordinate with their lead; tiny, read-only) | Root cause |
| C1 rules: eligibility, odds, cooldown, cap, raid lifecycle (`warn→arrive→fight/steal→return`), steal pick, serialize (old saves still load) + specs | `fh_alife/shared/alife_rules.lua` (or a new `raid_rules.lua`), config, specs | none | Root cause |
| C2 server: schedule, owner notices, spawn at the claim via squads.lua, repelled event, steal (chest 1 → camp stash via fh_core), cancel on logoff, `/alife raid <plotId>` (admin), `/alife` lists live raids; events.md | `fh_alife/server/*.lua`, events.md, spec | fh_zones stash (write only through fh_core container API) | Root cause |
| C3 OWNER-TESTS: claim a wilderness plot, `/alife raid`, wait at home and fight, repeat while away and check the chest and camp stash, town lot never raided | OWNER-TESTS.md | append only | Root cause |

Order: C0 ∥ C1 → C2 → C3.
Done-check: `~/.venvs/rf/bin/python tools/run-specs.py` green; Gemini review PASS (quote the reviewer's own verdict line); merge slot from the hub lead (`vs who lead --lane redfrontier`). Never commit to main outside the slot.

## Out of scope
- Offline raids.
- Damage to buildings or slots.
- Raids on town lots.
- Raids by law factions.
- Escort and rescue contracts (a-life-04 candidate).
- Owner-coloured blips.
