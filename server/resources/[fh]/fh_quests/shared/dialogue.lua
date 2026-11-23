-- Pure: build the fh_ui `dialogue` screen data for a family giver (plan ui-giver-dialogue). No natives.
-- Specced in spec/quests_dialogue_spec.lua.
local M = {}

M.PROMPT = 'Will you take the job?'
M.ACCEPT = 'I will'
M.DECLINE = 'Not yet'
M.NOTHING = 'Nothing more to say right now.'

---build(giver, dialogue) -> { speaker, pages, offer? }
---`dialogue` is the talk export's third result: an array of { lines = {...} } for advanced steps, plus `.offers`
---(quest ids this npc can start). Talk lines come first; giver.intro follows only when an offer for the giver's own
---line is present. No pages and no offer -> one fallback page.
function M.build(giver, dialogue)
    local pages = {}
    for _, d in ipairs(type(dialogue) == 'table' and dialogue or {}) do
        for _, line in ipairs(type(d) == 'table' and d.lines or {}) do
            if type(line) == 'string' then pages[#pages + 1] = line end
        end
    end
    local offer = nil
    local offers = type(dialogue) == 'table' and dialogue.offers or nil
    for _, qid in ipairs(type(offers) == 'table' and offers or {}) do
        if qid == giver.quest then
            for _, line in ipairs(giver.intro or {}) do pages[#pages + 1] = line end
            offer = { quest_id = qid, prompt = M.PROMPT, accept = M.ACCEPT, decline = M.DECLINE }
            break
        end
    end
    if #pages == 0 and not offer then pages[1] = M.NOTHING end
    return { speaker = giver.label, pages = pages, offer = offer }
end

if GetCurrentResourceName then
    FhQuestsDialogue = M
else
    return M
end
