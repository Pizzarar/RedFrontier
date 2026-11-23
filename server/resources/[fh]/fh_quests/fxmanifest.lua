fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

description 'RedFrontier quests: data-driven quest engine, jobs board, family questlines (plan quests-01)'

-- Q1: pure shared modules only. Q2 adds server/*.lua (intake, exports, persistence, payouts).
shared_scripts {
    'shared/match.lua',
    'shared/engine.lua',
    'shared/board.lua',
}

dependencies { 'fh_core', 'fh_economy' }

-- The contract other lanes build against (README.md "Exports"). Implemented in Q2/Q3; declared now.
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
