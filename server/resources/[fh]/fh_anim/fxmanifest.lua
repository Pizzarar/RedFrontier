fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

description 'RedFrontier fh_anim: cosmetic named action animations (skin, gather, eat, craft, ...) behind a config flag'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/anims.lua',
    'shared/anim_logic.lua',
}

client_scripts {
    'client/main.lua',
}

dependencies { 'ox_lib' }

client_exports { 'play', 'start', 'stop' }
