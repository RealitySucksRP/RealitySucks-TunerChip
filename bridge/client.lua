-- Local client provider for Qbox, QBCore, ESX and standalone.
-- UI ownership and shared key-mapping state remain local to this resource.

RSTCBridge = RSTCBridge or {}

function RSTCBridge.Framework()
    if GetResourceState('qbx_core') == 'started' then return 'qbox' end
    if GetResourceState('qb-core') == 'started' then return 'qbcore' end
    if GetResourceState('es_extended') == 'started' then return 'esx' end
    return 'standalone'
end

RSTCBridge.Core = {
    Functions = {
        Notify = function(message, notifyType, duration)
            if lib and lib.notify then
                local ok = pcall(lib.notify, {
                    title = 'RS Tuner Chip',
                    description = tostring(message),
                    type = notifyType or 'inform',
                    duration = duration
                })
                if ok then return true end
            end
            print(('[rs-tunerchip] %s'):format(tostring(message)))
            return false
        end,
        GetPlayerData = function()
            local provider = RSTCBridge.Framework()
            local ok, data
            if provider == 'qbox' then
                ok, data = pcall(function() return exports.qbx_core:GetPlayerData() end)
            elseif provider == 'qbcore' then
                ok, data = pcall(function()
                    return exports['qb-core']:GetCoreObject().Functions.GetPlayerData()
                end)
            elseif provider == 'esx' then
                ok, data = pcall(function()
                    return exports['es_extended']:getSharedObject().GetPlayerData()
                end)
            end
            return ok and type(data) == 'table' and data or {}
        end
    }
}

-- NUI focus is coordinated through local player state. Setting
-- rsUiOpen blocks other RS key mappings while the drift controller owns input,
-- and closing always releases both focus modes.
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

-- A NUI page is created as soon as the resource starts, before any vehicle or
-- menu state exists. Explicitly clear focus and hide the page so a cached CEF
-- document or interrupted resource restart can never leave a full-screen
-- surface over gameplay.
CreateThread(function()
    Wait(0)
    RSTCBridge.CloseTunerUi()
end)

-- Menu abstraction.
--
-- ox_lib is the framework-neutral fallback menu provider. qb-menu remains an
-- optional secondary fallback for QBCore servers that already use it.
--
-- items: { { title, description, onSelect = function() end }, ... }
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

-- qb-menu cannot carry closures through params, so route its selection back
-- to the stored item list.
RegisterNetEvent('rs-tunerchip:client:menuSelect', function(data)
    local items = RSTCBridge._menuItems
    local item = items and data and items[data.index]
    if item and item.onSelect then item.onSelect() end
end)
