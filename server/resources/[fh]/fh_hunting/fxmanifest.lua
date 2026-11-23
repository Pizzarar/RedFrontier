fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

description 'RedFrontier hunting (spec L8): pelt quality from shot placement, pelts as bulky/cargo items, price rules'

shared_scripts {
    'config.lua',
    'shared/animals.lua',
    'shared/quality.lua',
    'shared/price.lua',
}

server_scripts {
    'server/main.lua',
}

dependencies { 'fh_core', 'fh_economy' }

server_exports { 'getAnimal', 'getPeltItem', 'price' }
