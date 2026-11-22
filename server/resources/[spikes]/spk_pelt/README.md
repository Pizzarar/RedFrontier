TEST: `ensure spk_pelt`, run `/spk_pelt` (2 deer spawn ~20m ahead), shoot deer A in the head and deer B in the body, then skin both and read the F8 console / notifications (look at `quality=` and `lastBone` for each).

## Natives
GET_PED_LAST_DAMAGE_BONE — 0xD75960F6BD9EA49C — https://alloc8or.re/rdr3/nativedb/?n=0xD75960F6BD9EA49C
_GET_PED_QUALITY — 0x7BCC6087D130312A — https://alloc8or.re/rdr3/nativedb/?n=0x7BCC6087D130312A
_GET_PED_DAMAGE_CLEANLINESS — 0x88EFFED5FE8B0B4A — https://alloc8or.re/rdr3/nativedb/?n=0x88EFFED5FE8B0B4A
GET_PED_CAUSE_OF_DEATH — 0x16FFE42AB2D2DC59 — https://alloc8or.re/rdr3/nativedb/?n=0x16FFE42AB2D2DC59
GET_PED_SOURCE_OF_DEATH — 0x93C8B64DEB84728C — https://alloc8or.re/rdr3/nativedb/?n=0x93C8B64DEB84728C
_IS_ANIMAL_SKINNED — 0x88A5564B19C15391 — https://alloc8or.re/rdr3/nativedb/?n=0x88A5564B19C15391
_IS_ENTITY_FULLY_LOOTED — 0x8DE41E9902E85756 — https://alloc8or.re/rdr3/nativedb/?n=0x8DE41E9902E85756
_GET_IS_CARRIABLE_PELT — 0x255B6DB4E3AD3C3E — https://alloc8or.re/rdr3/nativedb/?n=0x255B6DB4E3AD3C3E
_GET_CARCASS_FROM_PELT — 0x2A77EF9BEC8518F4 — https://alloc8or.re/rdr3/nativedb/?n=0x2A77EF9BEC8518F4
IS_ENTITY_DEAD — 0x7D5B1F88E7504BBA — https://alloc8or.re/rdr3/nativedb/?n=0x7D5B1F88E7504BBA
GET_ENTITY_HEALTH — 0x82368787EA73C0F7 — https://alloc8or.re/rdr3/nativedb/?n=0x82368787EA73C0F7
CREATE_PED — 0xD49F9B0955C367DE — https://alloc8or.re/rdr3/nativedb/?n=0xD49F9B0955C367DE
_SET_RANDOM_OUTFIT_VARIATION — 0x283978A15512B2FE — https://alloc8or.re/rdr3/nativedb/?n=0x283978A15512B2FE
PLACE_ENTITY_ON_GROUND_PROPERLY — 0x9587913B9E772D29 — https://alloc8or.re/rdr3/nativedb/?n=0x9587913B9E772D29
REQUEST_MODEL — 0xFA28FE3A6246FC30 — https://alloc8or.re/rdr3/nativedb/?n=0xFA28FE3A6246FC30
HAS_MODEL_LOADED — 0x1283B8B89DD5D1B6 — https://alloc8or.re/rdr3/nativedb/?n=0x1283B8B89DD5D1B6
GET_ENTITY_COORDS — 0xA86D5F069399F44D — https://alloc8or.re/rdr3/nativedb/?n=0xA86D5F069399F44D
GET_ENTITY_FORWARD_VECTOR — 0x2412D9C05BB09B97 — https://alloc8or.re/rdr3/nativedb/?n=0x2412D9C05BB09B97
GET_ENTITY_HEADING — 0xC230DD956E2F5507 — https://alloc8or.re/rdr3/nativedb/?n=0xC230DD956E2F5507
DOES_ENTITY_EXIST — 0xD42BD6EB2E0F1677 — https://alloc8or.re/rdr3/nativedb/?n=0xD42BD6EB2E0F1677
PLAYER_PED_ID — 0x096275889B8E0EE0 — https://alloc8or.re/rdr3/nativedb/?n=0x096275889B8E0EE0
GetHashKey (joaat of `a_c_deer_01`) — [cfx] — https://docs.fivem.net/natives/?_0xD24D37CC275948CC

Notes: DB doc for _GET_PED_QUALITY says "Ped Quality used to calculate Skinning Quality" (enum LOW/MEDIUM/HIGH); _GET_PED_DAMAGE_CLEANLINESS enum POOR/GOOD/PERFECT. Both are read on death and after skin. The skinned pelt quality itself is an inventory item (no inventory calls in spikes), so it is not read. The probe also tracks the last damage bone while alive (the game may clear it on death). If quality never differs, NO-GO: roll quality from last bone ourselves. Bone ids are printed raw (no bone-name native verified). Unverified guess: `a_c_deer_01` is the model name.

## GO if
Quality readable from native carcass/kill data, differs by shot.

RESULT: 
