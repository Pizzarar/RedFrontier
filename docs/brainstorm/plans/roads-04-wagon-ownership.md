# Plan roads-04 · Player wagon ownership (buy, call, stow) + farm supplies

Lane: @roads · Lead: Roa4 (`vs who lead`) · Buddy: Roads · 2026-11-25

## Idea
Players still have no way to get a wagon: the only spawn path is the admin dev command `/fh_wagon`
(fh_cargo/server/main.lua:172, `restricted = 'group.admin'`). So M4 ("Haul a safe by wagon") and every freight
contract only work for admins. idea-850 asks for the buy/stable path gated on wagon_t2/t3. roads-04 adds owned
wagons that you buy, call and stow at trade posts. It also clears idea-915 (carrot/potato/corn supplies), which
is unblocked because supplies are on main (fh_trade/config.lua:20-29).

## Owner's words (verbatim)
"build everything autonomously, Aub tests only at the end." Overlord Red3: "no parking without a real blocker …
Buddy picks the next plan."

## Decided
- Trade posts double as wagon yards. No new map positions: use the fh_trade posts from FhRegions and the post
  radius check fh_trade already does. Checked: fh_trade posts, FhRegions, fh_progression README, fh_economy charge
  contract, `vs --help`. No stable or horse system (horses stay out of scope, roads-01).
- Ownership persists in a new `fh_wagons` table (citizenid, tier, bought_at), one row per owned tier. The wagon id
  is already deterministic per owner+tier (`rules.wagonId(citizenid, tierKey)`, main.lua:84), so cargo survives
  stow/call with no extra work. The worker confirms that the container contents persist.
- Buy: `fh_economy:charge(src, price, 'wagon_buy', post_region)`. The price per tier lives in fh_cargo config.
  t2/t3 purchases are gated on canUnlock(`wagon_t2`/`wagon_t3`) (same gate spawnWagon already uses). Map the charge
  errors: `fh_charge_busy` = retry once then refuse; the rest = refuse. Write the row only after the charge
  succeeds, and refund via credit if the insert fails (the roads-fixes pattern, idea-864).
- Call: within a post's radius, spawn an OWNED tier near the post (spawnWagon). One live wagon per player.
  Stow: within a post's radius, despawn your live wagon (cargo kept). The admin `/fh_wagon` stays as the dev
  bypass.
- UI = ox_lib menu stopgap at the post, the same pattern as the fh_quests/fh_fence fallbacks. Queue the @ui
  screen as a follow-up (inbox), not in this plan.
- Remove the stale `TODO(R0 @core idea-602)` comments in fh_cargo (B7 has shipped wagon spawn).

## Plan
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| R16 ownership + buy: migration `fh_wagons` (number at merge), pure rules (price, owned check, gate order), buy export + server handler with charge/refund, specs | `[fh]/fh_cargo` shared/server/config, `server/migrations`, spec | other lanes' migrations (renumber at merge) | Root cause |
| R17 call/stow at posts: post-radius check (reuse fh_trade post data via FhRegions), call = spawn the owned tier, stow = despawn and keep cargo, one live wagon; ox_lib post menu (Buy / Call / Stow); specs | fh_cargo server/client, spec | R16 (stacked) | Root cause |
| R18 idea-915 farm supplies: carrot/potato/corn in `supplies` (priced above value_base, no profit loop), removed from crafting_sources PENDING (spec/crafting_sources_spec.lua:19) in the same branch | fh_trade/config.lua, spec/crafting_sources_spec.lua | crafting spec (edit is PENDING removal only) | Root cause |
| R19 OWNER-TESTS `## Roads`: buy t1 → call → load → stow → call (cargo still there); t2 refused at tier 1, allowed at tier 2; supplies buy carrot. Update `docs/lanes/roads/SPEC.md` + TASKS. Queue the @ui wagon-yard screen to the ui inbox | OWNER-TESTS `## Roads`, docs/lanes/roads | other sections (append-only) | Root cause |

Order: R16 → R17 (stacked) ∥ R18 → R19. Specs on `~/.venvs/rf/bin/python tools/run-specs.py`; tierA review for R16
(money), normal for the rest; merge via the Red3 slot; `vs log decision "roads-04 playtest-ready <hash>"`.

## Done-check
- Venv specs green; crafting_sources PENDING has no idea-915 entries.
- A non-admin player can buy, call and stow a wagon (card steps); `/fh_wagon` is still admin-only.
- roads-04 playtest-ready logged.

## Out of scope
Horses/stables, wagon selling or trade-in, wagon damage persistence beyond the wheel, idea-863 offroad_hint (waits
on a road native, @spikes), ungated chase/ambush, @ui screens.

Credits: original design, no plugin parity.
