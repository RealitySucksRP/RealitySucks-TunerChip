-- =============================================================================
-- RS FRAMEWORK SHIM -- QBCore / Qbox / ESX, self-contained
-- =============================================================================
-- Local framework compatibility helpers. No schema or extra setup required.
--
-- WHAT IT IS FOR
-- --------------
-- RS resources are written against the QBCore shape: QBCore.Functions.GetPlayer,
-- Player.PlayerData.citizenid, Player.Functions.AddItem, and so on. That shape
-- works on QBCore, and it works on Qbox because qbx_core declares
-- provide 'qb-core'. On ESX there is no qb-core resource at all, so
-- exports['qb-core']:GetCoreObject() is a HARD ERROR AT LOAD -- the resource
-- does not merely misbehave, it fails to start.
--
-- This file resolves the framework and hands back a QBCore-shaped object in all
-- three cases, so existing call sites keep working unchanged. One line changes
-- per file:
--
--     local QBCore = exports['qb-core']:GetCoreObject()   -- before
--     local QBCore = RSFramework.GetCore()                -- after
--
-- WHY THE QB AND QBOX PATHS ARE PURE PASSTHROUGH
-- ----------------------------------------------
-- On QBCore and on Qbox this returns the REAL core object, untouched. Those two
-- paths already work on the live servers, and a shim that "improves" a working
-- path is a regression waiting to happen. ESX is the only branch that builds
-- anything, so an ESX bug cannot reach a QBCore or Qbox server.
--
-- DETECTION ORDER IS LOAD-BEARING
-- -------------------------------
-- qbx_core is tested FIRST because it is the only POSITIVE signal for Qbox.
--
-- Note what provide 'qb-core' does and does not do: it registers a
-- dependency-resolution alias, so exports['qb-core'] RESOLVES on Qbox -- but it
-- creates no resource, so GetResourceState('qb-core') returns 'missing' there.
-- Testing qb-core first would therefore fall through on Qbox and misreport it
-- as standalone. It also means GetResourceState is the WRONG feature test for
-- that export anywhere: pcall the export instead. Do not reorder.
-- =============================================================================

RSFramework = RSFramework or {}

local IS_SERVER = IsDuplicityVersion()

local function started(resource)
    return GetResourceState(resource) == 'started'
end

local function try(fn, ...)
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
    return nil
end

-- -----------------------------------------------------------------------------
-- Detection
-- -----------------------------------------------------------------------------

local cachedName

--- Returns 'qbox' | 'qbcore' | 'esx' | 'standalone'.
function RSFramework.Detect()
    -- Do not permanently cache standalone: a resource may start before the
    -- framework during a manual restart or unusual ensure order.
    if cachedName and cachedName ~= 'standalone' then return cachedName end

    if started('qbx_core') then
        cachedName = 'qbox'
    elseif started('qb-core') then
        cachedName = 'qbcore'
    elseif started('es_extended') then
        cachedName = 'esx'
    else
        cachedName = 'standalone'
    end

    return cachedName
end

function RSFramework.Is(name)
    return RSFramework.Detect() == name
end

-- -----------------------------------------------------------------------------
-- ESX shared object
-- -----------------------------------------------------------------------------

local esxObject

local function getESX()
    if esxObject then return esxObject end
    if not started('es_extended') then return nil end

    -- ESX Legacy (1.9+) exposes an export. Older builds only answer an event.
    esxObject = try(function() return exports['es_extended']:getSharedObject() end)

    if not esxObject then
        TriggerEvent('esx:getSharedObject', function(obj) esxObject = obj end)
    end

    return esxObject
end

RSFramework.GetESX = getESX

-- -----------------------------------------------------------------------------
-- ESX -> QB player shape
-- -----------------------------------------------------------------------------

local function esxItems(src, xPlayer)
    if started('ox_inventory') then
        local items = try(function() return exports.ox_inventory:GetInventoryItems(src) end)
        if type(items) == 'table' then return items end
    end
    if xPlayer and xPlayer.inventory then return xPlayer.inventory end
    return {}
end

--- Builds the PlayerData table ESX has no equivalent of.
---
--- Resolved fresh on every access rather than captured once, so a caller that
--- reads money or job AFTER a transaction sees current values rather than a
--- stale snapshot taken when GetPlayer was called.
local function esxPlayerData(src, xPlayer)
    if not xPlayer then return nil end

    local identifier = xPlayer.identifier or xPlayer.getIdentifier and try(function() return xPlayer.getIdentifier() end)
    local job = xPlayer.job or {}

    local first, last = nil, nil
    if xPlayer.variables then
        first = xPlayer.variables.firstName or xPlayer.variables.firstname
        last = xPlayer.variables.lastName or xPlayer.variables.lastname
    end

    local full = xPlayer.getName and try(function() return xPlayer.getName() end) or nil
    if (not first or not last) and type(full) == 'string' then
        local a, b = full:match('^(%S+)%s+(.+)$')
        first = first or a or full
        last = last or b or ''
    end

    local cash = 0
    if xPlayer.getMoney then cash = try(function() return xPlayer.getMoney() end) or 0 end

    local bank = 0
    if xPlayer.getAccount then
        local acct = try(function() return xPlayer.getAccount('bank') end)
        bank = (type(acct) == 'table' and acct.money) or 0
    end

    return {
        source = src,
        citizenid = identifier,
        identifier = identifier,
        charinfo = { firstname = first, lastname = last, name = full },
        job = {
            name = job.name or 'unemployed',
            label = job.label or 'Unemployed',
            -- ESX grade is a flat number; QB expects grade.level and grade.name.
            grade = { level = job.grade or 0, name = job.grade_label or job.grade_name or '' },
            onduty = true,
            isboss = (job.grade_name == 'boss'),
        },
        gang = { name = 'none', label = 'No Gang', grade = { level = 0, name = 'none' } },
        money = { cash = cash, bank = bank },
        metadata = {},
        items = esxItems(src, xPlayer),
    }
end

--- Wraps an ESX xPlayer so QB-shaped call sites work untouched.
local function wrapESX(src, xPlayer)
    if not xPlayer then return nil end

    local F = {}

    function F.AddMoney(account, amount, reason)
        amount = tonumber(amount) or 0
        if amount <= 0 then return false end
        if account == 'bank' then
            if xPlayer.addAccountMoney then
                try(function() xPlayer.addAccountMoney('bank', amount, reason) end)
                return true
            end
            return false
        end
        if xPlayer.addMoney then
            try(function() xPlayer.addMoney(amount, reason) end)
            return true
        end
        return false
    end

    function F.RemoveMoney(account, amount, reason)
        amount = tonumber(amount) or 0
        if amount <= 0 then return false end
        if account == 'bank' then
            if xPlayer.removeAccountMoney then
                try(function() xPlayer.removeAccountMoney('bank', amount, reason) end)
                return true
            end
            return false
        end
        if xPlayer.removeMoney then
            try(function() xPlayer.removeMoney(amount, reason) end)
            return true
        end
        return false
    end

    function F.SetMoney(account, amount, reason)
        amount = tonumber(amount) or 0
        if account == 'bank' then
            if xPlayer.setAccountMoney then
                try(function() xPlayer.setAccountMoney('bank', amount, reason) end)
                return true
            end
            return false
        end
        if xPlayer.setMoney then
            try(function() xPlayer.setMoney(amount, reason) end)
            return true
        end
        return false
    end

    -- QB signature is (item, amount, slot, metadata). Keep it exactly, even
    -- though ox_inventory and ESX both want a different order -- the call sites
    -- are QB-shaped and this is where the translation belongs.
    function F.AddItem(item, amount, slot, metadata)
        amount = tonumber(amount) or 1
        if started('ox_inventory') then
            local ok = try(function()
                return exports.ox_inventory:AddItem(src, item, amount, metadata, slot)
            end)
            return ok and true or false
        end
        if xPlayer.addInventoryItem then
            try(function() xPlayer.addInventoryItem(item, amount) end)
            return true
        end
        return false
    end

    function F.RemoveItem(item, amount, slot)
        amount = tonumber(amount) or 1
        if started('ox_inventory') then
            local ok = try(function()
                return exports.ox_inventory:RemoveItem(src, item, amount, nil, slot)
            end)
            return ok and true or false
        end
        if xPlayer.removeInventoryItem then
            try(function() xPlayer.removeInventoryItem(item, amount) end)
            return true
        end
        return false
    end

    --- QB returns the item table or nil.
    function F.GetItemByName(item)
        if started('ox_inventory') then
            local found = try(function() return exports.ox_inventory:Search(src, 'slots', item) end)
            if type(found) == 'table' and found[1] then return found[1] end
            return nil
        end
        if xPlayer.getInventoryItem then
            local it = try(function() return xPlayer.getInventoryItem(item) end)
            if type(it) == 'table' and (tonumber(it.count) or 0) > 0 then return it end
        end
        return nil
    end

    function F.SetMetaData(key, value)
        if not key then return false end
        if xPlayer.setMeta then
            local ok = try(function() xPlayer.setMeta(key, value) return true end)
            if ok then return true end
        end
        -- Older ESX has no metadata store. The statebag at least survives the
        -- session, which is better than dropping the write silently.
        local ply = Player(src)
        if ply and ply.state then
            ply.state:set(key, value, true)
            return true
        end
        return false
    end

    function F.GetMetaData(key)
        if xPlayer.getMeta then
            local v = try(function() return xPlayer.getMeta(key) end)
            if v ~= nil then return v end
        end
        local ply = Player(src)
        if ply and ply.state then return ply.state[key] end
        return nil
    end

    function F.SetJob(name, grade)
        if xPlayer.setJob then
            try(function() xPlayer.setJob(name, grade or 0) end)
            return true
        end
        return false
    end

    return setmetatable({ __esx = xPlayer, Functions = F }, {
        __index = function(_, key)
            if key == 'PlayerData' then return esxPlayerData(src, xPlayer) end
            -- Anything not modelled falls through to the real xPlayer so
            -- ESX-native fields still resolve.
            return xPlayer[key]
        end,
    })
end

RSFramework.WrapESX = wrapESX

-- -----------------------------------------------------------------------------
-- The ESX-backed QBCore-shaped core
-- -----------------------------------------------------------------------------

local function buildESXCore()
    local Functions = {}

    function Functions.GetPlayer(src)
        local ESX = getESX()
        if not ESX or not ESX.GetPlayerFromId then return nil end
        return wrapESX(src, ESX.GetPlayerFromId(src))
    end

    function Functions.GetPlayerData(src)
        if IS_SERVER then
            local p = Functions.GetPlayer(src)
            return p and p.PlayerData or nil
        end
        local ESX = getESX()
        if not ESX then return nil end
        local data = ESX.GetPlayerData and try(function() return ESX.GetPlayerData() end)
        return data
    end

    function Functions.GetPlayers()
        local ESX = getESX()
        if ESX and ESX.GetPlayers then return ESX.GetPlayers() end
        -- GetPlayers() is a server native; there is nothing sensible to return
        -- for it on the client, and an empty list is safer than a hard error.
        if IS_SERVER then return GetPlayers() end
        return {}
    end

    Functions.GetQBPlayers = function()
        local out = {}
        for _, src in ipairs(Functions.GetPlayers()) do
            out[tonumber(src)] = Functions.GetPlayer(tonumber(src))
        end
        return out
    end

    function Functions.Notify(a, b, c, d)
        if IS_SERVER then
            -- Server signature is (src, message, type, duration). ESX has no
            -- server-side ShowNotification on the shared object -- it is a
            -- client function -- so the message goes out as an event.
            if not a then return false end
            TriggerClientEvent('esx:showNotification', a, tostring(b or ''))
            return true
        end

        -- Client signature is (message, type, duration).
        local ESX = getESX()
        if ESX and ESX.ShowNotification then
            return try(function() return ESX.ShowNotification(a) end)
        end
        TriggerEvent('esx:showNotification', tostring(a or ''))
        return true
    end

    function Functions.CreateUseableItem(item, cb)
        local ESX = getESX()
        if ESX and ESX.RegisterUsableItem then
            return try(function() return ESX.RegisterUsableItem(item, cb) end)
        end
        return false
    end

    function Functions.CreateCallback(name, cb)
        local ESX = getESX()
        if ESX and ESX.RegisterServerCallback then
            -- QB hands the handler (source, cb, ...); ESX hands (source, cb, ...)
            -- too, so this passes straight through.
            return try(function() return ESX.RegisterServerCallback(name, cb) end)
        end
        return false
    end

    function Functions.TriggerCallback(name, cb, ...)
        local ESX = getESX()
        if ESX and ESX.TriggerServerCallback then
            -- `...` cannot be referenced inside a nested non-vararg closure, so
            -- pack it here and unpack inside. table.pack/unpack with an explicit
            -- n preserves an embedded nil in the argument list.
            local args = table.pack(...)
            return try(function()
                return ESX.TriggerServerCallback(name, cb, table.unpack(args, 1, args.n))
            end)
        end
        if cb then cb(nil) end
        return false
    end

    function Functions.HasPermission(src, perm)
        return IsPlayerAceAllowed(src, perm) == true
    end

    -- Shared.Items -- resolved lazily from ox_inventory when it is running,
    -- since ESX itself keeps no such table in the QB shape.
    local Items = setmetatable({}, {
        __index = function(_, name)
            if not name then return nil end
            if started('ox_inventory') then
                local defs = try(function() return exports.ox_inventory:Items() end)
                if type(defs) == 'table' then return defs[name] end
            end
            local ESX = getESX()
            if ESX and ESX.GetItems then
                local defs = try(function() return ESX.GetItems() end)
                if type(defs) == 'table' then return defs[name] end
            end
            return nil
        end,
    })

    return { Functions = Functions, Shared = { Items = Items }, Players = {} }
end

-- -----------------------------------------------------------------------------
-- Public entry point
-- -----------------------------------------------------------------------------

local cachedCore

--- Returns a QBCore-shaped core object for whichever framework is running.
---
--- QBCore and Qbox get the REAL object (passthrough, no wrapper). ESX gets the
--- shim above. Standalone returns nil -- callers already have to tolerate that,
--- because a framework can be absent or still starting.
function RSFramework.GetCore()
    if cachedCore then return cachedCore end

    local fw = RSFramework.Detect()

    if fw == 'qbox' or fw == 'qbcore' then
        -- Works on both: on Qbox this resolves through qbx_core's
        -- provide 'qb-core'. Deliberately NOT reimplemented against
        -- exports.qbx_core -- that would change a path that works today.
        cachedCore = try(function() return exports['qb-core']:GetCoreObject() end)
        return cachedCore
    end

    if fw == 'esx' then
        cachedCore = buildESXCore()
        return cachedCore
    end

    return nil
end

--- Blocks until a framework is up, then returns the core. Use at resource start
--- when load order is not guaranteed.
function RSFramework.WaitForCore(timeoutMs)
    local deadline = GetGameTimer() + (tonumber(timeoutMs) or 15000)
    while GetGameTimer() < deadline do
        cachedName = nil
        if RSFramework.Detect() ~= 'standalone' then
            local core = RSFramework.GetCore()
            if core then return core end
        end
        Wait(100)
    end
    return nil
end

return RSFramework
