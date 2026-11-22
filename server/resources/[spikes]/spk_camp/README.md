TEST: `ensure spk_camp`, stand on a road, run `/spk_camp` (read BOTH path lines in F8/console + notify: `server-side CreatePed ...` and `server CreateVehicle(cart01): OK|FAILED`), ride 300m away and back, `/spk_camp status`; then disconnect + rejoin and `/spk_camp status` again (same netIds, no dupes, owner changed); shoot one outlaw and `/spk_camp status` (shows DEAD); `/spk_camp clear` to reset.

## Natives

CREATE_PED — 0xD49F9B0955C367DE — https://alloc8or.re/rdr3/nativedb/?n=0xD49F9B0955C367DE
CREATE_OBJECT — 0x509D5878EB39E842 — https://alloc8or.re/rdr3/nativedb/?n=0x509D5878EB39E842
PLACE_OBJECT_ON_GROUND_PROPERLY — 0x58A850EAEE20FAA3 — https://alloc8or.re/rdr3/nativedb/?n=0x58A850EAEE20FAA3
SET_ENTITY_AS_MISSION_ENTITY — 0xDC19C288082E586E — https://alloc8or.re/rdr3/nativedb/?n=0xDC19C288082E586E
_SET_RANDOM_OUTFIT_VARIATION — 0x283978A15512B2FE — https://alloc8or.re/rdr3/nativedb/?n=0x283978A15512B2FE
IS_MODEL_IN_CDIMAGE — 0xD6F3B6D7716CFF8E — https://alloc8or.re/rdr3/nativedb/?n=0xD6F3B6D7716CFF8E
REQUEST_MODEL — 0xFA28FE3A6246FC30 — https://alloc8or.re/rdr3/nativedb/?n=0xFA28FE3A6246FC30
HAS_MODEL_LOADED — 0x1283B8B89DD5D1B6 — https://alloc8or.re/rdr3/nativedb/?n=0x1283B8B89DD5D1B6
SET_MODEL_AS_NO_LONGER_NEEDED — 0x4AD96EF928BD4F9A — https://alloc8or.re/rdr3/nativedb/?n=0x4AD96EF928BD4F9A
GET_GROUND_Z_FOR_3D_COORD — 0x24FA4267BB8D2431 — https://alloc8or.re/rdr3/nativedb/?n=0x24FA4267BB8D2431
NETWORK_GET_NETWORK_ID_FROM_ENTITY — 0xA11700682F3AD45C — https://alloc8or.re/rdr3/nativedb/?n=0xA11700682F3AD45C
NETWORK_DOES_NETWORK_ID_EXIST — 0x38CE16C96BD11344 — https://alloc8or.re/rdr3/nativedb/?n=0x38CE16C96BD11344
NET_TO_PED — 0xBDCD95FC216A8B3E — https://alloc8or.re/rdr3/nativedb/?n=0xBDCD95FC216A8B3E
DOES_ENTITY_EXIST — 0xD42BD6EB2E0F1677 — https://alloc8or.re/rdr3/nativedb/?n=0xD42BD6EB2E0F1677
PLAYER_ID — 0x217E9DC48139933D — https://alloc8or.re/rdr3/nativedb/?n=0x217E9DC48139933D
PLAYER_PED_ID — 0x096275889B8E0EE0 — https://alloc8or.re/rdr3/nativedb/?n=0x096275889B8E0EE0
GET_ENTITY_COORDS — 0xA86D5F069399F44D — https://alloc8or.re/rdr3/nativedb/?n=0xA86D5F069399F44D
IS_PED_DEAD_OR_DYING — 0x3317DEDB88C95038 — https://alloc8or.re/rdr3/nativedb/?n=0x3317DEDB88C95038
TASK_COMBAT_PED — 0xF166E48407BAC484 — https://alloc8or.re/rdr3/nativedb/?n=0xF166E48407BAC484
ADD_RELATIONSHIP_GROUP — 0xF372BC22FCB88606 — https://alloc8or.re/rdr3/nativedb/?n=0xF372BC22FCB88606
SET_PED_RELATIONSHIP_GROUP_HASH — 0xC80A74AC829DDD92 — https://alloc8or.re/rdr3/nativedb/?n=0xC80A74AC829DDD92
SET_RELATIONSHIP_BETWEEN_GROUPS — 0xBF25EB89375A37AD — https://alloc8or.re/rdr3/nativedb/?n=0xBF25EB89375A37AD
GIVE_WEAPON_TO_PED — 0x5E3BDDBCB83F3D84 — https://alloc8or.re/rdr3/nativedb/?n=0x5E3BDDBCB83F3D84
SET_CURRENT_PED_WEAPON — 0xADF692B254977C0C — https://alloc8or.re/rdr3/nativedb/?n=0xADF692B254977C0C
SET_BLOCKING_OF_NON_TEMPORARY_EVENTS — 0x9F8AA94D6D97DBF4 — https://alloc8or.re/rdr3/nativedb/?n=0x9F8AA94D6D97DBF4
SET_PED_ACCURACY — 0x7AEFB85C1D49DEB6 — https://alloc8or.re/rdr3/nativedb/?n=0x7AEFB85C1D49DEB6
SET_PED_KEEP_TASK — 0x971D38760FBC02EF — https://alloc8or.re/rdr3/nativedb/?n=0x971D38760FBC02EF
NETWORK_GET_ENTITY_OWNER — 0x526FEE31 — https://docs.fivem.net/natives/?_0x526FEE31 [cfx]
SET_ENTITY_ORPHAN_MODE — 0x489E9162 — https://docs.fivem.net/natives/?_0x489E9162 [cfx]
CREATE_PED — 0x0389EF71 — https://docs.fivem.net/natives/?_0x0389EF71 [cfx] — NOTE: fxserver source wraps server CreatePed/CreateObjectNoOffset in #ifndef STATE_RDR3, so likely NOT available on RedM; probe tests it and falls back to client spawn
CREATE_OBJECT_NO_OFFSET — 0x58040420 — https://docs.fivem.net/natives/?_0x58040420 [cfx] — NOTE: fxserver source wraps server CreatePed/CreateObjectNoOffset in #ifndef STATE_RDR3, so likely NOT available on RedM; probe tests it and falls back to client spawn
CREATE_VEHICLE — 0xDD75460A — https://docs.fivem.net/natives/?_0xDD75460A [cfx] (server Lua global CreateVehicle, 7 args: modelHash,x,y,z,heading,isNetwork,netMissionEntity; NOT CREATE_VEHICLE_SERVER_SETTER 0x6AE51D4B, which takes a `type` string) — NOTE: server vehicle creation is likely unavailable on RedM, so FAILED is expected; probe vehicle (cart01) is deleted immediately
DELETE_ENTITY — 0xFAA3D236 — https://docs.fivem.net/natives/?_0xFAA3D236 [cfx] (server-side use)
DOES_ENTITY_EXIST — 0x3AC90869 — https://docs.fivem.net/natives/?_0x3AC90869 [cfx]
GET_ENTITY_HEALTH — 0x8E3222B7 — https://docs.fivem.net/natives/?_0x8E3222B7 [cfx] (server-side use)
GET_ENTITY_COORDS — 0x1647F1CB — https://docs.fivem.net/natives/?_0x1647F1CB [cfx]
GET_ENTITY_HEADING — 0x972CC383 — https://docs.fivem.net/natives/?_0x972CC383 [cfx] (server-side use)
GET_PLAYER_PED — 0x6E31E993 — https://docs.fivem.net/natives/?_0x6E31E993 [cfx] (server-side use)
NETWORK_GET_ENTITY_FROM_NETWORK_ID — 0x5B912C3F — https://docs.fivem.net/natives/?_0x5B912C3F [cfx]
NETWORK_GET_NETWORK_ID_FROM_ENTITY — 0x9E35DAB6 — https://docs.fivem.net/natives/?_0x9E35DAB6 [cfx]

Not natives (guesses, unverified in-game): models `g_m_m_unibanditos_01`, `p_campfire01x`, `p_ambtentbedroll01x`, `p_tent_a_01x` (client skips any model IsModelInCdimage rejects and prints which). Relationship value 5 = hate and the TaskCombatPed flags (0, 16) are copied from GTA/RDR convention, unverified. No native found for "set ped hostile to player" beyond relationship groups + TASK_COMBAT_PED.

## GO if
Server spawns 4 outlaws + props once; no duplicates on 2nd join; camp persists across owner leave; kill state syncs.

RESULT: 