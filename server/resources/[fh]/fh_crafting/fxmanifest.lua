fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

description 'RedFrontier crafting (spec L5): reload press, apothecary tonics, station + inventory adapters for fh_gunsmith'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/recipes.lua',
    'shared/craft_rules.lua',
    'shared/gather_rules.lua',
}

server_scripts {
    'shared/craft_flow.lua',
    'server/stations.lua',
    'server/inv.lua',
    'server/craft.lua',
    'server/apothecary.lua',
    'server/gather.lua',
    'server/main.lua',
}

client_scripts {
    '@fh_core/client/safe.lua',
    'client/gather.lua',
}

dependencies { 'fh_core', 'ox_lib' }

server_exports { 'getRecipes', 'isNearStation', 'invCount', 'invTake', 'invGive', 'invSlot', 'invSetInfo',
    'getStations', 'stationAt', 'craft' }
