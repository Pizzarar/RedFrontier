fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

description 'RedFrontier cargo and wagons (spec L6): wagon tiers, cargo loading, fast-travel veto'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/cargo_rules.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/wagon_buy.lua',
    'server/wagon_post.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

dependencies { 'fh_core', 'rsg-core', 'ox_lib', 'oxmysql' }

server_exports {
    'canFastTravel', 'getWagon', 'spawnWagon', 'nearestWagon', 'isWheelBroken', 'getSpeedLimit',
    'buyWagon', 'ownsWagon', 'ownedTiers',
}
