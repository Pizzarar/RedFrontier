# fh_fence

Roving black-market fence: schedule, tiered stock, treasure leads. Trades: `server/trade.lua` (invariants in its header).

## Treasure leads (progression-02 G2)

A `fh_treasure_lead` bought from the fence carries only `{ lead = '<spot id>' }` in its item info (G2b).

- **Spots are server-only.** `config.lua` is a shared script (every client downloads it), so its stock names a lead's
  spot by an opaque id only (`stock[*].leads[*].lead = 'lead_hl_01'`). The exact coords and the hint live in
  `server/config_leads.lua` (`FhFenceLeadSpots`, a `server_scripts` entry: never move it to shared/client/files).
  Ids must not describe the spot. A stock id missing there is not listed in the fence menu (and logs an `ERROR lead
  spot ids missing` line at start), so no undiggable lead is sold. The menu payload's lead row carries the id only.
- **Pre-G2b leads** (bought before this change) still carry a server-written `{ target, hint }`. The server accepts
  that target (read server-side only), maps it back to a spot id when the coords match exactly (pay region of the
  stop that sells it, else `leads.regionId`; logs say `lead=legacy`), and the dig spends it exactly once like any
  lead. Their item info stays client-visible until they are dug: nothing rewrites existing items.

- **Client** (`client/leads.lua`): for every lead the player carries, the hint shows once as a notify, plus a map
  **area** blip (`leads.areaRadius`). The blip centre is offset 25-65 % of the radius from the spot and rounded to a
  5 m grid, so it never marks the spot. The client payload (area, key, hint) never carries the exact target or the spot id. Using the item shows the hint again. Inside the area, `[E] Dig for the cache` calls `fh:fence:dig`.
  No fh_ui screen.
- **Server** (`server/leads.lua`, pure rules in `shared/leads_logic.lua`): `fh:fence:dig` takes no client input. It
  uses the server-side ped coords and the player's own equipped + backpack items. Order:
  1. one dig per citizenid (`dig_busy`), `leads.cooldownSeconds` between attempts (`dig_cooldown`);
  2. pick a held lead whose spot (id resolved in `server/config_leads.lua`, or a pre-G2b stored target) is within
     `leads.digRadius` (`no_lead`, `lead_too_far`, also for an id with no spot; `lead_mixed` when the same section
     also holds a lead for another spot, because removeItem takes "one lead", not a given slot);
  3. roll ONE weighted `leads.loot` entry (`leads_logic.roll(loot, rng)`), then `canFit` the part in the backpack
     (`no_room`). Nothing has been taken yet;
  4. `fh_core removeItem(lead, 1)` (all-or-nothing). This is the one-shot step: N leads pay out at most N times;
  5. money via `fh_economy:pay(src, amount, 'fence_lead_dig', region)` (region = the stop that sells that lead) and
     the part via `fh_core addItem`. If either fails, the lead is **not** given back. A
     `WARNING lead dig: lead taken but payout incomplete, pay by hand: ...` line lists citizenid, target + spot id, region and
     the exact money / item owed, with the error code. Pay it by hand.
- **Character switch:** the citizenid is re-checked right before `removeItem`, `pay` and `addItem` and right after
  `removeItem`. A switch before removal refuses (`player_changed`, nothing taken). A switch after it hands nothing
  more to anyone and logs `WARNING lead dig: character switched ...` with both citizenids and what is owed.
- Config: `FhFenceConfig.leads` (item, digRadius, areaRadius, cooldownSeconds, lockStaleSeconds, regionId, loot).
  Keep loot money under fh_economy `maxPay`. Spots (coords + hint): `server/config_leads.lua`.
- Spec: `spec/fence_leads_spec.lua` (incl. a scan of everything fxmanifest ships to clients for spot coords / hints),
  `spec/fence_trade_spec.lua` (purchase writes `{ lead = id }` only).
