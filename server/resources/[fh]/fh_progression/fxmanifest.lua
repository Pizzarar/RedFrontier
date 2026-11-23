fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

description 'RedFrontier regional rep tiers & unlocks (M7)'

shared_scripts {
    '@fh_core/shared/regions.lua', -- FhRegions global (fh_core must be started first)
    'config.lua',
    'shared/progression_logic.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/compat_rep.lua',
    'server/progression_cache.lua',
    'server/main.lua',
}

dependencies { 'fh_core', 'fh_economy', 'oxmysql', 'rsg-core' }

server_exports { 'getTier', 'canUnlock', 'getRep' }
