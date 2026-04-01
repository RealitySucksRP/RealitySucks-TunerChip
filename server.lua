local QBCore = exports['qb-core']:GetCoreObject()

-- Useable item: ws_driftchip
QBCore.Functions.CreateUseableItem('ws_driftchip', function(source, item)
    TriggerClientEvent('ws-driftchip:client:SelectMode', source, { profile = 'Balanced' })
end)

RegisterNetEvent('ws-driftchip:saveEnabled', function(enabled, profile)
    local src    = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    Player.Functions.SetMetaData('drift_mode', enabled and true or false)

    if profile and type(profile) == 'string' then
        Player.Functions.SetMetaData('drift_profile', profile)
    end
end)

AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    local src  = Player.PlayerData.source
    local meta = Player.PlayerData.metadata or {}

    if meta['drift_mode'] then
        local profile = meta['drift_profile'] or 'Balanced'
        TriggerClientEvent('ws-driftchip:client:EnableDriftOnLogin', src, profile)
    end
end)
