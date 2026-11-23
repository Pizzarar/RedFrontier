-- Run from repo root: `lua spec/crafting_apothecary_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local base = here .. '../server/resources/[fh]/fh_crafting/'
local cfg = dofile(base .. 'config.lua')
local R = dofile(base .. 'shared/craft_rules.lua')
local A = dofile(base .. 'server/apothecary.lua')

-- Builds deps with call logs. opts: applyOk, applyThrows, removeOk, noRemove, held
local function mk(o)
    o = o or {}
    local log = { apply = {}, remove = {} }
    local d = {
        tonicFor = function(item) return R.tonicFor(item, cfg) end,
        apply = function(src, id, mag, dur)
            log.apply[#log.apply + 1] = { src, id, mag, dur }
            if o.applyThrows then error('boom') end
            if o.applyOk == false then return false, 'unknown_buff' end
            return true, { magnitude = mag, expires_at = 99 }
        end,
        count = function() return o.held == nil and 1 or o.held end,
    }
    if not o.noRemove then
        d.remove = function(src, item, amount)
            log.remove[#log.remove + 1] = { src, item, amount }
            if o.removeOk == false then return false, 'fh_not_registrable' end
            return true
        end
    end
    return d, log
end

describe('apothecary: success', function()
    it('applies the buff then consumes one tonic', function()
        local d, log = mk()
        local r = A.use(d, 7, 'tonic_vigor')
        eq(true, r.ok); eq(true, r.consumed)
        same({ { 7, 'tonic_vigor', 1.15, 600 } }, log.apply)
        same({ { 7, 'tonic_vigor', 1 } }, log.remove)
    end)
    it('tonic_steady uses its own magnitude and duration', function()
        local d, log = mk()
        A.use(d, 1, 'tonic_steady')
        same({ { 1, 'tonic_steady', 1.10, 300 } }, log.apply)
    end)
end)

describe('apothecary: apply error keeps the tonic', function()
    it('apply returns false -> not consumed, remove never called', function()
        local d, log = mk({ applyOk = false })
        local r = A.use(d, 7, 'tonic_vigor')
        eq(false, r.ok); eq(false, r.consumed); eq('buff_failed', r.reason); eq('unknown_buff', r.detail)
        eq(0, #log.remove)
    end)
    it('apply throws -> same, no crash', function()
        local d, log = mk({ applyThrows = true })
        local r = A.use(d, 7, 'tonic_vigor')
        eq('buff_failed', r.reason); eq(false, r.consumed); eq(0, #log.remove)
    end)
    it('message tells the player they keep it', function()
        local d = mk({ applyOk = false })
        local msg, kind = A.message(A.use(d, 7, 'tonic_vigor'))
        eq(A.MESSAGES.buff_failed, msg); eq('error', kind)
    end)
end)

describe('apothecary: remove fails after apply', function()
    it('buff stays (no revoke), ok=true, consumed=false, reason remove_failed', function()
        local d, log = mk({ removeOk = false })
        local r = A.use(d, 7, 'tonic_vigor')
        eq(true, r.ok); eq(false, r.consumed); eq('remove_failed', r.reason); eq('fh_not_registrable', r.detail)
        eq(1, #log.apply)
        local _, kind = A.message(r)
        eq('warning', kind)
    end)
    it('a throwing remover is contained', function()
        local d = mk()
        d.remove = function() error('x') end
        local r = A.use(d, 7, 'tonic_vigor')
        eq('remove_failed', r.reason); eq(false, r.consumed)
    end)
end)

describe('apothecary: refusals before apply', function()
    it('unknown tonic / non-string', function()
        local d, log = mk()
        eq('unknown_tonic', A.use(d, 7, 'bread').reason)
        eq('unknown_tonic', A.use(d, 7, nil).reason)
        eq(0, #log.apply)
    end)
    it('missing item', function()
        local d, log = mk({ held = 0 })
        local r = A.use(d, 7, 'tonic_vigor')
        eq('missing_item', r.reason); eq(false, r.ok); eq(0, #log.apply); eq(0, #log.remove)
    end)
    it('no remover -> no_remove and NO free buff', function()
        local d, log = mk({ noRemove = true })
        local r = A.use(d, 7, 'tonic_vigor')
        eq('no_remove', r.reason); eq(false, r.ok); eq(0, #log.apply)
    end)
    it('count check is optional', function()
        local d, log = mk()
        d.count = nil
        eq(true, A.use(d, 7, 'tonic_vigor').consumed); eq(1, #log.remove)
    end)
end)

T.finish()
