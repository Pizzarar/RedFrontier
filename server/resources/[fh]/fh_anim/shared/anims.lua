-- Action key -> animation. Dict entries: { dict, clip, flag, ms }; scenario entries: { scenario, ms }.
-- Instant keys are upper-body clips (flag 31/49) so the player can still move. Scenarios are only for
-- progress-bar sites (start/stop), which already disable movement.
local A = {
    skin       = { scenario = 'WORLD_HUMAN_CROUCH_INSPECT', ms = 5000 }, -- candidate, unproven (P0 spk_anim)
    gather     = { scenario = 'WORLD_HUMAN_CROUCH_INSPECT', ms = 4000 }, -- candidate, unproven (P0 spk_anim)
    eat        = { dict = 'mech_inventory@eating@multi_bite', clip = 'quick_right_hand', flag = 49, ms = 2500 },          -- candidate, unproven (P0 spk_anim)
    drink      = { dict = 'mech_inventory@drinking@bottle_cylinder_d1-3_h30-5_neck_h8-5_quick', clip = 'quick_right_hand', flag = 49, ms = 2500 }, -- candidate, unproven (P0 spk_anim)
    craft      = { dict = 'mech_inventory@item@fallbacks@tonic_potent@offhand', clip = 'use_quick', flag = 49, ms = 2000 }, -- candidate, unproven (P0 spk_anim)
    cook       = { dict = 'mech_inventory@item@fallbacks@tonic_potent@offhand', clip = 'use_quick', flag = 49, ms = 2000 }, -- candidate, unproven (P0 spk_anim)
    chest_open = { dict = 'mech_inventory@item@fallbacks@tonic_potent@offhand', clip = 'use_quick', flag = 31, ms = 1500 }, -- candidate, unproven (P0 spk_anim)
    trough     = { dict = 'mech_inventory@item@fallbacks@tonic_potent@offhand', clip = 'use_quick', flag = 31, ms = 1500 }, -- candidate, unproven (P0 spk_anim)
    plant      = { dict = 'mech_inventory@item@fallbacks@tonic_potent@offhand', clip = 'use_quick', flag = 31, ms = 1500 }, -- candidate, unproven (P0 spk_anim)
    harvest    = { dict = 'mech_inventory@item@fallbacks@tonic_potent@offhand', clip = 'use_quick', flag = 31, ms = 1500 }, -- candidate, unproven (P0 spk_anim)
    refill     = { dict = 'mech_inventory@item@fallbacks@tonic_potent@offhand', clip = 'use_quick', flag = 31, ms = 1500 }, -- candidate, unproven (P0 spk_anim)
    wash       = { dict = 'mech_inventory@item@fallbacks@tonic_potent@offhand', clip = 'use_quick', flag = 31, ms = 1500 }, -- candidate, unproven (P0 spk_anim)
}

if GetCurrentResourceName then
    FhAnimTable = A
else
    return A
end
