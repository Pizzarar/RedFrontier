# fh_fence

Roving black-market fence: schedule, tiered stock, treasure leads. Trades: `server/trade.lua` (invariants in its header).

## Treasure leads (progression-02 G2)

A `fh_treasure_lead` bought from the fence carries `{ target = {x,y,z}, hint }` in its item info.

- **Client** (`client/leads.lua`): for every lead the player carries, the hint shows once as a notify, plus a map
  **area** blip (`leads.areaRadius`). The blip centre is offset 25-65 % of the radius from the spot, so it never
  marks the spot. Using the item shows the hint again. Inside the area, `[E] Dig for the cache` calls `fh:fence:dig`.
  No fh_ui screen.
- **Server** (`server/leads.lua`, pure rules in `shared/leads_logic.lua`): `fh:fence:dig` takes no client input. It
  uses the server-side ped coords and the player's own equipped + backpack items. Order:
  1. one dig per citizenid (`dig_busy`), `leads.cooldownSeconds` between attempts (`dig_cooldown`);
  2. pick a held lead whose target is within `leads.digRadius` (`no_lead`, `lead_too_far`; `lead_mixed` when the
     same section also holds a lead for another spot, because removeItem takes "one lead", not a given slot);
  3. roll ONE weighted `leads.loot` entry (`leads_logic.roll(loot, rng)`), then `canFit` the part in the backpack
     (`no_room`). Nothing has been taken yet;
  4. `fh_core removeItem(lead, 1)` (all-or-nothing). This is the one-shot step: N leads pay out at most N times;
  5. money via `fh_economy:pay(src, amount, 'fence_lead_dig', region)` (region = the stop that sells that lead) and
     the part via `fh_core addItem`. If either fails, the lead is **not** given back. A
     `WARNING lead dig: lead taken but payout incomplete, pay by hand: ...` line lists citizenid, target, region and
     the exact money / item owed, with the error code. Pay it by hand.
- Config: `FhFenceConfig.leads` (item, digRadius, areaRadius, cooldownSeconds, lockStaleSeconds, regionId, loot).
  Keep loot money under fh_economy `maxPay`.
- Spec: `spec/fence_leads_spec.lua`.
