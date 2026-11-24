-- Run from repo root: `lua spec/crafting_gather_spec.lua` (or via tools/run-specs.py).
-- C9a pure herb-gathering rules: canPick (reach/regrowth/unknown), rollYield (injected rng), and config validation.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local base = here .. '../server/resources/[fh]/fh_crafting/'
local cfg = dofile(base .. 'config.lua')
local R = dofile(base .. 'shared/gather_rules.lua')

-- Known items = fh_crafting-registered (config.items) + rsg-core items not re-registered (same as the recipes spec).
local EXISTING = {
    resource_gunpowder = true, ammo_box_revolver = true, ammo_box_rifle = true,
    herb_american_ginseng = true, herb_wild_mint = true, herb_oregano = true, herb_red_sage = true,
}
local known = {}
for name in pairs(cfg.items or {}) do known[name] = true end
for name in pairs(EXISTING) do known[name] = true end

local patch = { id = 'p', herb = 'herb_oregano', coords = { x = 0, y = 0, z = 0 }, yield = { 1, 2 }, respawnSeconds = 900 }

describe('gather: canPick', function()
    it('ok in range and not on cooldown', function()
        eq(true, (R.canPick(patch, { x = 0, y = 0, z = 3 }, 100, nil)))
    end)
    it('vector3 and table coords read the same (x,y,z via pcall)', function()
        eq(true, (R.canPick(patch, { x = 1, y = 1, z = 1 }, 100, nil)))
        eq(true, (R.canPick(patch, { x = -2, y = 2, z = -1 }, 100, nil)))
    end)
    it('too far', function()
        local ok, why = R.canPick(patch, { x = 10, y = 0, z = 0 }, 100, nil)
        eq(false, ok); eq('fh_too_far', why)
    end)
    it('missing or invalid player coords = too far', function()
        local ok, why = R.canPick(patch, nil, 100, nil)
        eq(false, ok); eq('fh_too_far', why)
        ok, why = R.canPick(patch, 5, 100, nil)
        eq(false, ok); eq('fh_too_far', why)
        ok, why = R.canPick(patch, { x = 0 / 0, y = 0, z = 0 }, 100, nil)
        eq(false, ok); eq('fh_too_far', why)
    end)
    it('regrowing inside respawnSeconds', function()
        local ok, why = R.canPick(patch, { x = 0, y = 0, z = 0 }, 100, 50) -- 100 < 50 + 900
        eq(false, ok); eq('fh_regrowing', why)
    end)
    it('pickable again once respawnSeconds has passed', function()
        eq(true, (R.canPick(patch, { x = 0, y = 0, z = 0 }, 950, 50))) -- 950 >= 50 + 900
    end)
    it('unknown patch', function()
        local ok, why = R.canPick(nil, { x = 0, y = 0, z = 0 }, 100, nil)
        eq(false, ok); eq('fh_unknown_patch', why)
        ok, why = R.canPick({ id = 'x', herb = 'herb_oregano' }, { x = 0, y = 0, z = 0 }, 100, nil) -- no coords
        eq(false, ok); eq('fh_unknown_patch', why)
    end)
end)

describe('gather: rollYield', function()
    it('rolls within the patch yield using the injected rng', function()
        eq(12, R.rollYield(patch, function(lo, hi) return lo * 10 + hi end)) -- rng(1, 2)
    end)
    it('a fixed rng stays deterministic', function()
        eq(1, R.rollYield(patch, function() return 1 end))
        eq(2, R.rollYield(patch, function() return 2 end))
    end)
    it('missing or bad yield reads as {1, 2}', function()
        local function bounds(p)
            local got
            R.rollYield(p, function(lo, hi) got = { lo, hi }; return lo end)
            return got
        end
        same({ 1, 2 }, bounds({ yield = nil }))    -- missing -> default {1, 2}
        same({ 1, 2 }, bounds({}))                 -- empty table -> default {1, 2}
        same({ 5, 5 }, bounds({ yield = { 5 } }))  -- partial: hi defaults 2 then clamps to lo
        same({ 1, 1 }, bounds({ yield = { 0, -1 } })) -- bad: clamped to {1, 1}
    end)
end)

describe('gather: validatePatches', function()
    it('ships 8 patches, 2 per herb, all valid', function()
        local ok, errs = R.validatePatches(cfg.herbPatches, known)
        eq(true, ok, table.concat(errs or {}, '; '))
        eq(8, #cfg.herbPatches)
        local per = {}
        for _, p in ipairs(cfg.herbPatches) do per[p.herb] = (per[p.herb] or 0) + 1 end
        for _, herb in ipairs({ 'herb_american_ginseng', 'herb_oregano', 'herb_red_sage', 'herb_wild_mint' }) do
            eq(2, per[herb], herb)
        end
    end)
    it('every patch herb is a known item', function()
        local ok, errs = R.validatePatches(cfg.herbPatches, known)
        eq(true, ok, table.concat(errs or {}, '; '))
    end)
    it('rejects an unknown herb', function()
        local bad = { id = 'x', herb = 'nope', coords = { x = 1, y = 2, z = 3 }, yield = { 1, 2 }, respawnSeconds = 900 }
        local ok, errs = R.validatePatches({ bad }, known)
        eq(false, ok)
        eq(true, table.concat(errs, '; '):find('unknown herb nope', 1, true) ~= nil)
    end)
    it('rejects missing coords, duplicate ids, bad yield, bad respawn', function()
        local _, e1 = R.validatePatches({ { id = 'a', herb = 'herb_oregano', yield = { 1, 2 }, respawnSeconds = 900 } }, known)
        eq(true, table.concat(e1, '; '):find('coords', 1, true) ~= nil)
        local dup = {
            { id = 'a', herb = 'herb_oregano', coords = { x = 0, y = 0, z = 0 }, yield = { 1, 2 }, respawnSeconds = 900 },
            { id = 'a', herb = 'herb_wild_mint', coords = { x = 1, y = 1, z = 1 }, yield = { 1, 2 }, respawnSeconds = 900 },
        }
        local _, e2 = R.validatePatches(dup, known)
        eq(true, table.concat(e2, '; '):find('duplicate id', 1, true) ~= nil)
        local _, e3 = R.validatePatches({ { id = 'b', herb = 'herb_oregano', coords = { x = 0, y = 0, z = 0 }, yield = { 2, 1 }, respawnSeconds = 900 } }, known)
        eq(true, table.concat(e3, '; '):find('yield', 1, true) ~= nil)
        local _, e4 = R.validatePatches({ { id = 'c', herb = 'herb_oregano', coords = { x = 0, y = 0, z = 0 }, yield = { 1, 2 }, respawnSeconds = 0 } }, known)
        eq(true, table.concat(e4, '; '):find('respawnSeconds', 1, true) ~= nil)
    end)
    it('rejects an empty or non-list patches', function()
        local ok, errs = R.validatePatches(nil, known)
        eq(false, ok); eq(1, #errs)
        ok, errs = R.validatePatches({}, known)
        eq(false, ok)
    end)
    it('rejects two patches closer than 2x the prompt radius', function()
        local close = {
            { id = 'a', herb = 'herb_oregano', coords = { x = 0, y = 0, z = 0 }, yield = { 1, 2 }, respawnSeconds = 900 },
            { id = 'b', herb = 'herb_wild_mint', coords = { x = 3, y = 0, z = 0 }, yield = { 1, 2 }, respawnSeconds = 900 },
        }
        local ok, errs = R.validatePatches(close, known)
        eq(false, ok)
        eq(true, table.concat(errs, '; '):find('too close', 1, true) ~= nil)
    end)
end)

T.finish()
