-- core-08 P1: weapon/ammo use is wired. fh_inventory fires rsg-weapons:client:Use* and rsg-ammo opens the ammo
-- boxes, so every weapon / ammo_box_* item that loot or starters hand out must be known to the vendored
-- rsg-weapons / rsg-ammo, both resources must be ensured after fh_inventory, and fh_inventory must `provide` rsg-inventory.
-- Run from repo root: `lua spec/weapon_use_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq = T.describe, T.it, T.eq
local R = here .. '../server/resources/'

local function slurp(p)
    local f = assert(io.open(p, 'r'), p)
    local s = f:read('a')
    f:close()
    return s
end

local items = slurp(R .. '[rsg]/rsg-core/shared/items.lua')
local ammoCfg = slurp(R .. '[rsg]/rsg-ammo/shared/config.lua')
local wpnCfg = slurp(R .. '[rsg]/rsg-weapons/config.lua')
local zones = slurp(R .. '[fh]/fh_zones/config.lua')
local invMain = slurp(R .. '[fh]/fh_inventory/server/main.lua')
local cfg = slurp(here .. '../server/server.cfg')

-- one entry per distinct name matching prefix in a source text
local function names(src, pattern)
    local seen, out = {}, {}
    for n in src:gmatch(pattern) do
        if not seen[n] then seen[n] = true; out[#out + 1] = n end
    end
    table.sort(out)
    return out
end

describe('weapon and ammo use', function()
    it('every loot ammo box is an rsg-ammo box and a defined useable item', function()
        local boxes = names(zones, "'(ammo_box_[%w_]+)'")
        assert(#boxes >= 6, 'expected the six loot ammo boxes, found ' .. #boxes)
        for _, n in ipairs(boxes) do
            assert(ammoCfg:find("['" .. n .. "']", 1, true), n .. ' has no rsg-ammo Config.BoxAmmo entry')
            assert(items:find("name = '" .. n .. "'", 1, true), n .. ' missing from rsg-core shared/items.lua')
        end
    end)

    it('every rsg-ammo box item exists in shared/items.lua and is useable', function()
        for _, n in ipairs(names(ammoCfg, "%['(ammo_[%w_]+)'%]%s*=")) do
            local line = items:match("[^\n]*name = '" .. n .. "'[^\n]*")
            assert(line, n .. ' missing from shared/items.lua')
            assert(line:find('useable = true', 1, true), n .. ' is not useable')
        end
    end)

    it('every loot weapon is a type=weapon item with a damage entry in rsg-weapons', function()
        local list = names(zones, "'(weapon_[%w_]+)'")
        assert(#list >= 4, 'expected the four loot weapons')
        for _, n in ipairs(list) do
            local line = items:match("[^\n]*name = '" .. n .. "'[^\n]*")
            assert(line, n .. ' missing from shared/items.lua')
            if not line:find("type = 'item'", 1, true) then -- weapon_gun_oil and kin are plain items, not guns
                assert(line:find("type = 'weapon'", 1, true), n .. ' is not type weapon')
                assert(line:find('useable = true', 1, true), n .. ' is not useable')
                if not n:find('_kit_', 1, true) then -- binoculars and the like carry no damage row
                    assert(wpnCfg:lower():find("name = '" .. n .. "'", 1, true), n .. ' has no rsg-weapons WeaponDamage entry')
                end
            end
        end
    end)

    it('fh_inventory fires the events rsg-weapons registers', function()
        for _, ev in ipairs({ 'UseWeapon', 'UseThrownWeapon', 'UseEquipment' }) do
            assert(invMain:find('rsg-weapons:client:' .. ev, 1, true), 'fh_inventory no longer fires ' .. ev)
            assert(slurp(R .. '[rsg]/rsg-weapons/client/client.lua'):find("RegisterNetEvent('rsg-weapons:client:" .. ev .. "'", 1, true),
                'rsg-weapons has no ' .. ev .. ' handler')
        end
    end)

    it('fh_inventory provides rsg-inventory (rsg-weapons/rsg-ammo depend on it)', function()
        assert(slurp(R .. '[fh]/fh_inventory/fxmanifest.lua'):find("provide 'rsg-inventory'", 1, true))
    end)

    it('server.cfg ensures rsg-weapons and rsg-ammo after fh_inventory and oxmysql', function()
        local order = {}
        for r in cfg:gmatch('\nensure ([%w_%-]+)') do order[#order + 1] = r end
        local function idx(name)
            for i, r in ipairs(order) do if r == name then return i end end
        end
        assert(idx('rsg-weapons') and idx('rsg-ammo'), 'rsg-weapons / rsg-ammo not ensured')
        assert(idx('rsg-weapons') > idx('fh_inventory'), 'rsg-weapons before fh_inventory')
        assert(idx('rsg-ammo') > idx('fh_inventory') and idx('rsg-ammo') > idx('oxmysql'), 'rsg-ammo too early')
        eq(1, select(2, cfg:gsub('\nensure rsg%-weapons\n', '')))
    end)
end)

T.finish()
