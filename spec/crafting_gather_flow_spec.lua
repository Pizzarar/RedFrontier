-- Run from repo root: `lua spec/crafting_gather_flow_spec.lua` (or via tools/run-specs.py).
-- C9b server gather orchestration (FhGather.pick): unknown patch -> reach -> regrowing -> yield -> carried add ->
-- stamp the cooldown only on a successful add. Pure via injected deps; no natives are touched.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local base = here .. '../server/resources/[fh]/fh_crafting/'
local R = dofile(base .. 'shared/gather_rules.lua')
dofile(base .. 'server/gather.lua') -- FhGather (pure pick; native/exports references are lazy, not run here)

local patch = { id = 'p', herb = 'herb_oregano', coords = { x = 0, y = 0, z = 0 }, yield = { 1, 2 }, respawnSeconds = 900 }

local function fakeDeps(opts)
    opts = opts or {}
    local calls = {}
    local state = { last = opts.lastPicked }
    local deps = {
        patch = function(id)
            if opts.patches ~= nil then return opts.patches[id] end
            return patch
        end,
        playerCoords = function(src) return opts.coords or { x = 0, y = 0, z = 0 } end,
        canPick = opts.canPick or R.canPick,
        rollYield = opts.rollYield or function() return 1 end,
        addItem = function(ref, herb, amount)
            calls[#calls + 1] = { 'add', ref, herb, amount }
            if opts.addRefused then return false, opts.addRefused end
            return true
        end,
        stamp = function(patchId, now)
            calls[#calls + 1] = { 'stamp', patchId, now }
            state.last = now
        end,
        now = opts.now or function() return 1000 end,
        lastPicked = function(id) return state.last end,
    }
    return deps, calls, state
end

describe('gather flow: success', function()
    it('adds to the backpack carried ref, then stamps the cooldown', function()
        local deps, calls = fakeDeps()
        local ok, reason, info = FhGather.pick(deps, 7, 'p')
        eq(true, ok); eq(nil, reason)
        eq('herb_oregano', info.herb); eq(1, info.amount)
        same({ { 'add', { type = 'backpack', id = 7 }, 'herb_oregano', 1 }, { 'stamp', 'p', 1000 } }, calls)
    end)
    it('the rolled amount is what gets added', function()
        local deps, calls = fakeDeps({ rollYield = function() return 2 end })
        local _, _, info = FhGather.pick(deps, 7, 'p')
        eq(2, info.amount)
        eq(2, calls[1][4])
    end)
end)

describe('gather flow: refusals before any grant', function()
    it('unknown patch', function()
        local deps, calls = fakeDeps({ patches = {} })
        local ok, reason = FhGather.pick(deps, 7, 'nope')
        eq(false, ok); eq('fh_unknown_patch', reason); eq(0, #calls)
    end)
    it('too far', function()
        local deps, calls = fakeDeps({ coords = { x = 100, y = 0, z = 0 } })
        local ok, reason = FhGather.pick(deps, 7, 'p')
        eq(false, ok); eq('fh_too_far', reason); eq(0, #calls)
    end)
    it('regrowing (inside the shared cooldown)', function()
        local deps, calls = fakeDeps({ now = function() return 500 end, lastPicked = 100 }) -- 500 < 100 + 900
        local ok, reason = FhGather.pick(deps, 7, 'p')
        eq(false, ok); eq('fh_regrowing', reason); eq(0, #calls)
    end)
end)

describe('gather flow: refused add does not stamp', function()
    it('full/overweight add leaves the patch off cooldown', function()
        local deps, calls, state = fakeDeps({ addRefused = 'fh_refused' })
        local ok, reason = FhGather.pick(deps, 7, 'p')
        eq(false, ok); eq('fh_refused', reason)
        eq(nil, state.last)
        same({ { 'add', { type = 'backpack', id = 7 }, 'herb_oregano', 1 } }, calls)
    end)
end)

T.finish()
