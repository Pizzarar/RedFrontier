# Owner steps: first join (only Aub can do these)

1. Get a server key at https://portal.cfx.re/servers/registration-keys (any name, IP/host `localhost`).
2. Open `server/secrets.cfg` (setup already created it) and replace `REPLACE_WITH_CFX_LICENSE_KEY` with the key. This file is gitignored; never commit it or paste the key anywhere.
3. You need RDR2 (your own legit copy) and the RedM client installed.
4. In PowerShell from the repo root: `tools/setup-server.ps1` (only the first time; it downloads for about 10 minutes), then `tools/start-server.ps1` in its own window.
5. Open RedM, press F8, type `connect localhost:30120`.
6. Test: create a character, spawn in, walk around, press the inventory key. There's no HUD yet; that's expected.
7. To stop: Ctrl+C in the server window, then `tools/stop-server.ps1`.
8. Report anything odd to Core, and include the last lines of `server/logs/fxserver.log`.

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
