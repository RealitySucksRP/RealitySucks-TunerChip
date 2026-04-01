local QBCore = exports['qb-core']:GetCoreObject()

-- Make sure Config exists even if config.lua fails for some reason
Config = Config or {}
Config.Msg = Config.Msg or {
    needDriver   = 'Sit in the driver seat first.',
    classBlocked = 'This vehicle class cannot use the drift chip.',
    installing   = 'Installing Drift Chip...',
    enabled      = '🔥 Drift Enabled',
    disabled     = '❌ Drift Disabled',
    autoEnabled  = '🔥 Drift Auto-Enabled',
    menuTitle    = 'WS Drift Modes',
}
if Config.ApplyOnEnter == nil then Config.ApplyOnEnter = true end
Config.InstallMs = Config.InstallMs or 0
Config.AllowedVehicleClasses = Config.AllowedVehicleClasses or nil
Config.Modes = Config.Modes or {
    Balanced = { desc = 'Fallback', mult = {}, clamp = {}, tyres = true, reduceGrip = false, power = 6.0, torque = 1.04 }
}

local CurrentProfile = "Balanced"
local DriftStore     = {}
local AutoEnable     = false

-- Handling fields we touch and want to store/restore
local HANDLING_FLOATS = {
    'fTractionCurveMin',
    'fTractionCurveMax',
    'fTractionCurveLateral',
    'fLowSpeedTractionLossMult',
    'fTractionLossMult',
    'fDriveInertia',
    'fInitialDriveForce',
    'fClutchChangeRateScaleUpShift',
    'fClutchChangeRateScaleDownShift',
    'fSteeringLock',
    'fTractionBiasFront',
}

local function isClassAllowed(veh)
    if not veh or veh == 0 then return false end
    if not Config.AllowedVehicleClasses or #Config.AllowedVehicleClasses == 0 then
        return true
    end
    local vc = GetVehicleClass(veh)
    for _, allowed in ipairs(Config.AllowedVehicleClasses) do
        if allowed == vc then
            return true
        end
    end
    return false
end

local function getDriverVehicle()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return nil end
    local veh = GetVehiclePedIsIn(ped, false)
    if GetPedInVehicleSeat(veh, -1) ~= ped then return nil end
    return veh
end

local function ensureDriftStore(veh)
    if not veh or veh == 0 then return nil end
    if not DriftStore[veh] then
        DriftStore[veh] = { orig = {}, enabled = false }
        for _, field in ipairs(HANDLING_FLOATS) do
            DriftStore[veh].orig[field] = GetVehicleHandlingFloat(veh, "CHandlingData", field)
        end
        DriftStore[veh].orig.enginePower  = 0.0
        DriftStore[veh].orig.engineTorque = 1.0
    end
    return DriftStore[veh]
end

local function applyProfile(veh, profileName)
    if not veh or veh == 0 then return end
    local mode = Config.Modes[profileName]
    if not mode then
        mode = Config.Modes["Balanced"] or next(Config.Modes) and Config.Modes[next(Config.Modes)]
        profileName = profileName or "Balanced"
    end
    if not mode then return end

    local store = ensureDriftStore(veh)
    if not store then return end

    local mult  = mode.mult or {}
    local clamp = mode.clamp or {}

    for field, m in pairs(mult) do
        local base = store.orig[field]
        if base == nil then
            base = GetVehicleHandlingFloat(veh, "CHandlingData", field)
            store.orig[field] = base
        end
        if base then
            local newVal = base * m
            local limits = clamp[field]
            if limits then
                local minv, maxv = limits[1], limits[2]
                if minv and newVal < minv then newVal = minv end
                if maxv and newVal > maxv then newVal = maxv end
            end
            SetVehicleHandlingFloat(veh, "CHandlingData", field, newVal)
        end
    end

    if mode.reduceGrip then
        local baseLoss = store.orig['fTractionLossMult'] or GetVehicleHandlingFloat(veh, "CHandlingData", 'fTractionLossMult')
        local newLoss  = baseLoss * 1.08
        SetVehicleHandlingFloat(veh, "CHandlingData", 'fTractionLossMult', newLoss)
    end

    local p = mode.power or 0.0
    local t = mode.torque or 1.0
    SetVehicleEnginePowerMultiplier(veh, p)
    SetVehicleEngineTorqueMultiplier(veh, t)

    store.enabled = true
end

local function disableDrift(veh)
    if not veh or veh == 0 then return end
    local store = DriftStore[veh]
    if not store or not store.orig then return end

    for _, field in ipairs(HANDLING_FLOATS) do
        local base = store.orig[field]
        if base ~= nil then
            SetVehicleHandlingFloat(veh, "CHandlingData", field, base)
        end
    end

    SetVehicleEnginePowerMultiplier(veh, store.orig.enginePower or 0.0)
    SetVehicleEngineTorqueMultiplier(veh, store.orig.engineTorque or 1.0)

    store.enabled = false
end

local function progressInstall(cb)
    if (Config.InstallMs or 0) <= 0 then
        cb()
        return
    end
    QBCore.Functions.Notify(Config.Msg.installing, 'primary', Config.InstallMs)
    CreateThread(function()
        Wait(Config.InstallMs)
        cb()
    end)
end

local function openMenu()
    if GetResourceState('qb-menu') ~= 'started' then
        QBCore.Functions.Notify('qb-menu is not running', 'error')
        return
    end

    local p = {}

    for name, m in pairs(Config.Modes) do
        local header = name
        if name == CurrentProfile then
            header = header .. "  ✓"
        end

        p[#p+1] = {
            header = header,
            txt    = m.desc or "",
            params = {
                event = 'ws-driftchip:client:SelectMode',
                args  = { profile = name }
            }
        }
    end

    p[#p+1] = {
        header = 'Disable',
        txt    = 'Restore stock handling',
        params = {
            event = 'ws-driftchip:client:Disable'
        }
    }

    TriggerEvent('qb-menu:client:openMenu', p)
end

-- =====================================================
-- Events
-- =====================================================

RegisterNetEvent('ws-driftchip:client:SelectMode', function(data)
    local profile = data and data.profile or nil
    if not profile or not Config.Modes[profile] then
        profile = "Balanced"
    end

    CurrentProfile = profile
    local mode = Config.Modes[profile]

    QBCore.Functions.Notify(('Drift profile: %s'):format(profile), 'primary', 2000)

    local veh = getDriverVehicle()
    if veh then
        if not isClassAllowed(veh) then
            QBCore.Functions.Notify(Config.Msg.classBlocked, 'error')
            return
        end
        applyProfile(veh, profile)
        TriggerServerEvent('ws-driftchip:saveEnabled', true, profile)
        QBCore.Functions.Notify(Config.Msg.enabled, 'success', 2000)
    else
        TriggerServerEvent('ws-driftchip:saveEnabled', false, profile)
    end
end)

RegisterNetEvent('ws-driftchip:client:Disable', function()
    local veh = getDriverVehicle()
    if veh then
        disableDrift(veh)
    end
    QBCore.Functions.Notify(Config.Msg.disabled, 'error', 2000)
    TriggerServerEvent('ws-driftchip:saveEnabled', false, CurrentProfile)
end)

RegisterNetEvent('ws-driftchip:client:EnableDriftOnLogin', function(profile)
    if profile and Config.Modes[profile] then
        CurrentProfile = profile
    else
        CurrentProfile = "Balanced"
    end
    AutoEnable = true
end)

-- =====================================================
-- Auto apply on enter (if meta says drift was on)
-- =====================================================

CreateThread(function()
    local wasIn = false
    while true do
        Wait(500)
        local ped = PlayerPedId()
        local inVeh = IsPedInAnyVehicle(ped, false)

        if inVeh then
            local veh = GetVehiclePedIsIn(ped, false)
            if GetPedInVehicleSeat(veh, -1) == ped then
                if not wasIn then
                    wasIn = true
                    if AutoEnable and Config.ApplyOnEnter and isClassAllowed(veh) then
                        applyProfile(veh, CurrentProfile)
                        QBCore.Functions.Notify(Config.Msg.autoEnabled, 'success', 2000)
                    end
                end
            end
        else
            if wasIn then
                wasIn = false
            end
        end
    end
end)

-- Clean up on resource stop
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for veh, store in pairs(DriftStore) do
        if store.enabled and DoesEntityExist(veh) then
            disableDrift(veh)
        end
    end
end)

-- =====================================================
-- Commands & key mappings
-- =====================================================

RegisterCommand(Config.ToggleCommand or 'drift', function()
    local veh = getDriverVehicle()
    if not veh then
        QBCore.Functions.Notify(Config.Msg.needDriver, 'error')
        return
    end

    if not isClassAllowed(veh) then
        QBCore.Functions.Notify(Config.Msg.classBlocked, 'error')
        return
    end

    local store = ensureDriftStore(veh)
    if store and store.enabled then
        disableDrift(veh)
        QBCore.Functions.Notify(Config.Msg.disabled, 'error', 2000)
        TriggerServerEvent('ws-driftchip:saveEnabled', false, CurrentProfile)
    else
        progressInstall(function()
            applyProfile(veh, CurrentProfile)
            QBCore.Functions.Notify(Config.Msg.enabled, 'success', 2000)
            TriggerServerEvent('ws-driftchip:saveEnabled', true, CurrentProfile)
        end)
    end
end, false)

RegisterKeyMapping(
    Config.ToggleCommand or 'drift',
    'Toggle Drift Mode',
    'keyboard',
    Config.ToggleKey or 'F5'
)

RegisterCommand(Config.MenuCommand or 'driftmenu', function()
    openMenu()
end, false)

RegisterKeyMapping(
    Config.MenuCommand or 'driftmenu',
    'Open Drift Mode Menu',
    'keyboard',
    Config.MenuKey or 'F6'
)
