# crafting-02 · Herb gathering (idea-720)

## Idea
Wild herb patches in the world. Walk up, press E, a short progress bar plays, and you get herb_* items. This adds a second source for the four apothecary herbs. The first source, buying at trade posts (idea-716/719, @roads), stays.

## Owner's words (verbatim)
Overlord relay 2026-11-24: "owner has ~75% Claude quota for the next 1-2 days and wants it USED. Keep your lane working its goals: no parking without a real blocker... idea-720 herb gathering: riff it with Cra2."

## Decided
- Uses the same pattern as the camp stash and death bags: client `lib.points` + `lib.showTextUI('[E] ...')` (fh_zones/client/main.lua:77-84, fh_death/client/main.lua:24-28), then a server event. Progress bar: `lib.progressBar` in a pcall, the same way as fh_hunting/client/main.lua:114. No new game natives, no plant props, no composite natives.
- The server decides everything. The player position comes from `GetPlayerPed` + `GetEntityCoords` (already listed in fh_core/docs/natives.md). Reach uses the same radius rule as `FhContainers.canReach` (fh_core/shared/containers.lua:70), applied to patch coords inside the pure gather rules. Never trust coords sent by the client.
- The grant goes through `exports.fh_core:addItem` with a carried ref (fh_core/server/inventory.lua:249). If it's refused (full or overweight), the patch doesn't go on cooldown.
- Cooldown is **per patch, shared by everyone** (`respawnSeconds`, default 900, held in server memory, cleared on restart). It's a shared frontier resource, and it limits farming.
- Yield is a {min,max} roll per pick (default 1-2), using an injected rng so the specs are deterministic.
- Patches are config data in `fh_crafting/config.lua`: `herbPatches = { {id, herb, coords, yield, respawnSeconds}, ... }`, about 2 per herb (8 total) spread over 2-3 regions. Coords are `TODO-verify-in-game`.
- It lives in fh_crafting (the lane owns the herb inputs). A new resource isn't worth it for one module.
- Checked primitives: lib.points/showTextUI/progressBar (ox_lib, already used in 3 lanes), fh_core addItem carried ref (core-03), FhContainers.canReach. No new command, convar or flag. The visual cue reuses the existing `fh_spike_gated`.
- The C8 sources spec counts herbs as sourced once C9 merges. That clears the idea-718 PENDING entries for herbs without waiting on @roads.

## Blocks
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| C9a pure `shared/gather_rules.lua`: canPick(patch, playerCoords, now, lastPicked) → ok/reason (`fh_too_far`, `fh_regrowing`, `fh_unknown_patch`), rollYield(patch, rng), config validation (every patch herb is a registered/rsg item, coords present). Busted specs | fh_crafting/shared, fh_crafting/config.lua, spec/crafting_gather_* | C8 sources spec (same config file: append only) | Root cause |
| C9b server `server/gather.lua`: `fh:crafting:gather(patchId)` → canPick → addItem carried → stamp cooldown only on success. Rate-limit one pick in flight per src. Client `client/gather.lua`: lib.points per patch, showTextUI `[E] Pick <label>`, progressBar ~4s, then the event | fh_crafting/server, client, fxmanifest | none | Root cause |
| C9c README section + Crafting OWNER-TESTS card: walk to a patch, pick, get 1-2 herbs, a second pick says regrowing, wait/restart, pick again, brew tonic_* from gathered herbs | fh_crafting/README.md, OWNER-TESTS.md (Crafting section only) | other lanes' OWNER-TESTS sections | Root cause |

Order: C9a → C9b → C9c (C9c can be written alongside C9b). Done-check: venv specs green (`~/.venvs/rf/bin/python tools/run-specs.py`), the sources spec shows herbs sourced, Gemini review PASS, merge via the Red3 slot.

## Open
- Patches are invisible except for the [E] prompt. Players find them by location (landmark spots). Follow-up: a plant prop or blip at each patch needs in-game native checks, so it goes to the spikes lane as `spk_herb`, gated by `fh_spike_gated`. Additive: not a workaround for the source itself.
- Price balance vs the @roads supplies herbs: gathering is free but slow, buying costs money. Tune after playtest.

## Lead
Cra2 (rn-ba5485686a96), after C8 or in parallel (C9 is a separate worktree; it shares only append-only lines in fh_crafting/config.lua).

## Out of scope
Composite/world-native herb detection, plant props, skill or progression gating of picks, other gatherables (wood, ore).
