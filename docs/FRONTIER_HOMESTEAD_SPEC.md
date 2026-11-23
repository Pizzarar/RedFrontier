# Frontier Homestead — Product Spec & Lane Roadmap

> Input doc for VibeSquad lane splitting. High-level by design: each lane gets its own detailed spec once M0 contracts are locked.
> Source: owner (Aub), 2026-11-22. Hub feasibility notes live in docs/brainstorm/redfrontier.md.

---

## 1. Product Summary

A private, small-group (1–4 players) **PvE extraction sandbox** on RedM. No story, no RP-server politics. Core fantasy: build a homestead, ride out for dangerous jobs, physically haul loot home, reinvest.

**Pillars (every feature must serve at least one):**
1. **Extraction tension** — value only counts once it's home.
2. **Weight matters** — big money = big cargo = slow, exposed, no fast travel.
3. **Functional home** — every homestead upgrade unlocks a mechanic or buff, never pure cosmetics.
4. **Soft consequences** — death and neglect hurt, never ruin a session.
5. **No XP bars** — progression = capital + regional reputation.

**Non-goals:** story missions (amended 2026-11-23, Aub: optional one-time family questlines and an intro tutorial are in scope; text dialogue only, no cutscenes or voice acting), PvP, 32+ player scaling, lethal hunger/thirst meters, a full player-driven economy, a custom map.

---

## 2. Locked Decisions (rulings, change only deliberately)

| Decision | Ruling | Why |
|---|---|---|
| Platform | RedM (Cfx.re), local/private server | Matches pitch; uses native RDR2 world, horses, wagons, weapon condition |
| Framework | **RSGCore** (+ ox_lib, oxmysql) | QBCore-style, ox_lib utilities suit heavy custom Lua. VORP has the bigger script ecosystem, but this project is mostly custom. **Hard to undo:** switching later means migrating or wiping character data |
| Player count | 1–4, OneSync on | Keeps AI/entity sync budget manageable |
| Language | Lua 5.4 (client + server); NUI in vanilla JS/HTML/CSS | No build step; agents produce fewer toolchain errors |
| Authority | **Server-authoritative** for inventory, money, loot, heat, insurance | Even private, this prevents desync and dupes, and keeps state recoverable |
| Persistence | oxmysql, one migration folder owned by Core lane | Single source of schema truth |
| Resource prefix | `fh_` | Lane ownership = resource folder ownership |

---

## 3. Core Loop → System Map

| Loop step | Systems involved |
|---|---|
| **Prep at camp** | Homestead, Buffs/Survival, Insurance, Weapons (ammo crafting) |
| **Venture out** | Frontier Zones/AI, Contracts/Trade, Hunting |
| **Extract alive** | Containers/Cargo, Wagons, Heat/Ambush, Death |
| **Upgrade** | Economy/Rep, Homestead stations, Hired hands, Fence |

---

## 4. Shared Contracts (M0, defined by the Core lane BEFORE other lanes start)

Parallel agents collide here. Lock these first.

### 4.1 Item schema
Every item declares: `id`, `label`, `weight`, `size_class`, `stackable`, `value_base`, `illicit` (bool), `condition` (nullable 0–100), `quality` (nullable 1–3 stars).

**`size_class` drives extraction rules:**
| size_class | Can live in | Fast-travel allowed |
|---|---|---|
| `pocket` | equipped, backpack, saddlebag, wagon, chest | yes |
| `bulky` | saddlebag, wagon, chest | yes |
| `cargo` (safes, bullion, barrels, freight) | wagon, chest only | **no** |

### 4.2 Container model
`equipped` · `backpack` · `saddlebag` (horse) · `wagon` · `chest` (homestead) · `drop_bag` (death) · `fence_stash`
One server-side container API (`fh_core`): `move`, `canFit`, `getWeight`, `snapshot`, `transferAll`. No lane writes to inventory tables directly.

### 4.3 Event bus naming
`fh:<domain>:<verb>` e.g. `fh:death:dropped`, `fh:heat:changed`, `fh:cargo:delivered`. Each lane publishes a list of events it emits and consumes in its README.

### 4.4 Region & faction registry
Static config: regions (towns, safe roads, territories), faction IDs, territory tiers (T1–T3). Every other lane references these IDs and does not define its own.

### 4.5 Buff interface
`fh_buffs.apply(src, buff_id, magnitude, duration)` with stacking rules defined once. Homestead, Survival, and Hunting trophies all feed it.

### 4.6 Money & rep ledger
All payouts go through `fh_economy.pay(src, amount, reason, region_id)`. Rep changes go through `fh_economy.rep(src, region_id, delta, reason)`. The ledger is auditable, which makes balancing possible.

---

## 5. Lanes

Each lane = one or more `fh_*` resources, owned by a single agent stream.

| # | Lane | Resources | Scope (high level) | Depends on |
|---|---|---|---|---|
| L0 | **Core & Infra** | `fh_core`, migrations, server cfg | Framework install, shared contracts (§4), item registry, container API, event docs, dev/admin commands (spawn item, set heat, teleport) | — |
| L1 | **Homestead** | `fh_homestead` | Plot claim, clearing, prop placement (cabin, fence, chests), persistent storage, station slots, comfort score calculation | L0 |
| L2 | **Survival & Buffs** | `fh_buffs`, `fh_survival` | Needs-as-buffs (food, water, rest, temperature, cleanliness), Well-Rested from comfort, canteen refill, washing, sluggish debuffs (never lethal) | L0 |
| L3 | **Frontier Zones & AI** | `fh_zones` | Territory polygons, tiers, outlaw camp spawns/respawns, loot tables (worn weapons, safes, parts), camp clear state | L0 |
| L4 | **Death & Insurance** | `fh_death` | Soft death (keep equipped, drop bags), world drop-bag entity + despawn timer, tracker insurance (fee → delayed delivery to chest), doctor recovery fee | L0, L1 (chest target) |
| L5 | **Weapons & Crafting** | `fh_gunsmith`, `fh_crafting` | Worn-weapon condition, parts, restoration at gunsmith bench, reloading press (ammo), apothecary (tonics) | L0, L1 (stations) |
| L6 | **Cargo, Wagons & Trade** | `fh_cargo`, `fh_trade` | Cargo-class loading onto wagons, fast-travel block, wheel break + hammer repair, wagon tiers, regional price model (shortages), freight contracts, contract board | L0, L3 |
| L7 | **Heat & Ambush** | `fh_heat` | Per-faction heat, decay ("lay low"), bounty payoff, roadblocks, night smuggling ambushes, mounted chase gangs targeting wagons | L0, L3, L6 |
| L8 | **Hunting** | `fh_hunting` | Pelt quality from shot placement, pelt as `bulky`/`cargo` item, Legendary hunt quest chain, trophies → comfort score | L0, L1, L2 |
| L9 | **Economy & Progression** | `fh_economy`, `fh_fence`, `fh_hands` | Ledger, regional rep tiers + unlocks, roving black-market fence (route, schedule, rare parts, treasure leads), hired hands (ranch hand, stablehand, cook) automating upkeep | L0, + consumes all |
| L10 | **UI/NUI** | `fh_ui` | One shared NUI shell: buff HUD, heat indicator, insurance dialog, contract board, station menus, fence shop. Lanes ship data, L10 ships screens | L0, per-screen lane |

**Parallelism after M0:** L1, L2, L3 run fully parallel. L4/L5 start once L1 exposes chests and station slots. L6 → L7 is sequential. L9 depends on everything else and is built incrementally.

---

## 6. Milestones

| M | Name | Exit criteria (playable test) |
|---|---|---|
| **M0** | Foundation | Server boots on RSGCore; §4 contracts merged; admin tools work; an item moves between all container types with the weight/size rules enforced |
| **M1** | **Vertical slice: one extraction loop** | Claim a plot, place 1 chest → ride to 1 T1 outlaw camp → clear it, loot a worn rifle + small safe → die once (bags drop, equipped kept) → recover bag → ride home, stash. *Nothing else starts its full build until this loop is fun.* |
| M2 | Gunsmith & Stations | Restore the looted rifle at a bench; craft ammo; apothecary tonic; Well-Rested buff from a furnished cabin |
| M3 | Insurance & Soft Death polish | Tracker insurance end-to-end; doctor fee path; drop-bag despawn rules |
| M4 | Wagons & Trade | Haul a safe by wagon; fast-travel blocked; wheel break/repair; one freight contract; one shortage trade route |
| M5 | Heat & Ambush | Faction heat rises from repeat raids; roadblock + mounted wagon chase; lay-low decay; bounty payoff |
| M6 | Hunting | 3-star pelt economics; one Legendary hunt; trophy feeds comfort |
| M7 | Progression & Fence | Regional rep unlocks wagon tier + T2 contracts; roving fence route; one hired hand automating troughs |
| M8 | Balance & content pass | Ledger-driven tuning; T2/T3 territories; more loot/contract variety |

---

## 7. Risks & Gotchas (read before assigning agents)

| Risk | Impact | Mitigation |
|---|---|---|
| **LLMs hallucinate RDR3 natives** | High. Code compiles but silently does nothing in-game | Require every native to be checked against the rdr3 natives reference (name + hash) in the PR description. Keep an allowlist file of confirmed-working natives in `fh_core/docs/natives.md` |
| **AI chase/ambush behaviour** (mounted gangs pursuing wagons) | High, the hardest technical piece | Prototype in M1 as a throwaway spike. If native riding/combat tasks can't chase reliably, fall back to "ambush at chokepoint" roadblocks only |
| **Entity sync & ownership** under OneSync | Medium. Duplicate camps, ghost wagons | Server owns spawn decisions; clients only render. Strict entity budget per zone |
| **No automated test harness for game behaviour** | Medium. Agents will claim "done" on untested code | Each lane PR includes a manual in-game test checklist. Server logic stays in pure Lua functions testable outside the game (busted) where possible |
| **Scope** | High. This is 10 lanes of systems | M1 vertical slice is the gate. Cut L7 ambush chases and L9 hired hands first if time runs short |
| **Existing-script temptation** | Medium. Off-the-shelf RSG scripts bring their own inventory/housing assumptions that break §4 | Only adopt external scripts that can call the `fh_core` container API, or wrap them. Otherwise build in-house |
| **Legal/ToS** | Low for private use | Requires a legitimately owned RDR2 + Cfx.re server key. Don't monetise. |

---

## 8. Open Questions (non-blocking; defaults applied)

| Question | Default until changed |
|---|---|
| Solo vs co-op tuning? | Tune for solo; co-op = same loot, scaled AI count |
| Map scope for M1–M4? | One region (e.g. a single state's worth of territory), with expansion later |
| Do homesteads have fixed plots or free placement? | Fixed pre-defined plot locations (far easier collision/persistence) |
| Can AI raid the homestead? | No, it's a true safe zone (pitch pillar) |
| Heist-style safe cracking minigame? | No, a timed interaction for now |

---

## 9. Agent Rules (paste into each lane's brief)

- Own only your `fh_*` folder. Cross-lane changes go through a contract PR to L0.
- Never write to framework or inventory tables directly. Use the `fh_core` API.
- Every native used must appear in `natives.md` with its hash, or be added there with a source link.
- Server decides, client displays.
- Ship a `README.md` listing events emitted/consumed, config keys, DB tables, and the in-game test checklist.
- Config over constants: all tuning numbers live in `config.lua`.
