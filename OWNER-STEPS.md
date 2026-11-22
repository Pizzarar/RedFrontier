# Owner steps: first join (only Aub can do these)

1. Get a server key at https://portal.cfx.re/servers/registration-keys (any name, IP/host `localhost`).
2. Open `server/secrets.cfg` (setup already created it) and replace `REPLACE_WITH_CFX_LICENSE_KEY` with the key. This file is gitignored; never commit it or paste the key anywhere.
3. You need RDR2 (your own legit copy) and the RedM client installed.
4. In PowerShell from the repo root: `tools/setup-server.ps1` (only the first time; it downloads for about 10 minutes), then `tools/start-server.ps1` in its own window.
5. Open RedM, press F8, type `connect localhost:30120`.
6. Test: create a character, spawn in, walk around, press the inventory key. There's no HUD yet; that's expected.
7. To stop: Ctrl+C in the server window, then `tools/stop-server.ps1`.
8. Report anything odd to Core, and include the last lines of `server/logs/fxserver.log`.
