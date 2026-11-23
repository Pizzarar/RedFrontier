fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

description 'RedFrontier homestead: fixed plot claim + one chest (spec L1)'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/plot_rules.lua',
    'shared/build_rules.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

client_scripts {
    '@fh_core/client/safe.lua',
    'client/main.lua',
}

dependencies { 'fh_core', 'oxmysql', 'rsg-core', 'ox_lib' }

server_exports { 'claim', 'unclaim', 'getPlot', 'isInSafeZone' }
