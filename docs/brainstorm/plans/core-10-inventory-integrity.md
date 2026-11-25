# core-10 · Inventory integrity + starter items + pane hook

Lead: @core lead Cor4. Base: main after core-09 nits slot (5f770d2).

## Idea
Cor4 thought only owner-gated items were left, but the @core inbox still has five parked ideas. Four are real; one is already covered. Two are duplicate/loss risks (tierA).

## Requests (verbatim, condensed)
- idea-970: "fh_core addItem can't distinguish 'not added' from 'added then threw' … FhAddItem runs Refresh/TriggerClientEvent/Log AFTER InvCore.Commit … Callers doing fallback (homestead H14b refund) risk duplicates. Root fix: pcall post-commit side effects in FhAddItem (return true), or a distinct reason."
- idea-987: "fh_core:createDropBag drops the leftovers returned by Fh.CreateDropBag … Return leftovers to the caller. fh_alife works around it with one stack per bag."
- idea-923: "rsg-character pendingStarterItems is in-memory, lost on server/resource restart before first spawn … persist it or grant on first spawn from DB state; L: stale pending entry when an unspawned character is deleted."
- idea-1024: "saddlebag outfit pane hook for fh_tailor wardrobe … @ui needs a core hook (e.g. a pane button event) before it can wire openWardrobe."
- idea-965: "vertical window ±20 m … narrow per type (chest ±10 …)".

## Decided
- **idea-965 closed as covered by core-09 R1.** Access.SnapToleranceAbove/Below is now 13.5 = SNAP_TOLERANCE 10 + InteractDistance 3.5 (fh_core/config.lua:51-52), down from 20. Per-type narrowing would gain only 3.5 m. Archive it.
- **I1 (970+987, one worker, tierA):** everything after commit in fh_inventory fh_api.lua (FhAddItem, and the same pattern in FhRemoveItem/SetItemData/CreateDropBag if present) runs under pcall: commit succeeded → return true, and log the side-effect error. The rule: once committed, the call never reports failure. createDropBag returns `ref, leftovers` (leftovers = rejected stacks, `{}` when all fit; additive, old callers unaffected). README + specs. After merge, tell @alife it can drop the one-stack-per-bag workaround and @homestead that the H14b refund risk is closed.
- **I2 (923, tierA):** grant starter items from DB state, not memory. Lean: an `fh_starter_granted` row keyed by citizenid (migration). On first spawn, insert first (unique key), and only the winner grants. No in-memory map, so it survives a restart, and a deleted character leaves nothing stale. It's a fix inside vendored rsg-character (sv_appearance.lua:8,357,394), already forked by d28c462, so record it in the resource's FH-PATCHES note if one exists.
- **I3 (1024):** client hook only: fh_inventory exposes `exports.fh_inventory:registerPaneButton({id, label, pane='saddlebag'|'backpack'})`. Clicking fires the client event `fh_inventory:paneButton` with `{id, pane}`. Works even with fh_saddlebag_pane off (the button shows on whichever pane exists). @ui/@progression wire openWardrobe on their side. Normal review.
- Checked: fh_inventory fh_api.lua exports, fh_core inventory.lua createDropBag, the existing B6f pane code (dark), check-contracts (new exports must be added to it).

## Plan
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| I1 commit-safe returns + dropbag leftovers | fh_inventory/server/fh_api.lua, fh_core/server/inventory.lua (createDropBag, inv()), READMEs, specs | I3 (fh_inventory, different side: server vs client/NUI) | Root cause |
| I2 starter items from DB | [rsg]/rsg-character/server/sv_appearance.lua, new migration, specs | none | Root cause |
| I3 pane button hook | fh_inventory client + NUI pane, README, check-contracts allowlist/exports, spec if testable | I1 (rebase only) | Root cause |

All three run in parallel. Builders are Gemini. Reviews: I1 and I2 tierA (Claude), I3 normal.
Done-check: venv specs green, check-contracts 0, syntax clean, pd grep clean.
- I1: a spec where a post-commit throw still returns true (no duplicate on the caller's fallback), plus createDropBag leftovers for over-capacity input.
- I2: restart between create and first spawn still grants once; concurrent spawn grants once; deleted character leaves no row affecting others.
- I3: the export registers and the click event fires with the right payload.
After merge: notify @alife (987), @homestead (970), @ui + @progression (1024). Archive 923/965/970/987/1024.

## Open
- (none)

## Out of scope
CHEST-COORDS, B6f-cleanup, B1-live (owner-gated); openWardrobe wiring (@ui/@progression).
