# world-03 · road ambush nodes, region flips, faster owner walk (World Buddy, 2026-11-24)
Red3 (Overlord): "owner has ~75% Claude quota for the next 1-2 days and wants it USED ... world-03 next: e.g. per-region content (posts/shops) or ambush points with @roads heat as consumer."
A-Life Buddy: "a-life-02 now actually uses `regions[id].ambush = { {x,y,z}, ... }`, 2-3 road points per enabled region ... your data wins as soon as it exists."
Done-when gaps this closes: the owner can walk and verify places quickly; switching on the 11 regions is a config flip; ambush data has a real consumer (a-life-02 B1).

## Blocks
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| H Ambush nodes | fh_core/shared/regions.lua (`regions[id].ambush`), world spacing spec | @a-life a-life-02 B1 (reads it; W1 fallback in fh_alife/config.lua) | Root cause (replaces A-Life's W1 workaround) |
| I Region readiness + convar flip | regions.lua `isEnabled`, new spec/world_readiness_spec.lua, docs/first-run or OWNER-STEPS | H (same file, different function) | Root cause |
| J Walk tooling | fh_core/shared/admin_args.lua parseTp, fh_core/server/admin.lua (fh_tp, new fh_mark), fh_ui places lookup | none (fh_core admin is shared: tell Cor2) | Root cause |
| K Heat faction coverage | queued to @roads (fh_heat/config.lua roadblock/ambush/chase tables have only the 4 legacy factions) | n/a | Inbox, not built here |
Order: H ∥ J, then I (its readiness check counts H's nodes).

### H · Ambush nodes (idea-837 unparked)
- 2-3 points per region for all 15 regions: `regions[id].ambush = { { id = '<region>_amb_1', x, y, z, label = '<road description>', verified = false }, ... }`. A-Life reads x/y/z; the extra fields are optional. Confirm the shape with Ali1 before committing.
- Points sit on real roads or trails between towns, posts and camps (taken from map knowledge), at least 200 m from any town center, claim or lot, and not inside an enabled territory radius. Original labels only.
- Done-check: the spacing spec covers ambush nodes; a-life specs stay green with data present (the fallback is ignored); `/where` does not list ambush nodes, since they are not places.

### I · Region readiness + flip without a code edit
- A readiness spec over all 15 regions: at least 3 claims, at least 1 lot where the region has a town, at least 3 camps owned by a gang faction, at least 1 post, at least 2 ambush nodes, a law faction and a gang faction in `regions[].factions`, every id resolving (camp↔territory↔faction, plot↔region), and all spacing rules. It prints a per-region table (ready / missing X).
- Convar override: `setr fh_regions_enabled "heartlands,scarlett_meadows,..."`. When set, it replaces the static `enabled` flags in `isEnabled`; when unset, the data flags apply. This lets the owner switch regions on from server.cfg after a walk. Document it in OWNER-STEPS.md.
- Checked primitives: `isEnabled` (regions.lua:721) and the existing `fh_dev` / `fh_spike_gated` convar pattern. There is no existing per-region switch.
- Done-check: specs green; the convar is parsed on the server and its value reaches clients (shared file: use a replicated `setr`, or send the list from the server; lead's call). Unknown ids in the convar are logged and ignored.

### J · Walk tooling (so the owner can check ~140 spots in one evening)
- Extend `fh_tp` (admin_args.lua:44 parseTp) to accept a place id: `fh_tp <placeId>` teleports to a claim, lot, camp, post, town or ambush node, z-hinted with a ground snap on arrival. Today a bare number means a player id, so keep that; a non-numeric argument means a place id.
- `fh_tour <region>`: steps through that region's unverified places in a sensible riding order. `fh_tour next` goes to the next one.
- `fh_mark ok|bad [note]`: records a verdict for the place you are standing at (the nearest place within 30 m) into `fh_core` resource data `world_walk.json` (SaveResourceFile, append-only) with id, verdict, note and the player's current coords. A `bad` verdict plus "stand at the right spot" coords becomes the fix list for world-04.
- Admin-only (existing ace). Checked primitives: `fh_tp`, `/where`. `fh_tour` and `fh_mark` are new because nothing records verdicts today.
- Done-check: specs for parsing and nearest-place lookup; OWNER-TESTS "walk the claims" updated to use `fh_tour` / `fh_mark`.

### K · Heat factions → @roads (inbox)
- fh_heat roadblock, ambush and chase tables list only outlaws/lawmen/raiders/rhodes_law (fh_heat/config.lua:46-51, 58-63). desert_gang and the neutral factions have no entry. Ask @roads to resolve by faction `kind` or add rows.

## Decided
- Leans taken (R13, owner away, quota push). Checked: FhRegions §4.4 registry, isEnabled, fh_tp, /where, a-life-02 B1/W1 contract, fh_heat R6 tables.
- Merge via Red3's merge slot; specs via `~/.venvs/rf/bin/python tools/run-specs.py`.
- Lead: Wor1 rn-cb1d438f267f.

## Out of scope
- Applying the owner's walk verdicts (world-04). Shops/per-region economy (@trade). Contracts/legendaries (@quests/@hunting, idea-839/840).
