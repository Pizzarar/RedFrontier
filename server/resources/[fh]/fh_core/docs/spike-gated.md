# Behaviour behind `fh_spike_gated`

One convar, `fh_spike_gated` (server.cfg, `set fh_spike_gated true`, default `true`), from plan core-01
"Amendment 2026-11-22: autonomy". While it is true, anything that depends on unproven Spikes results (S1/S2) takes
the conservative path. The owner flips it to `false` once the named spike RESULT is GO. It is read on every use
(`GetConvar`), so a live `set fh_spike_gated false` applies to the next event; entities adopted while gated keep
the default orphan mode until they are re-requested.

| # | Behaviour | Gated path (`true`, default) | Ungated path (`false`) | Flipped by |
|---|---|---|---|---|
| 1 | Spawner or current network owner of an adopted entity drops (`playerDropped`) | Server `DeleteEntity`s it and re-requests it (fresh retry budget) from another ready client, or parks it as `pending_no_client` until a player joins / comes in range. `onReady` fires again with the new netId. | Keep the entity and its record; rely on OneSync ownership migration plus orphan mode (row 2). | `[spikes]/spk_camp` RESULT: "camp persists across owner leave" (S1) |
| 2 | Orphan mode at adoption | Not set (OneSync default). | `SetEntityOrphanMode(entity, 2)` (KeepEntity), pcall-wrapped. | same as row 1 |
| 3 | Camp ped whose spawner drops (fh_zones) | Same as row 1: the live ped is deleted and re-requested, so it comes back at full health at its spawn point and the new spawner re-runs the hostile-AI setup (`fh:spawn:adopted`). The camp keeps the same requestId and tolerates the new netId. A ped the server already saw dead is never revived (a re-adopted corpse is despawned). | Ungated: the ped keeps its entity; OneSync migrates it, but the relationship group / weapon set by the first client is client-local and may be lost until S1 shows what survives. | same as row 1 |

Code: `fh_core/server/spawn.lua` (`gated()`, `playerDropped` handler, `verify`), decision in
`fh_core/shared/spawn_rules.lua` `onPlayerDropped` (specced in `spec/spawn_rules_spec.lua`).

Not behind the flag (always on):
- No server-side entity creation at all: client creates, server adopts by netId. Changing that needs a spike proving
  a server create native works on RDR3 (S1 probes `CreateVehicle` `0xDD75460A`); wagons are out of scope until M4.
- Entity-gone watchdog: an adopted entity that no longer exists server-side is re-requested.
