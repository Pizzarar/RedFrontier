# world-04 · make the owner's walk verdicts a one-command fix (World Buddy, 2026-11-25)
Red3 (Overlord): "owner has ~75% Claude quota ... wants it USED. Keep your lane working its goals: no parking without a real blocker."
Wor1: "The owner's fh_mark verdicts don't exist yet, so world-04 can't be the walk-fix pass."

Done-when gap this closes: "enabled regions have places the owner has walked (verified via /where)". The walk itself needs the owner. This plan makes everything after the walk mechanical: verdicts become a reviewed patch in a single step.

## Blocks
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| L Walk-apply tool | new tools/world-walk-apply.py (reads world_walk.json, writes a patch to regions.lua / fh_homestead config), new spec or py test | none (tools/ only) | Root cause |
| M Ids visible in game | fh_ui /where label (append `[id]` for admins, or when fh_dev=1), fh_tour step message | @homestead H12 /where lot (same file, append-only label) | Root cause |
| N Per-region walk sheets | OWNER-TESTS.md (generated section), tools/world-walk-sheet.py | none | Root cause |
Order: L ∥ M ∥ N. All small.

### L · Walk-apply
- Input: `world_walk.json` (fh_core resource data, from fh_mark). Output: an edit to the data files.
  - `ok` → `verified = true` at the recorded entry.
  - `bad` with standing coords → replace x/y (and z hint) with the coords where the owner stood, and set `verified = true`.
  - `bad` with a note but no usable coords → a TODO list printed for the lead.
- Last verdict per id wins. Unknown ids are reported. It never touches ids or names. After applying, it re-runs the readiness and spacing specs and prints violations; a moved claim that lands too close to a town shows up here.
- Dry-run by default (`--apply` writes). Plain python3 is fine (no lupa needed); edits Lua by id-anchored line match, with a spec on a fixture.
- Done-check: fixture test covers ok / bad+coords / bad-without-coords / unknown id / duplicate verdicts; running against an empty file is a no-op.

### M · Ids visible in game
- When the player is an admin (or fh_dev=1), `/where` and `fh_tour` show each place's id (e.g. `Cotorra Bend claim [heartlands_02]`), so `fh_tp <id>` and bug reports can use it. Players see no change.
- Done-check: ui_places spec for both admin and player labels.

### N · Walk sheets
- Generate one OWNER-TESTS section per enabled region from the data, in fh_tour order: id, name, kind, and what to check ("flat? reachable by horse? not in a building? camp out of sight of the road?"). Re-runnable; replaces its own section between markers.
- Done-check: the sheet lists every unverified place in the 4 enabled regions; rerunning changes nothing.

## Decided
- Checked primitives: fh_mark / world_walk.json (world-03 J), fh_tour, /where (fh_ui), tools/run-specs.py. No new in-game command.
- After world-04, @world is blocked on the owner's walk (a real blocker). The next plan is world-05 = run L on the owner's verdicts, then switch regions on via `fh_regions_enabled`.
- Not doing neutral-faction outposts (rail depot, bounty office, etc.) until a consumer asks for them; same rule as ambush points.
- Merge via Red3's merge slot; specs via `~/.venvs/rf/bin/python tools/run-specs.py`.

## Out of scope
- Shops/per-region prices (@trade). Heat factions (idea-848 @roads). Town-lot purchase (@homestead).
