fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

description 'RedFrontier zones: one T1 outlaw camp (spec L3 seed, M1)'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/camp_rules.lua',
}

server_scripts {
    'server/main.lua',
}

client_scripts {
    '@fh_core/client/safe.lua',
    '@fh_core/shared/ground_snap.lua',
    '@fh_core/client/ground_snap.lua',
    'client/main.lua',
}

dependencies { 'fh_core', 'fh_inventory', 'ox_lib' }

server_exports { 'getCamp' }
