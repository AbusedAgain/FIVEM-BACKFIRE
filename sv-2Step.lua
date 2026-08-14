-- sv-2Step.lua — Fully Fixed Version

local ESX = nil
local installedVehicles = {}

-- FIX: get ESX safely instead of at script load time
CreateThread(function()
    while not ESX do
        pcall(function() ESX = exports['es_extended']:getSharedObject() end)
        Wait(100)
    end
end)

-- Load all ECU-flashed vehicles from DB on startup
MySQL.ready(function()
    MySQL.query('SELECT plate FROM owned_vehicles WHERE ecu_flash = 1', {}, function(result)
        if result then
            for _, row in ipairs(result) do
                installedVehicles[row.plate] = true
            end
        end
    end)
end)

-- FIX: broadcast plateECUChanged to all players so cache updates everywhere
local function broadcastECUChange(plate, installed)
    for _, playerId in ipairs(GetPlayers()) do
        TriggerClientEvent("antilag:plateECUChanged", tonumber(playerId), plate, installed)
    end
end

RegisterNetEvent("antilag:installECU")
AddEventHandler("antilag:installECU", function(plate)
    local src    = source
    local player = ESX and ESX.GetPlayerFromId(src)
    if not player then return end

    if player.getJob().name ~= 'mechanic' then
        TriggerClientEvent("antilag:notify", src, "~r~Only a mechanic can install this!")
        return
    end

    if installedVehicles[plate] then
        TriggerClientEvent("antilag:notify", src, "~r~ECU Flash already installed on this vehicle!")
        return
    end

    local item = exports.ox_inventory:GetItem(src, 'ecu_flash', nil, false)
    if not item or item.count < 1 then
        TriggerClientEvent("antilag:notify", src, "~r~You don't have an ECU Flash!")
        return
    end

    exports.ox_inventory:RemoveItem(src, 'ecu_flash', 1)

    MySQL.update('UPDATE owned_vehicles SET ecu_flash = 1 WHERE plate = ?', {plate}, function(rowsChanged)
        if rowsChanged > 0 then
            installedVehicles[plate] = true
            broadcastECUChange(plate, true)
            TriggerClientEvent("antilag:notify", src, "~g~ECU Flash successfully installed!")
        else
            -- DB update failed — refund the item
            exports.ox_inventory:AddItem(src, 'ecu_flash', 1)
            TriggerClientEvent("antilag:notify", src, "~r~Could not find vehicle in database!")
        end
    end)
end)

RegisterNetEvent("antilag:removeECU")
AddEventHandler("antilag:removeECU", function(plate)
    local src    = source
    local player = ESX and ESX.GetPlayerFromId(src)
    if not player then return end

    if player.getJob().name ~= 'mechanic' then
        TriggerClientEvent("antilag:notify", src, "~r~Only a mechanic can remove this!")
        return
    end

    if not installedVehicles[plate] then
        TriggerClientEvent("antilag:notify", src, "~r~No ECU Flash installed on this vehicle!")
        return
    end

    MySQL.update('UPDATE owned_vehicles SET ecu_flash = 0 WHERE plate = ?', {plate}, function(rowsChanged)
        if rowsChanged > 0 then
            installedVehicles[plate] = nil
            broadcastECUChange(plate, false)
            exports.ox_inventory:AddItem(src, 'ecu_flash', 1)
            TriggerClientEvent("antilag:notify", src, "~g~ECU Flash successfully removed!")
        else
            TriggerClientEvent("antilag:notify", src, "~r~Could not find vehicle in database!")
        end
    end)
end)

RegisterNetEvent("antilag:checkECU")
AddEventHandler("antilag:checkECU", function(plate)
    local src = source
    TriggerClientEvent("antilag:ecuStatus", src, plate, installedVehicles[plate] == true)
end)

-- Broadcast flame effect to all clients
RegisterNetEvent("2step:eff_flames")
AddEventHandler("2step:eff_flames", function(netVeh)
    TriggerClientEvent("2step:c_eff_flames", -1, netVeh)
end)