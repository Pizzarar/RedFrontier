local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq = T.describe, T.it, T.eq

local Containers = require('containers')

-- spec §4.1 table, plus the B4a choice for drop_bag / fence_stash (pocket + bulky, never cargo)
local MATRIX = {
    equipped    = { pocket = true,  bulky = false, cargo = false },
    backpack    = { pocket = true,  bulky = false, cargo = false },
    saddlebag   = { pocket = true,  bulky = true,  cargo = false },
    wagon       = { pocket = true,  bulky = true,  cargo = true },
    chest       = { pocket = true,  bulky = true,  cargo = true },
    drop_bag    = { pocket = true,  bulky = true,  cargo = false },
    fence_stash = { pocket = true,  bulky = true,  cargo = false },
}

describe('fh_core shared/containers', function()
    describe('size class x container matrix', function()
        for ctype, row in pairs(MATRIX) do
            for class, want in pairs(row) do
                it(ctype .. ' ' .. (want and 'accepts ' or 'refuses ') .. class, function()
                    local ok, reason = Containers.accepts(ctype, class)
                    eq(want, ok, ctype .. '/' .. class)
                    if not want then eq('fh_size_class', reason) end
                end)
            end
        end
        it('covers every declared type', function()
            for _, t in ipairs(Containers.TYPES) do assert(MATRIX[t], 'matrix row missing for ' .. t) end
        end)
        it('refuses an unknown container type', function()
            local ok, reason = Containers.accepts('pocket_dimension', 'pocket')
            eq(false, ok); eq('fh_unknown_container', reason)
        end)
    end)

    describe('coords rule', function()
        it('only carried containers skip coords', function()
            eq(false, Containers.requiresCoords('equipped'))
            eq(false, Containers.requiresCoords('backpack'))
            for _, t in ipairs({ 'saddlebag', 'wagon', 'chest', 'drop_bag', 'fence_stash' }) do
                eq(true, Containers.requiresCoords(t), t)
            end
        end)
        it('carried containers are always reachable', function()
            assert(Containers.canReach('backpack', nil, nil))
        end)
        it('refuses a world container with no coords', function()
            local ok, reason = Containers.canReach('chest', nil, { x = 0, y = 0, z = 0 })
            eq(false, ok); eq('fh_no_coords', reason)
        end)
        it('refuses junk coords', function()
            eq('fh_no_coords', select(2, Containers.canReach('chest', { x = 'a' }, { x = 0, y = 0, z = 0 })))
        end)
        it('allows inside reach and refuses beyond it (default 3.5 m)', function()
            local c = { x = 10, y = 0, z = 0 }
            assert(Containers.canReach('chest', c, { x = 7, y = 0, z = 0 }))
            local ok, reason = Containers.canReach('chest', c, { x = 6, y = 0, z = 0 })
            eq(false, ok); eq('fh_out_of_reach', reason)
        end)
        it('uses the per-type override (wagon 5.0 m)', function()
            eq(5.0, Containers.interactDistance('wagon'))
            eq(3.5, Containers.interactDistance('chest'))
            assert(Containers.canReach('wagon', { x = 0, y = 0, z = 0 }, { x = 0, y = 4.9, z = 0 }))
            eq(false, (Containers.canReach('wagon', { x = 0, y = 0, z = 0 }, { x = 0, y = 5.1, z = 0 })))
        end)
        it('measures in 3D', function()
            eq(false, (Containers.canReach('chest', { x = 0, y = 0, z = 0 }, { x = 2, y = 2, z = 3 })))
        end)
    end)

    describe('defaults', function()
        it('reads capacity from FhConfig.Containers', function()
            local d = Containers.defaults('wagon')
            eq(60, d.slots); eq(500000, d.maxWeight)
            eq(nil, Containers.defaults('nope'))
        end)
    end)
end)

T.finish()
