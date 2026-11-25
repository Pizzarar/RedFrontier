-- fh_crafting herb gathering client (plan crafting-02 C9b). A lib.points point per patch shows the [E] prompt; on E a
-- short progress bar runs in its own thread (FH.thread, like fh_hunting/client/main.lua:143) and then the client asks
-- the server to gather. The server decides everything (reach, cooldown, grant). No new game natives.
local cfg = FhCraftingConfig
local INPUT_CONTEXT = 0xCEFD9220 -- E (unverified)
local GATHER_MS = 4000           -- progress bar duration (~4 s)

local busy = false -- one pick in flight per client, so a held E cannot stack progress bars
local near = nil   -- patch id whose prompt is showing

local function herbLabel(herb)
    local name = tostring(herb):gsub('^herb_', ''):gsub('_', ' ')
    return (name:gsub('(%a)([%w]*)', function(a, b) return a:upper() .. b end))
end

-- Runs off the lib.points loop so the blocking progress bar never stalls the points tick. The `busy` guard (re-checked
-- here AND in the points callback) means a second E press while one pick runs starts no second bar.
local function pick(patch)
    if busy then return end
    busy = true
    -- pcall: if the progress bar throws, `busy` must still reset or the patch stays locked forever.
    pcall(function() exports.fh_anim:start('gather') end)
    local ok, done = pcall(lib.progressBar, {
        duration = GATHER_MS, label = 'Picking ' .. herbLabel(patch.herb) .. '...', canCancel = true,
        disable = { move = true, car = true, combat = true },
    })
    pcall(function() exports.fh_anim:stop('gather') end)
    busy = false
    if ok and done then
        TriggerServerEvent('fh:crafting:gather', patch.id)
    end
end

for _, p in ipairs(cfg.herbPatches or {}) do
    local patch = p
    lib.points.new({
        coords = vector3(patch.coords.x, patch.coords.y, patch.coords.z),
        distance = FhGatherRules.PROMPT_RADIUS,
        onEnter = FH.wrap(function()
            near = patch.id
            lib.showTextUI('[E] Pick ' .. herbLabel(patch.herb))
        end),
        onExit = FH.wrap(function()
            if near == patch.id then
                near = nil
                lib.hideTextUI()
            end
        end),
        nearby = FH.wrap(function()
            if not busy and IsControlJustReleased(0, INPUT_CONTEXT) then
                FH.thread(function() pick(patch) end)
            end
        end),
    })
end

FH.on('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    lib.hideTextUI()
end)
