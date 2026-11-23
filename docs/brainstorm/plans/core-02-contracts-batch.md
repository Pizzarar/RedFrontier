# Core plan 02: shared-contract batch for sibling lanes (`@core`)

Asks (verbatim from the inbox):
- idea-600 (@progression): "fh_economy exports: getRep(src, region_id)->int and charge(src, amount, reason, region_id) (ledger-first debit, mirror of pay, fails on insufficient funds)"
- idea-602 (@roads): "(1) fh_core spawn kind 'wagon' via client CreateVehicle + adopt netId (spawn_rules.lua:16 KINDS excludes vehicles); (2) admin fh_heat stub (admin.lua:46) delegates to exports.fh_heat:set when fh_heat started; (3) OK for roads to append rows to fh_core/docs/spike-gated.md and register hammer/wagon_wheel/freight items?"
- idea-603 (@homestead): "add fh_economy.charge(src, amount, reason, region_id) (RemoveMoney + ledger kind='charge', fails cleanly if short) and fh_core.removeItem(ref, item, amount)"

## Decided
- One block, **B7**, for Cor3. It runs in parallel with B-access because they touch different files. Unblocks @progression P2/P3, @homestead H2 and @roads R0.
- `fh_economy.charge(src, amount, reason, region_id)`: mirrors `pay`. The balance is checked first, then money removed and the ledger row (kind='charge') written in the same order and failure handling as `pay`. It never goes negative and returns `false, 'fh_insufficient_funds'`. 600 and 603 are the same contract and ship once.
- `fh_economy.getRep(src, region_id) -> int`, 0 when there's no row.
- `fh_core.removeItem(ref, item, amount)`: all-or-nothing across the ref's container. Returns `false, 'fh_not_enough'` with no partial removal.
- Spawn kind `wagon`: client CreateVehicle, then server adopts the netId (server vehicle creators are compiled out on RDR3, see core-01). Covered by `fh_spike_gated` and listed in spike-gated.md.
- `fh_heat` admin stub delegates to `exports.fh_heat:set` when fh_heat is started, otherwise stays a stub.
- Ownership: other lanes **may** append rows to `fh_core/docs/spike-gated.md`. They register their items from **their own resource** through the fh_core item registry API and never edit fh_core config files. If no runtime registration API exists, B7 adds `fh_core.registerItems(tbl)` (validates the §4.1 schema; duplicate id = error).
- Checked: existing fh_economy/fh_core exports (from the inbox asks' file:line refs). No primitive covers charge/getRep/removeItem.

| Block | Touches | Clashes with |
|---|---|---|
| B7 | fh_economy (charge, getRep), fh_core (removeItem, spawn KINDS wagon, registerItems if missing, admin.lua heat delegate), spike-gated.md, specs | B-access (none: admin/allowlist files); sibling lanes consume only |

Done-check: specs for charge (ok / short / ledger row), getRep (row / no row), removeItem (exact / short / no partial), wagon kind state machine, registerItems schema reject. Syntax clean. Each export is listed in the resource README. Root cause, no workarounds.
Out of scope: fh_heat itself, wagon tiers, items' gameplay.
