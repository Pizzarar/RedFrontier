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
    '@ox_lib/init.lua',
    'config.lua',
    '@fh_core/shared/regions.lua', -- FhRegions global (enabled gate for blips/where)
    -- Lane configs/shares, read-only: the single source of truth for place coordinates (mapblips). `@resource/file`
    -- reads the file content into fh_ui's own state, so these load even though the lanes start later in server.cfg.
    '@fh_homestead/config.lua',
    '@fh_trade/config.lua',
    '@fh_hunting/config.lua',
    '@fh_zones/config.lua',
    '@fh_crafting/config.lua',
    '@fh_fence/config.lua',
    '@fh_quests/shared/givers.lua',
    '@fh_quests/shared/board_spots.lua',
    'shared/relay.lua',
    'shared/hud.lua',
    'shared/fixtures.lua',
    'shared/quests_view.lua',
    'shared/places.lua',
}

server_scripts {
    'server/main.lua',
}

client_scripts {
    '@fh_core/client/safe.lua',
    'client/main.lua',
    'client/hud.lua',
    'client/adapter.lua',
    'client/blips.lua',
    'client/where.lua',
}

dependencies { 'fh_core', 'ox_lib' }
