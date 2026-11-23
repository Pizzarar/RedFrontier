fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

description 'RedFrontier quests: data-driven quest engine, jobs board, family questlines (plan quests-01)'

-- Pure modules (specced by tools/run-specs.py). Order matters: later modules use the earlier globals.
shared_scripts {
    '@fh_core/shared/regions.lua', -- FhRegions global (region ids for validate)
    'shared/match.lua',
    'shared/engine.lua',
    'shared/board.lua',
    'shared/jobs.lua',
    'shared/jobtypes.lua',
    'shared/intake.lua',
    'shared/journal.lua',
    'shared/rewards.lua',
    'shared/store.lua',
    'shared/givers.lua', -- family giver npcs (Q4)
}

-- Thin server glue: state cache/lock, persistence, payouts, sync (main.lua); exports + event intake (api.lua).
server_scripts {
    '@ox_lib/init.lua',
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/api.lua',
    'server/jobtypes.lua', -- built-in job types, registered through the public registerJobType
    'server/menu.lua',     -- WORKAROUND: ox_lib fallback jobs menu, server side (replaced by the @ui jobs board)
    'server/ui_text.lua',  -- pure error code -> notice text for the fh_ui jobs screen
    'server/ui.lua',       -- fh_ui jobs board glue (open + fh:quests:ui_accept)
    'server/families.lua', -- Q4: register the family questlines, spawn givers, WORKAROUND dialogue callbacks
}

client_scripts {
    '@ox_lib/init.lua',
    '@fh_core/client/safe.lua',
    'client/bounty.lua',     -- permanent: bounty NPC hostile-AI setup
    'client/jobs_menu.lua',  -- WORKAROUND: ox_lib fallback jobs menu (/jobs + board prop via rsg-target), replaced by the @ui jobs-board screen
    'client/givers.lua', -- WORKAROUND: ox_lib giver dialogue (replaced by the @ui journal/dialogue screen)
}

dependencies { 'fh_core', 'fh_economy', 'oxmysql', 'ox_lib', 'rsg-core' }

-- The contract other lanes build against (README.md "Server exports").
server_exports {
    'registerQuest',
    'registerJobType',
    'start',
    'abandon',
    'getActive',
    'getBoard',
    'acceptOffer',
    'talk',
}
