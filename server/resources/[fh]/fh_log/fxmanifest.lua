fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

description 'RedFrontier minimal rsg-log provider (console + server/logs/audit.log)'

provide 'rsg-log'

server_scripts {
    'server/format.lua',
    'server/main.lua',
}
