-- Family 5 (C6, West Elizabeth): the Ashbys, a cattle family on the open plains. Wolves at the calving ground and
-- rustlers in the grass. Events: pelt skinned (wolf or coyote), camp cleared in great_plains, a good pelt sold, talk.
-- Original content. Giver intro lines are in shared/givers.lua; position TODO-verify-in-game.
return {
    id = 'family_ashby', kind = 'line', title = 'Ashby Range: The Long Grass',
    giver = 'npc_ashby', region_id = 'great_plains',
    steps = {
        { on = 'fh:hunting:pelt_skinned', where = { animal = { any = { 'wolf', 'coyote' } } },
            text = 'Skin a wolf or coyote off the calving ground.' },
        { on = 'fh:zones:camp_cleared', where = { region_id = 'great_plains' },
            text = 'Clear the rustlers\' camp out on the plains.' },
        { on = 'fh:hunting:pelt_sold', where = { quality = { min = 2 } },
            text = 'Sell a good pelt to cover the hands\' wages.' },
        { talk = { npc = 'npc_ashby', lines = {
            'Counted the herd at sundown. Every head accounted for.',
            'My husband built this range on a handshake. Here is mine, and a little more.',
        } }, text = 'Ride back and tell June Ashby.' },
    },
    rewards = { money = 75, rep = { region_id = 'great_plains', delta = 8 } },
}
