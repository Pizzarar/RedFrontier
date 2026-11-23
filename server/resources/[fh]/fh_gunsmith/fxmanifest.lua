fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

description 'RedFrontier gunsmith (spec L5): /fh_restore raises weapon condition at a gunsmith station using gun_parts'

shared_scripts {
    '@fh_crafting/shared/craft_rules.lua',
    'shared/restore_flow.lua',
}

server_scripts {
    'server/main.lua',
}

client_scripts {
    'client/wear.lua',
}

dependencies { 'fh_core', 'fh_crafting' }
