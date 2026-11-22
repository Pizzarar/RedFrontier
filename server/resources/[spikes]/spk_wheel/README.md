TEST: `ensure spk_wheel`, hop on a wagon (draft vehicle; no wagon? `/spk_wheel wagon` with spk_wheel ensured), run `/spk_wheel` and drive ~20s (does one wheel visibly break and the wagon slow?), then `/spk_wheel fix` (does it restore?); if nothing breaks try `/spk_wheel 1`..`3` and `/spk_wheel alt`.

## Natives
_BREAK_OFF_DRAFT_WHEEL — 0xC372B6A88F6E4AD8 — https://alloc8or.re/rdr3/nativedb/?n=0xC372B6A88F6E4AD8
_BREAK_OFF_VEHICLE_WHEEL — 0xD4F5EFB55769D272 — https://alloc8or.re/rdr3/nativedb/?n=0xD4F5EFB55769D272
_IS_VEHICLE_WHEEL_DESTROYED — 0xCB2CA620C48BC875 — https://alloc8or.re/rdr3/nativedb/?n=0xCB2CA620C48BC875
_ARE_ANY_VEHICLE_WHEELS_DESTROYED — 0x18714953CCED17D3 — https://alloc8or.re/rdr3/nativedb/?n=0x18714953CCED17D3
SET_VEHICLE_WHEELS_CAN_BREAK — 0x839137C40275FB77 — https://alloc8or.re/rdr3/nativedb/?n=0x839137C40275FB77
SET_VEHICLE_FIXED — 0x79811282A9D1AE56 — https://alloc8or.re/rdr3/nativedb/?n=0x79811282A9D1AE56
MODIFY_VEHICLE_TOP_SPEED — 0x35AD938C74CACD6A — https://alloc8or.re/rdr3/nativedb/?n=0x35AD938C74CACD6A
IS_DRAFT_VEHICLE — 0xEA44E97849E9F3DD — https://alloc8or.re/rdr3/nativedb/?n=0xEA44E97849E9F3DD
GET_ENTITY_SPEED — 0xFB6BA510A533DF81 — https://alloc8or.re/rdr3/nativedb/?n=0xFB6BA510A533DF81
GET_VEHICLE_PED_IS_IN — 0x9A9112A0FE9A4713 — https://alloc8or.re/rdr3/nativedb/?n=0x9A9112A0FE9A4713
PLAYER_PED_ID — 0x096275889B8E0EE0 — https://alloc8or.re/rdr3/nativedb/?n=0x096275889B8E0EE0
DOES_ENTITY_EXIST — 0xD42BD6EB2E0F1677 — https://alloc8or.re/rdr3/nativedb/?n=0xD42BD6EB2E0F1677
CREATE_VEHICLE — 0xAF35D0D2583051B0 — https://alloc8or.re/rdr3/nativedb/?n=0xAF35D0D2583051B0
SET_PED_INTO_VEHICLE — 0xF75B0D629E1C063D — https://alloc8or.re/rdr3/nativedb/?n=0xF75B0D629E1C063D
REQUEST_MODEL — 0xFA28FE3A6246FC30 — https://alloc8or.re/rdr3/nativedb/?n=0xFA28FE3A6246FC30
HAS_MODEL_LOADED — 0x1283B8B89DD5D1B6 — https://alloc8or.re/rdr3/nativedb/?n=0x1283B8B89DD5D1B6
IS_MODEL_IN_CDIMAGE — 0xD6F3B6D7716CFF8E — https://alloc8or.re/rdr3/nativedb/?n=0xD6F3B6D7716CFF8E
SET_MODEL_AS_NO_LONGER_NEEDED — 0x4AD96EF928BD4F9A — https://alloc8or.re/rdr3/nativedb/?n=0x4AD96EF928BD4F9A
GET_OFFSET_FROM_ENTITY_IN_WORLD_COORDS — 0x1899F328B0E12848 — https://alloc8or.re/rdr3/nativedb/?n=0x1899F328B0E12848
GET_ENTITY_HEADING — 0xC230DD956E2F5507 — https://alloc8or.re/rdr3/nativedb/?n=0xC230DD956E2F5507

Notes: `/spk_wheel wagon` spawns model `cart01` (name from femga/rdr3_discoveries vehicles_list.lua) 5m to your right, seat -1 = driver (seat index convention unverified in DB). no "repair one wheel" native exists in the DB; fix = SET_VEHICLE_FIXED and we print whether wheels still report destroyed afterwards (a broken-off wheel may not come back: that is a valid finding). No dedicated "slow the wagon" native for player-driven wagons was verified; MODIFY_VEHICLE_TOP_SPEED(-50) is a guess at GTA5 semantics (percent), the probe prints speed so you can judge. Wheel index to physical wheel mapping is unknown (probe prints state of indexes 0..7).

## GO if
One wheel visibly breaks/slows wagon; fix restores it.

RESULT: 
