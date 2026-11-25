# spk_anim (spike S8, core animations, throwaway)

Client-local only, ox_lib only, no server code, no convar/flag. Block A0 of animations-01. **Every row below is
candidate, unproven** except `baseline`, whose name is the one `fh_inventory/client/main.lua:177` already uses.

TEST: `ensure spk_anim`, then `/spk_anim list`, then `/spk_anim 1` .. `/spk_anim 13`. Each row plays 3 s in the hash form, then 3 s in the string form (F8 and a notification say which row/name/form is playing). `/spk_anim <n> hash` or `/spk_anim <n> string` plays one form; `/spk_anim stop` clears. Fill in the RESULT lines.

## Forms
- **hash form** (scenario rows): `TaskStartScenarioInPlaceHash(ped, joaat(name), 3000, true, 0, -1.0, false)`, as rsg-core/client/progress.lua:45.
- **string form** (scenario rows): `lib.progressBar{duration=3000, anim={scenario=name}}`; ox_lib then calls `TaskStartScenarioInPlace(ped, name, 0, true)` (ox_lib progress.lua:92).
- **dict rows** (eat, drink, baseline, gather_alt, craft_alt): hash form = `RequestAnimDict` + `TaskPlayAnim` + `RemoveAnimDict`; string form = `lib.progressBar{anim={dict=, clip=}}`.
- Re-running a row mid-play cancels the old run (generation counter); dicts are released with `RemoveAnimDict`.

## Rows
| n | row | kind | name | source |
|---|---|---|---|---|
| 1 | skin | scenario | `WORLD_HUMAN_CROUCH_INSPECT` | plan spec; well-known RDR3 name, candidate, unproven |
| 2 | gather | scenario | `WORLD_HUMAN_CROUCH_INSPECT` | plan spec, candidate, unproven |
| 3 | eat | dict | `mech_inventory@eating@multi_bite` / `quick_left_hand` | well-known RDR3 name, candidate, unproven |
| 4 | drink | dict | `mech_inventory@drinking@multi_sip` / `quick_left_hand` | well-known RDR3 name, candidate, unproven |
| 5 | craft | scenario | `WORLD_HUMAN_HAMMER_TABLE` | plan spec, candidate, unproven |
| 6 | cook | scenario | `WORLD_HUMAN_STIR_POT` | plan spec, candidate, unproven |
| 7 | chest_open | scenario | `WORLD_HUMAN_CROUCH_INSPECT` | stand-in crouch, candidate, unproven |
| 8 | trough | scenario | `WORLD_HUMAN_BUCKET_POUR_LOW` | well-known RDR3 name, candidate, unproven |
| 9 | plant | scenario | `WORLD_HUMAN_FARMER_WEEDING` | plan spec, candidate, unproven |
| 10 | refill | scenario | `WORLD_HUMAN_WASH_FACE_BUCKET_GROUND` | well-known RDR3 name, candidate, unproven |
| 11 | baseline | dict | `mech_inventory@item@fallbacks@tonic_potent@offhand` / `use_quick` | fh_inventory/client/main.lua:177 (known working) |
| 12 | gather_alt | dict | `amb_work@world_human_pickup@male_a@base` / `base` | guess, candidate, unproven |
| 13 | craft_alt | dict | `amb_work@world_human_hammer@table@male_a@base` / `base` | guess, candidate, unproven |

Repo grep (server/resources) found only these scenario names in use: the `WORLD_HUMAN_*` poses in rsg-character/client/charselect.lua (none are in the rows above) and the `scenario` handling in rsg-core and ox_lib progress. The only dict/clip pair in repo use is the baseline (plus a face dict in rsg-character/client/creator.lua:886 that is not relevant). Every other name comes from well-known RDR3 lists, not from repo evidence.

## Natives
TASK_PLAY_ANIM — 0xEA47FE3719165B94 (called by name; repo use fh_inventory/client/main.lua:175)
CLEAR_PED_TASKS — 0xE1EF3C1216AFF2CD (called by name; rsg-core/client/progress.lua:58)
TaskStartScenarioInPlaceHash, TaskStartScenarioInPlace, RequestAnimDict, HasAnimDictLoaded, RemoveAnimDict, GET_HASH_KEY (`joaat`, 0xFD340785ADF8CFB7) — called by name; fh_core/docs/natives.md lists the anim-dict ones as "not looked up" and does not list the scenario natives, so their hashes are NOT cross-checked here (not guessed).
All via natives the repo already calls by name (rsg-core/client/progress.lua, fh_inventory/client/main.lua).

## GO if
You can say, per row, whether the hash form, the string form, or both play something that looks right.

## RESULT template (one line per row)
`row | name | hash Y/N | string Y/N | looks right Y/N | note`

RESULT:
