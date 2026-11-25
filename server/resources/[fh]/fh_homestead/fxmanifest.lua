fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

description 'RedFrontier homestead: fixed plots, build slots, stations, comfort (spec L1)'

shared_scripts {
    '@ox_lib/init.lua',
    '@fh_core/shared/regions.lua', -- FhRegions global (claim/buyLot region gate; fh_core must be started first)
    'config.lua',
    'shared/plot_rules.lua',
    'shared/build_rules.lua',
    'shared/stations.lua',
    'shared/comfort.lua',
    'shared/plotcheck.lua', -- FhPlotCheck (H16 /fh_plotcheck pure math)
    'shared/garden.lua', -- FhGarden (H18 garden pure rules)
    'shared/trough.lua', -- FhTrough (H20a pure refill rules)
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/slots.lua',
    'server/comfort.lua',
    'server/build.lua',
    'server/plotcheck.lua', -- H16 /fh_plotcheck (admin)
    'server/garden.lua', -- H19 /fh_plant, /fh_harvest, /fh_garden (FhHomesteadGarden; after build.lua: reads its BAG_ADD_UNCHANGED)
    'server/trough.lua', -- H20 trough: feedbag use handler, refill, getTrough (FhHomesteadTrough; after slots.lua)
}

client_scripts {
    '@fh_core/client/safe.lua',
    '@fh_core/shared/ground_snap.lua',
    '@fh_core/client/ground_snap.lua',
    'client/main.lua',
    'client/trough.lua', -- H20 refill on mount (flagged: troughRefill)
}

dependencies { 'fh_core', 'oxmysql', 'rsg-core', 'ox_lib', 'fh_economy' }

server_exports { 'claim', 'unclaim', 'buyLot', 'getPlot', 'claimedPlots', 'isInSafeZone', 'plotInfo', 'lawSafeAt', 'getStations', 'stationAt', 'isNearStation', 'getComfort', 'placeTrophy', 'unplaceTrophy', 'addTrophy', 'removeTrophy', 'getTrough' }
