fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

description 'RedFrontier tailor: fitted outfits as progression (catalog, regional-tier stock, owned outfits, wardrobe)'

shared_scripts {
    '@ox_lib/init.lua',
    '@fh_core/shared/regions.lua', -- FhRegions global (fh_core must be started first)
    'config.lua',
    'shared/tailor_logic.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/charge.lua',
    'server/tailor.lua',
    'server/main.lua',
}

client_scripts {
    '@fh_core/client/safe.lua',
    'client/main.lua',
}

dependencies { 'fh_core', 'fh_economy', 'fh_progression', 'ox_lib', 'oxmysql', 'rsg-core' }

server_exports { 'buy', 'grant', 'equip', 'saveOutfit', 'wearSaved', 'getStock', 'getWardrobe', 'message',
    'actBuy', 'actStock', 'actWardrobe', 'actEquip', 'actSave', 'actWear' }

client_exports { 'previewLook', 'revertLook' }
