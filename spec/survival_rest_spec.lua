-- Run from repo root: `lua spec/survival_rest_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
package.path = here .. '../server/resources/[fh]/fh_survival/shared/?.lua;' .. package.path
local case = T.it
local N = require('needs')
local R = require('rest')

case('missing exports: no bed, comfort 0, bedroll still 1.0', function()
    local info = R.resolve(false, 'boom', false, 'boom')
    assert(info.bed == false and info.comfort == 0)
    local m, err = R.magnitude(N, 'bed', info, 0.01, 1.20)
    assert(m == false and err == 'no_bed')
    assert(R.magnitude(N, 'bedroll', info, 0.01, 1.20) == 1.0)
end)

case('bed export present but getComfort missing: bed with comfort 0 = 1.0', function()
    local info = R.resolve(true, true, false, 'boom')
    assert(info.bed == true and info.comfort == 0)
    assert(R.magnitude(N, 'bed', info, 0.01, 1.20) == 1.0)
end)

case('not near a bed (false/nil/non-true) is no bed', function()
    assert(R.resolve(true, false, true, 50).bed == false)
    assert(R.resolve(true, nil, true, 50).bed == false)
    assert(R.resolve(true, 'yes', true, 50).comfort == 0)
end)

case('present exports: magnitude from comfort, capped', function()
    local info = R.resolve(true, true, true, 10)
    assert(info.bed and info.comfort == 10)
    local m = R.magnitude(N, 'bed', info, 0.01, 1.20)
    assert(math.abs(m - 1.10) < 1e-9)
    local big = R.resolve(true, true, true, 500)
    assert(R.magnitude(N, 'bed', big, 0.01, 1.20) == 1.20, 'capped at 1.20')
end)

case('bad comfort values count as 0; bad kind refused', function()
    assert(R.resolve(true, true, true, -5).comfort == 0)
    assert(R.resolve(true, true, true, 0 / 0).comfort == 0)
    assert(R.resolve(true, true, true, 'x').comfort == 0)
    local m, err = R.magnitude(N, 'couch', R.resolve(true, true, true, 5), 0.01, 1.20)
    assert(m == false and err == 'bad_kind')
end)

T.finish()
