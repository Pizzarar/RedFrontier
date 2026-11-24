-- fh_tutorial tuning (guide-02). Pure data: no natives, so the specs can load it.
-- The step bodies live in shared/tutorial.lua (M.STEPS, keyed by id); this file only decides their order.
FhTutorialConfig = {
    -- The intro step order, by stable step id (see shared/tutorial.lua M.STEPS).
    -- Teach needs before they bite: eat/drink early. Home and stash before shopping: claim the plot before the
    -- trade post. Jobs after the first sale proves the money loop. The family giver is the graduation.
    -- Edit this list to reorder. Unknown ids are dropped with a warning; greeting and inventory are mandatory
    -- (a list missing either falls back to the built-in default order).
    order = {
        'greeting',
        'inventory',
        'eat_drink',
        'claim_plot',
        'stash',
        'trade_post',
        'hunt',
        'gunsmith',
        'jobs',
        'cargo',
        'fence',
        'family',
    },
}
