-- =============================================================================
-- RS TUNER CHIP SERVER ADAPTER -- self-contained framework/inventory helpers
-- =============================================================================
-- Owns the server-side compatibility surface for this resource.
-- All compatibility logic is included inside this resource.
--
-- Frameworks: Qbox, QBCore, ESX
-- Inventory:  ox_inventory when present, otherwise framework inventory
-- =============================================================================

RSTCBridge = RSTCBridge or {}

local function started(resource)
    return GetResourceState(resource) == 'started'
end

local function safeCall(fn, ...)
    local ok, a, b = pcall(fn, ...)
    if ok then return true, a, b end
    return false, nil, a
end

local function core()
    if not RSFramework or not RSFramework.GetCore then return nil end
    local ok, value = pcall(RSFramework.GetCore)
    return ok and value or nil
end

function RSTCBridge.Framework()
    if RSFramework and RSFramework.Detect then
        local ok, fw = pcall(RSFramework.Detect)
        if ok then return fw end
    end
    return 'standalone'
end

function RSTCBridge.HasItem(src, itemName, amount)
    src = tonumber(src)
    amount = math.max(1, tonumber(amount) or 1)
    if not src or src <= 0 or type(itemName) ~= 'string' or itemName == '' then return false end

    if started('ox_inventory') then
        local ok, count = safeCall(function()
            return exports.ox_inventory:Search(src, 'count', itemName)
        end)
        return ok and (tonumber(count) or 0) >= amount
    end

    local c = core()
    local player = c and c.Functions and c.Functions.GetPlayer and c.Functions.GetPlayer(src) or nil
    if not player or not player.Functions then return false end

    if player.Functions.GetItemByName then
        local ok, item = safeCall(player.Functions.GetItemByName, itemName)
        if ok and type(item) == 'table' then
            local count = tonumber(item.amount or item.count or item.quantity or 1) or 0
            return count >= amount
        end
    end

    return false
end

function RSTCBridge.RemoveItem(src, itemName, amount, slot)
    src = tonumber(src)
    amount = math.max(1, tonumber(amount) or 1)
    slot = tonumber(slot)
    if not src or src <= 0 or type(itemName) ~= 'string' or itemName == '' then return false end

    if started('ox_inventory') then
        local ok, removed = safeCall(function()
            return exports.ox_inventory:RemoveItem(src, itemName, amount, nil, slot)
        end)
        return ok and removed == true
    end

    local c = core()
    local player = c and c.Functions and c.Functions.GetPlayer and c.Functions.GetPlayer(src) or nil
    if not player or not player.Functions or not player.Functions.RemoveItem then return false end

    local ok, removed = safeCall(player.Functions.RemoveItem, itemName, amount, slot)
    return ok and removed ~= false
end

function RSTCBridge.CreateUseableItem(itemName, callback)
    if type(itemName) ~= 'string' or itemName == '' or type(callback) ~= 'function' then
        return false, 'invalid item registration'
    end

    local fw = RSTCBridge.Framework()

    if fw == 'qbox' and started('qbx_core') then
        local ok, err = pcall(function()
            exports.qbx_core:CreateUseableItem(itemName, callback)
        end)
        return ok, ok and nil or tostring(err)
    end

    local c = core()
    if c and c.Functions and c.Functions.CreateUseableItem then
        local ok, result = pcall(c.Functions.CreateUseableItem, itemName, callback)
        if ok then return result ~= false, result == false and 'framework rejected usable item' or nil end
        return false, tostring(result)
    end

    return false, ('framework not ready (%s)'):format(tostring(fw))
end
