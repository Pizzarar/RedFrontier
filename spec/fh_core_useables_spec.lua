-- core-08 P2: fh_core/server/useables.lua with stubbed natives, exports and inventory.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local SERVER = here .. '../server/resources/[fh]/fh_core/server/useables.lua'

local function boot(o)
    o = o or {}
    local w = { events = {}, notes = {}, removed = {}, paid = {}, charged = {}, useables = {}, handlers = {}, logs = {} }
    local bag = o.bag or {}
    local env = setmetatable({}, { __index = _G })
    env.GetGameTimer = function() w.t = (w.t or 0) + 5000 return w.t end
    env.GetCurrentResourceName = function() return 'fh_core' end
    env.AddEventHandler = function(n, fn) w.handlers[n] = fn end
    env.CreateThread = function(fn) fn() end
    env.GetPlayerPed = function() return 7 end
    env.GetEntityHealth = function() return o.health or 200 end
    env.print = function(...) w.logs[#w.logs + 1] = table.concat({ ... }, ' ') end
    env.TriggerClientEvent = function(name, src, p)
        if name == 'RSGCore:Client:Notify' then w.notes[#w.notes + 1] = p.description else w.events[#w.events + 1] = { name = name, p = p } end
    end
    env.exports = setmetatable({}, { __index = function(_, res)
        return setmetatable({}, { __index = function(_, fn)
            return function(_, a, b, c, d)
                if res == 'rsg-core' and fn == 'CreateUseableItem' then w.useables[a] = b return end
                if res == 'rsg-inventory' then
                    if fn == 'GetItemBySlot' then return bag[b] end
                    if fn == 'GetItemByName' then for _, it in pairs(bag) do if it.name == b then return it end end return nil end
                    if fn == 'RemoveItem' then
                        if o.removeFails then return false end
                        w.removed[#w.removed + 1] = b w.order = (w.order or '') .. 'R' return true
                    end
                end
                if res == 'fh_economy' and fn == 'pay' then
                    if o.payFails then return false, 'refused' end
                    w.paid[#w.paid + 1] = { amount = b, reason = c } w.order = (w.order or '') .. 'P' return true, nil, 1
                end
                if res == 'fh_economy' and fn == 'charge' then w.charged[#w.charged + 1] = { amount = b, reason = c } return true end
            end
        end })
    end })
    assert(loadfile(SERVER, 't', env))()
    w.handlers.onResourceStart('fh_core')
    function w.use(src, name) w.useables[name](src, { name = name, slot = 1 }) end
    return w
end

local function bagOf(name, info) return { [1] = { name = name, slot = 1, info = info or {} } } end

case('registers all eight items; re-registers on rsg-core restart', function()
    local w = boot()
    for _, n in ipairs({ 'bandage', 'fieldbandage', 'firstaid', 'tonic_healing', 'tonic_stamina', 'tonic_energy', 'money_clip', 'blood_money_clip' }) do
        assert(w.useables[n], n) w.useables[n] = nil
    end
    w.handlers.onResourceStart('rsg-core')
    assert(w.useables.bandage and w.useables.money_clip)
end)

case('heal: consumes one item then sends the restore event with the configured fractions', function()
    local w = boot({ bag = bagOf('bandage') })
    w.use(1, 'bandage')
    assert(#w.removed == 1 and w.removed[1] == 'bandage')
    assert(#w.events == 1 and w.events[1].name == 'fh:core:useable:restore' and w.events[1].p.hp == 0.15 and w.events[1].p.stamina == 0)
    local w2 = boot({ bag = bagOf('firstaid') }) w2.use(1, 'firstaid')
    assert(w2.events[1].p.hp == 0.60)
    local w3 = boot({ bag = bagOf('tonic_stamina') }) w3.use(1, 'tonic_stamina')
    assert(w3.events[1].p.stamina == 0.60 and w3.events[1].p.hp == 0)
    local w4 = boot({ bag = bagOf('tonic_energy') }) w4.use(1, 'tonic_energy')
    assert(w4.events[1].p.hp == 0.10 and w4.events[1].p.stamina == 0.40)
end)

case('heal: failed removal grants nothing', function()
    local w = boot({ bag = bagOf('bandage'), removeFails = true })
    w.use(1, 'bandage')
    assert(#w.events == 0 and #w.notes == 1)
end)

case('heal: item not in the inventory grants nothing; dead ped refused without consuming', function()
    local w = boot({ bag = {} }) w.use(1, 'bandage')
    assert(#w.events == 0 and #w.removed == 0)
    local d = boot({ bag = bagOf('bandage'), health = 0 }) d.use(1, 'bandage')
    assert(#d.events == 0 and #d.removed == 0)
end)

case('money clip: pays before consuming, whole cents, within range', function()
    local w = boot({ bag = bagOf('money_clip') })
    w.use(1, 'money_clip')
    assert(w.order == 'PR', w.order)
    local a = w.paid[1].amount
    assert(a >= 5 and a <= 25 and math.abs(a * 100 - math.floor(a * 100 + 0.5)) < 1e-6)
    local w2 = boot({ bag = bagOf('blood_money_clip', { amount = 12.34 }) })
    w2.use(1, 'blood_money_clip')
    assert(w2.paid[1].amount == 12.34 and w2.paid[1].reason == 'blood_money_clip')
end)

case('money clip: refused payment keeps the clip; failed consume charges the cash back', function()
    local w = boot({ bag = bagOf('money_clip'), payFails = true })
    w.use(1, 'money_clip')
    assert(#w.removed == 0 and #w.paid == 0)
    local w2 = boot({ bag = bagOf('money_clip'), removeFails = true })
    w2.use(1, 'money_clip')
    assert(#w2.paid == 1 and #w2.charged == 1 and w2.charged[1].amount == w2.paid[1].amount)
end)
T.finish()
