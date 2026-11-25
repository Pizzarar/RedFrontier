-- Run from repo root: `lua spec/cargo_ui_spec.lua` (or via tools/run-specs.py).
-- fh_cargo/server/ui.lua: relayed wagonyard handlers (src from relay, refusals, error codes/detail, refresh, guards).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case, eq = T.it, T.eq
local UI = dofile(here .. '../server/resources/[fh]/fh_cargo/server/ui.lua')

local function rig(o)
    o = o or {}
    local r = { calls = {}, sent = {}, notes = {}, atPost = o.atPost ~= false, throttled = o.throttled == true,
        res = o.res or {} }
    local function menuData()
        if not r.atPost then return nil, 'fh_not_at_post' end
        return {
            post = { id = 'valentine_post', label = 'Valentine Trade Post', region = 'heartlands' },
            live = r.live,
            tiers = {
                { key = 't1', label = 'Cart', price = 150, owned = true },
                { key = 't2', label = 'Wagon', price = 600, owned = false },
            },
        }
    end
    local function rec(name)
        return function(...)
            r.calls[#r.calls + 1] = { name, ... }
            local custom = r.res[name]
            if custom then return custom[1], custom[2], custom[3] end
            if not r.atPost then return false, 'fh_not_at_post' end
            return true, { tier = select(2, ...) or 't1' }
        end
    end
    r.ui = UI.new({
        menu      = function(src) r.calls[#r.calls + 1] = { 'menu', src } return menuData() end,
        buy       = rec('buy'),
        call      = rec('call'),
        stow      = rec('stow'),
        throttled = function() return r.throttled end,
        open      = function(src, screen, data) r.sent[#r.sent + 1] = { 'open', src, screen, data } end,
        update    = function(src, screen, data) r.sent[#r.sent + 1] = { 'update', src, screen, data } end,
        notify    = function(src, text) r.notes[#r.notes + 1] = { src, text } end,
    })
    return r
end

local function ev(action, payload, src, screen)
    return { src = src == nil and 7 or src, screen = screen or 'wagonyard', action = action, payload = payload or {} }
end

case('open: opens wagonyard at a post; not-at-post notifies and opens nothing', function()
    local r = rig()
    eq(true, r.ui.open(7))
    eq(1, #r.sent); eq('open', r.sent[1][1]); eq(7, r.sent[1][2]); eq('wagonyard', r.sent[1][3])
    eq('Valentine Trade Post', r.sent[1][4].post.label)

    local away = rig({ atPost = false })
    local ok, err = away.ui.open(7)
    eq(false, ok); eq('fh_not_at_post', err)
    eq(0, #away.sent); eq(1, #away.notes); eq('Stand at a trade post first.', away.notes[1][2])
end)

case('buy / call / stow: uses relay ev.src (ignores payload src/coords/price/region) and pushes fresh data', function()
    local r = rig()
    r.ui.onBuy(ev('buy', { tier = 't2', src = 999, price = 0, region = 'evil', coords = { x = 0 } }, 7))
    eq('buy', r.calls[1][1]); eq(7, r.calls[1][2]); eq('t2', r.calls[1][3]); eq(3, #r.calls[1])
    eq('menu', r.calls[2][1]); eq(7, r.calls[2][2])
    eq('update', r.sent[1][1]); eq('wagonyard', r.sent[1][3])
    eq('ok', r.sent[1][4].notice_kind); eq('Wagon bought.', r.sent[1][4].notice)
    eq(2, #r.sent[1][4].tiers)

    r.ui.onCall(ev('call', { tier = 't1', coords = { x = 1 } }, 7))
    eq('Wagon on its way.', r.sent[2][4].notice); eq('ok', r.sent[2][4].notice_kind)

    r.ui.onStow(ev('stow', { tier = 't1', coords = { x = 1 } }, 7))
    eq('stow', r.calls[#r.calls - 1][1]); eq(2, #r.calls[#r.calls - 1])
    eq('Wagon stowed. Cargo kept.', r.sent[3][4].notice); eq('ok', r.sent[3][4].notice_kind)
end)

case('refusals pass error codes and details through unchanged with exact MSG text', function()
    local cases = {
        { 'buy',  { false, 'fh_locked' },                   'You have not earned that wagon yet.',         'fh_locked',        nil },
        { 'buy',  { false, 'fh_already_owned', 'refunded' }, 'You already own that wagon.',                'fh_already_owned', 'refunded' },
        { 'call', { false, 'fh_wagon_live', 't1' },         'You already have a wagon out. Stow it first.', 'fh_wagon_live',   't1' },
        { 'stow', { false, 'fh_wagon_far' },                'Your wagon is too far from the post.',        'fh_wagon_far',     nil },
    }
    for _, c in ipairs(cases) do
        local r = rig({ res = { [c[1]] = c[2] } })
        if c[1] == 'buy' then r.ui.onBuy(ev('buy', { tier = 't1' }))
        elseif c[1] == 'call' then r.ui.onCall(ev('call', { tier = 't2' }))
        else r.ui.onStow(ev('stow', {})) end
        local d = r.sent[1][4]
        eq('err', d.notice_kind, c[2][2])
        eq(c[3], d.notice, c[2][2])
        eq(c[4], d.err, c[2][2])
        eq(c[5], d.detail, c[2][2])
    end
end)

case('away from a post: forced buy/call notifies in chat and sends no fh:ui:update', function()
    local away = rig({ atPost = false })
    away.ui.onBuy(ev('buy', { tier = 't1' }, 7))
    away.ui.onCall(ev('call', { tier = 't1' }, 7))
    eq(0, #away.sent)
    eq(2, #away.notes)
    eq(7, away.notes[1][1]); eq('Stand at a trade post first.', away.notes[1][2])
    eq(7, away.notes[2][1]); eq('Stand at a trade post first.', away.notes[2][2])
end)

case('forged tier: bad string reaches post handler and returns fh_bad_tier; non-string/oversized ignored', function()
    local r = rig({ res = { buy = { false, 'fh_bad_tier' } } })
    r.ui.onBuy(ev('buy', { tier = 't99' }))
    eq('buy', r.calls[1][1]); eq('t99', r.calls[1][3])
    eq('err', r.sent[1][4].notice_kind); eq('fh_bad_tier', r.sent[1][4].err)

    local r2 = rig()
    r2.ui.onBuy(ev('buy', { tier = 123 }))
    r2.ui.onBuy(ev('buy', { tier = '' }))
    r2.ui.onBuy(ev('buy', { tier = string.rep('a', 17) }))
    r2.ui.onCall(ev('call', {}))
    eq(0, #r2.calls); eq(0, #r2.sent)
end)

case('no src, bad src, wrong screen, non-table event and throttle are ignored', function()
    local r = rig()
    r.ui.onBuy({ screen = 'wagonyard', action = 'buy', payload = { tier = 't1' } })
    r.ui.onBuy(ev('buy', { tier = 't1' }, 0))
    r.ui.onBuy(ev('buy', { tier = 't1' }, -1))
    r.ui.onBuy(ev('buy', { tier = 't1' }, '7'))
    r.ui.onBuy(ev('buy', { tier = 't1' }, 7, 'tradepost'))
    r.ui.onCall('not a table')
    r.ui.onStow({ src = 7, screen = 'wagonyard', payload = 'bad' })
    eq(false, (r.ui.open(nil)))
    eq(false, (r.ui.open(0)))
    eq(0, #r.calls); eq(0, #r.sent); eq(0, #r.notes)

    local t = rig({ throttled = true })
    t.ui.onBuy(ev('buy', { tier = 't1' }))
    t.ui.onCall(ev('call', { tier = 't1' }))
    t.ui.onStow(ev('stow', {}))
    eq(false, (t.ui.open(7)))
    eq(0, #t.calls); eq(0, #t.sent)
end)

T.finish()
