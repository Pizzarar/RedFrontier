-- fh_hunting legendary ladder (plan hunting-02 B1). Pure Lua, no gameplay natives: loads one data file per FhRegions
-- region, data/legendaries/<region_id>.lua, validates it and builds the registry the chain (shared/chain.lua), the
-- animal table (shared/animals.lua), the trophy comfort table (shared/trophies.lua) and the client points read.
--
-- A data file is pure data: it runs in an empty environment (no globals) and returns one entry table, or nil for a
-- region with no legendary yet (a stub, ignored). An entry that fails validation is ignored with a warning. Files are
-- only looked up for FhRegions ids, so a file for an unknown region is never loaded.
--
-- Entry shape (all coordinates UNVERIFIED in game until someone stands on the spot):
--   id             string  ^[a-z][a-z0-9_]*$, <= 40 chars. Also the chain_id (fh_hunting_chains) and the animal key.
--   label          string  display name ("Legendary Bear"); sell rows and item text use it.
--   species_model  string  base ped model (must have a plain row in animals.lua; the legendary shares it).
--   outfit         integer >= 0, optional (default 0)   outfit preset. Not applied yet (no fh_core spawn field).
--   scale          number  > 0, optional (default 1.0)  ped scale.   Not applied yet (no fh_core spawn field).
--   pelt   { item = 'pelt_<id>', label, value (> 0, 2-star base before multipliers), weight (> 0), image }
--   trophy { item = 'trophy_<id>', label, comfort (>= 0), image?, weight?, description? }
--   rumour { coords {x,y,z}, price (>= 0), label (the "[E] ..." prompt text), range? (m), text? (paid notice) }
--   markers { [2] = { id?, label, coords, radius? }, [3] = { ... } }  clue 2 (track) and clue 3 (carcass)
--   spawn  { coords {x,y,z,heading?} }
-- The loader adds region_id (the file's region) and chain_id (= id).
local M = {}

M.DIR = 'data/legendaries/'
M.DEFAULT_ID = 'legendary_bear' -- the Legendary Bear (heartlands): calls without a legendary id mean this one
M.MARKER_IDS = { [2] = 'track', [3] = 'carcass' } -- default marker id per clue step

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end
local function str(v) return type(v) == 'string' and v ~= '' end

local function regionsMod() return FhRegions or require('regions') end

---Enabled gate (FhRegions.isEnabled): read live on every call, so flipping a region's `enabled` needs no code change.
function M.isEnabled(regionId) return regionsMod().isEnabled(regionId) end

local function coords(v, withHeading)
    if type(v) ~= 'table' or not finite(v.x) or not finite(v.y) or not finite(v.z) then return nil end
    local out = { x = v.x, y = v.y, z = v.z }
    if withHeading then
        if v.heading ~= nil and not finite(v.heading) then return nil end
        out.heading = v.heading or 0.0
    end
    return out
end

---Validate one raw data-file entry for `regionId`. Returns a fresh normalised entry (the raw table is not kept).
---@return table|nil entry, string|nil err
function M.validate(raw, regionId)
    if type(raw) ~= 'table' then return nil, 'entry is not a table' end
    local id = raw.id
    if type(id) ~= 'string' or #id > 40 or not id:match('^[a-z][a-z0-9_]*$') then return nil, 'bad id' end
    if not str(raw.label) then return nil, 'bad label' end
    if not str(raw.species_model) then return nil, 'bad species_model' end
    local outfit = raw.outfit == nil and 0 or raw.outfit
    if math.type(outfit) ~= 'integer' or outfit < 0 then return nil, 'bad outfit' end
    local scale = raw.scale == nil and 1.0 or raw.scale
    if not finite(scale) or scale <= 0 then return nil, 'bad scale' end

    local p = raw.pelt
    if type(p) ~= 'table' then return nil, 'bad pelt' end
    if p.item ~= 'pelt_' .. id then return nil, 'pelt.item must be pelt_' .. id end
    if not str(p.label) or not str(p.image) then return nil, 'bad pelt label/image' end
    if not finite(p.value) or p.value <= 0 or not finite(p.weight) or p.weight <= 0 then
        return nil, 'bad pelt value/weight'
    end

    local t = raw.trophy
    if type(t) ~= 'table' then return nil, 'bad trophy' end
    if t.item ~= 'trophy_' .. id then return nil, 'trophy.item must be trophy_' .. id end
    if not str(t.label) or not finite(t.comfort) or t.comfort < 0 then return nil, 'bad trophy label/comfort' end
    if t.image ~= nil and not str(t.image) then return nil, 'bad trophy image' end
    if t.weight ~= nil and (not finite(t.weight) or t.weight <= 0) then return nil, 'bad trophy weight' end
    if t.description ~= nil and not str(t.description) then return nil, 'bad trophy description' end

    local r = raw.rumour
    if type(r) ~= 'table' then return nil, 'bad rumour' end
    local rc = coords(r.coords)
    if not rc then return nil, 'bad rumour coords' end
    if not finite(r.price) or r.price < 0 or not str(r.label) then return nil, 'bad rumour price/label' end
    if r.range ~= nil and (not finite(r.range) or r.range <= 0) then return nil, 'bad rumour range' end
    if r.text ~= nil and not str(r.text) then return nil, 'bad rumour text' end

    if type(raw.markers) ~= 'table' then return nil, 'bad markers' end
    local markers = {}
    for step = 2, 3 do
        local m = raw.markers[step]
        if type(m) ~= 'table' then return nil, 'missing marker ' .. step end
        local mc = coords(m.coords)
        if not mc or not str(m.label) then return nil, 'bad marker ' .. step end
        if m.id ~= nil and not str(m.id) then return nil, 'bad marker id ' .. step end
        if m.radius ~= nil and (not finite(m.radius) or m.radius <= 0) then return nil, 'bad marker radius ' .. step end
        markers[step] = { id = m.id or M.MARKER_IDS[step], label = m.label, coords = mc, radius = m.radius or 3.0 }
    end
    if markers[2].id == markers[3].id then return nil, 'marker ids must differ' end

    local sc = type(raw.spawn) == 'table' and coords(raw.spawn.coords, true)
    if not sc then return nil, 'bad spawn coords' end

    return {
        id = id, chain_id = id, region_id = regionId, label = raw.label, species_model = raw.species_model:lower(),
        outfit = outfit, scale = scale,
        pelt = { item = p.item, label = p.label, value = p.value, weight = p.weight, image = p.image },
        trophy = { item = t.item, label = t.label, comfort = t.comfort, image = t.image, weight = t.weight,
            description = t.description },
        rumour = { coords = rc, price = r.price, label = r.label, range = r.range, text = r.text },
        markers = markers,
        spawn = { coords = sc },
    }
end

-- ---------------------------------------------------------------- registry

local Registry = {}
Registry.__index = Registry

---Entry by legendary id, or nil (unknown, stub or invalid).
function Registry:get(id)
    if type(id) ~= 'string' then return nil end
    return self.byId[id]
end

---Entries whose region is enabled right now, in registry order (the client shows exactly these).
function Registry:active()
    local out = {}
    for _, e in ipairs(self.list) do
        if M.isEnabled(e.region_id) then out[#out + 1] = e end
    end
    return out
end

---Build a registry from { [region_id] = raw entry | nil } over `regionIds` (sorted order is the registry order).
---Invalid and duplicate entries are skipped and listed in reg.warnings.
function M.build(rawByRegion, regionIds)
    local reg = setmetatable({ list = {}, byId = {}, byRegion = {}, warnings = {}, isEnabled = M.isEnabled },
        Registry)
    for _, rid in ipairs(regionIds) do
        local raw = rawByRegion[rid]
        if raw ~= nil then
            local e, err = M.validate(raw, rid)
            if not e then
                reg.warnings[#reg.warnings + 1] = rid .. ': ' .. err
            elseif reg.byId[e.id] then
                reg.warnings[#reg.warnings + 1] = rid .. ': duplicate id ' .. e.id
            else
                reg.list[#reg.list + 1] = e
                reg.byId[e.id] = e
                reg.byRegion[rid] = e
            end
        end
    end
    return reg
end

---Sorted FhRegions ids.
function M.regionIds()
    local ids = {}
    for id in pairs(regionsMod().regions) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

---Run one data file's source in an empty environment. @return boolean ok, any resultOrErr (nil result = stub)
function M.runChunk(src, name)
    local fn, err = load(src, '@' .. name, 't', {})
    if not fn then return false, err end
    local ok, res = pcall(fn)
    if not ok then return false, res end
    return true, res
end

---Read every region's data file through read(relPath) -> source|nil. Missing files and load errors are warnings.
---@return table rawByRegion, table warnings
function M.readAll(read, regionIds)
    local raw, warnings = {}, {}
    for _, rid in ipairs(regionIds) do
        local path = M.DIR .. rid .. '.lua'
        local src = read(path)
        if type(src) ~= 'string' then
            warnings[#warnings + 1] = rid .. ': missing ' .. path
        else
            local ok, res = M.runChunk(src, path)
            if ok then raw[rid] = res else warnings[#warnings + 1] = rid .. ': ' .. tostring(res) end
        end
    end
    return raw, warnings
end

-- ---------------------------------------------------------------- the default registry (the data files)

local function readFile(path)
    if LoadResourceFile and GetCurrentResourceName then
        return LoadResourceFile(GetCurrentResourceName(), path)
    end
    local dir = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
    local f = io.open(dir .. '../' .. path, 'r')
    if not f then return nil end
    local s = f:read('a')
    f:close()
    return s
end

---Load the data files into a registry (the default one is M itself, built once below).
function M.load(read)
    local ids = M.regionIds()
    local raw, warnings = M.readAll(read or readFile, ids)
    local reg = M.build(raw, ids)
    for _, w in ipairs(reg.warnings) do warnings[#warnings + 1] = w end
    reg.warnings = warnings
    return reg
end

-- Outside FXServer (specs) the module is a singleton per Lua state, so chain/animals/trophies and the spec share it.
if not GetCurrentResourceName and package.loaded.fh_hunting_legendaries then
    return package.loaded.fh_hunting_legendaries
end

do
    local reg = M.load()
    for k, v in pairs(reg) do M[k] = v end
    setmetatable(M, Registry)
    if GetCurrentResourceName then
        for _, w in ipairs(M.warnings) do print('^3[fh_hunting] legendaries: ' .. w .. '^7') end
    end
end

if GetCurrentResourceName then
    FhHuntingLegendaries = M
else
    package.loaded.fh_hunting_legendaries = M
    return M
end
