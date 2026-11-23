-- fh_death client: open prompt at each death bag. The bag prop itself is spawned through fh_core's B4c spawn
-- contract (fh_core/client/spawn.lua), not here. Every bag is listed to every client (the prop is visible anyway);
-- the server refuses anyone but the owner and re-checks reach. Natives: see fh_core/docs/natives.md (unverified).
local points = {}                -- bag id -> lib.points point
local INPUT_CONTEXT = 0xCEFD9220 -- E (unverified)
local near = nil                 -- bag id whose prompt is showing

local function clear()
    for id, p in pairs(points) do
        p:remove()
        points[id] = nil
    end
    if near then
        lib.hideTextUI()
        near = nil
    end
end

local function set(list)
    clear()
    for _, b in ipairs(type(list) == 'table' and list or {}) do
        if type(b) == 'table' and type(b.id) == 'string' and tonumber(b.x) and tonumber(b.y) and tonumber(b.z) then
            local id = b.id
            points[id] = lib.points.new({
                coords = vector3(b.x + 0.0, b.y + 0.0, b.z + 0.0), distance = 2.0,
                onEnter = FH.wrap(function()
                    near = id
                    lib.showTextUI('[E] Dropped belongings')
                end),
                onExit = FH.wrap(function()
                    if near == id then
                        lib.hideTextUI()
                        near = nil
                    end
                end),
                nearby = FH.wrap(function()
                    if IsControlJustReleased(0, INPUT_CONTEXT) then TriggerServerEvent('fh:death:open', { id = id }) end
                end),
            })
        end
    end
end

FH.onNet('fh:death:bags', set)

FH.thread(function()
    set(lib.callback.await('fh:death:bags', false))
end)

FH.on('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clear()
end)
