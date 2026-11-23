# Plan · @ui giver dialogue screen (idea-722)

Lead: UI2 (rn-8c7a9bce2671). Cross-lane: @quests lead Que2 (rn-97a2281b22df). Follows docs/plans/ui-wiring-fence-quests.md (complete; idea-715 60ec4aa).

## Ask (verbatim, UI2 lead)
"idea-722: replace ox_lib text dialogue in fh_quests client/givers.lua (7 lib. calls) + server/families.lua (2) with an fh_ui dialogue screen. That's a new screen + cross-lane quests files, so I'd like a short plan from you (... screen data contract, actions, which lib.* calls map where, OWNER-TESTS steps, parallel table, quests-lead coordination)."

## Decided
- Primitives checked: fh_ui screens table (fh_ui/shared/relay.lua:7), relay `fh:ui:action` -> server-local `fh:<owner>:ui_<action>`, the `notice`/`notice_kind` convention (jobs/journal, fh_ui README:95-98), `fh_ui_demo` fixtures, fh_quests `server/ui.lua` open/handler pattern (`fh:quests:ui_open`, `ui_journal_open`), `FhQuestsUiText` for code->text, `FhQuestsGivers` (`get`, `byQuest`, `within`, `intro`). No new vs command, flag, core API or quests export: uses existing `talk` and `start` exports.
- Server builds the whole conversation; the screen only pages through it. Paging is client-side (no round trip per line).
- Proximity stays enforced server-side in both handlers (same `near(src, g)` as families.lua:46), per the families.lua:40-45 note.
- Screen owner `quests` (relay -> `fh:quests:ui_start`). Interactive, not passive.
- U3 review lesson applies: no autofocus, Enter does nothing; mutating button (`start`) only by click.

## Screen contract: `dialogue` (owner `quests`)
`open/update` data:
```
{ speaker,                       -- giver label (g.label)
  pages = { "line", ... },        -- talk lines for advanced steps, then g.intro if an offer follows; may be empty
  offer?  = { quest_id, prompt = "Will you take the job?", accept = "I will", decline = "Not yet" },
  notice?, notice_kind? }         -- ok|error, same as jobs/journal
```
- Shows one page at a time with **Next**; after the last page shows the offer (if any) with accept/decline buttons, else a **Goodbye** button.
- `pages` empty and no `offer` -> server sends `pages = { "Nothing more to say right now." }`.
- Actions: `start` `{ quest_id }` (relays `fh:quests:ui_start`; the lane answers with a `notice` update and drops `offer`), `close` `{}` (decline/Goodbye/Esc).
- Lists normalized with the dom.js Array helper (empty Lua `{}`).

## Call mapping (9 lib.* calls)
| Where | Today | Becomes |
|---|---|---|
| givers.lua:10 | `lib.alertDialog` per talk line (`say`) | `pages[]`, Next button |
| givers.lua:15 | `lib.callback.await('fh:quests:giver:talk')` | target `onSelect` -> `TriggerServerEvent('fh:quests:ui_talk', g.npc)` |
| givers.lua:17 | `lib.notify` "Not now (err)" | screen opens with `notice` (`FhQuestsUiText`), `notice_kind=error`, no pages |
| givers.lua:27 | `lib.alertDialog` "Will you take the job?" | `offer` block |
| givers.lua:30 | `lib.callback.await('fh:quests:giver:start')` | action `start` -> `fh:quests:ui_start` |
| givers.lua:31 | `lib.notify` started / error | `fh:ui:update` `{ notice, notice_kind, offer = false }` |
| givers.lua:38 | `lib.notify` "Nothing more to say" | single fallback page |
| families.lua:52 | `lib.callback.register('fh:quests:giver:talk')` | `RegisterNetEvent('fh:quests:ui_talk')` in server/ui.lua: validate npc (`G.get`), `near`, `talk`, build data, `fh:ui:open dialogue` |
| families.lua:59 | `lib.callback.register('fh:quests:giver:start')` | `AddEventHandler('fh:quests:ui_start')` in server/ui.lua: `G.byQuest`, `near`, `start`, notice update |

givers.lua keeps the rsg-target zones and the ped `fh:spawn:adopted` setup; `say`/`talkTo` go. families.lua keeps spawning + `near` (move `near` into ui.lua or share it; lead's call).

## Blocks
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| D1 fh_ui `dialogue` screen | fh_ui html/screens/dialogue.js, html/index.html script tag, shared/relay.lua screens (+ `dialogue = 'quests'`), README schema, shared/fixtures.lua + `fh_ui_demo dialogue`, specs | any other new fh_ui screen (none in flight) | Root cause |
| D2 fh_quests wiring | fh_quests server/ui.lua (`ui_talk`, `ui_start`), FhQuestsUiText codes (fh_bad_npc, fh_too_far, fh_unknown_quest, start errors), client/givers.lua (onSelect -> server event; delete say/talkTo), server/families.lua (delete 2 callbacks + WORKAROUND header), specs for the data builder (pure Lua) | @quests in-flight edits to these files: confirm with Que2 before dispatch | Root cause |
| D3 test card | OWNER-TESTS.md `## UI` (append dialogue steps), fh_quests README (drop "fallback dialogue" lines, point at dialogue screen) | other lanes' OWNER-TESTS sections (append only) | Root cause |

Order: D1 ∥ D2 (contract fixed above) -> D3. Done-check per block: Gemini review PASS, rebase on main, `~/.venvs/rf/bin/python tools/run-specs.py` green, merge in the merge slot, hash logged. Then `vs log decision "ui idea-722 merged <hash>"`.

## OWNER-TESTS steps (D3, `## UI`)
1. `/fh_ui_demo dialogue`: speaker + first page; Next pages through; offer shows accept/decline; Enter does nothing; Esc closes, controls return.
2. Walk to a family giver, "Talk to <name>": dialogue screen (no ox_lib popups) with the intro and offer.
3. "I will": "Quest started." notice, offer gone; quest appears in `/journal`.
4. Talk again: talk-step lines show if a step advanced, else "Nothing more to say right now."
5. Start the target, walk >3 m away, click "I will" -> "too far" error notice, quest not started.
6. grep: no `lib.alertDialog`/`giver:talk`/`giver:start` left in fh_quests.

## Quests-lead coordination
- UI2 pings Que2 with this path before dispatching D2; Que2 confirms no in-flight edits to givers.lua/families.lua/ui.lua (else D2 rebases after).
- D2 commit message credits the shared files; Que2 gets the merge hash.

## Out of scope
- Branching dialogue / choices beyond accept/decline; voice/portraits; non-family NPC dialogue; @guide tutorial prompts.
