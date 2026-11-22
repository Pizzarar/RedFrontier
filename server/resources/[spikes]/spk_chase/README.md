TEST: `ensure spk_chase`, get in a wagon on a road, run `/spk_chase`, drive 60s (some off-road); watch notify/F8 for per-5s lines `R1 distm mounted/UNMOUNTED goto|combat` plus STALL/BUNCH flags; `/spk_chase clear` afterwards.

## Natives

CREATE_PED — 0xD49F9B0955C367DE — https://alloc8or.re/rdr3/nativedb/?n=0xD49F9B0955C367DE
SET_PED_ONTO_MOUNT — 0x028F76B6E78246EB — https://alloc8or.re/rdr3/nativedb/?n=0x028F76B6E78246EB
IS_PED_ON_MOUNT — 0x460BC76A0E10655E — https://alloc8or.re/rdr3/nativedb/?n=0x460BC76A0E10655E
TASK_MOUNT_ANIMAL — 0x92DB0739813C5186 — https://alloc8or.re/rdr3/nativedb/?n=0x92DB0739813C5186
TASK_GO_TO_ENTITY — 0x6A071245EB0D1882 — https://alloc8or.re/rdr3/nativedb/?n=0x6A071245EB0D1882
TASK_COMBAT_PED — 0xF166E48407BAC484 — https://alloc8or.re/rdr3/nativedb/?n=0xF166E48407BAC484
GET_VEHICLE_PED_IS_IN — 0x9A9112A0FE9A4713 — https://alloc8or.re/rdr3/nativedb/?n=0x9A9112A0FE9A4713
IS_PED_IN_ANY_VEHICLE — 0x997ABD671D25CA0B — https://alloc8or.re/rdr3/nativedb/?n=0x997ABD671D25CA0B
PLAYER_PED_ID — 0x096275889B8E0EE0 — https://alloc8or.re/rdr3/nativedb/?n=0x096275889B8E0EE0
GET_OFFSET_FROM_ENTITY_IN_WORLD_COORDS — 0x1899F328B0E12848 — https://alloc8or.re/rdr3/nativedb/?n=0x1899F328B0E12848
GET_ENTITY_COORDS — 0xA86D5F069399F44D — https://alloc8or.re/rdr3/nativedb/?n=0xA86D5F069399F44D
GET_ENTITY_HEADING — 0xC230DD956E2F5507 — https://alloc8or.re/rdr3/nativedb/?n=0xC230DD956E2F5507
GET_ENTITY_SPEED — 0xFB6BA510A533DF81 — https://alloc8or.re/rdr3/nativedb/?n=0xFB6BA510A533DF81
GET_ENTITY_MODEL — 0xDA76A9F39210D365 — https://alloc8or.re/rdr3/nativedb/?n=0xDA76A9F39210D365
DOES_ENTITY_EXIST — 0xD42BD6EB2E0F1677 — https://alloc8or.re/rdr3/nativedb/?n=0xD42BD6EB2E0F1677
IS_PED_DEAD_OR_DYING — 0x3317DEDB88C95038 — https://alloc8or.re/rdr3/nativedb/?n=0x3317DEDB88C95038
SET_ENTITY_AS_MISSION_ENTITY — 0xDC19C288082E586E — https://alloc8or.re/rdr3/nativedb/?n=0xDC19C288082E586E
DELETE_ENTITY — 0x4CD38C78BD19A497 — https://alloc8or.re/rdr3/nativedb/?n=0x4CD38C78BD19A497
_SET_RANDOM_OUTFIT_VARIATION — 0x283978A15512B2FE — https://alloc8or.re/rdr3/nativedb/?n=0x283978A15512B2FE
GET_GROUND_Z_FOR_3D_COORD — 0x24FA4267BB8D2431 — https://alloc8or.re/rdr3/nativedb/?n=0x24FA4267BB8D2431
IS_MODEL_IN_CDIMAGE — 0xD6F3B6D7716CFF8E — https://alloc8or.re/rdr3/nativedb/?n=0xD6F3B6D7716CFF8E
REQUEST_MODEL — 0xFA28FE3A6246FC30 — https://alloc8or.re/rdr3/nativedb/?n=0xFA28FE3A6246FC30
HAS_MODEL_LOADED — 0x1283B8B89DD5D1B6 — https://alloc8or.re/rdr3/nativedb/?n=0x1283B8B89DD5D1B6
SET_MODEL_AS_NO_LONGER_NEEDED — 0x4AD96EF928BD4F9A — https://alloc8or.re/rdr3/nativedb/?n=0x4AD96EF928BD4F9A
ADD_RELATIONSHIP_GROUP — 0xF372BC22FCB88606 — https://alloc8or.re/rdr3/nativedb/?n=0xF372BC22FCB88606
SET_PED_RELATIONSHIP_GROUP_HASH — 0xC80A74AC829DDD92 — https://alloc8or.re/rdr3/nativedb/?n=0xC80A74AC829DDD92
SET_RELATIONSHIP_BETWEEN_GROUPS — 0xBF25EB89375A37AD — https://alloc8or.re/rdr3/nativedb/?n=0xBF25EB89375A37AD
GIVE_WEAPON_TO_PED — 0x5E3BDDBCB83F3D84 — https://alloc8or.re/rdr3/nativedb/?n=0x5E3BDDBCB83F3D84
SET_CURRENT_PED_WEAPON — 0xADF692B254977C0C — https://alloc8or.re/rdr3/nativedb/?n=0xADF692B254977C0C
SET_BLOCKING_OF_NON_TEMPORARY_EVENTS — 0x9F8AA94D6D97DBF4 — https://alloc8or.re/rdr3/nativedb/?n=0x9F8AA94D6D97DBF4
SET_PED_ACCURACY — 0x7AEFB85C1D49DEB6 — https://alloc8or.re/rdr3/nativedb/?n=0x7AEFB85C1D49DEB6
SET_PED_KEEP_TASK — 0x971D38760FBC02EF — https://alloc8or.re/rdr3/nativedb/?n=0x971D38760FBC02EF

Spawn is CLIENT-SIDE (caller's client creates networked riders + horses) for this probe; server only relays the command. No native found to confirm "vehicle is a wagon": the probe logs the model hash instead. Unverified guesses (not natives): models `g_m_m_unibanditos_01`, `a_c_horse_morgan_bay`, weapon `WEAPON_REPEATER_CARBINE`, relationship 5 = hate, TASK_GO_TO_ENTITY speed 3.0 = gallop, TASK_COMBAT_PED args (0, 16). Whether a mounted TASK_COMBAT_PED / TASK_GO_TO_ENTITY actually drives the horse is exactly what this spike tests; there is no separate verified 'ride to' native used.

## GO if
3 AI riders keep pace and shoot for 60s on road + some off-road, no stalls/bunching (summary line shows ~0 stall/bunch flags).

RESULT: 