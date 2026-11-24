fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

description 'RedFrontier homestead: fixed plots, build slots, stations, comfort (spec L1)'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/plot_rules.lua',
    'shared/build_rules.lua',
    'shared/stations.lua',
    'shared/comfort.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/slots.lua',
    'server/comfort.lua',
    'server/build.lua',
}

client_scripts {
    '@fh_core/client/safe.lua',
    'client/main.lua',
}

dependencies { 'fh_core', 'oxmysql', 'rsg-core', 'ox_lib', 'fh_economy' }

server_exports { 'claim', 'unclaim', 'buyLot', 'getPlot', 'claimedPlots', 'isInSafeZone', 'getStations', 'stationAt', 'isNearStation', 'getComfort', 'placeTrophy', 'unplaceTrophy', 'addTrophy', 'removeTrophy' }
