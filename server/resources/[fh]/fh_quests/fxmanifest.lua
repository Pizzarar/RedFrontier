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
    'shared/intake.lua',
    'shared/journal.lua',
    'shared/rewards.lua',
    'shared/store.lua',
}

-- Thin server glue: state cache/lock, persistence, payouts, sync (main.lua); exports + event intake (api.lua).
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/api.lua',
}

dependencies { 'fh_core', 'fh_economy', 'oxmysql', 'rsg-core' }

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
