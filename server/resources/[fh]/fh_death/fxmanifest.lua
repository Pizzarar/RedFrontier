fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

description 'RedFrontier soft death (spec L4): keep equipped, drop backpack + saddlebag into an owner-only drop bag'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/death_rules.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

client_scripts {
    '@fh_core/client/safe.lua',
    'client/main.lua',
}

dependencies { 'fh_core', 'fh_inventory', 'oxmysql', 'rsg-core', 'ox_lib' }

server_exports { 'getBags' }
