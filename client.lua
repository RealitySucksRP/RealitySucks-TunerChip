local QBCore = RSTCBridge.Core

Config = Config or {}
Config.Msg = Config.Msg or {}
Config.Modes = Config.Modes or {}

local DEFAULT_PROFILE = Config.DefaultProfile or 'Balanced'
local DriftStore = {}
local CurrentVehicleState = {
    installed = false,
    enabled = false,
    profile = DEFAULT_PROFILE,
    persistent = false,
    plate = '',
}
local actionRunning = false

local function notify(message, notifyType, duration)
    QBCore.Functions.Notify(message, notifyType or 'inform', duration)
end

local function isClassAllowed(vehicle)
    if not vehicle or vehicle == 0 then return false end
    local allowed = Config.AllowedVehicleClasses
    if type(allowed) ~= 'table' or #allowed == 0 then return true end

    local vehicleClass = GetVehicleClass(vehicle)
    for i = 1, #allowed do
        if allowed[i] == vehicleClass then return true end
    end
    return false
end

local function getDriverVehicle()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return nil end

    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then return nil end
    return vehicle
end

local function getVehicleNetId(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    if not NetworkGetEntityIsNetworked(vehicle) then return nil end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    return netId and netId > 0 and netId or nil
end

local function requireDriverVehicle()
    local vehicle = getDriverVehicle()
    if not vehicle then
        notify(Config.Msg.needDriver or 'Sit in the driver seat first.', 'error')
        return nil
    end
    if not isClassAllowed(vehicle) then
        notify(Config.Msg.classBlocked or 'This vehicle class cannot use the drift chip.', 'error')
        return nil
    end

    local netId = getVehicleNetId(vehicle)
    if not netId then
        notify(Config.Msg.serverRejected or 'The server could not verify this vehicle.', 'error')
        return nil
    end
    return vehicle, netId
end

-- Build the touched-field set from every profile, so adding a field to config
-- automatically gives it correct stock caching and restoration.
local handlingFieldSet = {
    fTractionCurveMin = true,
    fTractionCurveMax = true,
    fTractionCurveLateral = true,
    fLowSpeedTractionLossMult = true,
    fTractionLossMult = true,
    fDriveInertia = true,
    fInitialDriveForce = true,
    fClutchChangeRateScaleUpShift = true,
    fClutchChangeRateScaleDownShift = true,
    fSteeringLock = true,
    fTractionBiasFront = true,
    fHandBrakeForce = true,
    fCamberStiffnesss = true,
}

for _, mode in pairs(Config.Modes) do
    for field in pairs(mode.mult or {}) do handlingFieldSet[field] = true end
    for field in pairs(mode.add or {}) do handlingFieldSet[field] = true end
end

local HANDLING_FLOATS = {}
for field in pairs(handlingFieldSet) do HANDLING_FLOATS[#HANDLING_FLOATS + 1] = field end
table.sort(HANDLING_FLOATS)

local function driftKey(vehicle)
    if not vehicle or vehicle == 0 then return nil end
    local netId = getVehicleNetId(vehicle) or 0
    return ('%d:%d:%d'):format(vehicle, GetEntityModel(vehicle), netId)
end

local function findDriftStore(vehicle)
    local key = driftKey(vehicle)
    if not key then return nil, nil end

    local exact = DriftStore[key]
    if exact then return exact, key end

    -- Permit the one-way 0 -> real network-id transition for a newly spawned
    -- entity, but never let a recycled local handle inherit another car's data.
    local model = GetEntityModel(vehicle)
    local netId = getVehicleNetId(vehicle) or 0
    local now = GetGameTimer()
    for oldKey, store in pairs(DriftStore) do
        if store.vehicle == vehicle and store.model == model
            and (store.netId == netId
                or (store.netId == 0 and netId > 0 and now - (store.createdAt or 0) < 10000)) then
            DriftStore[oldKey] = nil
            store.netId = netId
            DriftStore[key] = store
            return store, key
        end
    end

    return nil, key
end

local function readDriftTyres(vehicle)
    if type(GetDriftTyresEnabled) ~= 'function' then return false end
    local ok, enabled = pcall(GetDriftTyresEnabled, vehicle)
    return ok and enabled == true or false
end

local function setDriftTyres(vehicle, enabled)
    if type(SetDriftTyresEnabled) ~= 'function' then return false end
    local ok = pcall(SetDriftTyresEnabled, vehicle, enabled == true)
    return ok
end

local function ensureDriftStore(vehicle)
    local store, key = findDriftStore(vehicle)
    if not key then return nil end
    if store then return store end

    store = {
        vehicle = vehicle,
        model = GetEntityModel(vehicle),
        netId = getVehicleNetId(vehicle) or 0,
        createdAt = GetGameTimer(),
        orig = {},
        enabled = false,
        token = 0,
        appliedPower = 0.0,
        appliedTorque = 1.0,
    }

    for i = 1, #HANDLING_FLOATS do
        local field = HANDLING_FLOATS[i]
        store.orig[field] = GetVehicleHandlingFloat(vehicle, 'CHandlingData', field)
    end
    store.orig.enginePower = 0.0
    store.orig.engineTorque = 1.0
    store.orig.driftTyres = readDriftTyres(vehicle)
    DriftStore[key] = store
    return store
end

local function resolveField(base, multiplier, offset, limits)
    local target = (base * (tonumber(multiplier) or 1.0)) + (tonumber(offset) or 0.0)

    -- Keep every tune proportional to the vehicle's own handling first. This
    -- prevents an absolute "drift pack" value from ruining unusually light,
    -- heavy, or imported cars.
    if base > 0.0 then
        local lower, upper = base * 0.60, base * 1.50
        if target < lower then target = lower end
        if target > upper then target = upper end
    end

    if limits then
        local minimum, maximum = tonumber(limits[1]), tonumber(limits[2])
        -- Absolute rails are useful for ordinary GTA handling values, but a
        -- custom vehicle that starts well outside that family must stay
        -- stock-relative. Zero-baseline additive fields (camber) still use the
        -- explicit rail.
        local lowerFit = not minimum or base == 0.0 or base >= (minimum * 0.80)
        local upperFit = not maximum or base == 0.0 or base <= (maximum * 1.20)
        if lowerFit and upperFit then
            if minimum and target < minimum then target = minimum end
            if maximum and target > maximum then target = maximum end
        end
    end
    return target
end

local function transitionValues(vehicle, store, fromValues, targets, fromPower, toPower, fromTorque, toTorque, durationMs, token, onComplete)
    durationMs = math.max(0, tonumber(durationMs) or 0)
    local steps = durationMs < 50 and 1 or math.max(2, math.floor(durationMs / 50))

    CreateThread(function()
        for step = 1, steps do
            if store.token ~= token or not DoesEntityExist(vehicle) then return end

            local t = step / steps
            -- Smoothstep avoids both a sharp launch and a sharp finish.
            local eased = t * t * (3.0 - (2.0 * t))

            for field, target in pairs(targets) do
                local start = fromValues[field]
                if start ~= nil then
                    SetVehicleHandlingFloat(
                        vehicle,
                        'CHandlingData',
                        field,
                        start + ((target - start) * eased)
                    )
                end
            end

            local power = fromPower + ((toPower - fromPower) * eased)
            local torque = fromTorque + ((toTorque - fromTorque) * eased)
            SetVehicleEnginePowerMultiplier(vehicle, power)
            SetVehicleEngineTorqueMultiplier(vehicle, torque)
            store.appliedPower = power
            store.appliedTorque = torque

            if step < steps then Wait(50) end
        end

        if store.token == token and onComplete then onComplete() end
    end)
end

local function applyProfile(vehicle, profileName, instant)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    local mode = Config.Modes[profileName]
    if not mode then
        profileName = DEFAULT_PROFILE
        mode = Config.Modes[profileName]
    end
    if not mode then return false end

    local store = ensureDriftStore(vehicle)
    if not store then return false end

    local mult, add, clamps = mode.mult or {}, mode.add or {}, mode.clamp or {}
    local targets, fromValues = {}, {}

    -- Every profile starts from stock. Fields omitted by a new profile return
    -- toward stock instead of inheriting the previous profile's modifications.
    for i = 1, #HANDLING_FLOATS do
        local field = HANDLING_FLOATS[i]
        local base = store.orig[field]
        if base ~= nil then
            targets[field] = resolveField(base, mult[field], add[field], clamps[field])
            fromValues[field] = GetVehicleHandlingFloat(vehicle, 'CHandlingData', field)
        end
    end

    local desiredPower = tonumber(mode.power) or 0.0
    local desiredTorque = tonumber(mode.torque) or 1.0
    local desiredDriftTyres = mode.driftTyres == true
    local desiredReduceGrip = mode.reduceGrip == true

    store.token = (store.token or 0) + 1
    store.enabled = true
    store.profile = profileName
    store.targets = targets
    store.power = desiredPower
    store.torque = desiredTorque
    store.driftTyres = desiredDriftTyres
    store.reduceGrip = desiredReduceGrip

    -- Each active profile owns the native drift-tire flag. This prevents a
    -- pre-existing native tire setting from stacking underneath Balanced,
    -- JDM, Muscle, Takeover, or Pursuit. Disabling restores the original flag.
    setDriftTyres(vehicle, desiredDriftTyres)

    if desiredReduceGrip or store.usedReduceGrip then
        pcall(SetVehicleReduceGrip, vehicle, desiredReduceGrip)
        store.usedReduceGrip = desiredReduceGrip
    end

    local token = store.token
    transitionValues(
        vehicle,
        store,
        fromValues,
        targets,
        store.appliedPower or 0.0,
        desiredPower,
        store.appliedTorque or 1.0,
        desiredTorque,
        instant and 0 or (Config.TransitionMs or 850),
        token
    )
    return true
end

local function disableDrift(vehicle, instant)
    if not vehicle or vehicle == 0 then return false end
    local store, key = findDriftStore(vehicle)
    if not store or not store.orig then return false end

    store.token = (store.token or 0) + 1
    store.enabled = false

    local fromValues, targets = {}, {}
    for i = 1, #HANDLING_FLOATS do
        local field = HANDLING_FLOATS[i]
        local base = store.orig[field]
        if base ~= nil then
            fromValues[field] = GetVehicleHandlingFloat(vehicle, 'CHandlingData', field)
            targets[field] = base
        end
    end

    setDriftTyres(vehicle, store.orig.driftTyres == true)
    if store.usedReduceGrip then
        pcall(SetVehicleReduceGrip, vehicle, false)
        store.usedReduceGrip = false
    end

    local token = store.token
    transitionValues(
        vehicle,
        store,
        fromValues,
        targets,
        store.appliedPower or 0.0,
        store.orig.enginePower or 0.0,
        store.appliedTorque or 1.0,
        store.orig.engineTorque or 1.0,
        instant and 0 or (Config.TransitionMs or 850),
        token,
        function()
            local current = DriftStore[key]
            if current == store and store.token == token then DriftStore[key] = nil end
        end
    )
    return true
end

local function reapplyVehicleTune(vehicle, powerOnly)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    local store = findDriftStore(vehicle)
    if not store or store.enabled ~= true then return false end

    SetVehicleEnginePowerMultiplier(vehicle, store.power or 0.0)
    SetVehicleEngineTorqueMultiplier(vehicle, store.torque or 1.0)
    store.appliedPower = store.power or 0.0
    store.appliedTorque = store.torque or 1.0

    if powerOnly ~= true then
        for field, value in pairs(store.targets or {}) do
            SetVehicleHandlingFloat(vehicle, 'CHandlingData', field, value)
        end
        setDriftTyres(vehicle, store.driftTyres == true)
        if store.reduceGrip or store.usedReduceGrip then
            pcall(SetVehicleReduceGrip, vehicle, store.reduceGrip == true)
        end
    end
    return true
end

exports('ReapplyVehicleTune', reapplyVehicleTune)
exports('SetBaseDriftTires', function(vehicle, enabled)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    local store = findDriftStore(vehicle)
    if store and store.orig then
        store.orig.driftTyres = enabled == true
        if store.enabled == true then
            return setDriftTyres(vehicle, store.driftTyres == true)
        end
    end
    return setDriftTyres(vehicle, enabled == true)
end)
exports('GetActiveTune', function(vehicle)
    local store = findDriftStore(vehicle)
    if not store or store.enabled ~= true then return nil end
    return {
        profile = store.profile,
        power = store.power,
        torque = store.torque,
        driftTyres = store.driftTyres == true,
        reduceGrip = store.reduceGrip == true,
    }
end)

-- Customisation scripts sometimes reapply stock handling. Keep only active
-- targets authoritative; power remains coordinated through ReapplyVehicleTune
-- so this loop does not fight nitrous.
CreateThread(function()
    while true do
        Wait(math.max(500, tonumber(Config.ReassertHandlingMs) or 1500))
        for _, store in pairs(DriftStore) do
            if store.enabled == true and store.vehicle and DoesEntityExist(store.vehicle) then
                for field, value in pairs(store.targets or {}) do
                    SetVehicleHandlingFloat(store.vehicle, 'CHandlingData', field, value)
                end
                setDriftTyres(store.vehicle, store.driftTyres == true)
                if store.reduceGrip or store.usedReduceGrip then
                    pcall(SetVehicleReduceGrip, store.vehicle, store.reduceGrip == true)
                end
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(60000)
        for key, store in pairs(DriftStore) do
            local vehicle = store.vehicle
            local invalid = not vehicle or not DoesEntityExist(vehicle)
            if not invalid and store.model ~= GetEntityModel(vehicle) then invalid = true end
            if invalid then DriftStore[key] = nil end
        end
    end
end)

local function modeOrder()
    local result, seen = {}, {}
    for _, name in ipairs(Config.ModeOrder or {}) do
        if Config.Modes[name] and not seen[name] then
            result[#result + 1] = name
            seen[name] = true
        end
    end

    local remainder = {}
    for name in pairs(Config.Modes) do
        if not seen[name] then remainder[#remainder + 1] = name end
    end
    table.sort(remainder)
    for i = 1, #remainder do result[#result + 1] = remainder[i] end
    return result
end

local function requestToggle()
    local _, netId = requireDriverVehicle()
    if not netId then return false end
    TriggerServerEvent('rs-tunerchip:server:requestToggle', netId)
    return true
end

local PROFILE_VISUALS = {
    Balanced = { image = 'assets/mode-balanced.jpg', accent = '#ff9a3d', tag = 'SMOOTH' },
    Arcade = { image = 'assets/mode-arcade.jpg', accent = '#ffd45e', tag = 'FUSION' },
    JDM = { image = 'assets/mode-jdm.jpg', accent = '#55c7ff', tag = 'TECHNICAL' },
    Muscle = { image = 'assets/mode-muscle.jpg', accent = '#c86bff', tag = 'TORQUE' },
    Takeover = { image = 'assets/mode-takeover.jpg', accent = '#ff49cf', tag = 'ANGLE' },
    Pursuit = { image = 'assets/mode-pursuit.jpg', accent = '#ffc83d', tag = 'HYBRID' },
    OEM = { image = 'assets/mode-oem.jpg', accent = '#7ef0ff', tag = 'NATIVE' },
    NativeX = { image = 'assets/mode-nativex.jpg', accent = '#8bf160', tag = 'NATIVE+' },
}

local function menuPayload(state)
    local profiles = {}
    for _, name in ipairs(modeOrder()) do
        local mode = Config.Modes[name]
        local visual = PROFILE_VISUALS[name] or PROFILE_VISUALS.Balanced
        profiles[#profiles + 1] = {
            name = name,
            label = mode.label or name,
            description = mode.desc or '',
            power = tonumber(mode.power) or 0.0,
            torque = tonumber(mode.torque) or 1.0,
            image = visual.image,
            accent = visual.accent,
            tag = visual.tag,
        }
    end

    return {
        installed = state.installed == true,
        enabled = state.enabled == true,
        profile = state.profile or DEFAULT_PROFILE,
        persistent = state.persistent == true,
        plate = state.plate or '',
        profiles = profiles,
    }
end

local function fallbackMenu(state)
    local items = {
        {
            title = state.enabled and 'Disable Drift Mode' or 'Enable Drift Mode',
            description = state.enabled
                and ('Restore stock handling; the chip stays installed. Active: %s'):format(state.profile)
                or ('Enable the saved %s tune on this vehicle.'):format(state.profile),
            icon = state.enabled and 'toggle-on' or 'toggle-off',
            onSelect = requestToggle,
        },
    }

    for _, name in ipairs(modeOrder()) do
        local selectedName = name
        local mode = Config.Modes[name]
        local selected = name == state.profile
        local title = (mode.label or name) .. (selected and '  [SAVED]' or '')
        local details = ('%s  Power +%.0f%% | Torque x%.2f%s'):format(
            mode.desc or '',
            tonumber(mode.power) or 0.0,
            tonumber(mode.torque) or 1.0,
            mode.driftTyres == true and ' | Native drift tires' or ''
        )

        items[#items + 1] = {
            title = title,
            description = details,
            icon = selected and 'circle-check' or 'gauge-high',
            onSelect = function()
                local _, netId = requireDriverVehicle()
                if netId then TriggerServerEvent('rs-tunerchip:server:setProfile', netId, selectedName) end
            end,
        }
    end

    local persistence = state.persistent and 'Persistent owned-vehicle install' or 'Session install'
    local title = ('%s | %s'):format(Config.Msg.menuTitle or 'RS Drift Controller', state.plate or '')
    RSTCBridge.OpenMenu(title, items, persistence)
end

local function openMenu(state)
    if not state or state.installed ~= true then
        RSTCBridge.CloseTunerUi()
        notify(Config.Msg.notInstalled or 'No chip is installed on this vehicle.', 'error')
        return
    end

    if not RSTCBridge.OpenTunerUi(menuPayload(state)) then fallbackMenu(state) end
end

RegisterNUICallback('close', function(_, cb)
    RSTCBridge.CloseTunerUi()
    cb({ ok = true })
end)

RegisterNUICallback('toggle', function(_, cb)
    cb({ ok = requestToggle() })
end)

RegisterNUICallback('setProfile', function(data, cb)
    local profile = type(data) == 'table' and data.profile or nil
    if type(profile) ~= 'string' or not Config.Modes[profile] then
        cb({ ok = false })
        return
    end

    local _, netId = requireDriverVehicle()
    if not netId then
        cb({ ok = false })
        return
    end

    TriggerServerEvent('rs-tunerchip:server:setProfile', netId, profile)
    cb({ ok = true })
end)

RegisterNetEvent('rs-tunerchip:client:Notify', function(message, notifyType, duration)
    if source ~= 65535 then return end
    notify(message, notifyType, duration)
end)

RegisterNetEvent('rs-tunerchip:client:SyncVehicle', function(netId, state, openAfter, smooth)
    if source ~= 65535 then return end
    local vehicle = getDriverVehicle()
    if not vehicle or getVehicleNetId(vehicle) ~= tonumber(netId) then return end

    state = type(state) == 'table' and state or {}
    if not Config.Modes[state.profile] then state.profile = DEFAULT_PROFILE end
    state.installed = state.installed == true
    state.enabled = state.enabled == true
    state.persistent = state.persistent == true
    CurrentVehicleState = state

    if state.installed and state.enabled and isClassAllowed(vehicle) then
        applyProfile(vehicle, state.profile, false)
    else
        disableDrift(vehicle, smooth ~= true)
    end

    if state.installed ~= true then
        if RSTCBridge.IsTunerUiOpen() then RSTCBridge.CloseTunerUi() end
    elseif openAfter then
        openMenu(state)
    elseif RSTCBridge.IsTunerUiOpen() then
        RSTCBridge.UpdateTunerUi(menuPayload(state))
    end
end)

local function performProgress(kind, duration)
    local label = kind == 'install'
        and (Config.Msg.installing or 'Installing RS Drift Chip...')
        or (Config.Msg.removing or 'Removing RS Drift Chip...')

    if lib and lib.progressBar then
        return lib.progressBar({
            duration = math.max(0, tonumber(duration) or 0),
            label = label,
            useWhileDead = false,
            canCancel = true,
            disable = {
                move = true,
                car = true,
                combat = true,
            },
        }) == true
    end

    notify(label, 'inform', duration)
    Wait(math.max(0, tonumber(duration) or 0))
    return true
end

RegisterNetEvent('rs-tunerchip:client:BeginItemAction', function(kind, netId, duration)
    if source ~= 65535 or actionRunning then return end
    if kind ~= 'install' and kind ~= 'remove' then return end

    local vehicle = getDriverVehicle()
    if not vehicle or getVehicleNetId(vehicle) ~= tonumber(netId) then
        TriggerServerEvent('rs-tunerchip:server:cancelItemAction', kind, netId)
        return
    end

    actionRunning = true
    local completed = performProgress(kind, duration)
    actionRunning = false

    vehicle = getDriverVehicle()
    if completed and vehicle and getVehicleNetId(vehicle) == tonumber(netId) then
        TriggerServerEvent('rs-tunerchip:server:completeItemAction', kind, netId)
    else
        TriggerServerEvent('rs-tunerchip:server:cancelItemAction', kind, netId)
        notify(
            kind == 'install' and (Config.Msg.installCanceled or 'Installation canceled.')
                or (Config.Msg.removeCanceled or 'Removal canceled.'),
            'error'
        )
    end
end)

-- Driver changes are the only automatic activation point. There is no player
-- global flag: entering a different vehicle always requests that vehicle's own
-- authoritative install record.
CreateThread(function()
    local lastDriverVehicle = 0
    local stateRequested = false

    while true do
        Wait(400)
        local vehicle = getDriverVehicle()

        if vehicle then
            if vehicle ~= lastDriverVehicle then
                if RSTCBridge.IsTunerUiOpen() then RSTCBridge.CloseTunerUi() end
                if lastDriverVehicle ~= 0 and DoesEntityExist(lastDriverVehicle) then
                    disableDrift(lastDriverVehicle, true)
                end
                lastDriverVehicle = vehicle
                stateRequested = false
                CurrentVehicleState = {
                    installed = false,
                    enabled = false,
                    profile = DEFAULT_PROFILE,
                    persistent = false,
                    plate = GetVehicleNumberPlateText(vehicle) or '',
                }
            end

            if not stateRequested then
                local netId = getVehicleNetId(vehicle)
                if netId then
                    stateRequested = true
                    TriggerServerEvent('rs-tunerchip:server:requestVehicleState', netId)
                end
            end
        else
            if RSTCBridge.IsTunerUiOpen() then RSTCBridge.CloseTunerUi() end
            if lastDriverVehicle ~= 0 and DoesEntityExist(lastDriverVehicle) then
                disableDrift(lastDriverVehicle, true)
            end
            lastDriverVehicle = 0
            stateRequested = false
            CurrentVehicleState = {
                installed = false,
                enabled = false,
                profile = DEFAULT_PROFILE,
                persistent = false,
                plate = '',
            }
        end
    end
end)

local function handlePlayerUnloaded()
    RSTCBridge.CloseTunerUi()
    local vehicle = getDriverVehicle()
    if vehicle then disableDrift(vehicle, true) end
end

AddEventHandler('QBCore:Client:OnPlayerUnload', handlePlayerUnloaded)
AddEventHandler('qbx_core:client:playerLoggedOut', handlePlayerUnloaded)
AddEventHandler('esx:onPlayerLogout', handlePlayerUnloaded)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    RSTCBridge.CloseTunerUi()
    for _, store in pairs(DriftStore) do
        local vehicle = store.vehicle
        if vehicle and DoesEntityExist(vehicle) then
            -- Direct restore: threads do not survive a resource stop.
            for field, base in pairs(store.orig or {}) do
                if handlingFieldSet[field] then
                    SetVehicleHandlingFloat(vehicle, 'CHandlingData', field, base)
                end
            end
            SetVehicleEnginePowerMultiplier(vehicle, store.orig.enginePower or 0.0)
            SetVehicleEngineTorqueMultiplier(vehicle, store.orig.engineTorque or 1.0)
            setDriftTyres(vehicle, store.orig.driftTyres == true)
            if store.usedReduceGrip then pcall(SetVehicleReduceGrip, vehicle, false) end
        end
    end
end)

RegisterCommand(Config.ToggleCommand or 'drift', requestToggle, false)
RegisterKeyMapping(
    Config.ToggleCommand or 'drift',
    'Toggle installed vehicle drift mode',
    'keyboard',
    Config.ToggleKey or 'F5'
)

RegisterCommand(Config.MenuCommand or 'driftmenu', function()
    local _, netId = requireDriverVehicle()
    if netId then TriggerServerEvent('rs-tunerchip:server:requestMenu', netId) end
end, false)
RegisterKeyMapping(
    Config.MenuCommand or 'driftmenu',
    'Open installed vehicle drift controller',
    'keyboard',
    Config.MenuKey or 'F10'
)

RegisterCommand(Config.StatusCommand or 'driftstatus', function()
    local vehicle = getDriverVehicle()
    if not vehicle then
        notify(Config.Msg.needDriver or 'Sit in the driver seat first.', 'error')
        return
    end

    if CurrentVehicleState.installed ~= true then
        notify(Config.Msg.notInstalled or 'No chip is installed on this vehicle.', 'error', 4000)
        return
    end

    local store = findDriftStore(vehicle)
    if CurrentVehicleState.enabled ~= true or not store or store.enabled ~= true then
        notify(Config.Msg.statusOff or 'The chip is installed, but drift mode is off.', 'inform', 3500)
        return
    end

    local localVelocity = GetEntitySpeedVector(vehicle, true)
    local slipAngle = math.deg(math.atan(math.abs(localVelocity.x), math.max(0.01, math.abs(localVelocity.y))))
    local speedKph = GetEntitySpeed(vehicle) * 3.6
    local summary = ('%s active | %.0f km/h | %.1f deg slip | power +%.0f%% | torque x%.2f'):format(
        store.profile or CurrentVehicleState.profile,
        speedKph,
        slipAngle,
        store.power or 0.0,
        store.torque or 1.0
    )
    notify(summary, 'success', 6000)
end, false)
