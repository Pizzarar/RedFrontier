-- Pure heat HUD builder (plan T3): turns fh_heat's getAll(src) map into the fh_ui `heat` screen data. No natives,
-- specced under busted (spec/heat_hud_spec.lua). Read-only: it never mutates heat, thresholds or the getAll result.
--
-- fh_ui heat schema (fh_ui/README.md "heat"): { factions = { { id, label, level (0-100), tier } }, lay_low = { active, seconds_left? } }.
--   id     = faction id
--   label  = faction display label (regions.factions[id].label; falls back to the id)
--   level  = heat 0..100
--   tier   = threshold name (watched/wanted/hunted from config thresholds), or nil below the first threshold
-- Only factions with heat > 0 are listed, so the widget shows the factions a player actually has heat with and
-- hides entirely when none remain. `lay_low` is stubbed to inactive: fh_heat has no player-level lay-low countdown
-- to report (decay is per-faction and continuous), and the builder never invents one.
local M = {}

---@param all { [faction] = { heat:number, level:string|nil } }  -- exports.fh_heat:getAll(src)
---@param factions { [id] = { label:string } }                    -- FhRegions.factions (for labels)
---@return { factions:{ { id, label, level, tier } }, lay_low:{ active:boolean } }
function M.build(all, factions)
    local rows = {}
    if type(all) == 'table' then
        for id, v in pairs(all) do
            if type(id) == 'string' then
                local heat = (type(v) == 'table' and type(v.heat) == 'number' and v.heat) or 0
                if heat > 0 then
                    local f = type(factions) == 'table' and factions[id] or nil
                    rows[#rows + 1] = {
                        id = id,
                        label = (type(f) == 'table' and f.label) or id,
                        level = heat,
                        tier = (type(v) == 'table' and v.level) or nil,
                    }
                end
            end
        end
    end
    table.sort(rows, function(a, b) return a.id < b.id end)
    return { factions = rows, lay_low = { active = false } }
end

if GetCurrentResourceName then
    FhHeatHud = M
else
    return M
end
