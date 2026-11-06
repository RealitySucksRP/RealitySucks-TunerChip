-- =============================================================================
-- RS TUNER CHIP CLIENT ADAPTER -- local framework helpers
-- =============================================================================
-- Uses the included RSFramework adapter for framework detection,
-- notifications, and player data.
-- =============================================================================

RSTCBridge = RSTCBridge or {}

local function core()
    if not RSFramework or not RSFramework.GetCore then return nil end
    local ok, value = pcall(RSFramework.GetCore)
    return ok and value or nil
end

function RSTCBridge.Framework()
    if not RSFramework or not RSFramework.Detect then return 'standalone' end
    local ok, framework = pcall(RSFramework.Detect)
    return ok and framework or 'standalone'
end

RSTCBridge.Core = {
    Functions = {
        Notify = function(message, notifyType, duration)
            local c = core()
            if c and c.Functions and c.Functions.Notify then
                local ok = pcall(c.Functions.Notify, message, notifyType, duration)
                if ok then return true end
            end

            if lib and lib.notify then
                local ok = pcall(lib.notify, {
                    description = tostring(message or ''),
                    type = notifyType or 'inform',
                    duration = tonumber(duration) or 5000,
                })
                if ok then return true end
            end

            if message then
                BeginTextCommandThefeedPost('STRING')
                AddTextComponentSubstringPlayerName(tostring(message))
                EndTextCommandThefeedPostTicker(false, false)
                return true
            end
            return false
        end,
        GetPlayerData = function()
            local c = core()
            if c and c.Functions and c.Functions.GetPlayerData then
                local ok, data = pcall(c.Functions.GetPlayerData)
                if ok and type(data) == 'table' then return data end
            end
            return {}
        end
    }
}

-- Custom NUI focus coordination. Setting rsUiOpen blocks other RS key mappings
-- while the drift controller owns input, and closing always releases focus.
local tunerUiOpen = false

local function setSharedUiState(open)
    local state = LocalPlayer and LocalPlayer.state
    if state then state:set('rsUiOpen', open == true, false) end
end

function RSTCBridge.OpenTunerUi(payload)
    if type(payload) ~= 'table' then return false end

    tunerUiOpen = true
    setSharedUiState(true)
    SetNuiFocus(true, true)
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
    SendNUIMessage({ action = 'open', payload = payload })
    return true
end

function RSTCBridge.UpdateTunerUi(payload)
    if not tunerUiOpen or type(payload) ~= 'table' then return false end
    SendNUIMessage({ action = 'update', payload = payload })
    return true
end

function RSTCBridge.CloseTunerUi()
    tunerUiOpen = false
    setSharedUiState(false)
    SetNuiFocus(false, false)
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
    SendNUIMessage({ action = 'close' })
    return true
end

function RSTCBridge.IsTunerUiOpen()
    return tunerUiOpen
end

CreateThread(function()
    Wait(0)
    RSTCBridge.CloseTunerUi()
end)

-- Menu abstraction. ox_lib is framework-neutral and preferred; qb-menu remains
-- a fallback for QBCore servers that still use it.
function RSTCBridge.OpenMenu(title, items)
    if lib and lib.registerContext and lib.showContext then
        local options = {}
        for i = 1, #items do
            local item = items[i]
            options[i] = {
                title = item.title,
                description = item.description,
                icon = item.icon,
                onSelect = item.onSelect
            }
        end

        local ok, err = pcall(function()
            lib.registerContext({
                id = 'rs_tunerchip_menu',
                title = title,
                options = options
            })
            lib.showContext('rs_tunerchip_menu')
        end)
        if ok then return true end
        print(('[rs-tunerchip] ox_lib menu failed: %s'):format(tostring(err)))
    end

    if GetResourceState('qb-menu') == 'started' then
        local header = { { header = title, isMenuHeader = true } }
        for i = 1, #items do
            local item = items[i]
            header[#header + 1] = {
                header = item.title,
                txt = item.description,
                params = {
                    event = 'rs-tunerchip:client:menuSelect',
                    args = { index = i }
                }
            }
        end
        RSTCBridge._menuItems = items
        TriggerEvent('qb-menu:client:openMenu', header)
        return true
    end

    RSTCBridge.Core.Functions.Notify('No menu system found (ox_lib or qb-menu required).', 'error')
    return false
end

RegisterNetEvent('rs-tunerchip:client:menuSelect', function(data)
    local items = RSTCBridge._menuItems
    local item = items and data and items[data.index]
    if item and item.onSelect then item.onSelect() end
end)
