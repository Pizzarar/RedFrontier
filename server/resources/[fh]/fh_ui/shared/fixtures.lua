-- Fixture data + pure helpers for the U3 screens (heat, insurance, jobs, journal, dialogue, station, fence). No natives, specced
-- under busted (spec/ui_fixtures_spec.lua). The producing lanes do not exist yet, so `fh_ui_demo <screen>` opens these.
local M = {}

M.fixtures = {
    heat = {
        factions = {
            { id = 'lawmen',   label = 'Lawmen',        level = 62, tier = 'wanted' },
            { id = 'bandits',  label = 'Hollis Gang',   level = 18, tier = 'watched' },
            { id = 'railroad', label = 'Railroad Guard', level = 0,  tier = 'clear' },
        },
        lay_low = { active = true, seconds_left = 340 },
    },
    insurance = {
        title = 'Tracker Insurance',
        fee = 75,
        delay_minutes = 20,
        target_chest = 'Homestead stash chest',
        note = 'Pay now; if you die your pack is delivered to the chest after the delay.',
    },
    jobs = {
        region_id = 'heartlands',
        expires_at = 4102444800,
        offers = {
            { id = 'heartlands:1:hunt_request:wolf_2', job_type = 'hunt_request', title = 'Two-star wolf pelt',
              text = 'Sell a 2-star or better wolf pelt.', rewards = { money = 12 }, accepted = false },
            { id = 'heartlands:1:bounty:hollis', job_type = 'bounty', title = 'Hollis Gang lookout',
              text = 'Take down the lookout.', rewards = { money = 150, rep = { region_id = 'heartlands', delta = 5 } },
              accepted = true },
            { id = 'heartlands:1:bounty:ridge_boss', job_type = 'bounty', title = 'Ridge Gang boss',
              text = 'A seasoned hand only.', rewards = { money = 300 }, accepted = false, locked = { min_tier = 2 } },
        },
    },
    journal = {
        entries = {
            { quest_id = 'family_hale_1', kind = 'line', title = 'A Roof Over Your Head', giver = 'npc_hale',
              region_id = 'heartlands', status = 'active', step = 2, steps_total = 3, step_text = 'Sell three good pelts.',
              count = 1, need = 3, updated_at = 1795651200,
              rewards = { money = 25, rep = { region_id = 'heartlands', delta = 5 }, items = { { name = 'bread', amount = 2 } } } },
            { quest_id = 'job:heartlands:hunt_request:wolf_2', kind = 'job', title = 'Two-star wolf pelt',
              status = 'done', step = 1, steps_total = 1, step_text = 'Sell a 2-star or better wolf pelt.',
              updated_at = 1795640000, rewards = { money = 12 } },
        },
    },
    dialogue = {
        speaker = 'Martha Hale',
        pages = { 'Heard you were looking for work.', 'The roof leaks and the pelts are piling up.' },
        offer = { quest_id = 'family_hale_1', prompt = 'Will you take the job?', accept = 'I will', decline = 'Not yet' },
    },
    station = {
        title = 'Cookfire',
        options = {
            { id = 'stew', label = 'Hearty stew', inputs = { { item = 'meat', qty = 2 }, { item = 'carrot', qty = 1 } },
              outputs = { { item = 'stew', qty = 1 } }, time_seconds = 20, can_craft = true },
            { id = 'jerky', label = 'Jerky', inputs = { { item = 'meat', qty = 3 }, { item = 'salt', qty = 1 } },
              outputs = { { item = 'jerky', qty = 2 } }, time_seconds = 45, can_craft = false },
        },
    },
    fence = {
        title = 'Roving Fence',
        stock = {
            { id = 'lockpick', label = 'Lockpick', price = 12, qty = 20, category = 'common' },
            { id = 'old_map', label = 'Torn treasure map', price = 220, qty = 1, category = 'leads' },
        },
        sell = {
            { id = 'pocket_watch', label = 'Pocket watch', price = 30, qty = 2 },
            { id = 'silver_ring', label = 'Silver ring', price = 45, qty = 1 },
        },
    },
    tradepost = {
        label = 'Valentine Trade Post',
        region = 'heartlands',
        goods = {
            { item = 'trade_salt', label = 'Salt Sack', price = 6.0, shortage = 0.5, saturation = 0.0 },
            { item = 'trade_cloth', label = 'Bolt of Cloth', price = 14.0, shortage = 0.0, saturation = 0.4 },
            { item = 'trade_whiskey', label = 'Whiskey Crate', price = 40.0, shortage = 0.0, saturation = 0.0 },
        },
        supplies = {
            { item = 'lumber', label = 'Lumber', price = 3 },
            { item = 'nails', label = 'Nails', price = 2 },
        },
        max_sell = 100,
        max_buy = 100,
    },
    fieldguide = {
        entries = {
            { id = 'survival', title = 'Survival & Needs',
              lines = { 'Eat, drink and rest to keep your cores up.', 'Cold saps health; stand by a fire to warm up.', 'Sleep in a bedroll or homestead cot to recover.' },
              controls = { 'E: open stash', 'Tab: open satchel', 'F: interact' },
              wiki_path = 'docs/wiki/systems/survival.md' },
            { id = 'inventory', title = 'Carrying & Stash',
              lines = { 'Your satchel holds what you carry.', 'Heavy loads slow you down and tire you faster.', 'Stash extras in a homestead chest to keep moving.' },
              controls = { 'Tab: open satchel', 'E: open stash' },
              wiki_path = 'docs/wiki/systems/fh_inventory.md' },
            { id = 'hunting', title = 'Hunting & Pelts',
              lines = { 'Clean kills keep pelts worth more.', 'Two-star or better pelts sell well.', 'Skin the animal before it cools.' },
              controls = { 'Hold R: track', 'LMB: shoot', 'E: skin' },
              wiki_path = 'docs/wiki/systems/fh_hunting.md' },
        },
    },
    trapper = {
        title = 'Trapper',
        rows = {
            { container = 'saddlebag', slot = 1, item = 'pelt_deer', label = 'Deer pelt', stars = 3, legendary = false, price = 25 },
            { container = 'saddlebag', slot = 3, item = 'pelt_fox', label = 'Fox pelt', stars = 1, legendary = false, price = 3 },
            { container = 'wagon', slot = 2, item = 'pelt_legendary_bear', label = 'Legendary bear pelt', stars = 3, legendary = true, price = 432 },
        },
    },
    tailor = {
        shop = { id = 'valentine_tailor', label = 'Valentine Tailor', region_id = 'heartlands', size = 2 },
        tier = 1,
        rows = {
            { id = 'outfit_ranch_hand', label = 'Ranch hand outfit', kind = 'outfit', sex = 'male', price = 18, min_tier = 0, owned = true },
            { id = 'outfit_town_dandy', label = 'Town dandy outfit', kind = 'outfit', sex = 'male', price = 45, min_tier = 1, owned = false },
            { id = 'item_trail_hat', label = 'Trail hat', kind = 'item', sex = 'any', price = 9, min_tier = 1, owned = false },
            { id = 'outfit_frontier_coat', label = 'Frontier long coat', kind = 'outfit', sex = 'male', price = 120, min_tier = 3, owned = false },
        },
    },
    wardrobe = {
        owned = {
            { id = 'outfit_ranch_hand', label = 'Ranch hand outfit', kind = 'outfit', source = 'starter' },
            { id = 'outfit_town_dandy', label = 'Town dandy outfit', kind = 'outfit', source = 'buy' },
            { id = 'item_trail_hat', label = 'Trail hat', kind = 'item', source = 'buy' },
            { id = 'item_work_gloves', label = 'Work gloves', kind = 'item', source = 'quests:hale_1' },
        },
        worn = { outfit = 'outfit_ranch_hand', items = { 'item_trail_hat' } },
        saved = {
            [1] = { label = 'Everyday', outfit = 'outfit_ranch_hand', items = { 'item_trail_hat' }, valid = true },
            [3] = { label = 'Church', outfit = 'outfit_town_dandy', items = {}, valid = true },
        },
        fitted = false,
        maxItems = 3,
        maxSaved = 4,
    },
}

-- Tiny schema: field -> type, with '?' suffix for optional. 'table[]' / '<name>[]' nested lists via {list=schema}.
local S = {}
S.heat = {
    factions = { list = { id = 'string', label = 'string', level = 'number', tier = 'string' } },
    lay_low = { obj = { active = 'boolean', seconds_left = 'number?' } },
}
S.insurance = { title = 'string', fee = 'number', delay_minutes = 'number', target_chest = 'string', note = 'string?' }
local item = { list = { item = 'string', qty = 'number' } }
S.jobs = {
    region_id = 'string', expires_at = 'number', expired = 'boolean?', notice = 'string?',
    offers = { list = { id = 'string', job_type = 'string', title = 'string', text = 'string?', accepted = 'boolean', locked = 'table?',
        rewards = { obj = { money = 'number?' } } } },
}
S.journal = {
    notice = 'string?', notice_kind = 'string?',
    entries = { list = { quest_id = 'string', kind = 'string', title = 'string', giver = 'string?', region_id = 'string?',
        status = 'string', step = 'number?', steps_total = 'number?', step_text = 'string?', count = 'number?',
        need = 'number?', cooldown_until = 'number?', updated_at = 'number?', rewards = { obj = { money = 'number?' } } } },
}
S.dialogue = {
    speaker = 'string', notice = 'string?', notice_kind = 'string?', pages = 'table',
    offer = { obj = { quest_id = 'string', prompt = 'string', accept = 'string', decline = 'string' } },
}
S.station = {
    title = 'string',
    options = { list = { id = 'string', label = 'string', inputs = item, outputs = item, time_seconds = 'number',
        can_craft = 'boolean' } },
}
S.fence = {
    title = 'string?',
    stock = { list = { id = 'string', label = 'string', price = 'number', qty = 'number', category = 'string' } },
    sell = { list = { id = 'string', label = 'string', price = 'number', qty = 'number' } },
}
S.tradepost = {
    label = 'string', region = 'string',
    goods = { list = { item = 'string', label = 'string', price = 'number', shortage = 'number', saturation = 'number' } },
    supplies = { list = { item = 'string', label = 'string', price = 'number' } },
    max_sell = 'number', max_buy = 'number',
    notice = 'string?', notice_kind = 'string?',
}
S.fieldguide = {
    selected = 'string?',
    entries = { list = { id = 'string', title = 'string', lines = 'table', controls = 'table', wiki_path = 'string' } },
}
S.trapper = {
    title = 'string',
    notice = 'string?', notice_kind = 'string?',
    rows = { list = { container = 'string', slot = 'number', item = 'string', label = 'string',
        stars = 'number', legendary = 'boolean', price = 'number' } },
}
S.tailor = {
    notice = 'string?', notice_kind = 'string?',
    shop = { obj = { id = 'string', label = 'string', region_id = 'string', size = 'number' } },
    tier = 'number',
    rows = { list = { id = 'string', label = 'string', kind = 'string', sex = 'string', price = 'number',
        min_tier = 'number', owned = 'boolean' } },
}
S.wardrobe = {
    notice = 'string?', notice_kind = 'string?',
    owned = { list = { id = 'string', label = 'string', kind = 'string', source = 'string' } },
    worn = 'table?', -- { outfit, items }; absent before the starter set is granted
    saved = 'table', -- sparse { [slot] = { label, outfit, items, valid } }
    fitted = 'boolean', maxItems = 'number', maxSaved = 'number',
}
M.schemas = S

local function check(schema, v, path, errs)
    if type(v) ~= 'table' then errs[#errs + 1] = path .. ': not a table'; return end
    for k, t in pairs(schema) do
        local x, p = v[k], path .. '.' .. k
        if type(t) == 'string' then
            local base, opt = t:gsub('%?$', '')
            if x == nil then
                if opt == 0 then errs[#errs + 1] = p .. ': missing' end
            elseif type(x) ~= base or (base == 'number' and x ~= x) then
                errs[#errs + 1] = p .. ': expected ' .. base
            end
        elseif t.obj then
            if x == nil then errs[#errs + 1] = p .. ': missing' else check(t.obj, x, p, errs) end
        elseif t.list then
            if type(x) ~= 'table' then errs[#errs + 1] = p .. ': expected list'
            else for i, e in ipairs(x) do check(t.list, e, p .. '[' .. i .. ']', errs) end end
        end
    end
end

-- Returns true | false, { error strings }.
function M.validate(screen, data)
    local schema = S[screen]
    if not schema then return false, { 'no schema for ' .. tostring(screen) } end
    local errs = {}
    check(schema, data, screen, errs)
    return #errs == 0, errs
end

-- Pure arg parsing for `fh_ui_demo <screen|close> [screen]`. Returns { action = 'open'|'close', screen } | nil, code.
function M.parseDemo(args)
    local a = args and args[1]
    if type(a) ~= 'string' or a == '' then return nil, 'fh_ui_demo_usage' end
    a = a:lower()
    if a == 'close' then
        local s = args[2] and tostring(args[2]):lower() or nil
        if s and not M.fixtures[s] then return nil, 'fh_ui_demo_unknown_screen' end
        return { action = 'close', screen = s }
    end
    if not M.fixtures[a] then return nil, 'fh_ui_demo_unknown_screen' end
    return { action = 'open', screen = a }
end

if GetCurrentResourceName then
    FhUiFixtures = M
else
    return M
end
