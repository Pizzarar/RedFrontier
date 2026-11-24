-- Run from repo root: `lua spec/quests_chunk_arg_spec.lua` (or via tools/run-specs.py).
-- C0 regression: shared/jobtypes/*.lua and data/regions/*.lua pick their registry from the chunk argument only when
-- it is a table (specs). In FXServer a shared script's `...` is a number, so they must fall back to the
-- FhQuestsJobTypes global instead of indexing the number ("attempt to index a number value (local 'JT')").
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq = T.describe, T.it, T.eq
local root = here .. '../server/resources/[fh]/fh_quests/'
package.path = root .. 'shared/?.lua;' .. package.path
local JT = dofile(root .. 'shared/jobtypes.lua')

-- Load path as FXServer does (a number as the chunk argument) with the global set to JT, then restore.
local function loadAsFxServer(path)
    local before = FhQuestsJobTypes
    FhQuestsJobTypes = JT
    local ok, err = pcall(function() assert(loadfile(path))(7) end)
    FhQuestsJobTypes = before
    if not ok then error(err, 0) end
end

describe('quests chunk arg: a number chunk argument falls back to the global', function()
    it('shared/jobtypes/bounty.lua registers its builder into FhQuestsJobTypes', function()
        local before = JT.BUILDERS.bounty
        JT.BUILDERS.bounty = nil
        local ok, err = pcall(loadAsFxServer, root .. 'shared/jobtypes/bounty.lua')
        local got = JT.BUILDERS.bounty
        JT.BUILDERS.bounty = before
        assert(ok, err)
        eq('function', type(got))
    end)
    it('data/regions/heartlands.lua registers its region into FhQuestsJobTypes', function()
        local before = JT.DATA.heartlands
        JT.DATA.heartlands = nil
        local ok, err = pcall(loadAsFxServer, root .. 'data/regions/heartlands.lua')
        local got = JT.DATA.heartlands
        JT.DATA.heartlands = before
        assert(ok, err)
        eq('table', type(got))
        eq('table', type(got.hunt))
    end)
end)

T.finish()
