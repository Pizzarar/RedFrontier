-- supply_run offers (quests-02 C1): deliver goods to a trade post by selling them there. Pure Lua.
-- Data: data/regions/<region_id>.lua `supply = { { post, item, amount, money, rep }, ... }`. Verdicts: shared/jobtypes.lua.
-- NOTE: this file reads the FhQuestsJobTypes global directly (not `... or FhQuestsJobTypes`): under FXServer the
-- chunk vararg `...` is a number, so the C0 `... or` form indexes a number and breaks the live server (Red3 fix).
local JT = FhQuestsJobTypes

JT.registerBuilder('supply_run', function(region_id, d)
    local out = {}
    for _, e in ipairs(d.supply or {}) do
        out[#out + 1] = {
            key = ('supply_%s_%s'):format(e.post, e.item),
            title = ('Supply run: %dx %s'):format(e.amount, e.item),
            text = ('Sell %d or more %s at the %s trade post.'):format(e.amount, e.item, e.post),
            on = 'fh:trade:sold',
            -- fh:trade:sold carries { src, region, post, item, amount } (fh_trade server/main.lua:144). The key is
            -- `region` (NOT region_id); the intake resolves src -> citizenid. `post`/`item` must match exactly and at
            -- least `amount` must be sold in one sale.
            where = { post = { eq = e.post }, item = { eq = e.item }, amount = { min = e.amount } },
            rewards = JT.rewards(region_id, e.money, e.rep), region_id = region_id,
            min_tier = JT.minTier(e.min_tier),
        }
    end
    return out
end)
