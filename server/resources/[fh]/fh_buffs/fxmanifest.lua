fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

description 'RedFrontier buff interface (spec 4.5)'

shared_scripts {
    'config.lua',
    'shared/buff_logic.lua',
}

server_scripts {
    'server/main.lua',
}

client_scripts {
    'client/main.lua', -- stub: no effects yet
}

server_exports { 'apply', 'get' }
