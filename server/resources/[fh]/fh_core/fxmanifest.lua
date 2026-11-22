fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

description 'RedFrontier core contracts (pure-Lua shared modules are unit-tested with busted)'

shared_scripts {
    'config.lua',
    'shared/*.lua', -- modules resolve each other at call time, so glob order does not matter
}

server_scripts {
    'server/*.lua',
}
