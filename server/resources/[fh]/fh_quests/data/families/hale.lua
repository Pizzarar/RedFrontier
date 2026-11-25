-- Family 1: the Hales, homesteaders. Events: homestead claim, a paid sale, talk steps. Original content.
-- The giver's intro lines are in shared/givers.lua (shown before the start offer). Giver position: see client/givers.lua (TODO-verify-in-game).
return {
    id = 'family_hale', kind = 'line', title = 'Hale & Daughters: A Roof Over Your Head',
    giver = 'npc_hale', region_id = 'heartlands',
    steps = {
        { on = 'fh:homestead:claimed', text = 'Claim a homestead plot.' },
        { on = 'fh:economy:paid', where = { amount = { min = 15 } }, text = 'Earn $15 honest money in one go.' },
        { talk = { npc = 'npc_hale', lines = {
            'Four walls and a payday. You work faster than the mule.',
            'The girls will be telling folks about you. Take this, and stay for supper.',
        } }, text = 'Report back to Ruth Hale.' },
    },
    rewards = { money = 40, rep = { region_id = 'heartlands', delta = 5 },
        outfit = { male = 'quest_hale_male', female = 'quest_hale_female' } },
}
