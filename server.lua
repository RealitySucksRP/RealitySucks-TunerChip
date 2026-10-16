local DEFAULT_PROFILE = Config.DefaultProfile or 'Balanced'
local STATE_BAG_KEY = Config.StateBagKey or 'rsTunerchip'
local KVP_PREFIX = 'rs_tunerchip:v3:'

local sessionRecords = {}
local pendingActions = {}
local actionLocks = {}
local lastMutation = {}

local function validProfile(profile)
    return type(profile) == 'string' and Config.Modes and Config.Modes[profile] ~= nil
end

local function cleanPlate(value)
    value = tostring(value or ''):upper():gsub('[%c]', ''):match('^%s*(.-)%s*$') or ''
    return value:sub(1, 16)
end

local function notify(src, message, notifyType, duration)
    TriggerClientEvent('rs-tunerchip:client:Notify', src, message, notifyType or 'inform', duration)
end

local function getDrivenVehicle(src, expectedNetId)
    src = tonumber(src)
    expectedNetId = expectedNetId and tonumber(expectedNetId) or nil
    if not src or src <= 0 or GetPlayerPing(src) <= 0 then return nil end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end

    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if not netId or netId == 0 or (expectedNetId and netId ~= expectedNetId) then return nil end

    local driver = 0
    local ok = pcall(function()
        driver = GetPedInVehicleSeat(vehicle, -1)
    end)
    if not ok or driver ~= ped then return nil end

    local playerBucket = GetPlayerRoutingBucket(src)
    local entityBucket = GetEntityRoutingBucket(vehicle)
    if playerBucket ~= entityBucket then return nil end

    return vehicle, netId
end

local function classAllowed(vehicle)
    local allowed = Config.AllowedVehicleClasses
    if type(allowed) ~= 'table' or #allowed == 0 then return true end

    local ok, vehicleClass = pcall(GetVehicleClass, vehicle)
    if not ok or type(vehicleClass) ~= 'number' then
        -- Older artifacts may not expose GetVehicleClass server-side. The
        -- client still refuses to apply the profile to a blocked class.
        return true
    end

    for i = 1, #allowed do
        if allowed[i] == vehicleClass then return true end
    end
    return false
end

local function vehicleSpeedKph(vehicle)
    local ok, speed = pcall(GetEntitySpeed, vehicle)
    return ok and (tonumber(speed) or 0.0) * 3.6 or 0.0
end

local function resolveIdentity(vehicle, netId)
    local model = GetEntityModel(vehicle)
    local plate = ''
    pcall(function()
        plate = cleanPlate(GetVehicleNumberPlateText(vehicle))
    end)

    -- Qbox provides a stable vehicle ID for owned vehicles. Keep the original
    -- v3 key format so previously installed chips continue to load.
    if GetResourceState('qbx_core') == 'started' and plate ~= '' then
        local vehicleId
        pcall(function()
            vehicleId = Entity(vehicle).state.vehicleid
        end)
        if not tonumber(vehicleId) and GetResourceState('qbx_vehicles') == 'started' then
            pcall(function()
                vehicleId = exports.qbx_vehicles:GetVehicleIdByPlate(plate)
            end)
        end

        vehicleId = tonumber(vehicleId)
        if vehicleId and vehicleId > 0 then
            return {
                key = ('owned:%d'):format(vehicleId),
                persistent = true,
                vehicleId = vehicleId,
                netId = netId,
                model = model,
                plate = plate,
            }
        end
    end

    if Config.PersistentPlateFallback == true and plate ~= '' then
        local safePlate = plate:gsub('[^%w%-_]', '')
        return {
            key = ('plate:%s:%u'):format(safePlate, model),
            persistent = true,
            netId = netId,
            model = model,
            plate = plate,
        }
    end

    return {
        key = ('entity:%d'):format(netId),
        persistent = false,
        netId = netId,
        model = model,
        plate = plate,
    }
end

local function normaliseRecord(record, identity)
    if type(record) ~= 'table' or record.installed ~= true then return nil end
    if not validProfile(record.profile) then record.profile = DEFAULT_PROFILE end
    record.enabled = record.enabled == true
    record.installed = true
    record.model = identity.model
    record.plate = identity.plate
    record.netId = identity.netId
    return record
end

local function loadRecord(identity)
    if identity.persistent then
        local raw = GetResourceKvpString(KVP_PREFIX .. identity.key)
        if not raw or raw == '' then return nil end

        local ok, decoded = pcall(json.decode, raw)
        return ok and normaliseRecord(decoded, identity) or nil
    end

    local record = sessionRecords[identity.key]
    if not record then return nil end
    if record.netId ~= identity.netId or record.model ~= identity.model or record.plate ~= identity.plate then
        sessionRecords[identity.key] = nil
        return nil
    end
    return normaliseRecord(record, identity)
end

local function saveRecord(identity, record)
    record = normaliseRecord(record, identity)
    if not record then return false end

    if identity.persistent then
        SetResourceKvp(KVP_PREFIX .. identity.key, json.encode(record))
    else
        sessionRecords[identity.key] = record
    end
    return true
end

local function deleteRecord(identity)
    if identity.persistent then
        DeleteResourceKvp(KVP_PREFIX .. identity.key)
    else
        sessionRecords[identity.key] = nil
    end
end

local function publicRecord(record, identity)
    if not record then
        return {
            installed = false,
            enabled = false,
            profile = DEFAULT_PROFILE,
            persistent = identity and identity.persistent == true or false,
            plate = identity and identity.plate or '',
        }
    end

    return {
        installed = true,
        enabled = record.enabled == true,
        profile = validProfile(record.profile) and record.profile or DEFAULT_PROFILE,
        persistent = identity.persistent == true,
        plate = identity.plate,
    }
end

local function replicate(vehicle, record, identity)
    local payload = record and publicRecord(record, identity) or nil
    pcall(function()
        Entity(vehicle).state:set(STATE_BAG_KEY, payload, true)
    end)
end

local function syncClient(src, vehicle, netId, record, identity, openMenu, smooth)
    replicate(vehicle, record, identity)
    TriggerClientEvent(
        'rs-tunerchip:client:SyncVehicle',
        src,
        netId,
        publicRecord(record, identity),
        openMenu == true,
        smooth == true
    )
end

local function customsCallerAllowed()
    local invoking = GetInvokingResource and GetInvokingResource() or nil
    if not invoking or invoking == '' then return false end
    for _, resourceName in ipairs(Config.CustomsInstallers or {}) do
        if invoking == tostring(resourceName) then return true end
    end
    return false
end

local function validateCustomsInstall(src, expectedNetId)
    if not customsCallerAllowed() then return false, 'This customs resource is not authorized to install tuner chips.' end
    if actionLocks[src] or pendingActions[src] then return false, 'Another tuner-chip action is already in progress.' end
    local vehicle, netId = getDrivenVehicle(src, expectedNetId)
    if not vehicle then return false, Config.Msg.serverRejected or 'The server could not verify this vehicle.' end
    if not classAllowed(vehicle) then return false, Config.Msg.classBlocked or 'This vehicle class cannot use the drift chip.' end
    if vehicleSpeedKph(vehicle) > (tonumber(Config.MaxInstallSpeedKph) or 5.0) then
        return false, Config.Msg.tooFastInstall or 'Stop the vehicle before installing the chip.'
    end
    local identity = resolveIdentity(vehicle, netId)
    if loadRecord(identity) then return false, Config.Msg.alreadyInstalled or 'This vehicle already has an RS Drift Chip installed.' end
    return true, nil, vehicle, netId, identity
end

exports('CanInstallFromCustoms', function(src, expectedNetId)
    src = tonumber(src)
    local ok, reason = validateCustomsInstall(src, expectedNetId)
    return ok == true, reason
end)

exports('InstallFromCustoms', function(src, expectedNetId)
    src = tonumber(src)
    local ok, reason, vehicle, netId, identity = validateCustomsInstall(src, expectedNetId)
    if not ok then return false, reason end

    actionLocks[src] = true
    local record = {
        installed = true,
        enabled = false,
        profile = DEFAULT_PROFILE,
        installedAt = os.time(),
        installedBy = 'customs',
    }
    if not saveRecord(identity, record) then
        actionLocks[src] = nil
        return false, 'The tuner-chip installation could not be saved.'
    end
    actionLocks[src] = nil
    syncClient(src, vehicle, netId, record, identity, false, false)
    return true, nil, {
        key = identity.key,
        persistent = identity.persistent == true,
        netId = netId,
        model = identity.model,
        plate = identity.plate,
        installedAt = record.installedAt,
    }
end)

exports('RollbackCustomsInstall', function(src, token)
    if not customsCallerAllowed() or type(token) ~= 'table' or type(token.key) ~= 'string' then return false end
    local identity = {
        key = token.key,
        persistent = token.persistent == true,
        netId = tonumber(token.netId) or 0,
        model = tonumber(token.model) or 0,
        plate = cleanPlate(token.plate),
    }
    local record = loadRecord(identity)
    if not record or record.installedBy ~= 'customs' or tonumber(record.installedAt) ~= tonumber(token.installedAt) then return false end
    deleteRecord(identity)

    local vehicle = identity.netId > 0 and NetworkGetEntityFromNetworkId(identity.netId) or 0
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) and GetEntityModel(vehicle) == identity.model then
        replicate(vehicle, nil, identity)
        TriggerClientEvent('rs-tunerchip:client:SyncVehicle', tonumber(src) or -1, identity.netId, publicRecord(nil, identity), false, true)
    end
    return true
end)

local function mutationAllowed(src)
    local now = GetGameTimer()
    local earliest = lastMutation[src] or 0
    if now < earliest then return false end
    lastMutation[src] = now + math.max(100, tonumber(Config.ActionCooldownMs) or 350)
    return true
end

-- Inventory operations are server-side and fail closed when no compatible
-- provider is running. Never trust the player's item-use event as proof of
-- possession: the item is checked again immediately before saving a chip.
local function qbPlayer(src)
    if GetResourceState('qb-core') ~= 'started' then return nil end
    local ok, player = pcall(function()
        local core = exports['qb-core']:GetCoreObject()
        return core.Functions.GetPlayer(src)
    end)
    return ok and player or nil
end

local function esxPlayer(src)
    if GetResourceState('es_extended') ~= 'started' then return nil end
    local ok, player = pcall(function()
        return exports['es_extended']:getSharedObject().GetPlayerFromId(src)
    end)
    return ok and player or nil
end

local function hasItem(src, itemName)
    if GetResourceState('ox_inventory') == 'started' then
        local ok, count = pcall(function()
            return exports.ox_inventory:Search(src, 'count', itemName)
        end)
        return ok and (tonumber(count) or 0) >= 1
    end

    if GetResourceState('qb-inventory') == 'started' then
        local ok, found = pcall(function()
            return exports['qb-inventory']:HasItem(src, itemName, 1)
        end)
        if ok then return found == true end
    end

    local player = qbPlayer(src)
    if player and player.Functions and player.Functions.GetItemByName then
        local ok, item = pcall(player.Functions.GetItemByName, itemName)
        return ok and item ~= nil and (tonumber(item.amount) or 0) >= 1
    end

    player = esxPlayer(src)
    if player and player.getInventoryItem then
        local ok, item = pcall(function() return player.getInventoryItem(itemName) end)
        return ok and item ~= nil and (tonumber(item.count) or 0) >= 1
    end

    return false
end

local function removeItem(src, itemName, slot)
    if GetResourceState('ox_inventory') == 'started' then
        local ok, removed = pcall(function()
            return exports.ox_inventory:RemoveItem(src, itemName, 1, nil, slot)
        end)
        return ok and removed == true
    end

    if GetResourceState('qb-inventory') == 'started' then
        local ok, removed = pcall(function()
            return exports['qb-inventory']:RemoveItem(src, itemName, 1, slot, 'rs-tunerchip')
        end)
        if ok then return removed == true end
    end

    local player = qbPlayer(src)
    if player and player.Functions and player.Functions.RemoveItem then
        local ok, removed = pcall(player.Functions.RemoveItem, itemName, 1, slot)
        return ok and removed == true
    end

    player = esxPlayer(src)
    if player and player.getInventoryItem and player.removeInventoryItem then
        local ok, removed = pcall(function()
            local before = player.getInventoryItem(itemName)
            local count = before and tonumber(before.count) or 0
            if count < 1 then return false end
            player.removeInventoryItem(itemName, 1)
            local after = player.getInventoryItem(itemName)
            return after and (tonumber(after.count) or count) < count
        end)
        return ok and removed == true
    end

    return false
end

local function beginItemAction(src, kind, itemName, itemData)
    if pendingActions[src] or actionLocks[src] then return end

    local vehicle, netId = getDrivenVehicle(src)
    if not vehicle then
        notify(src, Config.Msg.needDriver, 'error')
        return
    end
    if not classAllowed(vehicle) then
        notify(src, Config.Msg.classBlocked, 'error')
        return
    end
    if vehicleSpeedKph(vehicle) > (tonumber(Config.MaxInstallSpeedKph) or 5.0) then
        notify(src, Config.Msg.tooFastInstall, 'error')
        return
    end

    local identity = resolveIdentity(vehicle, netId)
    local record = loadRecord(identity)

    if kind == 'install' and record then
        syncClient(src, vehicle, netId, record, identity, true, false)
        return
    elseif kind == 'remove' and not record then
        notify(src, Config.Msg.notInstalled, 'error')
        return
    end

    pendingActions[src] = {
        kind = kind,
        itemName = itemName,
        slot = type(itemData) == 'table' and tonumber(itemData.slot) or nil,
        netId = netId,
        identityKey = identity.key,
        expiresAt = GetGameTimer() + math.max(5000, (kind == 'install' and Config.InstallMs or Config.RemoveMs) + 5000),
    }

    TriggerClientEvent(
        'rs-tunerchip:client:BeginItemAction',
        src,
        kind,
        netId,
        kind == 'install' and Config.InstallMs or Config.RemoveMs
    )
end

-- Native usable-item registrations for Qbox, QBCore and ESX. For a direct
-- ox_inventory server.export integration, the same handler is exposed below.
local registeredItems = {}

local function itemKind(itemName)
    for _, name in ipairs(Config.UseableItems or { 'tunerchip' }) do
        if name == itemName then return 'install' end
    end
    for _, name in ipairs(Config.RemoverItems or { 'tunerchip_remover' }) do
        if name == itemName then return 'remove' end
    end
end

local function registerUseableItem(itemName, kind)
    if type(itemName) ~= 'string' or itemName == '' then return end

    local provider
    if GetResourceState('qbx_core') == 'started' then
        provider = 'qbx_core'
    elseif GetResourceState('qb-core') == 'started' then
        provider = 'qb-core'
    elseif GetResourceState('es_extended') == 'started' then
        provider = 'es_extended'
    end
    if not provider or registeredItems[itemName] == provider then return end

    local callback = function(src, itemData)
        beginItemAction(tonumber(src), kind, itemName, itemData)
    end

    local ok, err = pcall(function()
        if provider == 'qbx_core' then
            exports.qbx_core:CreateUseableItem(itemName, callback)
        elseif provider == 'qb-core' then
            exports['qb-core']:GetCoreObject().Functions.CreateUseableItem(itemName, callback)
        else
            exports['es_extended']:getSharedObject().RegisterUsableItem(itemName, callback)
        end
    end)
    if ok then
        registeredItems[itemName] = provider
    else
        print(('[rs-tunerchip] Item %s registration failed for %s: %s'):format(itemName, provider, tostring(err)))
    end
end

local function registerAllItems()
    for _, itemName in ipairs(Config.UseableItems or { 'tunerchip' }) do
        registerUseableItem(itemName, 'install')
    end
    for _, itemName in ipairs(Config.RemoverItems or { 'tunerchip_remover' }) do
        registerUseableItem(itemName, 'remove')
    end
end

registerAllItems()

-- ox_inventory alternative: set server.export = 'rs-tunerchip.useTunerChip'
-- and consume = 0 for each item in ox_inventory/data/items.lua. The tuner
-- resource controls consumption only after its own timed server revalidation.
exports('useTunerChip', function(event, item, inventory, slot)
    if event ~= 'usedItem' or type(item) ~= 'table' then return end
    local kind = itemKind(item.name)
    local src = type(inventory) == 'table' and tonumber(inventory.id) or tonumber(inventory)
    if not kind or not src or src <= 0 or GetPlayerPing(src) <= 0 then return end
    beginItemAction(src, kind, item.name, { slot = slot })
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == 'qbx_core' or resource == 'qb-core' or resource == 'es_extended' then
        for name in pairs(registeredItems) do registeredItems[name] = nil end
        SetTimeout(500, registerAllItems)
    end
end)

RegisterNetEvent('rs-tunerchip:server:cancelItemAction', function(kind, netId)
    local src = source
    local pending = pendingActions[src]
    if pending and pending.kind == kind and pending.netId == tonumber(netId) then
        pendingActions[src] = nil
    end
end)

RegisterNetEvent('rs-tunerchip:server:completeItemAction', function(kind, netId)
    local src = source
    if actionLocks[src] or not mutationAllowed(src) then return end

    local pending = pendingActions[src]
    pendingActions[src] = nil
    if not pending or pending.kind ~= kind or pending.netId ~= tonumber(netId) then return end
    if GetGameTimer() > pending.expiresAt then return end

    actionLocks[src] = true

    local vehicle, currentNetId = getDrivenVehicle(src, pending.netId)
    if not vehicle or not classAllowed(vehicle)
        or vehicleSpeedKph(vehicle) > (tonumber(Config.MaxInstallSpeedKph) or 5.0) then
        actionLocks[src] = nil
        notify(src, Config.Msg.serverRejected, 'error')
        return
    end

    local identity = resolveIdentity(vehicle, currentNetId)
    if identity.key ~= pending.identityKey then
        actionLocks[src] = nil
        notify(src, Config.Msg.serverRejected, 'error')
        return
    end

    local record = loadRecord(identity)
    if kind == 'install' then
        if record then
            actionLocks[src] = nil
            syncClient(src, vehicle, currentNetId, record, identity, true, false)
            return
        end

        if not hasItem(src, pending.itemName)
            or (Config.ConsumeInstaller == true and not removeItem(src, pending.itemName, pending.slot)) then
            actionLocks[src] = nil
            notify(src, Config.Msg.itemMissing, 'error')
            return
        end

        record = {
            installed = true,
            enabled = false,
            profile = DEFAULT_PROFILE,
            installedAt = os.time(),
        }
        saveRecord(identity, record)
        actionLocks[src] = nil
        syncClient(src, vehicle, currentNetId, record, identity, true, false)
        notify(src, Config.Msg.installed, 'success')
        return
    end

    if not record then
        actionLocks[src] = nil
        notify(src, Config.Msg.notInstalled, 'error')
        return
    end

    if not hasItem(src, pending.itemName)
        or (Config.ConsumeRemover == true and not removeItem(src, pending.itemName, pending.slot)) then
        actionLocks[src] = nil
        notify(src, Config.Msg.itemMissing, 'error')
        return
    end

    deleteRecord(identity)
    actionLocks[src] = nil
    syncClient(src, vehicle, currentNetId, nil, identity, false, true)
    notify(src, Config.Msg.removed, 'success')
end)

RegisterNetEvent('rs-tunerchip:server:requestVehicleState', function(netId)
    local src = source
    local vehicle, currentNetId = getDrivenVehicle(src, netId)
    if not vehicle then return end

    local identity = resolveIdentity(vehicle, currentNetId)
    local record = loadRecord(identity)
    syncClient(src, vehicle, currentNetId, record, identity, false, false)
end)

RegisterNetEvent('rs-tunerchip:server:requestMenu', function(netId)
    local src = source
    local vehicle, currentNetId = getDrivenVehicle(src, netId)
    if not vehicle then
        notify(src, Config.Msg.needDriver, 'error')
        return
    end
    if not classAllowed(vehicle) then
        notify(src, Config.Msg.classBlocked, 'error')
        return
    end

    local identity = resolveIdentity(vehicle, currentNetId)
    local record = loadRecord(identity)
    if not record then
        notify(src, Config.Msg.notInstalled, 'error')
        syncClient(src, vehicle, currentNetId, nil, identity, false, false)
        return
    end

    syncClient(src, vehicle, currentNetId, record, identity, true, false)
end)

RegisterNetEvent('rs-tunerchip:server:requestToggle', function(netId)
    local src = source
    if actionLocks[src] or not mutationAllowed(src) then return end

    local vehicle, currentNetId = getDrivenVehicle(src, netId)
    if not vehicle then
        notify(src, Config.Msg.needDriver, 'error')
        return
    end
    if not classAllowed(vehicle) then
        notify(src, Config.Msg.classBlocked, 'error')
        return
    end

    local identity = resolveIdentity(vehicle, currentNetId)
    actionLocks[src] = true
    local record = loadRecord(identity)
    if not record then
        actionLocks[src] = nil
        notify(src, Config.Msg.notInstalled, 'error')
        return
    end

    record.enabled = not record.enabled
    saveRecord(identity, record)
    actionLocks[src] = nil
    syncClient(src, vehicle, currentNetId, record, identity, false, true)
    notify(
        src,
        record.enabled and (('%s: %s'):format(Config.Msg.enabled, record.profile))
            or Config.Msg.disabled,
        record.enabled and 'success' or 'error',
        2500
    )
end)

RegisterNetEvent('rs-tunerchip:server:setProfile', function(netId, profile)
    local src = source
    if actionLocks[src] or not mutationAllowed(src) then return end
    if not validProfile(profile) then return end

    local vehicle, currentNetId = getDrivenVehicle(src, netId)
    if not vehicle then
        notify(src, Config.Msg.needDriver, 'error')
        return
    end
    if not classAllowed(vehicle) then
        notify(src, Config.Msg.classBlocked, 'error')
        return
    end
    if vehicleSpeedKph(vehicle) > (tonumber(Config.MaxConfigureSpeedKph) or 25.0) then
        notify(src, Config.Msg.tooFastTune, 'error')
        return
    end

    local identity = resolveIdentity(vehicle, currentNetId)
    actionLocks[src] = true
    local record = loadRecord(identity)
    if not record then
        actionLocks[src] = nil
        notify(src, Config.Msg.notInstalled, 'error')
        return
    end

    record.profile = profile
    record.enabled = true
    saveRecord(identity, record)
    actionLocks[src] = nil
    syncClient(src, vehicle, currentNetId, record, identity, true, true)
    notify(src, ('%s: %s'):format(Config.Msg.profileSaved, profile), 'success', 2500)
end)

AddEventHandler('playerDropped', function()
    pendingActions[source] = nil
    actionLocks[source] = nil
    lastMutation[source] = nil
end)

-- Session-only installs follow a specific network entity. Drop them when the
-- entity disappears so recycled network ids can never inherit an installation.
CreateThread(function()
    while true do
        Wait(60000)
        for key, record in pairs(sessionRecords) do
            local netId = tonumber(record.netId)
            local vehicle = netId and NetworkGetEntityFromNetworkId(netId) or 0
            if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle)
                or GetEntityModel(vehicle) ~= record.model then
                sessionRecords[key] = nil
            end
        end

        local now = GetGameTimer()
        for src, pending in pairs(pendingActions) do
            if now > pending.expiresAt then pendingActions[src] = nil end
        end
    end
end)
