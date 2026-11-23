fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

description 'RedFrontier shared NUI shell (spec L10): screens + focus handling + validated action relay; no game authority'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/screens/*.js',
}

shared_scripts {
    'shared/relay.lua',
}

server_scripts {
    'server/main.lua',
}

client_scripts {
    '@fh_core/client/safe.lua',
    'client/main.lua',
}

dependencies { 'fh_core' }
