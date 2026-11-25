-- Run from repo root: `lua spec/hunting_trappers_spec.lua` (or via tools/run-specs.py).
-- hunting-03 C1: one trapper per region (data/legendaries/<region>.lua `trapper`). Sales pay and emit pelt_sold with the
-- region_id of the trapper the player stands at; a disabled region's trapper refuses fh_region_closed; the rumour is
-- bought at its region's trapper only; the loader validates the new field.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local base = here .. '../server/resources/[fh]/fh_hunting/'
local cfg = dofile(base .. 'config.lua')
local A = dofile(base .. 'shared/animals.lua')
local P = dofile(base .. 'shared/price.lua')
FhHuntingWagon = dofile(base .. 'shared/wagon.lua')
local S = dofile(base .. 'shared/sell.lua')
local L = dofile(base .. 'shared/legendaries.lua')
local Chain = dofile(base .. 'shared/chain.lua')

local SRC, CID = 7, 'CID123'
local BAG = { type = 'saddlebag', id = 'fh:saddle:' .. CID }
local SCARLETT, HEART = 'scarlett_meadows', 'heartlands'

local function enabledSet(set) return function(rid) return set[rid] == true end end

local function world(player, enabled)
    local W = { player = player, items = { [1] = { name = 'pelt_deer', amount = 1, info = { stars = 3 } } },
        pays = {}, events = {}, removes = 0 }
    W.deps = {
        citizenid = function(src) return src == SRC and CID or nil end,
        playerCoords = function() return W.player end,
        refFor = function(kind) if kind == 'saddlebag' then return BAG end end,
        snapshot = function(ref) if ref == BAG then return W.items end end,
        removeItem = function(_, name, _, slot)
            W.removes = W.removes + 1
            if not W.items[slot] then return false end
            W.items[slot] = nil
            return true
        end,
        addItem = function() return true end,
        pay = function(src, amount, reason, region)
            W.pays[#W.pays + 1] = { src = src, amount = amount, reason = reason, region = region }
            return true
        end,
        emit = function(name, payload) W.events[#W.events + 1] = { name = name, payload = payload } end,
    }
    W.t = S.new({ cfg = cfg, animals = A, price = P, deps = W.deps, trappers = S.trappers(cfg, L),
        isEnabled = enabledSet(enabled) })
    W.sell = function() return W.t.sell(SRC, { container = 'saddlebag', slot = 1, item = 'pelt_deer' }) end
    return W
end

local function at(rid)
    local c = L.byRegion[rid].trapper.coords
    return { x = c.x + 1.0, y = c.y, z = c.z }
end

describe('hunting trappers: data + loader', function()
    it('all 15 data files carry a valid trapper; rumour coords follow it', function()
        eq(15, #L.list)
        for _, e in ipairs(L.list) do
            assert(type(e.trapper) == 'table' and e.trapper.label ~= '', e.region_id .. ': no trapper')
            same(e.trapper.coords, e.rumour.coords, e.region_id)
        end
    end)
    it('heartlands trapper equals the config.lua fallback values', function()
        same(cfg.Trapper.coords, L.byRegion[HEART].trapper.coords)
        eq(cfg.Trapper.label, L.byRegion[HEART].trapper.label)
    end)
    it('the loader rejects a malformed trapper and accepts none', function()
        local raw = dofile(base .. 'data/legendaries/' .. SCARLETT .. '.lua')
        local function with(tr) local r = {}; for k, v in pairs(raw) do r[k] = v end; r.trapper = tr; return r end
        local bad = {
            'x', { coords = raw.trapper.coords }, { label = '', coords = raw.trapper.coords },
            { label = 'T' }, { label = 'T', coords = { x = 0, y = 0 } }, { label = 'T', coords = { x = 0, y = 0, z = 0 / 0 } },
        }
        for i, tr in ipairs(bad) do
            local e, err = L.validate(with(tr), SCARLETT)
            eq(nil, e, 'case ' .. i)
            assert(err:match('trapper'), 'case ' .. i .. ': ' .. tostring(err))
        end
        local e = L.validate(with(nil), SCARLETT)
        assert(e and e.trapper == nil)
    end)
    it('build: missing/malformed trapper warns for a disabled region, errors (drops the entry) for an enabled one', function()
        local raw = dofile(base .. 'data/legendaries/' .. SCARLETT .. '.lua')
        local function with(tr) local r = {}; for k, v in pairs(raw) do r[k] = v end; r.trapper = tr; return r end
        local real = L.isEnabled
        local function run(enabled, tr)
            L.isEnabled = function() return enabled end
            local reg = L.build({ [SCARLETT] = with(tr) }, { SCARLETT })
            L.isEnabled = real
            return reg
        end
        local build = run
        for _, tr in ipairs({ 'x', { label = 'T' }, { label = 'T', coords = { x = 0, y = 0 } } }) do
            local d = build(false, tr)
            assert(d.byRegion[SCARLETT] and d.byRegion[SCARLETT].trapper == nil, 'disabled keeps entry')
            assert(d.warnings[1] and d.warnings[1]:match('bad trapper') and not d.warnings[1]:match('error'), tostring(d.warnings[1]))
            local en = build(true, tr)
            eq(nil, en.byRegion[SCARLETT])
            assert(en.warnings[1]:match('error: bad trapper'), tostring(en.warnings[1]))
        end
        local d = build(false, nil)
        assert(d.byRegion[SCARLETT] and d.warnings[1]:match('missing trapper') and not d.warnings[1]:match('error'))
        local en = build(true, nil)
        eq(nil, en.byRegion[SCARLETT])
        assert(en.warnings[1]:match('error: missing trapper'))
        local ok = build(true, raw.trapper)
        assert(ok.byRegion[SCARLETT] and #ok.warnings == 0)
    end)
    it('S.trappers lists every registry trapper and falls back to config for heartlands', function()
        local list = S.trappers(cfg, L)
        eq(15, #list)
        local none = S.trappers(cfg, { list = {} })
        same({ { region_id = HEART, label = cfg.Trapper.label, coords = cfg.Trapper.coords } }, none)
    end)
end)

describe('hunting trappers: sell uses the trapper the player stands at', function()
    it('a scarlett_meadows sale pays and emits region_id scarlett_meadows', function()
        local W = world(at(SCARLETT), { [SCARLETT] = true, [HEART] = true })
        local ok = W.sell()
        eq(true, ok)
        eq(SCARLETT, W.pays[1].region)
        eq('fh:hunting:pelt_sold', W.events[1].name)
        eq(SCARLETT, W.events[1].payload.region_id)
        local keys = {}
        for key in pairs(W.events[1].payload) do keys[#keys + 1] = key end
        table.sort(keys)
        same({ 'animal', 'citizenid', 'item_id', 'price', 'quality', 'region_id', 'size_class' }, keys) -- shape unchanged
    end)
    it('heartlands unchanged: the config position sells with region_id heartlands', function()
        local W = world({ x = cfg.Trapper.coords.x, y = cfg.Trapper.coords.y, z = cfg.Trapper.coords.z },
            { [HEART] = true })
        eq(true, W.sell())
        eq(HEART, W.pays[1].region)
        eq(HEART, W.events[1].payload.region_id)
    end)
    it('a disabled region refuses fh_region_closed, takes and pays nothing', function()
        local W = world(at(SCARLETT), { [HEART] = true })
        local ok, err = W.sell()
        eq(false, ok); eq('fh_region_closed', err)
        eq(0, W.removes); eq(0, #W.pays); eq(0, #W.events)
        local rows, lerr = W.t.list(SRC)
        eq(nil, rows); eq('fh_region_closed', lerr)
        eq(nil, W.t.at(SRC))
    end)
    it('out of range of every trapper refuses fh_too_far', function()
        local W = world({ x = 0.0, y = 0.0, z = 0.0 }, { [SCARLETT] = true, [HEART] = true })
        local ok, err = W.sell()
        eq(false, ok); eq('fh_too_far', err)
        eq(0, #W.pays)
    end)
    it('the trapper label titles the screen data', function()
        local W = world(at(SCARLETT), { [SCARLETT] = true })
        eq('Scarlett Meadows Trapper', W.t.at(SRC).label)
        eq('Scarlett Meadows Trapper', S.screenData(cfg, {}, nil, nil, W.t.at(SRC).label).title)
    end)
    it('overlapping in-range trappers: the enabled one wins over a disabled one', function()
        local pos = at(SCARLETT)
        local list = { { region_id = 'bayou_nwa', label = 'A', coords = pos },
            { region_id = SCARLETT, label = 'B', coords = { x = pos.x + 0.5, y = pos.y, z = pos.z } } }
        local W = world(pos, { [SCARLETT] = true })
        W.t = S.new({ cfg = cfg, animals = A, price = P, deps = W.deps, trappers = list, isEnabled = enabledSet({ [SCARLETT] = true }) })
        eq(true, W.sell())
        eq(SCARLETT, W.pays[1].region)
    end)
end)

describe('hunting trappers: the rumour is bought at its own trapper', function()
    local function chain()
        local D = { charges = {}, events = {} }
        local c = Chain.new({ cfg = cfg, legendaries = L, isEnabled = function() return true end, deps = {
            load = function() return nil end, save = function() return true end,
            charge = function(src, cid, amount, reason, region)
                D.charges[#D.charges + 1] = { region = region }; return true
            end,
            spawn = function() return 1 end, despawn = function() end,
            emit = function(name, p) D.events[#D.events + 1] = { name = name, payload = p } end } })
        return c, D
    end
    it('at the scarlett_meadows trapper the stag rumour works; at the heartlands trapper it does not', function()
        local stag = L.byRegion[SCARLETT].id
        local c, D = chain()
        local ok, err = c.buyRumour(SRC, CID, L.byRegion[HEART].trapper.coords, stag)
        eq(false, ok); eq('fh_chain_too_far', err)
        ok = c.buyRumour(SRC, CID, L.byRegion[SCARLETT].trapper.coords, stag)
        eq(true, ok)
        eq(SCARLETT, D.charges[1].region)
    end)
    it('the bear rumour is still bought at the heartlands (config) trapper', function()
        local c = chain()
        eq(true, (c.buyRumour(SRC, CID, cfg.Trapper.coords, 'legendary_bear')))
    end)
end)

T.finish()
