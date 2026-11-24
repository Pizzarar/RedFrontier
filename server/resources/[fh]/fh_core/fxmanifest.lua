fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

description 'RedFrontier core contracts (pure-Lua shared modules are unit-tested with busted)'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/*.lua', -- modules resolve each other at call time, so glob order does not matter
}

server_scripts {
    -- world-03 J: fh_core admin (fh_tp place ids, fh_tour, fh_mark) builds its place index from the lane configs.
    -- Read-only `@`-include (no dependency on those resources), same as fh_ui; fh_zones/config.lua resolves camps here.
    '@fh_homestead/config.lua',
    '@fh_zones/config.lua',
    'server/*.lua',
}

client_scripts {
    'client/safe.lua',
    'client/ground_snap.lua',
    'client/spawn.lua',
    'client/saddlebag.lua',
}
