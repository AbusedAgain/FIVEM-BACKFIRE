--[[
    Antilag & 2-Step Script — Client
    - ECU state persists across restarts (server-authoritative)
    - gameEvent filtered to local player only
    - Flames handled locally (no server round-trip for visuals/sound)
]]

RegisterNetEvent("2step:Anti-lag")
RegisterNetEvent("2step:c_eff_flames")
RegisterNetEvent("antilag:ecuStatus")
RegisterNetEvent("antilag:plateECUChanged")
RegisterNetEvent("antilag:notify")

local activated        = false
local antilag          = true
local AntilagDisplay   = false
local firstGearDisplay = false
local ecuInstalled     = false
local ecuCache         = {}
local animPlaying      = false
local lastFlameTime    = 0
local ptfxLoaded       = false

-- ── Preload ptfx asset on resource start ─────────────────────────────────────
CreateThread(function()
    RequestNamedPtfxAsset("core")
    local timeout = 0
    while not HasNamedPtfxAssetLoaded("core") do
        Wait(10)
        timeout = timeout + 10
        if timeout > 5000 then break end
    end
    ptfxLoaded = HasNamedPtfxAssetLoaded("core")
end)

-- ── Anti-lag toggle ──────────────────────────────────────────────────────────
AddEventHandler("2step:Anti-lag", function()
    antilag = not antilag
    Notif(antilag and "~c~Anti-Lag has been ~b~Enabled!" or "~c~Anti-Lag has been ~r~Disabled!")
end)

-- ── ECU status received from server ─────────────────────────────────────────
AddEventHandler("antilag:ecuStatus", function(plate, status)
    ecuCache[plate] = status
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return end
    local veh = GetVehiclePedIsIn(ped, false)
    if GetPedInVehicleSeat(veh, -1) == ped and GetVehicleNumberPlateText(veh) == plate then
        ecuInstalled = status
    end
end)

-- ── ECU changed broadcast ─────────────────────────────────────────────────────
AddEventHandler("antilag:plateECUChanged", function(plate, installed)
    ecuCache[plate] = installed
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return end
    local veh = GetVehiclePedIsIn(ped, false)
    if GetPedInVehicleSeat(veh, -1) == ped and GetVehicleNumberPlateText(veh) == plate then
        ecuInstalled = installed
        Notif(installed and "~g~ECU Flash is now active on this vehicle!" or "~r~ECU Flash has been removed from this vehicle.")
    end
end)

-- ── Notify ────────────────────────────────────────────────────────────────────
AddEventHandler("antilag:notify", function(msg)
    Notif(msg)
end)

-- ── gameEvent: filter to local player only ────────────────────────────────────
AddEventHandler('gameEvent', function(name, args)
    if name == 'CEventNetworkPlayerEnteredVehicle' then
        local ped = PlayerPedId()
        if args[1] ~= ped then return end
        local veh = GetVehiclePedIsIn(ped, false)
        if veh and veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
            ecuInstalled = false
            local plate = GetVehicleNumberPlateText(veh)
            if ecuCache[plate] ~= nil then ecuInstalled = ecuCache[plate] end
            TriggerServerEvent("antilag:checkECU", plate)
        end
    end
    if name == 'CEventNetworkPlayerLeftVehicle' then
        local ped = PlayerPedId()
        if args[1] ~= ped then return end
        ecuInstalled = false
    end
end)

-- ── Resource start — already in vehicle ──────────────────────────────────────
CreateThread(function()
    Wait(1000)
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        local veh = GetVehiclePedIsIn(ped, false)
        if GetPedInVehicleSeat(veh, -1) == ped then
            local plate = GetVehicleNumberPlateText(veh)
            ecuInstalled = false
            if ecuCache[plate] ~= nil then ecuInstalled = ecuCache[plate] end
            TriggerServerEvent("antilag:checkECU", plate)
        end
    end
end)

-- ── Nearby vehicle ECU cache ──────────────────────────────────────────────────
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local veh = GetClosestVehicle(coords.x, coords.y, coords.z, 5.0, 0, 71)
        if veh and veh ~= 0 and DoesEntityExist(veh) then
            local plate = GetVehicleNumberPlateText(veh)
            if plate and ecuCache[plate] == nil then
                TriggerServerEvent("antilag:checkECU", plate)
            end
        end
        Wait(1000)
    end
end)

-- ── Exhaust bone names ────────────────────────────────────────────────────────
local exhaustBones = {
    "exhaust", "exhaust_2", "exhaust_3", "exhaust_4",
    "exhaust_5", "exhaust_6", "exhaust_7", "exhaust_8",
}

-- ── Core effect function: optimized flames + custom explosion sound ───────────
local function fireEffect(veh)
    if not DoesEntityExist(veh) then return end

    local pos = GetEntityCoords(veh)

    -- Sound: optimized explosion type 59 (sound only, no physics/damage)
    AddExplosion(pos.x, pos.y, pos.z, 59, 0.0, true, false, 0.0, false)

    -- Optimized particles on exhaust bones
    if ptfxLoaded then
        for _, boneName in ipairs(exhaustBones) do
            local boneIdx = GetEntityBoneIndexByName(veh, boneName)
            if boneIdx ~= -1 then
                local bonePos = GetWorldPositionOfEntityBone(veh, boneIdx)
                local off     = GetOffsetFromEntityGivenWorldCoords(veh, bonePos.x, bonePos.y, bonePos.z)
                UseParticleFxAssetNextCall("core")
                StartParticleFxNonLoopedOnEntity(
                    "veh_backfire", veh,
                    off.x, off.y, off.z,
                    0.0, 0.0, 0.0,
                    2.0, false, false, false
                )
            end
        end
    end
end

-- ── Flame broadcast for OTHER players seeing your car ────────────────────────
AddEventHandler("2step:c_eff_flames", function(c_veh)
    local veh = NetToVeh(c_veh)
    if not DoesEntityExist(veh) then return end

    -- Skip if this is our own vehicle (we already fired locally)
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) == veh then return end

    if ptfxLoaded then
        for _, boneName in ipairs(exhaustBones) do
            local boneIdx = GetEntityBoneIndexByName(veh, boneName)
            if boneIdx ~= -1 then
                local bonePos = GetWorldPositionOfEntityBone(veh, boneIdx)
                local off     = GetOffsetFromEntityGivenWorldCoords(veh, bonePos.x, bonePos.y, bonePos.z)
                UseParticleFxAssetNextCall("core")
                StartParticleFxNonLoopedOnEntity(
                    "veh_backfire", veh,
                    off.x, off.y, off.z,
                    0.0, 0.0, 0.0,
                    2.0, false, false, false
                )
            end
        end
    end
end)

-- ── Hood animation ───────────────────────────────────────────────────────────
local function playHoodAnimation(ped, veh, duration, callback)
    if animPlaying then return end
    animPlaying = true
    local animDict = "mini@repair"
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do Wait(10) end
    SetVehicleDoorOpen(veh, 4, false, false)
    TaskPlayAnim(ped, animDict, "fixing_a_ped", 2.0, -1.0, duration, 1, 0, false, false, false)
    Wait(duration)
    ClearPedTasks(ped)
    SetVehicleDoorShut(veh, 4, false)
    RemoveAnimDict(animDict)
    animPlaying = false
    if callback then callback() end
end

-- ── ox_target ─────────────────────────────────────────────────────────────────
CreateThread(function()
    exports.ox_target:addGlobalVehicle({
        {
            name        = 'install_ecu',
            icon        = 'fas fa-microchip',
            label       = 'Install ECU Flash',
            distance    = 2.0,
            onSelect    = function(data)
                local veh   = data.entity
                local plate = GetVehicleNumberPlateText(veh)
                Notif("~y~Installing ECU Flash...")
                playHoodAnimation(PlayerPedId(), veh, 7000, function()
                    TriggerServerEvent("antilag:installECU", plate)
                end)
            end,
            canInteract = function(entity)
                if IsPedInAnyVehicle(PlayerPedId(), false) then return false end
                if animPlaying then return false end
                return ecuCache[GetVehicleNumberPlateText(entity)] ~= true
            end
        },
        {
            name        = 'remove_ecu',
            icon        = 'fas fa-microchip',
            label       = 'Remove ECU Flash',
            distance    = 2.0,
            onSelect    = function(data)
                local veh   = data.entity
                local plate = GetVehicleNumberPlateText(veh)
                Notif("~y~Removing ECU Flash...")
                playHoodAnimation(PlayerPedId(), veh, 3500, function()
                    TriggerServerEvent("antilag:removeECU", plate)
                end)
            end,
            canInteract = function(entity)
                if IsPedInAnyVehicle(PlayerPedId(), false) then return false end
                if animPlaying then return false end
                return ecuCache[GetVehicleNumberPlateText(entity)] == true
            end
        }
    })
end)

-- ── Main effects loop ─────────────────────────────────────────────────────────
Citizen.CreateThread(function()
    while true do
        local sleep = 250
        local ped   = PlayerPedId()

        activated        = false
        AntilagDisplay   = false
        firstGearDisplay = false

        if IsPedInAnyVehicle(ped, false) then
            local veh = GetVehiclePedIsIn(ped, false)

            if GetPedInVehicleSeat(veh, -1) == ped then
                sleep = 0

                local speed    = GetEntitySpeed(veh) * 2.236936
                local gear     = GetVehicleCurrentGear(veh)
                local throttle = GetControlNormal(0, 71)
                local rpm      = GetVehicleCurrentRpm(veh)
                local now      = GetGameTimer()
                local canFire  = (now - lastFlameTime) > 150

                if ecuInstalled then

                    -- 2-Step: stationary rev limiter
                    if speed < 15.0 and throttle > 0.05 and rpm > 0.88 then
                        activated = true
                        if canFire then
                            lastFlameTime = now
                            fireEffect(veh)
                            TriggerServerEvent("2step:eff_flames", VehToNet(veh))
                        end
                        Wait(math.random(350, 700))

                    -- Anti-Lag: lift-off at speed
                    elseif antilag and speed > 10.0 and throttle <= 0.05 and rpm > 0.45 then
                        AntilagDisplay = true
                        if canFire then
                            lastFlameTime = now
                            fireEffect(veh)
                            TriggerServerEvent("2step:eff_flames", VehToNet(veh))
                            SetVehicleTurboPressure(veh, 25.0)
                        end
                        Wait(math.random(200, 450))

                    -- First gear pops
                    elseif gear == 1 and speed > 5.0 and speed < 35.0 and throttle > 0.05 and rpm > 0.35 then
                        firstGearDisplay = true
                        if canFire then
                            lastFlameTime = now
                            fireEffect(veh)
                            TriggerServerEvent("2step:eff_flames", VehToNet(veh))
                        end
                        Wait(math.random(80, 180))
                    end

                end
            end
        end

        Wait(sleep)
    end
end)

-- ── HUD ──────────────────────────────────────────────────────────────────────
Citizen.CreateThread(function()
    while true do
        local sleep = 500
        if activated then
            sleep = 0
            DrawHudText("|",      {255, 0, 0, 255},   0.955, 0.8825, 0.7, 0.7, 7)
            DrawHudText("2Step",   {0, 255, 85, 255},   0.92,  0.88,   0.7, 0.7, 6)
        end
        if AntilagDisplay then
            sleep = 0
            DrawHudText("|",        {255, 0, 0, 255},  0.955, 0.8825, 0.7, 0.7, 7)
            DrawHudText("Anti-Lag", {0, 255, 85, 255},  0.92,  0.88,   0.7, 0.7, 6)
        end
        if firstGearDisplay then
            sleep = 0
            DrawHudText("|",        {255, 0, 0, 255},  0.955, 0.8825, 0.7, 0.7, 7)
            DrawHudText("1st Gear", {0, 255, 85, 255},  0.92,  0.88,   0.7, 0.7, 6)
        end
        Wait(sleep)
    end
end)

-- ── Helpers ───────────────────────────────────────────────────────────────────
function DrawHudText(text, colour, coordsx, coordsy, scalex, scaley, font)
    SetTextFont(font)
    SetTextProportional(true)
    SetTextScale(scalex, scaley)
    SetTextColour(colour[1], colour[2], colour[3], colour[4])
    SetTextDropshadow(0, 0, 0, 0, 0)
    SetTextEdge(0, 0, 0, 0, 0)
    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(coordsx, coordsy)
end

function Notif(text)
    SetNotificationTextEntry("STRING")
    AddTextComponentString(text)
    DrawNotification(false, false)
end