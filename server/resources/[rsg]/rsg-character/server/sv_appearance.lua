RSGCore = exports['rsg-core']:GetCoreObject()

-- Server-side session state. The client can never open these on its own:
-- a creator session only exists after the server itself sent OpenCreator.
CreatorSessions = {}   -- [src] = { cid = number|nil, isNew = bool, created = bool }
local assignedBuckets = {} -- [src] = bucket this resource put the player in
local previousBuckets = {} -- [src] = bucket the player was in before this resource moved them
local MarkStarterPending -- defined with the starter-item grant below (FH core-10 I2)

local MAX_JSON_SIZE = 32768

---------------------------------------------------------------------------
-- Routing buckets
---------------------------------------------------------------------------
function RSG.SetPrivateBucket(src)
    -- already in one of our private buckets: keep it (no bucket churn, and the stored previous bucket stays correct)
    if assignedBuckets[src] and GetPlayerRoutingBucket(src) == assignedBuckets[src] then return end
    local bucket = math.random(10000, 0xfffff)
    previousBuckets[src] = GetPlayerRoutingBucket(src)
    SetRoutingBucketPopulationEnabled(bucket, false)
    SetPlayerRoutingBucket(src, bucket)
    assignedBuckets[src] = bucket
end

function RSG.ResetBucket(src)
    -- only ever undo a bucket this resource assigned, so players can't use
    -- this resource to escape instances created by other resources (jail etc.)
    if not assignedBuckets[src] then return end
    if GetPlayerRoutingBucket(src) == assignedBuckets[src] then
        -- put them back where they were, not blindly in bucket 0 (e.g. a house or jail instance)
        SetPlayerRoutingBucket(src, previousBuckets[src] or 0)
    end
    assignedBuckets[src] = nil
    previousBuckets[src] = nil
end

local function IsNearClothingStore(src, maxDist)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local coords = GetEntityCoords(ped)
    for _, zone in ipairs(RSG.Zones1) do
        if #(coords - zone.fittingcoords.xyz) <= maxDist or #(coords - zone.promtcoords) <= maxDist then
            return true
        end
    end
    return false
end
RSG.IsNearClothingStore = IsNearClothingStore

function RSG.NotifyLoginFailed(src)
    TriggerClientEvent('RSGCore:Client:Notify', src, {
        title = locale('charselect.login_failed.title'),
        description = locale('charselect.login_failed.description'),
        type = 'error',
        duration = 5000,
    })
end

-- Only used by the clothing store now: random = enter fitting room, otherwise leave it.
RegisterNetEvent('rsg-character:server:SetPlayerBucket', function(_, random)
    local src = source
    if random then
        if not RSGCore.Functions.GetPlayer(src) then return end
        if not IsNearClothingStore(src, 10.0) then return end
        RSG.SetPrivateBucket(src)
    elseif not CreatorSessions[src] then
        RSG.ResetBucket(src)
    end
end)

AddEventHandler('playerDropped', function()
    CreatorSessions[source] = nil
    assignedBuckets[source] = nil
    previousBuckets[source] = nil
end)

---------------------------------------------------------------------------
-- Creator sessions
---------------------------------------------------------------------------
function RSG.OpenCreatorFor(src, data)
    CreatorSessions[src] = { cid = data and data.cid, isNew = data ~= nil, created = false }
    RSG.SetPrivateBucket(src)
    TriggerClientEvent('rsg-character:client:OpenCreator', src, data, data == nil)
end

local function ValidateSkin(skin)
    if type(skin) ~= 'table' then return false end
    local count = 0
    for k, v in pairs(skin) do
        count = count + 1
        if count > 150 or type(k) ~= 'string' or #k > 32 then return false end
        local t = type(v)
        if t == 'table' then
            for k2, v2 in pairs(v) do
                if type(k2) ~= 'string' or type(v2) ~= 'number' then return false end
            end
        elseif t ~= 'number' then
            return false
        end
    end
    return true
end

RegisterNetEvent('rsg-character:server:SaveSkin', function(skin, clothes)
    local src = source
    local session = CreatorSessions[src]
    if not session then return end -- only valid at the end of a server-opened creator
    if session.isNew and not session.created then return end

    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    if not ValidateSkin(skin) or type(clothes) ~= 'table' then
        RSG.NotifyLoginFailed(src)
        return
    end

    local gender = tonumber(Player.PlayerData.charinfo and Player.PlayerData.charinfo.gender) or 0
    skin.sex = gender == 1 and 2 or 1 -- trust the character record, not the client

    -- New characters that finish the creator without picking any clothes would otherwise save an empty
    -- outfit and spawn in underwear: give them the configured default outfit instead.
    if session.isNew and next(clothes) == nil then
        local defaults = RSG.DefaultClothes or {}
        clothes = (gender == 0 and defaults.male) or defaults.female or {}
    end

    if not ValidateClothesData(clothes, gender == 0) then
        RSG.NotifyLoginFailed(src)
        return
    end

    local encodedSkin, encodedClothes = json.encode(skin), json.encode(clothes)
    if #encodedSkin > MAX_JSON_SIZE or #encodedClothes > MAX_JSON_SIZE then
        RSG.NotifyLoginFailed(src)
        return
    end

    local citizenid = Player.PlayerData.citizenid
    local affected = MySQL.update.await('UPDATE playerskins SET skin = ?, clothes = ? WHERE citizenid = ?', { encodedSkin, encodedClothes, citizenid })
    if not affected or affected == 0 then
        MySQL.insert.await('INSERT INTO playerskins (citizenid, skin, clothes) VALUES (?, ?, ?)', { citizenid, encodedSkin, encodedClothes })
    end

    -- first-time creation: store the chosen clothes as the protected "Default" wardrobe outfit
    if session.isNew then
        local hasDefault = MySQL.scalar.await('SELECT 1 FROM playeroutfit WHERE citizenid = ? AND is_default = 1 LIMIT 1', { citizenid })
        if not hasDefault then
            MySQL.insert.await('INSERT INTO playeroutfit (citizenid, name, clothes, is_default) VALUES (?, ?, ?, 1)', { citizenid, locale('default_outfit_name'), encodedClothes })
        end
    end

    local isNew = session.isNew
    CreatorSessions[src] = nil
    RSG.ResetBucket(src)
    TriggerEvent('rsg-character:server:appearanceSaved', src, citizenid, isNew)
    -- The creator's ped still wears whatever the client left on it (empty clothes = underwear). Send the final
    -- skin + clothes so the default outfit substituted above reaches the client for the first spawn — exactly like
    -- LoadSkinForSource does for returning characters (the spawn flow waits for ApplySkin before it proceeds).
    TriggerClientEvent('rsg-character:client:ApplySkin', src, skin, clothes)
    TriggerClientEvent('rsg-character:client:OpenSpawnSelect', src, nil, isNew)

    local identityFields = RSG.WebhookIdentityFields(src)
    RSG.SendWebhook('appearance_saved', {
        title = locale('webhooks.appearance_saved.title_initial'),
        description = locale('webhooks.appearance_saved.description', citizenid),
        fields = {
            { name = locale('webhooks.appearance_saved.field_citizenid'), value = citizenid, inline = true },
            identityFields[1],
            identityFields[2],
        },
    })
end)

local function SafeDecode(value, fallback)
    if type(value) ~= 'string' or value == '' then return fallback end
    local ok, decoded = pcall(json.decode, value)
    if ok and type(decoded) == 'table' then return decoded end
    return fallback
end

local function GetSkinRow(citizenid)
    return MySQL.single.await('SELECT skin, clothes FROM playerskins WHERE citizenid = ? ORDER BY id DESC LIMIT 1', { citizenid })
end

-- Saved clothes for a character, or the configured default outfit when none are saved. A character that finished
-- the creator without picking clothes (or a legacy row) has an empty playerskins.clothes and would otherwise spawn
-- in underwear. gender is 0 = male, 1 = female.
local function ClothesWithDefault(gender, clothes)
    if next(clothes or {}) == nil then
        local defaults = RSG.DefaultClothes or {}
        clothes = (gender == 0 and defaults.male) or defaults.female or {}
    end
    return clothes
end

local function GenderOf(Player)
    return tonumber(Player.PlayerData.charinfo and Player.PlayerData.charinfo.gender) or 0
end

-- Returns true when a skin was found and applied, false when the creator was opened instead.
function RSG.LoadSkinForSource(src)
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return false end
    local row = GetSkinRow(Player.PlayerData.citizenid)
    local skin = row and SafeDecode(row.skin)
    if skin then
        -- legacy rows (rsg-appearance) can have NULL/empty clothes: fall back to the default outfit
        TriggerClientEvent('rsg-character:client:ApplySkin', src, skin, ClothesWithDefault(GenderOf(Player), SafeDecode(row.clothes, {})))
        return true
    end
    RSG.OpenCreatorFor(src, nil)
    return false
end

local function GetAppearance(src)
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return nil end
    local row = GetSkinRow(Player.PlayerData.citizenid)
    local skin = row and SafeDecode(row.skin)
    if not skin then return nil end
    return { skin = skin, clothes = ClothesWithDefault(GenderOf(Player), SafeDecode(row.clothes, {})) }
end

RSGCore.Functions.CreateCallback('rsg-character:server:getAppearance', function(src, cb)
    cb(GetAppearance(src))
end)

-- legacy name kept for external resources that still call it
RSGCore.Functions.CreateCallback('rsg-multicharacter:server:getAppearance', function(src, cb)
    cb(GetAppearance(src) or { skin = {}, clothes = {} })
end)

---------------------------------------------------------------------------
-- New character
---------------------------------------------------------------------------
local validNationality
local function IsValidNationality(value)
    if not validNationality then
        validNationality = {}
        -- The client builds the dropdown in its own locale language, which can
        -- differ from the server's language. Accept the translation from every locale
        -- file so players on any language can create a character.
        local resource = GetCurrentResourceName()
        local langs = { 'en', 'de', 'el', 'es', 'fr', 'ja', 'nl', 'pl', 'pt-br', 'ro', 'ru' }
        for _, lang in ipairs(langs) do
            local raw = LoadResourceFile(resource, ('locales/%s.json'):format(lang))
            local ok, data = pcall(json.decode, raw or '')
            local list = ok and type(data) == 'table' and data.nationalities
            if type(list) == 'table' then
                for _, key in ipairs(RSG.Nationalities) do
                    if type(list[key]) == 'string' then
                        validNationality[list[key]] = true
                    end
                end
            end
        end
        -- Always include the server's own locale as a fallback
        for _, key in ipairs(RSG.Nationalities) do
            validNationality[locale('nationalities.' .. key)] = true
        end
    end
    return validNationality[value] == true
end

local function IsValidName(name)
    return type(name) == 'string' and #name >= 2 and #name <= 20
        and name:match('^%u%l+$') ~= nil and not RSG.ProfanityWords[name:lower()]
end

RSG.IsValidName = IsValidName

function RSG.NameExists(firstname, lastname, excludeCitizenid)
    if not RSG.UniqueNames then return false end
    return MySQL.scalar.await([[
        SELECT 1 FROM players
        WHERE JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')) = ?
          AND JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname')) = ?
          AND citizenid <> ?
        LIMIT 1
    ]], { firstname, lastname, excludeCitizenid or '' }) ~= nil
end

-- the creator asks before the player spends time on the appearance steps
RSGCore.Functions.CreateCallback('rsg-character:server:isNameAvailable', function(src, cb, firstname, lastname)
    local session = CreatorSessions[src]
    if not session or not session.isNew or not IsValidName(firstname) or not IsValidName(lastname) then return cb(false) end
    cb(not RSG.NameExists(firstname, lastname))
end)

RegisterNetEvent('rsg-multicharacter:server:createCharacter', function(newData)
    local src = source
    local session = CreatorSessions[src]
    if not session or not session.isNew or session.created then return end
    if RSGCore.Functions.GetPlayer(src) then return end -- already logged in
    if type(newData) ~= 'table' then return end

    local cid = tonumber(newData.cid)
    if not cid or cid ~= session.cid then return end

    if not IsValidName(newData.firstname) or not IsValidName(newData.lastname)
        or not IsValidNationality(newData.nationality) or not RSG.IsValidBirthdate(newData.birthdate) then
        -- never fail silently: the client has already closed the creator
        CreatorSessions[src] = nil
        TriggerClientEvent('RSGCore:Client:Notify', src, { title = locale('missing_character_info.title'), description = locale('missing_character_info.description'), type = 'error', duration = 7000 })
        TriggerClientEvent('rsg-character:client:OpenCharSelect', src)
        return
    end

    local license = RSGCore.Functions.GetIdentifier(src, 'license')
    if not license then
        CreatorSessions[src] = nil
        RSG.NotifyLoginFailed(src)
        TriggerClientEvent('rsg-character:client:OpenCharSelect', src)
        return
    end

    if MySQL.scalar.await('SELECT citizenid FROM players WHERE license = ? AND cid = ?', { license, cid }) then
        CreatorSessions[src] = nil
        TriggerClientEvent('RSGCore:Client:Notify', src, { title = locale('charselect.slot_taken.title'), description = locale('charselect.slot_taken.desc'), type = 'error', duration = 5000 })
        TriggerClientEvent('rsg-character:client:OpenCharSelect', src)
        return
    end

    if RSG.NameExists(newData.firstname, newData.lastname) then
        CreatorSessions[src] = nil
        TriggerClientEvent('RSGCore:Client:Notify', src, { title = locale('name_taken.title'), description = locale('name_taken.description'), type = 'error', duration = 7000 })
        TriggerClientEvent('rsg-character:client:OpenCharSelect', src)
        return
    end

    local gender = tonumber(newData.gender) == 1 and 1 or 0
    session.created = true

    RSGCore.Player.Login(src, nil, {
        cid = cid,
        charinfo = {
            firstname = newData.firstname,
            lastname = newData.lastname,
            nationality = newData.nationality,
            birthdate = newData.birthdate,
            gender = gender,
        }
    })

    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then
        CreatorSessions[src] = nil
        RSG.NotifyLoginFailed(src)
        TriggerClientEvent('rsg-character:client:OpenCharSelect', src)
        return
    end

    -- Starter items are granted on the first spawn (RSGCore:Server:OnPlayerLoaded below), not here: granting
    -- now fires the add-item toasts while the player is still in the creator. Deferring the whole grant (not just
    -- the toast) keeps the item boxes to one per item, at the right time. FH core-10 I2: the pending grant is a DB
    -- row (fh_starter_granted, keyed by citizenid), so a disconnect, resource restart or server restart before the
    -- first spawn does not lose it.
    MarkStarterPending(Player.PlayerData.citizenid)

    TriggerEvent('rsg-character:server:characterCreated', src, Player.PlayerData.citizenid, cid)

    local identityFields = RSG.WebhookIdentityFields(src)
    RSG.SendWebhook('character_created', {
        title = locale('webhooks.character_created.title'),
        description = locale('webhooks.character_created.description', newData.firstname, newData.lastname, cid),
        fields = {
            { name = locale('webhooks.character_created.field_citizenid'), value = Player.PlayerData.citizenid, inline = true },
            { name = locale('webhooks.character_created.field_gender'), value = gender == 0 and locale('webhooks.character_created.male') or locale('webhooks.character_created.female'), inline = true },
            { name = locale('webhooks.character_created.field_nationality'), value = newData.nationality, inline = true },
            { name = locale('webhooks.character_created.field_birthdate'), value = newData.birthdate, inline = true },
            identityFields[1],
            identityFields[2],
        },
    })
end)

-- Starter items for a brand-new character are granted on their first spawn (after creation), so the add-item
-- toasts appear in-world instead of over the creator. AddItem already fires its own `rsg-inventory:client:ItemBox`,
-- so nothing else is needed here; the grant is the mirror of what createCharacter used to do inline.
--
-- FH core-10 I2 (idea-923): the pending grant lives in `fh_starter_granted` (server/migrations/0023), not memory.
--   * createCharacter: MarkStarterPending upserts (citizenid, granted = 0). ON DUPLICATE KEY resets the row because
--     rsg-core's CreateCitizenId only checks `players`, so a deleted character's citizenid can be handed out again.
--   * first spawn: an atomic UPDATE ... WHERE granted = 0 claims the row; only the caller that sees affectedRows = 1
--     grants. A second load, a concurrent load, or a character with no row (made before this table) grants nothing.
--   * failure policy: the claim is taken BEFORE the items are added. If an AddItem then fails or throws, it is
--     logged (citizenid, item, amount) and NOT retried: a missed kit is an admin give, a double grant is a dupe.
--     A DB error on the mark or the claim is logged the same way and grants nothing.
local STARTER_TAG = '[rsg-character] starter items:'

MarkStarterPending = function(citizenid)
    local ok, err = pcall(MySQL.insert.await,
        'INSERT INTO fh_starter_granted (citizenid, granted) VALUES (?, 0) ON DUPLICATE KEY UPDATE granted = 0, granted_at = NULL, created_at = current_timestamp()',
        { citizenid })
    if not ok then
        print(('%s could not mark %s pending (is migration 0023 applied?): %s'):format(STARTER_TAG, tostring(citizenid), tostring(err)))
    end
end

-- true only for the one caller whose UPDATE flipped the row from pending to granted.
local function ClaimStarterGrant(citizenid)
    local ok, affected = pcall(MySQL.update.await,
        'UPDATE fh_starter_granted SET granted = 1, granted_at = current_timestamp() WHERE citizenid = ? AND granted = 0',
        { citizenid })
    if not ok then
        print(('%s claim failed for %s (nothing granted): %s'):format(STARTER_TAG, tostring(citizenid), tostring(affected)))
        return false
    end
    return tonumber(affected) == 1
end

local function GrantStarterItems(src, citizenid)
    for _, entry in ipairs(RSG.StarterItems or {}) do
        local itemName, amount = entry.item, tonumber(entry.amount) or 1
        if itemName and amount > 0 and RSGCore.Shared.Items[itemName] then
            local ok, added = pcall(exports['rsg-inventory'].AddItem, exports['rsg-inventory'], src, itemName, amount, nil, nil, 'rsg-character:starter-items')
            if not ok or not added then
                print(('%s %s x%d NOT granted to %s (claim already taken, not retried; give by hand): %s'):format(
                    STARTER_TAG, itemName, amount, tostring(citizenid), ok and 'AddItem returned false' or tostring(added)))
            end
        end
    end
end

-- First spawn after character creation: claim the pending row and grant the starter items (and their toasts) once.
RegisterNetEvent('RSGCore:Server:OnPlayerLoaded', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    local citizenid = Player.PlayerData.citizenid
    if not citizenid or not ClaimStarterGrant(citizenid) then return end
    GrantStarterItems(src, citizenid)
end)
