-- Family 2: the Marrows, a lawman's kin gone sour on outlaws. Events: camp cleared (needs the zones lane to add
-- participants, Q0a, before it can credit a player), pelt sold, talk steps. Original content.
return {
    id = 'family_marrow', kind = 'line', title = 'Marrow\'s Debt: Smoke on the Ridge',
    giver = 'npc_marrow', region_id = 'heartlands',
    steps = {
        { on = 'fh:zones:camp_cleared', where = { region_id = { optional = true, eq = 'heartlands' } },
            text = 'Clear an outlaw camp.' },
        { on = 'fh:hunting:pelt_sold', count = 2, text = 'Sell two pelts to fund the burying.' },
        { talk = { npc = 'npc_marrow', lines = {
            'Quiet ridge tonight. First time in years.',
            'Badge says I cannot pay a bounty. This is just a thank you.',
        } }, text = 'Tell Sheriff Marrow it is done.' },
    },
    rewards = { money = 60, rep = { region_id = 'heartlands', delta = 8 },
        outfit = { male = 'quest_marrow_male', female = 'quest_marrow_female' } },
}
