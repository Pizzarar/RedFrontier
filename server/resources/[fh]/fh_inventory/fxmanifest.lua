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
    -- FH: fh_core's pure-Lua rule modules, loaded into this resource's state (FhConfig, FhItems,
    -- FhContainers, FhRules). Must come before shared/config.lua, which reads FhConfig.
    '@fh_core/config.lua',
    '@fh_core/shared/items.lua',
    '@fh_core/shared/containers.lua',
    '@fh_core/shared/rules.lua',
    'shared/config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    '@fh_core/shared/regions.lua', -- FH: FhRegions, the ledger region of a shop (server/shops.lua, core M3)
    'server/main.lua',
    'server/shops.lua',
    'server/compat.lua',
    'server/fh_api.lua', -- FH: exports only fh_core may call
}

client_scripts {
    'client/panebuttons.lua', -- FH (core-10 I3)
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
    'fh_core',
}

lua54 'yes'
