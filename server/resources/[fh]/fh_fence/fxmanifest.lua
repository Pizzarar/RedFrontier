fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

description 'RedFrontier roving black-market fence: schedule, tiered stock, treasure leads (M7)'

shared_scripts {
    '@ox_lib/init.lua',
    '@fh_core/shared/regions.lua', -- FhRegions global (fh_core must be started first)
    'config.lua',
    'shared/fence_logic.lua',
    'shared/leads_logic.lua',
}

server_scripts {
    'server/config_leads.lua', -- SERVER ONLY: exact treasure lead spots (FhFenceLeadSpots); never make this shared
    'server/charge.lua',
    'server/trade.lua',
    'server/main.lua',
    'server/leads.lua',
}

client_scripts {
    '@fh_core/client/safe.lua',
    'client/main.lua',
    'client/leads.lua',
}

dependencies { 'fh_core', 'fh_inventory', 'fh_economy', 'fh_progression', 'ox_lib' }

server_exports { 'getSchedule' }
