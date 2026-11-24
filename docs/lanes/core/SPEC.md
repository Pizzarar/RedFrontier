# @core SPEC · Core & Infra (L0)

Source: docs/FRONTIER_HOMESTEAD_SPEC.md §4 (contracts), §5 L0, §6 M0/M1. Rolling brief: docs/brainstorm/core.md.

## Goal
Own the server baseline every lane builds on: FXServer + RSGCore + MariaDB setup, `fh_core` shared contracts (item registry, container API, spawn contract, events, regions, buffs interface), `fh_economy` money/rep ledger, the `fh_inventory` fork (server veto), admin/dev tools, and the test tooling (`tools/run-specs.py`, boot-check, first-run). Keep the contracts stable and documented, so sibling lanes integrate through exports, never around them.

## Done when
- M0: server boots on RSGCore with every `[fh]` resource started and no errors; admin tools work in-game; an item moves between all container types with size/weight rules enforced (owner-verified).
- M1: the §6 extraction loop is playable end-to-end by the owner (OWNER-TESTS.md M1 card PASS).
- Every cross-resource export/event a sibling calls is either a real fh_core/fh_economy export, or listed as an intended gap. Checked statically in CI (core-07 L1).
- Specs green via `~/.venvs/rf/bin/python tools/run-specs.py`; `[fh]` syntax clean.
- Money paths (pay/charge/credit/pending-credit) audited tierA with no open crit/high.

## Contracts owned (README is the source of truth per resource)
- fh_core: item registry (registerItems), containers (registerContainer, addItem/removeItem incl. carried refs, setItemInfo, move, transferAll, snapshot, view, canFit, getWeight, clear/delete, createDropBag), spawn (requestSpawn, despawn, getSpawn, requestOfNetId), regions, events (fh:* bus), admin cmds, fh_spike_gated convar.
- fh_economy: pay, charge, credit (offline-safe, fh_pending_credit), rep, getRep.
- fh_inventory: fork of rsg-inventory with server veto; compat AddItem/RemoveItem/SetItemData.

## Out of lane
Wagons (@roads), buffs/needs content (@survival), loot tables beyond data requests, UI screens (@ui), horse ownership (unowned; see brief Open).
