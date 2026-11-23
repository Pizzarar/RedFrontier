-- Run from repo root: `lua spec/crafting_apothecary_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local base = here .. '../server/resources/[fh]/fh_crafting/'
local cfg = dofile(base .. 'config.lua')
local R = dofile(base .. 'shared/craft_rules.lua')
local A = dofile(base .. 'server/apothecary.lua')

-- Builds deps with call logs and an event order. opts: applyOk, applyThrows, removeOk, giveOk, noRemove, noGive, held
local function mk(o)
    o = o or {}
    local log = { apply = {}, remove = {}, give = {}, order = {} }
    local d = {
        tonicFor = function(item) return R.tonicFor(item, cfg) end,
        apply = function(src, id, mag, dur)
            log.apply[#log.apply + 1] = { src, id, mag, dur }; log.order[#log.order + 1] = 'apply'
            if o.applyThrows then error('boom') end
            if o.applyOk == false then return false, 'unknown_buff' end
            return true, { magnitude = mag, expires_at = 99 }
        end,
        count = function() return o.held == nil and 1 or o.held end,
    }
    if not o.noRemove then
        d.remove = function(src, item, amount)
            log.remove[#log.remove + 1] = { src, item, amount }; log.order[#log.order + 1] = 'remove'
            if o.removeOk == false then return false, 'fh_not_registrable' end
            return true
        end
    end
    if not o.noGive then
        d.give = function(src, item, amount)
            log.give[#log.give + 1] = { src, item, amount }; log.order[#log.order + 1] = 'give'
            if o.giveOk == false then return false, 'fh_not_registrable' end
            return true
        end
    end
    return d, log
end

describe('apothecary: success', function()
    it('removes one tonic first, then applies the buff, no refund', function()
        local d, log = mk()
        local r = A.use(d, 7, 'tonic_vigor')
        eq(true, r.ok); eq(true, r.consumed)
        same({ { 7, 'tonic_vigor', 1.15, 600 } }, log.apply)
        same({ { 7, 'tonic_vigor', 1 } }, log.remove)
        same({ 'remove', 'apply' }, log.order)
    end)
    it('tonic_steady uses its own magnitude and duration', function()
        local d, log = mk()
        A.use(d, 1, 'tonic_steady')
        same({ { 1, 'tonic_steady', 1.10, 300 } }, log.apply)
    end)
end)

describe('apothecary: remove fails -> no buff', function()
    it('remove returns false: remove_failed, apply and give never called', function()
        local d, log = mk({ removeOk = false })
        local r = A.use(d, 7, 'tonic_vigor')
        eq(false, r.ok); eq(false, r.consumed); eq('remove_failed', r.reason); eq('fh_not_registrable', r.detail)
        eq(0, #log.apply); eq(0, #log.give)
    end)
    it('a throwing remover is contained and applies nothing', function()
        local d, log = mk()
        d.remove = function() error('x') end
        local r = A.use(d, 7, 'tonic_vigor')
        eq('remove_failed', r.reason); eq(0, #log.apply); eq(0, #log.give)
    end)
end)

describe('apothecary: apply error -> refunded', function()
    it('apply returns false: tonic given back, buff_failed', function()
        local d, log = mk({ applyOk = false })
        local r = A.use(d, 7, 'tonic_vigor')
        eq(false, r.ok); eq(false, r.consumed); eq('buff_failed', r.reason); eq('unknown_buff', r.detail)
        same({ { 7, 'tonic_vigor', 1 } }, log.give)
        same({ 'remove', 'apply', 'give' }, log.order)
    end)
    it('apply throws: same, refunded, no crash', function()
        local d, log = mk({ applyThrows = true })
        local r = A.use(d, 7, 'tonic_vigor')
        eq('buff_failed', r.reason); eq(false, r.consumed); eq(1, #log.give)
    end)
    it('message tells the player it was returned', function()
        local d = mk({ applyOk = false })
        local msg, kind = A.message(A.use(d, 7, 'tonic_vigor'))
        eq(A.MESSAGES.buff_failed, msg); eq('error', kind)
    end)
end)

describe('apothecary: refund fails -> logged, no buff', function()
    it('apply error + give fails: refund_failed, consumed=true, detail carries both, one apply only', function()
        local d, log = mk({ applyOk = false, giveOk = false })
        local r = A.use(d, 7, 'tonic_vigor')
        eq(false, r.ok); eq(true, r.consumed); eq('refund_failed', r.reason)
        assert(r.detail:find('unknown_buff', 1, true) and r.detail:find('fh_not_registrable', 1, true), r.detail)
        eq(1, #log.apply)
    end)
    it('a throwing giver is contained', function()
        local d = mk({ applyThrows = true })
        d.give = function() error('g') end
        eq('refund_failed', A.use(d, 7, 'tonic_vigor').reason)
    end)
end)

describe('apothecary: refusals touch nothing', function()
    it('unknown tonic / non-string', function()
        local d, log = mk()
        eq('unknown_tonic', A.use(d, 7, 'bread').reason)
        eq('unknown_tonic', A.use(d, 7, nil).reason)
        eq(0, #log.order)
    end)
    it('missing item', function()
        local d, log = mk({ held = 0 })
        eq('missing_item', A.use(d, 7, 'tonic_vigor').reason); eq(0, #log.order)
    end)
    it('no remover -> no_remove', function()
        local d, log = mk({ noRemove = true })
        eq('no_remove', A.use(d, 7, 'tonic_vigor').reason); eq(0, #log.order)
    end)
    it('no giver -> no_remove (cannot refund, so never remove)', function()
        local d, log = mk({ noGive = true })
        eq('no_remove', A.use(d, 7, 'tonic_vigor').reason); eq(0, #log.order)
    end)
    it('count check is optional', function()
        local d, log = mk()
        d.count = nil
        eq(true, A.use(d, 7, 'tonic_vigor').consumed); eq(1, #log.remove)
    end)
end)

T.finish()
