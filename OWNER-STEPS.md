# Owner steps: install, start, connect, playtest prep

Two machines. **DevPC** hosts the repo, FXServer, MariaDB and the Cfx license key. **Main PC** runs only RDR2 + the RedM client and connects to the DevPC on port **30120**. Then work through `OWNER-TESTS.md` from its "Playtest order" section.

## 1. Prerequisites

- **Main PC:** your own legit RDR2 copy + the RedM client.
- **DevPC:** the server host is **Media-Host**, Windows, this repo checked out, PowerShell, NordVPN Meshnet (the Main PC and friends reach it through Meshnet, no router port-forward; friends join via a Meshnet invite, see section 6). FXServer and MariaDB are downloaded for you by `tools/setup-server.ps1`; nothing to install by hand.
- **Cfx key:** from https://portal.cfx.re (Server Keys). Where it asks for an IP/name, give the host's Meshnet IP `100.102.50.11` (LAN `192.168.1.135` on the same network; not `localhost`).

## 2. First-time setup (DevPC, about 10 minutes of downloads)

1. Run `tools/setup-server.ps1` once. It is idempotent: downloads FXServer, creates a portable MariaDB, creates the database + DB user, writes `server/secrets.cfg` (gitignored, from `server/secrets.example.cfg`: `sv_licenseKey`, `mysql_connection_string`, `rcon_password`) and **applies every `server/migrations/*.sql` in name order** (0001 to 0015), recording each in a `schema_migrations` table. Re-running skips what is applied, so run it again after pulling new migrations.
2. Only if you use your own MariaDB instead: create the DB, put its connection string in `server/secrets.cfg`, and apply `0001_rsg_schema.sql` ... `0015_fh_pending_credit.sql` in order (`mariadb DATABASE < server/migrations/00NN_*.sql`; they are `CREATE TABLE IF NOT EXISTS`, safe to repeat).
3. `server/server.cfg` ships ready (do not reorder the `ensure` lines): `exec secrets.cfg`/`admins.cfg`/`allowlist.cfg`, `set fh_dev_autoadmin 1`, `setr fh_dev 1`, `set fh_spike_gated true`, then rsg-core, fh_core, fh_inventory and every `fh_*` lane resource.

## 3. Start the server (DevPC)

Double-click `tools/first-run.cmd`, accept the UAC prompt (opens the firewall on 30120), paste the Cfx key when asked (hidden; saved to `server/secrets.cfg`). It starts MariaDB + FXServer (`tools/start-server.ps1`) and prints the connect line. Safe to run again any time (it is also how you restart). If you skipped step 2, `first-run` stops early and tells you to run `tools/setup-server.ps1` first. Stop: close the server window, then `tools/stop-server.ps1`.

## 4. Connect (Main PC)

Open RedM, press F8, type `connect 100.102.50.11:30120` (or `192.168.1.135:30120` if the Main PC is on the same LAN). Then follow `OWNER-TESTS.md` "Playtest order".

## 5. Admin and dev mode

- **Auto-admin:** with `fh_dev_autoadmin 1` and no admin yet, the **first player to join** is added to `group.admin` (one `granted group.admin to license:<hash>` line in `server/logs/fxserver.log`). The claim is saved in `server/resources/[fh]/fh_core/access.txt` (and copied into `server/admins.cfg` when the server can write it), so it persists across restarts. Nothing to configure. Check it with `fh_dump backpack <yourId>` (replies, no "no permission"). This is OWNER-TESTS "Core: B-access". To revoke, delete your `admin license:...` line in `fh_core/access.txt` AND your line in `server/admins.cfg` (if there), then restart (the next first joiner becomes admin). Set `fh_dev_autoadmin 0` for a public server.
- **`fh_dev 1` (dev mode, on in server.cfg):** client script errors are reported to the server and appended to `server/logs/client-errors.log` on the DevPC. Run `fh_clienterr` in game (admin) to check the pipe: expect a line in that file. Exception: `fh_inventory` (an rsg-inventory fork) is not wrapped, so its client errors only show in the RedM client log on the Main PC.
- **`fh_spike_gated true` (leave it):** conservative path until the spike verdicts are recorded (see OWNER-TESTS "Spike verdicts").
- **`fh_regions_enabled` (optional, switch regions on without a code edit):** not set by default, so the code's own flags apply (on today: heartlands, scarlett_meadows, bayou_nwa, great_plains). To choose the regions yourself, add **one** line to `server/server.cfg` next to `setr fh_dev 1` (it must be `setr`, not `set`, so players' games get the list too), then restart the server. The list **replaces** the code flags, so name every region you want on, including the four above. Example with all 15 on:
  `setr fh_regions_enabled "heartlands,scarlett_meadows,bayou_nwa,great_plains,bluewater_marsh,roanoke_ridge,grizzlies_east,grizzlies_west,cumberland_forest,big_valley,tall_trees,hennigans_stead,cholla_springs,gaptooth_ridge,rio_bravo"`
  Commas or spaces both work; upper/lower case doesn't matter. A misspelled id is ignored and logged once in `server/logs/fxserver.log` as `[fh_core] fh_regions_enabled: unknown region id "<id>" ignored`. An empty value (`setr fh_regions_enabled ""`) or deleting the line goes back to the code flags. A region switched on gets its claims, lots, camps, trade posts, job board, blips and `/where` entries. Restart after changing the line (camps, map blips and job board props are set up when the server starts).

## 6. Friends (max 6 players)

1. Send your friend a NordVPN Meshnet invite to Media-Host (NordVPN app > Meshnet > Invite, using their NordVPN account email; leave "Allow remote access" on for them); they install NordVPN + RedM, accept the invite, and F8 `connect 100.102.50.11:30120` (`192.168.1.135:30120` on the same LAN). They are rejected the first time.
2. In the DevPC server window copy the license from the `allowlist: rejected <name> license:<hash>` line and type `fh_allow license:<hash>` there (or in game F8 as admin). It is saved in `fh_core/access.txt` (re-applied at every start); `server/allowlist.cfg` still works for adding friends by hand.
3. They connect again and get in (not as admin).

## 7. Materials you'll need `fh_give` / `/giveitem` for

Everything in this list has an in-game source. Trade posts sell the supplies at a flat price with unlimited stock, at every post; today the only post is the **Valentine Trade Post** (heartlands, about -176, 630, 114, radius 6). Buy with `/tradebuy <item> <n>` (max 100 per buy) or the Buy entries in the `/tradepost` menu; `/tradequote` lists prices; a failed grant refunds in full. You need cash (`/givemoney <yourId> cash 500`). `fh_give <yourId> <item> <n>` (admin) or `/giveitem <yourId> <item> <n>` is just a shortcut that skips the shop.

| Item name | Used for | Source |
|---|---|---|
| `lumber` | homestead builds (5 to 40 per slot tier) | Valentine trade post $3 (roads); defined in fh_homestead |
| `nails` | homestead build tier 2 (20) | Valentine trade post $2 (roads); defined in fh_homestead |
| `lead` | ammo recipes (2 each) | Valentine trade post $2 (roads); defined in fh_crafting |
| `casings` | ammo recipes (2 each) | Valentine trade post $2 (roads); defined in fh_crafting |
| `resource_gunpowder` | ammo recipes (1 to 2) | Valentine trade post $3 (roads); defined in rsg-core |
| `herb_american_ginseng` | tonic recipe (2) | Valentine trade post $3 (roads); defined in rsg-core |
| `herb_wild_mint` | tonic recipe (1) | Valentine trade post $3 (roads); defined in rsg-core |
| `herb_oregano` | tonic recipe (2) | Valentine trade post $3 (roads); defined in rsg-core |
| `herb_red_sage` | tonic recipe (1) | Valentine trade post $3 (roads); defined in rsg-core |
| `gun_parts` | `/fh_restore` (fh_gunsmith) | outlaw camp loot (core-05); defined in fh_crafting |

Note: if `fh_give` replies `fh_unknown_item` for `lumber`/`nails`, restart `fh_homestead` after `fh_core` and tell Core. Counts per build are in `fh_homestead/config.lua`; per recipe in `fh_crafting/shared/recipes.lua`. Other test items: `bread`, `hammer`, `wagon_wheel`, `test_cargo_crate`, `weapon_revolver_cattleman` (the OWNER-TESTS steps name them).

## If something breaks

- Fresh DevPC: run `tools/setup-server.ps1` once, then step 3 again.
- Declined UAC: LAN/Meshnet may still work; run `first-run.cmd` again to retry the firewall rules.
- Report anything odd to Core with the last lines of `server/logs/fxserver.log` (DevPC). If the client log is needed, send the tail of `%LOCALAPPDATA%\RedM\RedM.app\logs\CitizenFX_log_*.log` from the Main PC (path to be confirmed).

## B5 admin commands (needs your account in `group.admin`; none of this is runtime-tested yet)

1. `fh_give <yourId> bread 2` then open the inventory: 2 bread in your backpack (anything that does not fit stays in a drop bag and the reply says so).
2. `fh_give <yourId> notanitem` replies `fh_unknown_item`.
3. `fh_tp 0 0 100` moves you; `fh_tp <otherId>` moves you to them.
4. `fh_dump backpack <yourId>` prints the snapshot JSON in the server console.
5. `fh_heat <yourId> 40` replies "heat stub" (no effect until fh_zones exists).

## B6a homestead plot + chest (needs two characters; none of this is runtime-tested yet)

1. Stand on the plot (about -300, 790, 118 in the Heartlands) and run `fh_claim`: reply "claimed plot heartlands_01". A chest prop should appear near you; press E next to it.
2. Put an item in the chest (e.g. `fh_give <yourId> bread 2`, then drag it in), close, relog, reopen: the item is still there.
3. A second character at the plot: `fh_claim` says `fh_plot_taken`, and E on the chest says `chest: fh_not_owner`.
4. Run `fh_claim` far from the plot: `fh_not_in_plot`. `fh_unclaim` as the owner releases the plot (chest items stay in the stash for now).
5. The chest model (`p_chest01x`) and plot coordinates are guesses: if nothing shows, report the model/coords to Core.
