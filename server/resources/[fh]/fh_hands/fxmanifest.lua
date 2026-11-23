fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

description 'RedFrontier hired hands: wage ticks and automated upkeep tasks (M7)'

shared_scripts {
    'config.lua',
    'shared/hands_logic.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/compat_charge.lua',
    'server/main.lua',
}

dependencies { 'fh_core', 'fh_economy', 'fh_progression', 'fh_homestead', 'oxmysql', 'rsg-core' }

server_exports { 'hire', 'fire', 'getHands', 'registerTask' }
