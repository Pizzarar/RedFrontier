-- fh_crafting herb gathering client (plan crafting-02 C9b). A lib.points point per patch shows the [E] prompt; on E a
-- short progress bar runs (pcall, same pattern as fh_hunting/client/main.lua:114) and then the client asks the server
-- to gather. The server decides everything (reach, cooldown, grant). No new game natives.
local cfg = FhCraftingConfig
local INPUT_CONTEXT = 0xCEFD9220 -- E (unverified)
local GATHER_MS = 4000           -- progress bar duration (~4 s)

local busy = false -- one pick in flight per client, so a held E cannot stack progress bars
local near = nil   -- patch id whose prompt is showing

local function herbLabel(herb)
    local name = tostring(herb):gsub('^herb_', ''):gsub('_', ' ')
    return (name:gsub('(%a)([%w]*)', function(a, b) return a:upper() .. b end))
end

for _, p in ipairs(cfg.herbPatches or {}) do
    local patch = p
    lib.points.new({
        coords = vector3(patch.coords.x, patch.coords.y, patch.coords.z),
        distance = 2.0,
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
                busy = true
                -- pcall: if the progress bar throws, `busy` must still reset or the patch stays locked forever.
                local ok, done = pcall(lib.progressBar, {
                    duration = GATHER_MS, label = 'Picking ' .. herbLabel(patch.herb) .. '...', canCancel = true,
                    disable = { move = true, car = true, combat = true },
                })
                busy = false
                if ok and done then
                    TriggerServerEvent('fh:crafting:gather', patch.id)
                end
            end
        end),
    })
end

FH.on('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    lib.hideTextUI()
end)
