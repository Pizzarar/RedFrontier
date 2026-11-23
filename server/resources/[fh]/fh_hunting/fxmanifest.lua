fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

description 'RedFrontier hunting (spec L8): pelt quality from shot placement, pelts as bulky/cargo items, price rules'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/animals.lua',
    'shared/quality.lua',
    'shared/price.lua',
}

server_scripts {
    '@fh_core/shared/containers.lua',
    'shared/skin.lua',
    'shared/wagon.lua',
    'shared/sell.lua',
    'server/main.lua',
}

client_scripts {
    '@fh_core/client/safe.lua',
    'client/main.lua',
}

dependencies { 'fh_core', 'fh_economy', 'ox_lib', 'rsg-target' }

server_exports { 'getAnimal', 'getPeltItem', 'price' }
