TEST: `ensure spk_wear`, draw a gun and run `/spk_wear get`, fire 50 rounds then `/spk_wear get` again (does degradation/dirt/soot rise?), then `/spk_wear set 0.8`, holster/redraw and `/spk_wear get` (did it stick, and does the gun look/jam worse?).

## Natives
GET_CURRENT_PED_WEAPON — 0x3A87E44BB9A01D54 — https://alloc8or.re/rdr3/nativedb/?n=0x3A87E44BB9A01D54
GET_CURRENT_PED_WEAPON_ENTITY_INDEX — 0x3B390A939AF0B5FC — https://alloc8or.re/rdr3/nativedb/?n=0x3B390A939AF0B5FC
GET_WEAPON_DEGRADATION — 0x0D78E1097F89E637 — https://alloc8or.re/rdr3/nativedb/?n=0x0D78E1097F89E637
GET_WEAPON_PERMANENT_DEGRADATION — 0xD56E5F336C675EFA — https://alloc8or.re/rdr3/nativedb/?n=0xD56E5F336C675EFA
_GET_WEAPON_DAMAGE — 0x904103D5D2333977 — https://alloc8or.re/rdr3/nativedb/?n=0x904103D5D2333977
_GET_WEAPON_DIRT — 0x810E8AE9AFEA7E54 — https://alloc8or.re/rdr3/nativedb/?n=0x810E8AE9AFEA7E54
_GET_WEAPON_SOOT — 0x4BF66F8878F67663 — https://alloc8or.re/rdr3/nativedb/?n=0x4BF66F8878F67663
_SET_WEAPON_DEGRADATION — 0xA7A57E89E965D839 — https://alloc8or.re/rdr3/nativedb/?n=0xA7A57E89E965D839
DOES_ENTITY_EXIST — 0xD42BD6EB2E0F1677 — https://alloc8or.re/rdr3/nativedb/?n=0xD42BD6EB2E0F1677
PLAYER_PED_ID — 0x096275889B8E0EE0 — https://alloc8or.re/rdr3/nativedb/?n=0x096275889B8E0EE0

Notes: weapon object comes from GET_CURRENT_PED_WEAPON_ENTITY_INDEX(ped, 0) (attachPoint 0 = right hand is a guess). Setters for damage/dirt/soot also exist (_SET_WEAPON_DAMAGE 0xE22060121602493B, _SET_WEAPON_DIRT 0x812CE61DEBCAB948, _SET_WEAPON_SOOT 0xA9EF4AD10BDDDB57) but are not exercised here. Also seen, unused: _SET_WEAPON_DEGRADATION_MODIFIER 0x11A7FF918EF6BC66 (player-wide wear rate). The weapon object is client-side and degradation lives on the game's weapon entity, so persistence across holster/relog is part of what this tests (inventory/DB persistence is out of scope).

## GO if
Per-weapon degradation readable and settable.

RESULT: 
