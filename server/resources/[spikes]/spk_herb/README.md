TEST: `ensure spk_herb`, then `/spk_herb props` (6 candidate herb models spawn in a line 2m apart ~4m in front of you — read the `[n] <model>` lines and pick the model+index that looks like a herb patch), `/spk_herb blip` (a blip cycles 4 candidate plant sprites every 3s — note which sprite looks right), `/spk_herb clear` to clean up. Finish by naming the model and sprite that looked right.

## Natives
BLIP_ADD_FOR_COORDS — 0x554D9D53F696D002 — https://alloc8or.re/rdr3/nativedb/?n=0x554D9D53F696D002  (first arg is a blip STYLE hash, not a sprite; we pass `1664425300` = BLIP_STYLE_PICKUP_WEAPON, the base style rsg-character/fh_ui use)
_SET_BLIP_NAME — 0x9CB1A1623062F402 — https://alloc8or.re/rdr3/nativedb/?n=0x9CB1A1623062F402  (plain string, not VarString)
SET_BLIP_SPRITE — 0x74F74D3207ED525C — https://alloc8or.re/rdr3/nativedb/?n=0x74F74D3207ED525C  (called by name: `SetBlipSprite(blip, joaat(sprite), 1)`)
SET_BLIP_SCALE — 0xD38744167B2FA257 — https://alloc8or.re/rdr3/nativedb/?n=0xD38744167B2FA257  (called by name)
REMOVE_BLIP — 0xF2C3C9DA47AAA54A — https://alloc8or.re/rdr3/nativedb/?n=0xF2C3C9DA47AAA54A  (called by name)
IS_MODEL_VALID — 0x392C8D8E07B70EFC — https://alloc8or.re/rdr3/nativedb/?n=0x392C8D8E07B70EFC  (called by name)
REQUEST_MODEL — 0xFA28FE3A6246FC30 — https://alloc8or.re/rdr3/nativedb/?n=0xFA28FE3A6246FC30
HAS_MODEL_LOADED — 0x1283B8B89DD5D1B6 — https://alloc8or.re/rdr3/nativedb/?n=0x1283B8B89DD5D1B6
SET_MODEL_AS_NO_LONGER_NEEDED — 0x4AD96EF928BD4F9A — https://alloc8or.re/rdr3/nativedb/?n=0x4AD96EF928BD4F9A
CREATE_OBJECT (isNetwork=false) — 0x509D5878EB39E842 — https://alloc8or.re/rdr3/nativedb/?n=0x509D5878EB39E842  (called by name, 7 args: model, x, y, z, false, false, false)
PLACE_OBJECT_ON_GROUND_PROPERLY — 0x58A850EAEE20FAA3 — https://alloc8or.re/rdr3/nativedb/?n=0x58A850EAEE20FAA3  (called by name)
FREEZE_ENTITY_POSITION — 0x7D9EFB7AD6B19754 — https://alloc8or.re/rdr3/nativedb/?n=0x7D9EFB7AD6B19754  (called by name)
DOES_ENTITY_EXIST — 0xD42BD6EB2E0F1677 — https://alloc8or.re/rdr3/nativedb/?n=0xD42BD6EB2E0F1677
DELETE_ENTITY — 0x4CD38C78BD19A497 — https://alloc8or.re/rdr3/nativedb/?n=0x4CD38C78BD19A497  (client)
PLAYER_PED_ID — 0x096275889B8E0EE0 — https://alloc8or.re/rdr3/nativedb/?n=0x096275889B8E0EE0
GET_ENTITY_COORDS — 0xA86D5F069399F44D — https://alloc8or.re/rdr3/nativedb/?n=0xA86D5F069399F44D
GET_ENTITY_FORWARD_VECTOR — 0x2412D9C05BB09B97 — https://alloc8or.re/rdr3/nativedb/?n=0x2412D9C05BB09B97
GET_HASH_KEY (client Lua global `joaat`) — 0xFD340785ADF8CFB7 — https://alloc8or.re/rdr3/nativedb/?n=0xFD340785ADF8CFB7

## Candidate herb prop models (candidate, unproven)
| index | model | joaat (signed) | note |
|---|---|---|---|
| 1 | `yarrow01_p` | -1970486567 | Yarrow |
| 2 | `ginseng_p` | -918246837 | Ginseng (recipe herb) |
| 3 | `wildmint_p` | -58637410 | Wild Mint (recipe herb) |
| 4 | `oregano_p` | -803247065 | Oregano (recipe herb) |
| 5 | `redsage_p` | -822499418 | Red Sage (recipe herb) |
| 6 | `thyme_p` | -819966349 | Creeping Thyme |

## Candidate blip sprites (candidate, unproven)
| name | joaat (signed) |
|---|---|
| `blip_plant` | -675651933 |
| `blip_grub` | 935247438 |
| `blip_supplies_food` | -1852063472 |
| `blip_donate_food` | -1236018085 |

Notes: model names are the RDR2 herb PICKUP models from femga/rdr3_discoveries `objects/object_list.lua`
(s_lev_des.rpf); sprite names from femga/rdr3_discoveries `textures/blips`. All are verified in the lists only,
**not** run in game — a model that RedM does not know fails `IsModelValid` and prints `FAIL`; one that does not
stream in 5s prints `FAIL: load timed out`. Each prop is created local (non-networked), placed with
PlaceObjectOnGroundProperly and frozen, then the model is released (SetModelAsNoLongerNeeded). The blip cycles
the 4 sprites forever until `/spk_herb clear` (or resource stop), printing which one is showing. Only `blip_plant`
is literally a plant icon; the other three are food/gathering icons included so the tester can compare which reads
best as "a herb to pick". No convar/flag gates any of this (plan Decided).

## GO if
You can name one herb model (index) and one blip sprite that read as the herb-patch cue.

RESULT:
