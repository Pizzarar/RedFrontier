-- Family 4 (C6, Lemoyne): the Cormiers, who keep a ferry landing in the bayou. Swamp Gang raiders and a big gator
-- have them cut off from town. Events: pelt skinned (alligator), camp cleared in bayou_nwa, pelts sold, talk.
-- Original content. Giver intro lines are in shared/givers.lua; position TODO-verify-in-game.
return {
    id = 'family_cormier', kind = 'line', title = 'Cormier Landing: High Water',
    giver = 'npc_cormier', region_id = 'bayou_nwa',
    steps = {
        { on = 'fh:hunting:pelt_skinned', where = { animal = 'alligator' },
            text = 'Skin the gator that has been taking the Cormier goats.' },
        { on = 'fh:zones:camp_cleared', where = { region_id = 'bayou_nwa' },
            text = 'Clear a Swamp Gang camp in the bayou.' },
        { on = 'fh:hunting:pelt_sold', count = 2, text = 'Sell two pelts to pay for new ferry rope.' },
        { talk = { npc = 'npc_cormier', lines = {
            'The ferry ran twice today. Folks are coming back across.',
            'We do not have much, but the landing remembers its friends. Take this.',
        } }, text = 'Tell Odile Cormier the water is safe again.' },
    },
    rewards = { money = 70, rep = { region_id = 'bayou_nwa', delta = 8 } },
}
