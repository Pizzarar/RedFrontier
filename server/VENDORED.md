# Vendored dependencies (plain files, no submodules)

All under `server/resources/[rsg]/`. Schema: `server/migrations/0001_rsg_schema.sql` = Rexshack-RedM/txAdminRecipe `rsgcore.sql` (main, verbatim; superset incl. tables for resources not vendored).
Config order follows the same recipe's server.cfg. FXServer/MariaDB are fetched by `tools/setup-server.ps1` (pins live in that script).

| Dep | Source | Pin | Download | sha256 |
|---|---|---|---|---|
| oxmysql | CommunityOx/oxmysql | v2.12.3 | https://github.com/CommunityOx/oxmysql/releases/download/v2.12.3/oxmysql.zip | b6f54204b3931e064df490739ee17a8c4004fb6f904a50ffdf838c27030816c6 |
| ox_lib | CommunityOx/ox_lib | v3.32.3 (declares rdr3) | https://github.com/CommunityOx/ox_lib/releases/download/v3.32.3/ox_lib.zip | 10a328352906073f18646e5ba148545fb6cfd986c298dc93e99023d80c6505e2 |
| rsg-core | Rexshack-RedM/rsg-core | 82da3e2b85c9f3aeaf32f4215b57ea6115e154cf (main) | https://github.com/Rexshack-RedM/rsg-core/archive/82da3e2b85c9f3aeaf32f4215b57ea6115e154cf.zip | n/a (git commit pin; no release asset) |
| rsg-inventory | Rexshack-RedM/rsg-inventory | a151ee4c27a8d251ae69e85f92f83bdd9175b13c (main) | https://github.com/Rexshack-RedM/rsg-inventory/archive/a151ee4c27a8d251ae69e85f92f83bdd9175b13c.zip | n/a (git commit pin; no release asset) |
| rsg-character | Rexshack-RedM/rsg-character | 3603e61b7aab15f8262d7e4c677199caf1b51f16 (main) | https://github.com/Rexshack-RedM/rsg-character/archive/3603e61b7aab15f8262d7e4c677199caf1b51f16.zip | n/a (git commit pin; no release asset) |
| rsg-weather | Rexshack-RedM/rsg-weather | 45c6a3f30232bb977de0b81562b7fdeb822cf127 (main) | https://github.com/Rexshack-RedM/rsg-weather/archive/45c6a3f30232bb977de0b81562b7fdeb822cf127.zip | n/a (git commit pin; no release asset) |
| rsg-target | Rexshack-RedM/rsg-target | 583404d5e8a365579247d19c431b7797d3097d01 (main) | https://github.com/Rexshack-RedM/rsg-target/archive/583404d5e8a365579247d19c431b7797d3097d01.zip | n/a (git commit pin; no release asset) |
| rsg-chat | Rexshack-RedM/rsg-chat | e2b342cc30591ecb912eda02ce1418119b3df741 (main) | https://github.com/Rexshack-RedM/rsg-chat/archive/e2b342cc30591ecb912eda02ce1418119b3df741.zip | n/a (git commit pin; no release asset) |
| rsg-loading | Rexshack-RedM/rsg-loading | bf79401d5cee578f4d3fa5a84086b2b8e67a7986 (main) | https://github.com/Rexshack-RedM/rsg-loading/archive/bf79401d5cee578f4d3fa5a84086b2b8e67a7986.zip | n/a (git commit pin; no release asset) |
| mapmanager, spawnmanager | citizenfx/cfx-server-data resources/[managers] | c6afa3909c763e3327ed76825e78453286c99f05 | https://github.com/citizenfx/cfx-server-data/archive/c6afa3909c763e3327ed76825e78453286c99f05.zip | n/a (git commit pin) |

Not vendored on purpose (skipped from the recipe for the B1 minimum): rsg-hud, rsg-banking, rsg-wardrobe, rsg-menubase, PolyZone, menu_base, rNotify, rsg-voice, xsound, etc.
rsg-core guards its optional rsg-banking call with GetResourceState. Add more as later blocks need them.
