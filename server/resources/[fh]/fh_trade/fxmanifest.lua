fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

description 'RedFrontier regional trade prices, shortages and trade-post selling and supplies buying (spec L6)'

shared_scripts {
    '@ox_lib/init.lua',
    '@fh_core/shared/regions.lua',        -- FhRegions global (fh_core must be started first)
    '@fh_core/shared/place_resolver.lua', -- FhPlaceResolver (resolves posts from FhRegions at config load)
    'config.lua',
    'shared/trade_prices.lua',
    'shared/freight.lua',
    'shared/supplies.lua',
    'shared/posts.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/freight.lua',
}

client_scripts {
    'client/main.lua',
}

dependencies { 'fh_core', 'fh_economy', 'oxmysql', 'rsg-core', 'ox_lib' }

server_exports { 'quote', 'getShortages', 'setShortage', 'listGoods', 'previewSell', 'getContracts' }
