fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

description 'RedFrontier A-Life: camp ownership sim + outlaw retake squads (plan a-life-01)'

shared_scripts {
    '@ox_lib/init.lua',
    '@fh_core/shared/regions.lua',        -- FhRegions global (fh_core must be started first)
    '@fh_core/shared/place_resolver.lua', -- FhPlaceResolver (resolves @fh_zones/config.lua camps at load)
    '@fh_zones/config.lua',        -- FhZonesConfig camp list (fh_zones must be started first)
    '@fh_zones/shared/camp_rules.lua', -- FhCampRules.safeParticipants (squad_wiped participants, as camp_cleared)
    'config.lua',
    'shared/alife_rules.lua',
    'shared/contracts_rules.lua',
}

server_scripts {
    'server/main.lua',
    'server/squads.lua',    -- uses FhAlifeServer from main.lua
    'server/contracts.lua', -- uses FhAlifeContracts (shared) + FhAlifeServer.getState
}

dependencies { 'fh_core', 'fh_zones', 'fh_trade', 'ox_lib' }

server_exports { 'getOwner', 'isLawHeld' }
