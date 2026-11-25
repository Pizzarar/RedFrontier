-- Visual wear (plan C3). The weapon degradation native (_SET_WEAPON_DEGRADATION 0xA7A57E89E965D839) is still
-- "candidate, unproven" in fh_core/docs/natives.md, so this stays DATA ONLY: wear lives in item info.quality.
-- When the native is verified, call it here under the fh_spike_gated == false branch.
RegisterNetEvent('fh_gunsmith:conditionChanged', function(slot, condition, spikeGated)
    if spikeGated == false then
        print(('[fh_gunsmith] quality %s on slot %s: degradation native unverified, data-only'):format(tostring(condition), tostring(slot)))
    end
end)
