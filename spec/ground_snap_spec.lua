-- Run from repo root: `python tools/run-specs.py spec/ground_snap_spec.lua`.
-- world-01 (block D): the pure ground-snap decision logic (retry / fallback / once-per-id logging). No natives.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local G = dofile(here .. '../server/resources/[fh]/fh_core/shared/ground_snap.lua')

case('usable: truthy found + finite number only', function()
    T.eq(true, G.usable(true, 105.0))
    T.eq(true, G.usable(1, 0.0)) -- truthy found (not strictly boolean)
    T.eq(false, G.usable(false, 105.0))
    T.eq(false, G.usable(nil, 105.0))
    T.eq(false, G.usable(true, nil))
    T.eq(false, G.usable(true, 'high'))
    T.eq(false, G.usable(true, 0 / 0))
end)

case('resolve: groundZ on success, hint on failure', function()
    T.eq(105.0, G.resolve(true, 105.0, 118.0))
    T.eq(118.0, G.resolve(false, nil, 118.0))
    T.eq(118.0, G.resolve(true, 0 / 0, 118.0))
    T.eq(118.0, G.resolve(true, nil, 118.0))
end)

case('shouldRetry: keeps probing until max attempts or the deadline', function()
    T.eq(true, G.shouldRetry(0, 40, 0, 2000))  -- before the first probe
    T.eq(true, G.shouldRetry(1, 40, 0, 2000))
    T.eq(true, G.shouldRetry(39, 40, 0, 2000))
    T.eq(false, G.shouldRetry(40, 40, 0, 2000)) -- attempt == max
    T.eq(false, G.shouldRetry(41, 40, 0, 2000))
    T.eq(false, G.shouldRetry(1, 40, 2000, 2000)) -- now >= deadline
    T.eq(false, G.shouldRetry(nil, 40, 0, 2000))
    T.eq(true, G.shouldRetry(1, nil, 0, nil)) -- defaults to MAX_RETRIES, no deadline
    T.eq(true, G.shouldRetry(39, nil, 0, nil))
    T.eq(false, G.shouldRetry(40, nil, 0, nil))
end)

case('markUnsnapped: logs each id exactly once until reset', function()
    G.reset()
    T.eq(true, G.markUnsnapped('heartlands_01'))
    T.eq(false, G.markUnsnapped('heartlands_01'))
    T.eq(true, G.markUnsnapped('heartlands_02'))
    T.eq(false, G.markUnsnapped('heartlands_02'))
    T.eq(false, G.markUnsnapped(nil))
    T.eq(false, G.markUnsnapped(''))
    G.reset()
    T.eq(true, G.markUnsnapped('heartlands_01'))
end)

T.finish()
