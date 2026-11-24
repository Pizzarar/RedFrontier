fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

description 'RedFrontier intro tutorial (guide-02): a skippable, never-blocking first-day guide on the fh_quests API'

shared_scripts {
    '@ox_lib/init.lua',    -- `lib` (client notify)
    'shared/tutorial.lua', -- FhTutorial: pure quest def + step/persistence decisions (specced in spec/tutorial_spec.lua)
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

client_scripts {
    '@fh_core/client/safe.lua',
    'client/main.lua',
}

dependencies { 'fh_core', 'fh_quests', 'oxmysql', 'ox_lib', 'rsg-core' }
