-- Shared prelude for fh_core specs. Each spec loads it with dofile(<its own folder> .. "support/fh_prelude.lua").
-- Sets package.path to fh_core (works with or without .busted's lpath) and, when busted's describe/it are absent
-- (plain `lua spec/x_spec.lua`), installs a tiny runner that uses plain assert. Specs only use assert(cond, msg)
-- and the eq/same helpers below, which behave the same under both.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local root = here .. '../../server/resources/[fh]/fh_core/'
package.path = root .. '?.lua;' .. root .. 'shared/?.lua;' .. package.path

local P = {}

local function dump(v)
    if type(v) ~= 'table' then return tostring(v) end
    local parts = {}
    for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. '=' .. dump(x) end
    table.sort(parts)
    return '{' .. table.concat(parts, ',') .. '}'
end

local function deepEqual(a, b)
    if a == b then return true end
    if type(a) ~= 'table' or type(b) ~= 'table' then return false end
    for k, v in pairs(a) do if not deepEqual(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

function P.eq(expected, actual, msg)
    assert(expected == actual, (msg or 'eq') .. ': expected ' .. dump(expected) .. ', got ' .. dump(actual))
end

function P.same(expected, actual, msg)
    assert(deepEqual(expected, actual), (msg or 'same') .. ': expected ' .. dump(expected) .. ', got ' .. dump(actual))
end

if describe and it then
    P.describe, P.it, P.finish = describe, it, function() end
else
    local count, failures, stack = 0, 0, {}
    P.describe = function(name, fn)
        stack[#stack + 1] = name
        fn()
        stack[#stack] = nil
    end
    P.it = function(name, fn)
        count = count + 1
        local ok, err = pcall(fn)
        if not ok then
            failures = failures + 1
            print('FAIL ' .. table.concat(stack, ' > ') .. ' > ' .. name .. ': ' .. tostring(err))
        end
    end
    P.finish = function()
        print(('%d tests, %d failures'):format(count, failures))
        if failures > 0 then os.exit(1) end
    end
end

return P
