-- FH (core-10 I3): registry behind exports.fh_inventory:registerPaneButton. Pure Lua (no natives), specced in
-- spec/pane_buttons_spec.lua. main.lua owns the export, the NUI plumbing and the fh_inventory:paneButton event.
FhPaneButtons = {}

local PANES = { saddlebag = true, backpack = true }
local buttons, order = {}, {}

-- Validates and stores (or replaces, same id keeps its position) a button. Returns true, or false + reason.
function FhPaneButtons.register(def)
    if type(def) ~= 'table' then return false, 'bad_args' end
    if type(def.id) ~= 'string' or def.id == '' then return false, 'bad_id' end
    if type(def.label) ~= 'string' or def.label == '' then return false, 'bad_label' end
    local pane = def.pane == nil and 'backpack' or def.pane
    if type(pane) ~= 'string' or not PANES[pane] then return false, 'bad_pane' end
    if not buttons[def.id] then order[#order + 1] = def.id end
    buttons[def.id] = { id = def.id, label = def.label, pane = pane }
    return true
end

function FhPaneButtons.get(id) return buttons[id] end

-- Array of { id, label, pane } in registration order (fresh tables, safe to hand to NUI).
function FhPaneButtons.list()
    local out = {}
    for i = 1, #order do
        local b = buttons[order[i]]
        out[i] = { id = b.id, label = b.label, pane = b.pane }
    end
    return out
end

-- Click payload for a registered id, or nil.
function FhPaneButtons.payload(id)
    local b = type(id) == 'string' and buttons[id] or nil
    return b and { id = b.id, pane = b.pane } or nil
end

function FhPaneButtons.reset() buttons, order = {}, {} end
