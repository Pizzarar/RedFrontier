# Owner steps: first join (only you can do these)

Two machines. **DevPC** has the repo, FXServer, MariaDB and the Cfx key. **Main PC** runs only RDR2 + RedM.

1. **Main PC:** install RDR2 (your own legit copy) and the RedM client.
2. **Cfx key:** get a server key at https://portal.cfx.re (Server Keys). Where it asks for an IP/name, give the DevPC's Tailscale IP `100.83.196.251` (not `localhost`).
3. **DevPC:** double-click `tools/first-run.cmd`, accept the UAC prompt (opens the firewall on port 30120), and paste the key when asked (it is hidden and saved to the gitignored `server/secrets.cfg`). It starts the server and prints the connect line.
4. **Main PC:** open RedM, press F8, type `connect 100.83.196.251:30120`, then work through OWNER-TESTS.md.

## If something breaks

- First time on a fresh DevPC only: run `tools/setup-server.ps1` once (about 10 minutes of downloads), then repeat step 3. `first-run.cmd` is safe to run again any time.
- Stop the server: close its window, then `tools/stop-server.ps1`.
- Declined UAC: LAN/Tailscale may still work; run `first-run.cmd` again to retry the firewall rules.
- Report anything odd to Core with the last lines of `server/logs/fxserver.log` (DevPC). If the client log is needed, send the tail of `%LOCALAPPDATA%\RedM\RedM.app\logs\CitizenFX_log_*.log` from the Main PC (path to be confirmed).
- With `fh_dev` on (see `server.cfg`), client script errors are also appended to `server/logs/client-errors.log` on the DevPC. Run `fh_clienterr` in game (admin) to check the pipe: expect a line in that file. Exception: `fh_inventory` (an rsg-inventory fork) is not wrapped, so its client errors only show in the RedM client log on the Main PC.

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
