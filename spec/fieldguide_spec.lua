-- fh_tutorial Field Guide spec (guide-02 T2). Run from repo root: `lua spec/fieldguide_spec.lua` (or tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq = T.describe, T.it, T.eq
local root = here .. '../'
local fgPath = root .. 'server/resources/[fh]/fh_tutorial/shared/field_guide.lua'

T.ok = function(c, msg) if not c then error(msg or 'assertion failed', 2) end end

FhFieldGuide = nil
local ret = dofile(fgPath)

local function fileExists(p)
    local f = io.open(p, 'r')
    if f then f:close() return true end
    return false
end

local function listSystemPages()
    local f = assert(io.open(root .. 'docs/wiki/README.md', 'r'), 'cannot open docs/wiki/README.md')
    local text = f:read('*a')
    f:close()
    local seen, out = {}, {}
    for rel in text:gmatch('%((systems/[^)%s#]+%.md)%)') do
        local full = 'docs/wiki/' .. rel
        if not seen[full] then
            seen[full] = true
            out[#out + 1] = full
        end
    end
    table.sort(out)
    return out
end

describe('field_guide structure', function()
    it('defines global FhFieldGuide with a non-empty contiguous entries list', function()
        T.ok(type(FhFieldGuide) == 'table', 'global FhFieldGuide missing')
        eq(FhFieldGuide, ret)
        T.ok(type(FhFieldGuide.entries) == 'table', 'entries missing')
        T.ok(#FhFieldGuide.entries > 0, 'entries empty')
        local count = 0
        for _ in pairs(FhFieldGuide.entries) do count = count + 1 end
        eq(#FhFieldGuide.entries, count, 'entries must be a contiguous array')
    end)

    it('every entry matches the fieldguide screen schema (id, title, 3-5 lines, controls, wiki_path)', function()
        local seenIds = {}
        local seenPaths = {}
        for i, e in ipairs(FhFieldGuide.entries) do
            local tag = ('entry[%d] (%s)'):format(i, tostring(e and e.id))
            T.ok(type(e) == 'table', tag .. ' must be a table')
            T.ok(type(e.id) == 'string' and e.id:match('^[a-z0-9_]+$'), tag .. ' invalid id')
            T.ok(not seenIds[e.id], tag .. ' duplicate id')
            seenIds[e.id] = true

            T.ok(type(e.title) == 'string' and e.title ~= '', tag .. ' missing title')

            T.ok(type(e.lines) == 'table', tag .. ' lines must be a table')
            T.ok(#e.lines >= 3 and #e.lines <= 5, tag .. ' lines count ' .. #e.lines .. ' outside 3-5')
            local lc = 0
            for _ in pairs(e.lines) do lc = lc + 1 end
            eq(#e.lines, lc, tag .. ' lines must be contiguous')
            for j, line in ipairs(e.lines) do
                T.ok(type(line) == 'string' and line ~= '', tag .. ' line ' .. j .. ' must be non-empty string')
            end

            T.ok(type(e.controls) == 'table', tag .. ' controls must be a table')
            local cc = 0
            for _ in pairs(e.controls) do cc = cc + 1 end
            eq(#e.controls, cc, tag .. ' controls must be contiguous')
            for j, c in ipairs(e.controls) do
                T.ok(type(c) == 'string' and c ~= '', tag .. ' control ' .. j .. ' must be non-empty string')
            end

            T.ok(type(e.wiki_path) == 'string' and e.wiki_path:match('^docs/wiki/systems/.+%.md$'),
                tag .. ' invalid wiki_path: ' .. tostring(e.wiki_path))
            T.ok(not seenPaths[e.wiki_path], tag .. ' duplicate wiki_path: ' .. e.wiki_path)
            seenPaths[e.wiki_path] = true
            T.ok(fileExists(root .. e.wiki_path), tag .. ' wiki_path missing on disk: ' .. e.wiki_path)
        end
    end)

    it('preserves (unverified) tags on keys marked unverified in the wiki', function()
        local byId = {}
        for _, e in ipairs(FhFieldGuide.entries) do byId[e.id] = e end
        for _, id in ipairs({ 'death', 'homestead', 'hunting' }) do
            local e = byId[id]
            T.ok(e ~= nil, 'missing entry ' .. id)
            local found = false
            for _, c in ipairs(e.controls) do
                if c:find('E (unverified)', 1, true) then found = true break end
            end
            T.ok(found, id .. ' must keep (unverified) tag on E key')
        end
    end)
end)

describe('field_guide coverage', function()
    it('has exactly one entry for every docs/wiki/systems/*.md page', function()
        local pages = listSystemPages()
        T.ok(#pages > 0, 'expected system wiki pages')
        local byPath = {}
        for _, e in ipairs(FhFieldGuide.entries) do byPath[e.wiki_path] = e.id end
        for _, page in ipairs(pages) do
            T.ok(byPath[page] ~= nil, 'missing field_guide entry for ' .. page)
        end
        eq(#pages, #FhFieldGuide.entries, 'entry count must match docs/wiki/systems/*.md count')
    end)
end)

T.finish()
