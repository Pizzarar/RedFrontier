fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

description 'RedFrontier regional trade prices, shortages and trade-post selling (spec L6)'

shared_scripts {
    '@ox_lib/init.lua',
    '@fh_core/shared/regions.lua', -- FhRegions global (fh_core must be started first)
    'config.lua',
    'shared/trade_prices.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

dependencies { 'fh_core', 'fh_economy', 'oxmysql', 'rsg-core', 'ox_lib' }

server_exports { 'quote', 'getShortages', 'setShortage', 'listGoods', 'previewSell' }
