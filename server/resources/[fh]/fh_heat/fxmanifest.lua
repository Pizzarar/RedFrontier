fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

description 'RedFrontier faction heat (spec L7): per-faction heat, lay-low decay, bounty payoff'

shared_scripts {
    '@fh_core/shared/regions.lua', -- FhRegions global (fh_core must be started first)
    'config.lua',
    'shared/heat_rules.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

dependencies { 'fh_core', 'oxmysql', 'rsg-core' }

server_exports { 'add', 'addSource', 'get', 'set', 'getAll', 'level', 'payoff' }
