# core-08 · First-play items (weapons, use handlers, icons, gates)

Source: Red4 request 2026-11-25, audit /tmp/rf-miss-audit.keep.md §2 H1, H2, M1, M2 (+ §3 G1/G3). Owner is playtesting: Highs first.
job=core-08 first-play items. Lead: Cor3.

## Decided
- Weapon use = vendor `rsg-weapons` (Rexshack-RedM, GPL-3) at a pinned main commit, same pattern as the other `[rsg]` deps in server/VENDORED.md (pin + zip URL row). Why: fh_inventory is a fork of rsg-inventory and already fires exactly its events (`rsg-weapons:client:UseWeapon|UseThrownWeapon|UseEquipment`, server/main.lua:1522-1524, client/main.lua:137); writing our own would re-derive RedM weapon/ammo natives that upstream already handles. Fallback (worker decides, reports why): if rsg-weapons pulls in deps we don't vendor and can't guard (GetResourceState) in <~50 lines of local edits, write a small fh_inventory/client weapons handler for the same three events instead.
  Credit line: "Implemented weapon/ammo use — Thanks to rsg-weapons by Rexshack-RedM" (CREDITS.md + commit).
- Medical/tonic/money_clip handlers live in a new core-owned file `fh_core/server/useables.lua` (one place, registered via RSGCore CreateUseableItem). @survival owns needs/buffs content and may move medical later; told via inbox.
- Every other loot/starter item with no handler gets `useable = false` (local edit to rsg-core/shared/items.lua, recorded in VENDORED.md). fh_inventory's silent return on no handler (server/main.lua:1510-1513) becomes a "You can't use that." notify.
- Icons: placeholders now (copy a fitting existing rsg png per fh_* item into fh_inventory/html/images under the item's image name); real art later via Art duet (queued, not this plan).
- Gates (audit G1/G3 + M1): extend tools/check-contracts.py, which core owns (L1).
- Checked existing primitives: fh_core exports + README (no use registry), fh_survival/shared/items.lua (registers 14 food useables, the pattern to copy), check-contracts.py rules (exports/events/items only), VENDORED.md pattern.

## Blocks
| block | goal | touches | clashes with | profile | stakes |
|---|---|---|---|---|---|
| P1 | vendor rsg-weapons, ensure in server.cfg after fh_inventory; weapons + ammo_box_* usable; guard missing deps (rsg-log etc.) | [rsg]/rsg-weapons (new), server.cfg, VENDORED.md, CREDITS.md, maybe fh_inventory client/main.lua | P2 (VENDORED.md, fh_inventory main.lua, minor) | Implement - Sonnet | normal |
| P2 | useables.lua (bandage, fieldbandage, firstaid, tonic_healing/stamina/energy, money_clip, blood_money_clip); useable=false for the rest of the audit list; "can't use" notify | fh_core/server/useables.lua (new), fh_core fxmanifest, rsg-core/shared/items.lua, fh_inventory/server/main.lua ~1510, VENDORED.md | P1 (minor) | Implement - Sonnet | normal |
| P3 | placeholder icons for every fh_* registered item missing an image | fh_inventory/html/images/* | none | Mechanical - DSF | mechanical |
| P4 | DROPPED 11-25 per Red4: hub rf-gate-lint (rn-8b07778f27e6) adds these check-contracts rules | — | — | — | — |

P1-P3 run in parallel. P1/P2 overlap only on VENDORED.md + fh_inventory main.lua: whichever merges second rebases. Merge order: P1, P2, P3.

## Done when
- Owner can draw a looted revolver, load ammo from an ammo box, use a bandage (heals), and every other loot item either does something or says it can't be used; every fh_* item shows an icon. OWNER-TESTS.md card added by P1/P2.
- venv specs green, `--contracts` 0 findings, `--syntax` clean.

## In flight
