TEST: `ensure spk_outfit` on a male rsg character and a female rsg character. Step 5+ presets each (`/spk_outfit 0`, `/spk_outfit next` ...), check face/hair/body vs `/spk_outfit reset`, turn `/spk_outfit auto on`, test respawn (die or `/kill`) and relog, and test `/spk_outfit layer hat|bandana|gloves|coat [1..3]` + `/spk_outfit layer clear` over 2 presets.

## Natives
SET_PED_OUTFIT_PRESET — 0x77FF8D35EEC6BBC4 — https://alloc8or.re/rdr3/nativedb/?n=0x77FF8D35EEC6BBC4  (called by name `SetPedOutfitPreset(ped, index, false)`, same native as rsg-character/client/functions.lua:270,332-337 and client/charselect.lua:194)
_APPLY_SHOP_ITEM_TO_PED — 0xD3A7B003ED343FD9 — https://alloc8or.re/rdr3/nativedb/?n=0xD3A7B003ED343FD9  (rsg-character/client/functions.lua:1073,1129)
_REMOVE_TAG_FROM_META_PED — 0xD710A5007C2AC539 — https://alloc8or.re/rdr3/nativedb/?n=0xD710A5007C2AC539  (rsg-character/client/clothes.lua:272,842)
_GET_SHOP_ITEM_COMPONENT_CATEGORY — 0x5FF9A878C3D115B8 — https://alloc8or.re/rdr3/nativedb/?n=0x5FF9A878C3D115B8  (rsg-character/client/functions.lua:1134)
_REFRESH_SHOP_ITEMS_FOR_PED (NativeFixMeshIssues) — 0x59BD177A1A48600A — https://alloc8or.re/rdr3/nativedb/?n=0x59BD177A1A48600A  (rsg-character/client/functions.lua:1138)
_UPDATE_PED_VARIATION_PREP (NativeUpdatePedVariation step 1) — 0x704C908E9C405136 — https://alloc8or.re/rdr3/nativedb/?n=0x704C908E9C405136  (rsg-character/client/functions.lua:1142)
_UPDATE_PED_VARIATION — 0xCC8CA3E88256E58F — https://alloc8or.re/rdr3/nativedb/?n=0xCC8CA3E88256E58F  (rsg-character/client/functions.lua:1143)
_UPDATE_PED_VARIATION_POST (NativeUpdatePedVariation step 3) — 0xAAB86462966168CE — https://alloc8or.re/rdr3/nativedb/?n=0xAAB86462966168CE  (rsg-character/client/functions.lua:1144)
_IS_PED_READY_TO_RENDER (NativeHasPedComponentLoaded) — 0xA0BC8FAED8CFEB3C — https://alloc8or.re/rdr3/nativedb/?n=0xA0BC8FAED8CFEB3C  (rsg-character/client/functions.lua:1078,1146)
PLAYER_PED_ID — 0x096275889B8E0EE0 — https://alloc8or.re/rdr3/nativedb/?n=0x096275889B8E0EE0  (in fh_core/docs/natives.md)
GET_ENTITY_MODEL — 0xDA76A9F39210D365 — https://alloc8or.re/rdr3/nativedb/?n=0xDA76A9F39210D365  (in fh_core/docs/natives.md)
GET_HASH_KEY (client Lua global `joaat`) — 0xFD340785ADF8CFB7 — https://alloc8or.re/rdr3/nativedb/?n=0xFD340785ADF8CFB7  (in fh_core/docs/natives.md)
Cfx runtime (not game natives): `GetResourceKvpString`, `SetResourceKvp`, `RegisterCommand`, `AddEventHandler`, `CreateThread`, `Wait`, `GetGameTimer`, `GetCurrentResourceName`, `exports['rsg-character']:ApplySkin()`.

## Candidate outfit presets (candidate, unproven)
`mp_male` and `mp_female`: indices `0..7`+ via `/spk_outfit <n>` and `/spk_outfit next` / `prev` (`rsg-character` uses `3` on preview peds at `client/functions.lua:332,337` and `client/charselect.lua:194`, and `7` on `LoadModel` at `client/functions.lua:270,970`). All indices are **candidate, unproven** for keeping rsg face/hair/body.

## Candidate layer item hashes (candidate, unproven)
Extracted from `server/resources/[rsg]/rsg-character/data/clothing.lua`. Category hashes: `hats`=`0x9925C067`, `neckwear`=`0x5FC29285`, `gloves`=`0xEABE0032`, `coats`=`0xE06D30CE`.

| sex | slot | k | hash (dec) | hash (hex) | hashname | status |
|---|---|---|---|---|---|---|
| male | hat | 1 | 1820410246 | `0x6C814186` | `CLOTHING_ITEM_M_FRONTIER_HAT_000` | candidate, unproven |
| male | hat | 2 | 2754281087 | `0xA42AFE7F` | `CLOTHING_ITEM_M_HAT_000_TINT_001` | candidate, unproven |
| male | hat | 3 | 3382727215 | `0xC9A0522F` | `CLOTHING_ITEM_M_HAT_001_TINT_001` | candidate, unproven |
| male | bandana | 1 | 1906846397 | `0x71A82ABD` | `bandana` | candidate, unproven |
| male | bandana | 2 | 2458134595 | `0x92842843` | `gathered_bandana` | candidate, unproven |
| male | bandana | 3 | 1580751299 | `0x5E3859C3` | `patterned_bandana` | candidate, unproven |
| male | gloves | 1 | 745251899 | `0x2C6BA43B` | `CLOTHING_ITEM_M_GLOVES_000_TINT_001` | candidate, unproven |
| male | gloves | 2 | 2674335993 | `0x9F6720F9` | `CLOTHING_ITEM_M_GLOVES_001_TINT_001` | candidate, unproven |
| male | gloves | 3 | 3799630629 | `0xE279C325` | `CLOTHING_ITEM_M_GLOVES_002_TINT_001` | candidate, unproven |
| male | coat | 1 | 3349172660 | `0xC7A051B4` | `CLOTHING_ITEM_M_COAT_000_TINT_001` | candidate, unproven |
| male | coat | 2 | 1696062810 | `0x6517DD5A` | `CLOTHING_ITEM_M_COAT_001_TINT_001` | candidate, unproven |
| male | coat | 3 | 3148604518 | `0xBBABE466` | `CLOTHING_ITEM_M_COAT_002_TINT_001` | candidate, unproven |
| female | hat | 1 | 3313189151 | `0xC57B411F` | `CLOTHING_ITEM_F_FRONTIER_HAT_000` | candidate, unproven |
| female | hat | 2 | 2424693915 | `0x9085E49B` | `CLOTHING_ITEM_F_HAT_000_TINT_001` | candidate, unproven |
| female | hat | 3 | 414370589 | `0x18B2CB1D` | `CLOTHING_ITEM_F_HAT_001_TINT_001` | candidate, unproven |
| female | bandana | 1 | 2401499311 | `0x8F23F8AF` | `bandana` | candidate, unproven |
| female | bandana | 2 | 2410224255 | `0x8FA91A7F` | `gathered_bandana` | candidate, unproven |
| female | bandana | 3 | 2262899489 | `0x86E11B21` | `patterned_bandana` | candidate, unproven |
| female | gloves | 1 | 590067755 | `0x232BB82B` | `CLOTHING_ITEM_F_GLOVES_000_TINT_001` | candidate, unproven |
| female | gloves | 2 | 3682376111 | `0xDB7C99AF` | `CLOTHING_ITEM_F_GLOVES_001_TINT_001` | candidate, unproven |
| female | gloves | 3 | 1531697767 | `0x5B4BDA67` | `CLOTHING_ITEM_F_GLOVES_002_TINT_001` | candidate, unproven |
| female | coat | 1 | 3555396598 | `0xD3EB0BF6` | `CLOTHING_ITEM_F_COAT_000_TINT_001` | candidate, unproven |
| female | coat | 2 | 422907192 | `0x19350D38` | `CLOTHING_ITEM_F_COAT_001_TINT_001` | candidate, unproven |
| female | coat | 3 | 2588043597 | `0x9A42694D` | `CLOTHING_ITEM_F_COAT_002_TINT_001` | candidate, unproven |

Notes: `auto` persists in client KVP (`spk_outfit:auto`, `spk_outfit:index`) and listens to `rsg-character:client:ApplySkin` via `AddEventHandler` (listen-only, never `RegisterNetEvent`), re-applying after 2.5s so `ApplySkinMultiChar` finishes swapping the ped. `/spk_outfit reset` calls `exports['rsg-character']:ApplySkin()` so you can compare the ped's original face/hair/body. No convar/flag gates any command (plan Decided).

## GO if
Fitted outfit presets work on both `mp_male` and `mp_female` while keeping rsg face/hair/body (or you have a clear PASS/FAIL + good indices list and which layer slots sit cleanly without clipping).

RESULT: male good: [..] / female good: [..] / face kept Y/N / auto after respawn Y/N / after relog Y/N / layers clean: ...
