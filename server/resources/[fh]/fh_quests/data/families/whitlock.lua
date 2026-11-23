-- Family 3: Old Whitlock and the legendary bear. DEPENDS ON @hunting: step 2 waits for
-- fh:hunting:chain_complete with chain_id 'legendary_bear' (plan hunting-01-l8, H4). Until that event exists the
-- line simply parks on that step. Original content.
return {
    id = 'family_whitlock', kind = 'line', title = 'Whitlock\'s Ghost: The Bear of Bear Hollow',
    giver = 'npc_whitlock', region_id = 'heartlands',
    steps = {
        { on = 'fh:hunting:pelt_sold', where = { quality = { min = 2 } }, text = 'Sell a good pelt to prove you can skin.' },
        { on = 'fh:hunting:chain_complete', where = { chain_id = 'legendary_bear' },
            text = 'Finish the Legendary Bear hunt.' },
        { talk = { npc = 'npc_whitlock', lines = {
            'You really did it. Forty winters, and a stranger does it in a season.',
            'Hang that hide where folks can see it. This is for the tellin\'.',
        } }, text = 'Take the news to Whitlock.' },
    },
    rewards = { money = 120, rep = { region_id = 'heartlands', delta = 12 } },
}
