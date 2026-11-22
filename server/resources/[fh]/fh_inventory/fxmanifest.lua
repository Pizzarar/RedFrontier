fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'

description 'fh_inventory: RedFrontier fork of rsg-inventory (Rexshack-RedM), GPL-3'
version '3.4.0-fh.1'

-- FH: stands in for rsg-inventory (rsg-core and rsg-character call it by that name).
-- Exports are aliased by shared/fh_provide.lua; `provide` covers GetResourceState / dependencies.
provide 'rsg-inventory'

shared_scripts {
    'shared/fh_provide.lua', -- FH: must load before any exports() call
    '@rsg-core/shared/locale.lua',
    'shared/config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/shops.lua',
    'server/compat.lua',
    'server/versionchecker.lua',
}

client_scripts {
    'client/main.lua',
}

ui_page 'html/index.html'

files {
    'locales/*.json',
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/images/*.png',
}

dependencies {
    'rsg-core',
    'oxmysql',
}

lua54 'yes'
