fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

description 'RedFrontier survival needs as timed buffs (plan survival-01): food, water, rest, cleanliness, warmth; never lethal'

shared_scripts {
    '@fh_core/shared/regions.lua', -- FhRegions global (fh_core must be started first)
    'config.lua',
    'shared/needs.lua',
    'shared/items.lua',
    'shared/rest.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/actions.lua',
    'server/homestead_adapter.lua',
    'server/rest.lua',
}

client_scripts {
    '@fh_core/client/safe.lua',
    'client/main.lua', -- stub: S5 adds the sluggish effect
    'client/actions.lua',
}

dependencies { 'fh_core', 'fh_buffs', 'oxmysql', 'rsg-core' }
