-- Run from repo root: `lua spec/survival_rest_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
package.path = here .. '../server/resources/[fh]/fh_survival/shared/?.lua;' .. package.path
local case = T.it
local N = require('needs')
local R = require('rest')

case('not near a bed: no bed, comfort 0, bedroll still 1.0', function()
    local info = R.resolve(false, 0)
    assert(info.bed == false and info.comfort == 0)
    local m, err = R.magnitude(N, 'bed', info, 0.01, 1.20)
    assert(m == false and err == 'no_bed')
    assert(R.magnitude(N, 'bedroll', info, 0.01, 1.20) == 1.0)
end)

case('near a bed but no comfort: bed with comfort 0 = 1.0', function()
    local info = R.resolve(true, 0)
    assert(info.bed == true and info.comfort == 0)
    assert(R.magnitude(N, 'bed', info, 0.01, 1.20) == 1.0)
end)

case('not near a bed (false/nil/non-true) is no bed', function()
    assert(R.resolve(false, 50).bed == false)
    assert(R.resolve(nil, 50).bed == false)
    assert(R.resolve('yes', 50).comfort == 0)
end)

case('near a bed: magnitude from comfort, capped', function()
    local info = R.resolve(true, 10)
    assert(info.bed and info.comfort == 10)
    local m = R.magnitude(N, 'bed', info, 0.01, 1.20)
    assert(math.abs(m - 1.10) < 1e-9)
    local big = R.resolve(true, 500)
    assert(R.magnitude(N, 'bed', big, 0.01, 1.20) == 1.20, 'capped at 1.20')
end)

case('bad comfort values count as 0; bad kind refused', function()
    assert(R.resolve(true, -5).comfort == 0)
    assert(R.resolve(true, 0 / 0).comfort == 0)
    assert(R.resolve(true, 'x').comfort == 0)
    local m, err = R.magnitude(N, 'couch', R.resolve(true, 5), 0.01, 1.20)
    assert(m == false and err == 'bad_kind')
end)

T.finish()
