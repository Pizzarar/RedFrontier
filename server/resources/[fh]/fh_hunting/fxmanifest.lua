fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

description 'RedFrontier hunting (spec L8): pelt quality from shot placement, pelts as bulky/cargo items, price rules'

shared_scripts {
    '@ox_lib/init.lua',
    '@fh_core/shared/regions.lua', -- FhRegions global (region ids + the isEnabled gate)
    'config.lua',
    'shared/plain_animals.lua',    -- FhHuntingPlainAnimals: the plain rows the loader validates against
    'shared/legendaries.lua',      -- FhHuntingLegendaries: reads data/legendaries/<region_id>.lua (LoadResourceFile)
    'shared/animals.lua',          -- derives the legendary pelt rows from it
    'shared/quality.lua',
    'shared/price.lua',
}

server_scripts {
    '@fh_core/shared/containers.lua',
    '@oxmysql/lib/MySQL.lua',
    'shared/skin.lua',
    'shared/wagon.lua',
    'shared/sell.lua',
    'shared/trophies.lua',
    'shared/chain.lua',
    'shared/coats.lua',
    'server/main.lua',
    'server/trappers_export.lua',
    'server/chain_export.lua',
}

-- Legendary data files (one per FhRegions id), read by shared/legendaries.lua on both sides; never run as scripts.
files {
    'data/legendaries/*.lua',
}

client_scripts {
    '@fh_core/client/safe.lua',
    'client/main.lua',
}

dependencies { 'fh_core', 'fh_economy', 'ox_lib', 'rsg-target', 'oxmysql' }

server_exports { 'getAnimal', 'getPeltItem', 'price', 'getTrophyComfort', 'getTrappers', 'chainState' }
