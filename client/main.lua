-----------------------
----   Variables   ----
-----------------------
local QBCore = exports['qb-core']:GetCoreObject()
local Countdown = 10
local ToFarCountdown = 10
local FinishedUITimeout = false
local useDebug = Config.Debug
local RaceData = {
    InCreator = false,
    InRace = false,
    ClosestCheckpoint = 0
}

local CreatorData = {
    RaceName = nil,
    RacerName = nil,
    Checkpoints = {},
    TireDistance = 3.0,
    ConfirmDelete = false
}

local CurrentRaceData = {
    RaceId = nil,
    RaceName = nil,
    RacerName = nil,
    MaxClass = nil,
    Checkpoints = {},
    Started = false,
    CurrentCheckpoint = nil,
    TotalLaps = 0,
    TotalRacers = 0,
    Lap = 0,
    Position = 0,
    Ghosted = false,
}

local Classes = exports['cw-performance']:getPerformanceClasses()
local Entities = {}

-- for debug
local function dump(o)
    if type(o) == 'table' then
       local s = '{ '
       for k,v in pairs(o) do
          if type(k) ~= 'number' then k = '"'..k..'"' end
          s = s .. '['..k..'] = ' .. dump(v) .. ','
       end
       return s .. '} '
    else
       return tostring(o)
    end
end

-----------------------
----   Functions   ----
-----------------------

local function LoadModel(model)
    while not HasModelLoaded(model) do
        RequestModel(model)
        Wait(10)
    end
end

local function DeleteClosestObject(coords, model)
    local Obj = GetClosestObjectOfType(coords.x, coords.y, coords.z, 5.0, model, 0, 0, 0)
    DeleteObject(Obj)
    ClearAreaOfObjects(coords.x, coords.y, coords.z, 50.0, 0)
end

local function CreatePile(offset, model)
    ClearAreaOfObjects(offset.x, offset.y, offset.z, 50.0, 0)
    LoadModel(model)

    local Obj = CreateObject(model, offset.x, offset.y, offset.z, 0, 0, 0) -- CHANGE ONE OF THESE TO MAKE NETWORKED???
    PlaceObjectOnGroundProperly(Obj)
    -- FreezeEntityPosition(Obj, 1)
    SetEntityAsMissionEntity(Obj, 1, 1)

    return Obj
end

local function GhostPlayers()
    CreateGhostLoop()
end

local function UnGhostPlayer()
    SetLocalPlayerAsGhost(false)
    SetGhostedEntityAlpha(254)
end

function DeleteAllCheckpoints()
    for k, v in pairs(CreatorData.Checkpoints) do
        local CurrentCheckpoint = CreatorData.Checkpoints[k]

        if CurrentCheckpoint then
            local LeftPile = CurrentCheckpoint.pileleft
            local RightPile = CurrentCheckpoint.pileright

            if LeftPile then
                DeleteClosestObject(CurrentCheckpoint.offset.left, Config.StartAndFinishModel)
                DeleteClosestObject(CurrentCheckpoint.offset.left, Config.CheckpointPileModel)
                LeftPile = nil
            end
            if RightPile then
                DeleteClosestObject(CurrentCheckpoint.offset.right, Config.StartAndFinishModel)
                DeleteClosestObject(CurrentCheckpoint.offset.right, Config.CheckpointPileModel)
                RightPile = nil
            end
        end
    end

    for k, v in pairs(CurrentRaceData.Checkpoints) do
        local CurrentCheckpoint = CurrentRaceData.Checkpoints[k]

        if CurrentCheckpoint then
            local LeftPile = CurrentCheckpoint.pileleft
            local RightPile = CurrentCheckpoint.pileright

            if LeftPile then
                DeleteClosestObject(CurrentRaceData.Checkpoints[k].offset.left, Config.StartAndFinishModel)
                DeleteClosestObject(CurrentRaceData.Checkpoints[k].offset.left, Config.CheckpointPileModel)
                LeftPile = nil
            end

            if RightPile then
                DeleteClosestObject(CurrentRaceData.Checkpoints[k].offset.right, Config.StartAndFinishModel)
                DeleteClosestObject(CurrentRaceData.Checkpoints[k].offset.right, Config.CheckpointPileModel)
                RightPile = nil
            end
        end
    end
end

function DeleteCheckpoint()
    local NewCheckpoints = {}
    if RaceData.ClosestCheckpoint ~= 0 then
        local ClosestCheckpoint = CreatorData.Checkpoints[RaceData.ClosestCheckpoint]

        if ClosestCheckpoint then
            local Blip = ClosestCheckpoint.blip
            if Blip then
                RemoveBlip(Blip)
                Blip = nil
            end

            local PileLeft = ClosestCheckpoint.pileleft
            if PileLeft then
                DeleteClosestObject(ClosestCheckpoint.offset.left, Config.StartAndFinishModel)
                DeleteClosestObject(ClosestCheckpoint.offset.left, Config.CheckpointPileModel)
                PileLeft = nil
            end

            local PileRight = ClosestCheckpoint.pileright
            if PileRight then
                DeleteClosestObject(ClosestCheckpoint.offset.right, Config.StartAndFinishModel)
                DeleteClosestObject(ClosestCheckpoint.offset.right, Config.CheckpointPileModel)
                PileRight = nil
            end

            for id, data in pairs(CreatorData.Checkpoints) do
                if id ~= RaceData.ClosestCheckpoint then
                    NewCheckpoints[#NewCheckpoints + 1] = data
                end
            end
            CreatorData.Checkpoints = NewCheckpoints
        else
            QBCore.Functions.Notify(Lang:t("error.slow_down"), 'error')
        end
    else
        QBCore.Functions.Notify(Lang:t("error.slow_down"), 'error')
    end
end

function DeleteCreatorCheckpoints()
    for id, _ in pairs(CreatorData.Checkpoints) do
        local CurrentCheckpoint = CreatorData.Checkpoints[id]

        local Blip = CurrentCheckpoint.blip
        if Blip then
            RemoveBlip(Blip)
            Blip = nil
        end

        if CurrentCheckpoint then
            local PileLeft = CurrentCheckpoint.pileleft
            if PileLeft then
                DeleteClosestObject(CurrentCheckpoint.offset.left, Config.CheckpointPileModel)
                DeleteClosestObject(CurrentCheckpoint.offset.left, Config.StartAndFinishModel)
                PileLeft = nil
            end

            local PileRight = CurrentCheckpoint.pileright
            if PileRight then
                DeleteClosestObject(CurrentCheckpoint.offset.right, Config.CheckpointPileModel)
                DeleteClosestObject(CurrentCheckpoint.offset.right, Config.StartAndFinishModel)
                PileRight = nil
            end
        end
    end
end

function SetupPiles()
    for k, v in pairs(CreatorData.Checkpoints) do
        if not CreatorData.Checkpoints[k].pileleft then
            CreatorData.Checkpoints[k].pileleft = CreatePile(v.offset.left, Config.CheckpointPileModel)
        end

        if not CreatorData.Checkpoints[k].pileright then
            CreatorData.Checkpoints[k].pileright = CreatePile(v.offset.right, Config.CheckpointPileModel)
        end
    end
end

function SaveRace()
    local RaceDistance = 0

    for k, v in pairs(CreatorData.Checkpoints) do
        if k + 1 <= #CreatorData.Checkpoints then
            local checkpointdistance = #(vector3(v.coords.x, v.coords.y, v.coords.z) -
                                           vector3(CreatorData.Checkpoints[k + 1].coords.x,
                    CreatorData.Checkpoints[k + 1].coords.y, CreatorData.Checkpoints[k + 1].coords.z))
            RaceDistance = RaceDistance + checkpointdistance
        end
    end

    CreatorData.RaceDistance = RaceDistance

    TriggerServerEvent('cw-racingapp:server:SaveRace', CreatorData)
    Lang:t("error.slow_down")
    QBCore.Functions.Notify(Lang:t("success.race_saved") .. '(' .. CreatorData.RaceName .. ')', 'success')

    DeleteCreatorCheckpoints()

    RaceData.InCreator = false
    CreatorData.RaceName = nil
    CreatorData.RacerName = nil
    CreatorData.Checkpoints = {}
end

function GetClosestCheckpoint()
    local pos = GetEntityCoords(PlayerPedId(), true)
    local current = nil
    local dist = nil
    for id, _ in pairs(CreatorData.Checkpoints) do
        if current ~= nil then
            if #(pos -
                vector3(CreatorData.Checkpoints[id].coords.x, CreatorData.Checkpoints[id].coords.y,
                    CreatorData.Checkpoints[id].coords.z)) < dist then
                current = id
                dist = #(pos -
                           vector3(CreatorData.Checkpoints[id].coords.x, CreatorData.Checkpoints[id].coords.y,
                        CreatorData.Checkpoints[id].coords.z))
            end
        else
            dist = #(pos -
                       vector3(CreatorData.Checkpoints[id].coords.x, CreatorData.Checkpoints[id].coords.y,
                    CreatorData.Checkpoints[id].coords.z))
            current = id
        end
    end
    RaceData.ClosestCheckpoint = current
end

function CreatorUI()
    CreateThread(function()
        while true do
            if RaceData.InCreator then
                SendNUIMessage({
                    action = "Update",
                    type = "creator",
                    data = CreatorData,
                    racedata = RaceData,
                    active = true
                })
            else
                SendNUIMessage({
                    action = "Update",
                    type = "creator",
                    data = CreatorData,
                    racedata = RaceData,
                    active = false
                })
                break
            end
            Wait(200)
        end
    end)
end

function AddCheckpoint()
    local PlayerPed = PlayerPedId()
    local PlayerPos = GetEntityCoords(PlayerPed)
    local PlayerVeh = GetVehiclePedIsIn(PlayerPed)
    local Offset = {
        left = {
            x = (GetOffsetFromEntityInWorldCoords(PlayerVeh, -CreatorData.TireDistance, 0.0, 0.0)).x,
            y = (GetOffsetFromEntityInWorldCoords(PlayerVeh, -CreatorData.TireDistance, 0.0, 0.0)).y,
            z = (GetOffsetFromEntityInWorldCoords(PlayerVeh, -CreatorData.TireDistance, 0.0, 0.0)).z
        },
        right = {
            x = (GetOffsetFromEntityInWorldCoords(PlayerVeh, CreatorData.TireDistance, 0.0, 0.0)).x,
            y = (GetOffsetFromEntityInWorldCoords(PlayerVeh, CreatorData.TireDistance, 0.0, 0.0)).y,
            z = (GetOffsetFromEntityInWorldCoords(PlayerVeh, CreatorData.TireDistance, 0.0, 0.0)).z
        }
    }

    CreatorData.Checkpoints[#CreatorData.Checkpoints + 1] = {
        coords = {
            x = PlayerPos.x,
            y = PlayerPos.y,
            z = PlayerPos.z
        },
        offset = Offset
    }

    for id, CheckpointData in pairs(CreatorData.Checkpoints) do
        if CheckpointData.blip ~= nil then
            RemoveBlip(CheckpointData.blip)
        end

        CheckpointData.blip = CreateCheckpointBlip(CheckpointData.coords, id)
    end
end

function CreateCheckpointBlip(coords, id)
    local Blip = AddBlipForCoord(coords.x, coords.y, coords.z)

    SetBlipSprite(Blip, 1)
    SetBlipDisplay(Blip, 4)
    SetBlipScale(Blip, Config.Blips.Generic.Size)
    SetBlipAsShortRange(Blip, true)
    SetBlipColour(Blip, Config.Blips.Generic.Color)
    ShowNumberOnBlip(Blip, id)
    SetBlipShowCone(Blip, false)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName("Checkpoint: " .. id)
    EndTextCommandSetBlipName(Blip)

    return Blip
end

function CreatorLoop()
    CreateThread(function()
        while RaceData.InCreator do
            local PlayerPed = PlayerPedId()
            local PlayerVeh = GetVehiclePedIsIn(PlayerPed)

            if PlayerVeh ~= 0 then
                if IsControlJustPressed(0, 161) or IsDisabledControlJustPressed(0, 161) then
                    AddCheckpoint()
                end

                if IsControlJustPressed(0, 162) or IsDisabledControlJustPressed(0, 162) then
                    if CreatorData.Checkpoints and next(CreatorData.Checkpoints) then
                        DeleteCheckpoint()
                    else
                        QBCore.Functions.Notify(Lang:t("error.no_checkpoints_to_delete"), 'error')
                    end
                end

                if IsControlJustPressed(0, 311) or IsDisabledControlJustPressed(0, 311) then
                    if CreatorData.Checkpoints and #CreatorData.Checkpoints >= Config.MinimumCheckpoints then
                        SaveRace()
                    else
                        QBCore.Functions.Notify(Lang:t("error.not_enough_checkpoints") .. '(' ..
                                                    Config.MinimumCheckpoints .. ')', 'error')
                    end
                end

                if IsControlJustPressed(0, 40) or IsDisabledControlJustPressed(0, 40) then
                    if CreatorData.TireDistance < Config.MaxTireDistance then
                        CreatorData.TireDistance = CreatorData.TireDistance + 1.0
                    else
                        QBCore.Functions.Notify(Lang:t("error.max_tire_distance") .. Config.MaxTireDistance)
                    end
                end

                if IsControlJustPressed(0, 39) or IsDisabledControlJustPressed(0, 39) then
                    if CreatorData.TireDistance > Config.MinTireDistance then
                        CreatorData.TireDistance = CreatorData.TireDistance - 1.0
                    else
                        QBCore.Functions.Notify(Lang:t("error.min_tire_distance") .. Config.MinTireDistance)
                    end
                end
            else
                local coords = GetEntityCoords(PlayerPedId())
                DrawText3Ds(coords.x, coords.y, coords.z, Lang:t("text.get_in_vehicle"))
            end

            if IsControlJustPressed(0, 163) or IsDisabledControlJustPressed(0, 163) then
                if not CreatorData.ConfirmDelete then
                    CreatorData.ConfirmDelete = true
                    QBCore.Functions.Notify(Lang:t("error.editor_confirm"), 'error')
                else
                    DeleteCreatorCheckpoints()

                    RaceData.InCreator = false
                    CreatorData.RaceName = nil
                    CreatorData.Checkpoints = {}
                    QBCore.Functions.Notify(Lang:t("error.editor_canceled"), 'error')
                    CreatorData.ConfirmDelete = false
                end
            end
            Wait(0)
        end
    end)
end

local Players = {}

local function playerIswithinDistance()
    local ply = GetPlayerPed(-1)
    local plyCoords = GetEntityCoords(ply, 0)    
    for index,player in ipairs(Players) do
        local playerIdx = GetPlayerFromServerId(player.sourceplayer)
        local target = GetPlayerPed(playerIdx)
        if useDebug then
           print('player id', player.id, player.name)
        end
        if(target ~= ply) then
            local targetCoords = GetEntityCoords(target, 0)
            local distance = #(targetCoords.xy-plyCoords.xy)
            if useDebug then
               print('distance', distance)
            end
            if(distance < Config.Ghosting.NearestDistanceLimit) then
                return true
            end
        end
    end  
    return false
end

local ghostLoopStart = 0

local function actuallyValidateTime(Timer)
    if Timer == 0 then
        if useDebug then
           print('Timer is off')
        end
        return true
    else
        if GetTimeDifference(GetCloudTimeAsInt(), ghostLoopStart) < Timer then
            if useDebug then
               print('Timer has NOT been reached', GetTimeDifference(GetCloudTimeAsInt(), ghostLoopStart) )
            end
            return true
        end
        if useDebug then
           print('Timer has been reached')
        end
        return false
    end
end

local function validateTime()
    if CurrentRaceData.Ghosting and CurrentRaceData.GhostingTime then
        return actuallyValidateTime(CurrentRaceData.GhostingTime)
    else
        return actuallyValidateTime(Config.Ghosting.Timer)
    end
end

function CreateGhostLoop()
    ghostLoopStart = GetCloudTimeAsInt()
    if useDebug then
       print('non racers', dump(Players))
    end
    CreateThread(function()
        while true do
            if validateTime() then
                if CurrentRaceData.Checkpoints ~= nil and next(CurrentRaceData.Checkpoints) ~= nil then
                    if playerIswithinDistance() then
                        if useDebug then
                           print('DE GHOSTED')
                        end
                        CurrentRaceData.Ghosted = false
                        SetLocalPlayerAsGhost(false)
                        SetGhostedEntityAlpha(254)
                    else
                        if useDebug then
                           print('GHOSTED')
                        end
                        CurrentRaceData.Ghosted = true
                        SetLocalPlayerAsGhost(true)
                        SetGhostedEntityAlpha(254)
                    end
                else
                    break
                end
            else
                if useDebug then
                   print('Breaking due to time')
                end
                CurrentRaceData.Ghosted = false
                SetLocalPlayerAsGhost(false)
                SetGhostedEntityAlpha(254)
                break
            end
            Wait(Config.Ghosting.DistanceLoopTime)
        end
    end)
end

local startTime = 0
local lapStartTime = 0

local function updateCountdown(value)
    SendNUIMessage({
        action = "Countdown",
        data = {
            value = value
        },
        active = true
    })
end

function RaceUI()
    CreateThread(function()
        while true do
            if CurrentRaceData.Checkpoints ~= nil and next(CurrentRaceData.Checkpoints) ~= nil then
                if CurrentRaceData.Started then
                    CurrentRaceData.RaceTime = GetTimeDifference(GetCloudTimeAsInt(), lapStartTime)
                    CurrentRaceData.TotalTime = GetTimeDifference(GetCloudTimeAsInt(), startTime)
                end
                SendNUIMessage({
                    action = "Update",
                    type = "race",
                    data = {
                        CurrentCheckpoint = CurrentRaceData.CurrentCheckpoint,
                        TotalCheckpoints = #CurrentRaceData.Checkpoints,
                        TotalLaps = CurrentRaceData.TotalLaps,
                        CurrentLap = CurrentRaceData.Lap,
                        RaceStarted = CurrentRaceData.Started,
                        RaceName = CurrentRaceData.RaceName,
                        Time = CurrentRaceData.RaceTime,
                        TotalTime = CurrentRaceData.TotalTime,
                        BestLap = CurrentRaceData.BestLap,
                        Position = CurrentRaceData.Position,
                        TotalRacers = CurrentRaceData.TotalRacers,
                        Ghosted = CurrentRaceData.Ghosted
                    },
                    racedata = RaceData,
                    active = true
                })
            else
                if not FinishedUITimeout then
                    FinishedUITimeout = true
                    SetTimeout(10000, function()
                        FinishedUITimeout = false
                        SendNUIMessage({
                            action = "Update",
                            type = "race",
                            data = {},
                            racedata = RaceData,
                            active = false
                        })
                    end)
                end
                break
            end
            Wait(12)
        end
    end)
end

local function isFinishOrStart(CurrentRaceData, checkpoint)
    if CurrentRaceData.TotalLaps == 0 then
        if checkpoint == 1 or checkpoint == #CurrentRaceData.Checkpoints then
            return true
        else 
            return false
        end
    else
        if checkpoint == 1 then
            return true
        else 
            return false
        end  
    end
end

local function SetupRace(RaceData, Laps)
    CurrentRaceData = {
        RaceId = RaceData.RaceId,
        Creator = RaceData.Creator,
        OrganizerCID = RaceData.OrganizerCID,
        RacerName = RaceData.RacerName,
        RaceName = RaceData.RaceName,
        Checkpoints = RaceData.Checkpoints,
        Ghosting = RaceData.Ghosting,
        GhostingTime = RaceData.GhostingTime,
        Started = false,
        CurrentCheckpoint = 1,
        TotalLaps = Laps,
        Lap = 1,
        RaceTime = 0,
        TotalTime = 0,
        BestLap = 0,
        MaxClass = RaceData.MaxClass,
        Racers = {},
        Position = 0
    }
    ClearGpsMultiRoute()
    StartGpsMultiRoute(6, false , false)
    for k, v in pairs(CurrentRaceData.Checkpoints) do
        AddPointToGpsMultiRoute(CurrentRaceData.Checkpoints[k].coords.x,CurrentRaceData.Checkpoints[k].coords.y)
        ClearAreaOfObjects(v.offset.right.x, v.offset.right.y, v.offset.right.z, 50.0, 0)
        if isFinishOrStart(CurrentRaceData,k) then
            CurrentRaceData.Checkpoints[k].pileleft = CreatePile(v.offset.left, Config.StartAndFinishModel)
            CurrentRaceData.Checkpoints[k].pileright = CreatePile(v.offset.right, Config.StartAndFinishModel)
        else
            CurrentRaceData.Checkpoints[k].pileleft = CreatePile(v.offset.left, Config.CheckpointPileModel)
            CurrentRaceData.Checkpoints[k].pileright = CreatePile(v.offset.right, Config.CheckpointPileModel)
        end
        
        CurrentRaceData.Checkpoints[k].blip = CreateCheckpointBlip(v.coords, k)
    end
    if CurrentRaceData.TotalLaps > 0 then 
        for k=1, CurrentRaceData.TotalLaps-1, 1 do
            for k=1, #CurrentRaceData.Checkpoints, 1 do
                AddPointToGpsMultiRoute(CurrentRaceData.Checkpoints[k].coords.x,CurrentRaceData.Checkpoints[k].coords.y)
            end
        end
        AddPointToGpsMultiRoute(CurrentRaceData.Checkpoints[1].coords.x,CurrentRaceData.Checkpoints[1].coords.y)
    end
    RaceUI()
end

local function showNonLoopParticle(dict, particleName, coords, scale, time)
    while not HasNamedPtfxAssetLoaded(dict) do
        RequestNamedPtfxAsset(dict)
        Wait(0)
    end

    UseParticleFxAssetNextCall(dict)

    local particleHandle = StartParticleFxLoopedAtCoord(particleName, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0,
    scale, false, false, false)
    SetParticleFxLoopedColour(particleHandle,0.0,0.0,1.0)
    return particleHandle
end

local function handleFlare (checkpoint)
    -- QBCore.Functions.Notify('Lighting '..checkpoint, 'success')

    local Size = 1.0
    local left = showNonLoopParticle('core', 'exp_grd_flare',
        CurrentRaceData.Checkpoints[checkpoint].offset.left, Size)
    local right = showNonLoopParticle('core', 'exp_grd_flare',
        CurrentRaceData.Checkpoints[checkpoint].offset.right, Size)

    SetTimeout(Config.FlareTime, function()
        StopParticleFxLooped(left, false)
        StopParticleFxLooped(right, false)
    end)
end


local function DoPilePfx()
    if CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint + 1] ~= nil then
        handleFlare(CurrentRaceData.CurrentCheckpoint + 1)
    end
    if CurrentRaceData.CurrentCheckpoint == 1 then -- start
        if useDebug then
           print('start')
        end
        -- QBCore.Functions.Notify('Lighting start '..CurrentRaceData.CurrentCheckpoint, 'success')
        handleFlare(CurrentRaceData.CurrentCheckpoint)

    end
    if CurrentRaceData.TotalLaps > 0 and CurrentRaceData.CurrentCheckpoint == #CurrentRaceData.Checkpoints then -- finish
        if useDebug then
           print('finish')
        end
        --QBCore.Functions.Notify('Lighting finish/startline '..CurrentRaceData.CurrentCheckpoint + 1, 'success')
        handleFlare(1)
        if CurrentRaceData.Lap ~= CurrentRaceData.TotalLaps then
            if useDebug then
               print('not last lap')
            end
            handleFlare(2)
        end
    end
end

local function GetMaxDistance(OffsetCoords)
    local Distance = #(vector3(OffsetCoords.left.x, OffsetCoords.left.y, OffsetCoords.left.z) -
                         vector3(OffsetCoords.right.x, OffsetCoords.right.y, OffsetCoords.right.z))
    local Retval = 12.5
    if Distance > 20.0 then
        Retval = 18.5
    end
    return Retval
end

function SecondsToClock(seconds)
    local seconds = tonumber(seconds)
    local retval = 0
    if seconds <= 0 then
        retval = "00:00:00";
    else
        hours = string.format("%02.f", math.floor(seconds / 3600));
        mins = string.format("%02.f", math.floor(seconds / 60 - (hours * 60)));
        secs = string.format("%02.f", math.floor(seconds - hours * 3600 - mins * 60));
        retval = hours .. ":" .. mins .. ":" .. secs
    end
    return retval
end

function DeleteCurrentRaceCheckpoints()
    for k, v in pairs(CurrentRaceData.Checkpoints) do
        local CurrentCheckpoint = CurrentRaceData.Checkpoints[k]
        local Blip = CurrentCheckpoint.blip
        if Blip then
            RemoveBlip(Blip)
            Blip = nil
        end

        local PileLeft = CurrentCheckpoint.pileleft
        if PileLeft then
            DeleteClosestObject(CurrentCheckpoint.offset.left, Config.StartAndFinishModel)
            DeleteClosestObject(CurrentCheckpoint.offset.left, Config.CheckpointPileModel)
            PileLeft = nil
        end

        local PileRight = CurrentCheckpoint.pileright
        if PileRight then
            DeleteClosestObject(CurrentCheckpoint.offset.right, Config.StartAndFinishModel)
            DeleteClosestObject(CurrentCheckpoint.offset.right, Config.CheckpointPileModel)
            PileRight = nil
        end
    end

    CurrentRaceData.RaceName = nil
    CurrentRaceData.Checkpoints = {}
    CurrentRaceData.Started = false
    CurrentRaceData.CurrentCheckpoint = 0
    CurrentRaceData.TotalLaps = 0
    CurrentRaceData.Lap = 0
    CurrentRaceData.RaceTime = 0
    CurrentRaceData.TotalTime = 0
    CurrentRaceData.BestLap = 0
    CurrentRaceData.RaceId = nil
    CurrentRaceData.RacerName = nil
    RaceData.InRace = false
end

-- local currentTotalTime = 0

-- CreateThread(function()
--     while true do
--         if CurrentRaceData.RaceName ~= nil then
--             if CurrentRaceData.Started then
--                 currentTotalTime = currentTotalTime+10;
--             end
--             Wait(10)
--         end
--         Wait(1000)
--     end
-- end)

function FinishRace()
    local PlayerPed = PlayerPedId()
    local info, class, perfRating, vehicleModel = exports['cw-performance']:getVehicleInfo(GetVehiclePedIsIn(PlayerPed, false))
    -- print('NEW TIME TEST', currentTotalTime, SecondsToClock(currentTotalTime))
    TriggerServerEvent('cw-racingapp:server:FinishPlayer', CurrentRaceData, CurrentRaceData.TotalTime,
        CurrentRaceData.TotalLaps, CurrentRaceData.BestLap, class, vehicleModel)
    QBCore.Functions.Notify(Lang:t("success.race_finished") .. SecondsToClock(CurrentRaceData.TotalTime*60), 'success')
    if CurrentRaceData.BestLap ~= 0 then
        QBCore.Functions.Notify(Lang:t("success.race_best_lap") .. SecondsToClock(CurrentRaceData.BestLap*60), 'success')
    end
    UnGhostPlayer()
    ClearGpsMultiRoute()
    DeleteCurrentRaceCheckpoints()
end

function Info()
    local PlayerPed = PlayerPedId()
    local plyVeh = GetVehiclePedIsIn(PlayerPed, false)
    local IsDriver = GetPedInVehicleSeat(plyVeh, -1) == PlayerPed
    local returnValue = plyVeh ~= 0 and plyVeh ~= nil and IsDriver
    return returnValue, plyVeh
end

exports('IsInRace', IsInRace)
function IsInRace()
    local retval = false
    if RaceData.InRace then
        retval = true
    end
    return retval
end

exports('IsInEditor', IsInEditor)
function IsInEditor()
    local retval = false
    if RaceData.InCreator then
        retval = true
    end
    return retval
end

function DrawText3Ds(x, y, z, text)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry("STRING")
    SetTextCentre(true)
    AddTextComponentString(text)
    SetDrawOrigin(x, y, z, 0)
    DrawText(0.0, 0.0)
    local factor = (string.len(text)) / 370
    DrawRect(0.0, 0.0 + 0.0125, 0.017 + factor, 0.03, 0, 0, 0, 75)
    ClearDrawOrigin()
end

-----------------------
----   Threads     ----
-----------------------



CreateThread(function()
    while true do
        if RaceData.InCreator then
            GetClosestCheckpoint()
            SetupPiles()
        end
        Wait(1000)
    end
end)

CreateThread(function()
    while true do
        local Driver, plyVeh = Info()
        if Driver then
            if GetVehicleCurrentGear(plyVeh) < 3 and GetVehicleCurrentRpm(plyVeh) == 1.0 and
                math.ceil(GetEntitySpeed(plyVeh) * 2.236936) > 50 then
                while GetVehicleCurrentRpm(plyVeh) > 0.6 do
                    SetVehicleCurrentRpm(plyVeh, 0.3)
                    Wait(0)
                end
                Wait(800)
            end
        end
        Wait(500)
    end
end)

local function genericBlip(Blip)
    SetBlipScale(Blip, Config.Blips.Generic.Size)
    SetBlipColour(Blip, Config.Blips.Generic.Color)
end

local function nextBlip(Blip)
    SetBlipScale(Blip, Config.Blips.Next.Size)
    SetBlipColour(Blip, Config.Blips.Next.Color)
end

local function passedBlip(Blip)
    SetBlipScale(Blip, Config.Blips.Passed.Size)
    SetBlipColour(Blip, Config.Blips.Passed.Color)
end

local function resetBlips()
    for i, checkpoint in pairs(CurrentRaceData.Checkpoints) do
        genericBlip(checkpoint.blip)
    end
end

-- Racing
CreateThread(function()
    while true do
        if CurrentRaceData.RaceName ~= nil then
            if CurrentRaceData.Started then
                local ped = PlayerPedId()
                local pos = GetEntityCoords(ped)
                local cp = 0
                if CurrentRaceData.CurrentCheckpoint + 1 > #CurrentRaceData.Checkpoints then
                    cp = 1
                else
                    cp = CurrentRaceData.CurrentCheckpoint + 1
                end
                local data = CurrentRaceData.Checkpoints[cp]
                local CheckpointDistance = #(pos - vector3(data.coords.x, data.coords.y, data.coords.z))
                local MaxDistance = GetMaxDistance(CurrentRaceData.Checkpoints[cp].offset)
                if CheckpointDistance < MaxDistance then
                    if CurrentRaceData.TotalLaps == 0 then -- Sprint
                        if CurrentRaceData.CurrentCheckpoint + 1 < #CurrentRaceData.Checkpoints then
                            CurrentRaceData.CurrentCheckpoint = CurrentRaceData.CurrentCheckpoint + 1
                            AddPointToGpsMultiRoute(CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint + 1].coords.x,
                                CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint + 1].coords.y)
                            TriggerServerEvent('cw-racingapp:server:UpdateRacerData', CurrentRaceData.RaceId,
                                CurrentRaceData.CurrentCheckpoint, CurrentRaceData.Lap, false, CurrentRaceData.TotalTime)
                            DoPilePfx()
                            PlaySound(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", 0, 0, 1)
                            passedBlip(CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint].blip)
                            nextBlip(CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint + 1].blip)
                        else
                            DoPilePfx()
                            PlaySound(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", 0, 0, 1)
                            CurrentRaceData.CurrentCheckpoint = CurrentRaceData.CurrentCheckpoint + 1
                            TriggerServerEvent('cw-racingapp:server:UpdateRacerData', CurrentRaceData.RaceId,
                                CurrentRaceData.CurrentCheckpoint, CurrentRaceData.Lap, true, CurrentRaceData.TotalTime)
                            FinishRace()
                        end
                    else -- Circuit
                        if CurrentRaceData.CurrentCheckpoint + 1 > #CurrentRaceData.Checkpoints then -- If new lap
                            if CurrentRaceData.Lap + 1 > CurrentRaceData.TotalLaps then -- if finish
                                DoPilePfx()
                                PlaySound(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", 0, 0, 1)
                                if CurrentRaceData.RaceTime < CurrentRaceData.BestLap then
                                    CurrentRaceData.BestLap = CurrentRaceData.RaceTime
                                elseif CurrentRaceData.BestLap == 0 then
                                    CurrentRaceData.BestLap = CurrentRaceData.RaceTime
                                end
                                CurrentRaceData.CurrentCheckpoint = CurrentRaceData.CurrentCheckpoint + 1
                                TriggerServerEvent('cw-racingapp:server:UpdateRacerData', CurrentRaceData.RaceId,
                                    CurrentRaceData.CurrentCheckpoint, CurrentRaceData.Lap, true, CurrentRaceData.TotalTime)
                                FinishRace()
                            else -- if next lap
                                DoPilePfx()
                                resetBlips()
                                PlaySound(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", 0, 0, 1)
                                if CurrentRaceData.RaceTime < CurrentRaceData.BestLap then
                                    CurrentRaceData.BestLap = CurrentRaceData.RaceTime
                                elseif CurrentRaceData.BestLap == 0 then
                                    CurrentRaceData.BestLap = CurrentRaceData.RaceTime
                                end
                                lapStartTime = GetCloudTimeAsInt()
                                CurrentRaceData.Lap = CurrentRaceData.Lap + 1
                                CurrentRaceData.CurrentCheckpoint = 1
                                AddPointToGpsMultiRoute(
                                    CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint + 1].coords.x,
                                    CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint + 1].coords.y)
                                TriggerServerEvent('cw-racingapp:server:UpdateRacerData', CurrentRaceData.RaceId,
                                    CurrentRaceData.CurrentCheckpoint, CurrentRaceData.Lap, false, CurrentRaceData.TotalTime)
                                passedBlip(CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint].blip)
                                nextBlip(CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint + 1].blip)
                            end
                        else -- if next checkpoint 
                            CurrentRaceData.CurrentCheckpoint = CurrentRaceData.CurrentCheckpoint + 1
                            if CurrentRaceData.CurrentCheckpoint ~= #CurrentRaceData.Checkpoints then
                                AddPointToGpsMultiRoute(
                                    CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint + 1].coords.x,
                                    CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint + 1].coords.y)
                                TriggerServerEvent('cw-racingapp:server:UpdateRacerData', CurrentRaceData.RaceId,
                                    CurrentRaceData.CurrentCheckpoint, CurrentRaceData.Lap, false, CurrentRaceData.TotalTime)
                                    passedBlip(CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint].blip)
                                    nextBlip(CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint + 1].blip)
                            else
                                AddPointToGpsMultiRoute(CurrentRaceData.Checkpoints[1].coords.x,
                                    CurrentRaceData.Checkpoints[1].coords.y)
                                TriggerServerEvent('cw-racingapp:server:UpdateRacerData', CurrentRaceData.RaceId,
                                    CurrentRaceData.CurrentCheckpoint, CurrentRaceData.Lap, false, CurrentRaceData.TotalTime)
                                    passedBlip(CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint].blip)
                                    nextBlip(CurrentRaceData.Checkpoints[1].blip)
                            end
                            DoPilePfx()
                            PlaySound(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", 0, 0, 1)
                        end
                    end
                end
            else
                local data = CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint]
                DrawMarker(4, data.coords.x, data.coords.y, data.coords.z + 1.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.9, 1.5,
                    1.5, 255, 255, 255, 255, 0, 1, 0, 0, 0, 0, 0)
                    nextBlip(CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint+1].blip)
            end
        else
            Wait(1000)
        end

        Wait(0)
    end
end)

-- Creator
CreateThread(function()
    while true do
        if RaceData.InCreator then
            local PlayerPed = PlayerPedId()
            local PlayerVeh = GetVehiclePedIsIn(PlayerPed)

            if PlayerVeh ~= 0 then
                local Offset = {
                    left = {
                        x = (GetOffsetFromEntityInWorldCoords(PlayerVeh, -CreatorData.TireDistance, 0.0, 0.0)).x,
                        y = (GetOffsetFromEntityInWorldCoords(PlayerVeh, -CreatorData.TireDistance, 0.0, 0.0)).y,
                        z = (GetOffsetFromEntityInWorldCoords(PlayerVeh, -CreatorData.TireDistance, 0.0, 0.0)).z
                    },
                    right = {
                        x = (GetOffsetFromEntityInWorldCoords(PlayerVeh, CreatorData.TireDistance, 0.0, 0.0)).x,
                        y = (GetOffsetFromEntityInWorldCoords(PlayerVeh, CreatorData.TireDistance, 0.0, 0.0)).y,
                        z = (GetOffsetFromEntityInWorldCoords(PlayerVeh, CreatorData.TireDistance, 0.0, 0.0)).z
                    }
                }

                DrawText3Ds(Offset.left.x, Offset.left.y, Offset.left.z, Lang:t("text.checkpoint_left"))
                DrawText3Ds(Offset.right.x, Offset.right.y, Offset.right.z, Lang:t("text.checkpoint_right"))
            end
        end
        Wait(0)
    end
end)

-----------------------
---- Client Events ----
-----------------------

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        DeleteAllCheckpoints()
    end
end)

RegisterNetEvent('cw-racingapp:client:ReadyJoinRace', function(RaceData)
    local PlayerPed = PlayerPedId()
    local PlayerIsInVehicle = IsPedInAnyVehicle(PlayerPed, false)

    local info, class, perfRating = '', '', ''
    if PlayerIsInVehicle then
        info, class, perfRating = exports['cw-performance']:getVehicleInfo(GetVehiclePedIsIn(PlayerPed, false))
    else
        QBCore.Functions.Notify('You are not in a vehicle', 'error')
    end
    
    if myCarClassIsAllowed(RaceData.MaxClass, class) then
        RaceData.RacerName = RaceData.SetupRacerName
        RaceData.PlayerVehicleEntity = GetVehiclePedIsIn(PlayerPed, false)
        TriggerServerEvent('cw-racingapp:server:JoinRace', RaceData)
    else 
        QBCore.Functions.Notify('Your car is not the correct class', 'error')
    end
end)

RegisterNetEvent('cw-racingapp:client:StartRaceEditor', function(RaceName, RacerName)
    if not RaceData.InCreator then
        CreatorData.RaceName = RaceName
        CreatorData.RacerName = RacerName
        RaceData.InCreator = true
        CreatorUI()
        CreatorLoop()
    else
        QBCore.Functions.Notify(Lang:t("error.already_making_race"), 'error')
    end
end)

local function getIndex (Positions) 
    for k,v in pairs(Positions) do
        if v.RacerName == CurrentRaceData.RacerName then return k end
    end
end

RegisterNetEvent('cw-racingapp:client:UpdateRaceRacerData', function(RaceId, RaceData, Positions)
    if (CurrentRaceData.RaceId ~= nil) and CurrentRaceData.RaceId == RaceId then
        local MyPosition = getIndex(Positions)
        CurrentRaceData.Racers = RaceData.Racers
        CurrentRaceData.Position = MyPosition
    end
end)

RegisterNetEvent('cw-racingapp:client:JoinRace', function(Data, Laps, RacerName)
    if not RaceData.InRace then
        Data.RacerName = RacerName
        RaceData.InRace = true
        SetupRace(Data, Laps)
        QBCore.Functions.Notify(Lang:t("primary.race_joined"))
        TriggerServerEvent('cw-racingapp:server:UpdateRaceState', CurrentRaceData.RaceId, false, true)
    else
        QBCore.Functions.Notify(Lang:t("error.already_in_race"), 'error')
    end
end)

RegisterNetEvent('cw-racingapp:client:UpdateRaceRacers', function(RaceId, Racers)
    if CurrentRaceData.RaceId == RaceId then
        CurrentRaceData.Racers = Racers
    end
end)

RegisterNetEvent('cw-racingapp:client:LeaveRace', function(data)
    ClearGpsMultiRoute()
    UnGhostPlayer()
    DeleteCurrentRaceCheckpoints()
    FreezeEntityPosition(GetVehiclePedIsIn(PlayerPedId(), false), false)
end)

local function getKeysSortedByValue(tbl, sortFunction)
    local keys = {}
    for key in pairs(tbl) do
      table.insert(keys, key)
    end
  
    table.sort(keys, function(a, b)
      return sortFunction(tbl[a], tbl[b])
    end)
    if useDebug then
       print('KEYS',dump(keys))
    end
    return keys
end

RegisterNetEvent("cw-racingapp:Client:DeleteTrackConfirmed", function(data)
    QBCore.Functions.Notify(data.RaceName..Lang:t("primary.has_been_removed"))
    TriggerServerEvent("cw-racingapp:Server:DeleteTrack", data.RaceId)
end)

RegisterNetEvent("cw-racingapp:Client:ClearLeaderboardConfirmed", function(data)
    QBCore.Functions.Notify(data.RaceName..Lang:t("primary.leaderboard_has_been_cleared"))
    TriggerServerEvent("cw-racingapp:Server:ClearLeaderboard", data.RaceId)
end)


RegisterNetEvent("cw-racingapp:Client:DeleteTrack", function(data)
    local menu = {{
        header = Lang:t("menu.are_you_sure_you_want_to_delete_track")..' ('..data.RaceName..')' ,
        isMenuHeader = true
    }}
    menu[#menu + 1] = {
        header = Lang:t("menu.yes"),
        icon = "fas fa-check",
        params = {
            event = "cw-racingapp:Client:DeleteTrackConfirmed",
            args = {
                type = data.type,
                name = data.name,
                RaceId = data.RaceId,
                RaceName = data.RaceName
            }
        }
    }
    menu[#menu + 1] = {
        header = Lang:t("menu.no"),
        icon = "fas fa-xmark",
        params = {
            event = "cw-racingapp:Client:TrackInfo",
            args = {
                type = data.type,
                name = data.name,
                RaceId = data.RaceId,
                RaceName = data.RaceName
            }
        }
    }
    exports['qb-menu']:openMenu(menu)
end)

RegisterNetEvent("cw-racingapp:Client:ClearLeaderboard", function(data)
    local menu = {{
        header = Lang:t("menu.are_you_sure_you_want_to_clear")..' ('..data.RaceName..')' ,
        isMenuHeader = true
    }}
    menu[#menu + 1] = {
        header = Lang:t("menu.yes"),
        icon = "fas fa-check",
        params = {
            event = "cw-racingapp:Client:ClearLeaderboardConfirmed",
            args = {
                type = data.type,
                name = data.name,
                RaceId = data.RaceId,
                RaceName = data.RaceName
            }
        }
    }
    menu[#menu + 1] = {
        header = Lang:t("menu.no"),
        icon = "fas fa-xmark",
        params = {
            event = "cw-racingapp:Client:TrackInfo",
            args = {
                type = data.type,
                name = data.name,
                RaceId = data.RaceId,
                RaceName = data.RaceName
            }
        }
    }
    exports['qb-menu']:openMenu(menu)
end)

RegisterNetEvent("cw-racingapp:Client:TrackInfo", function(data)
    local menu = {{
        header = data.RaceName,
        isMenuHeader = true
    }}

    menu[#menu + 1] = {
        header = Lang:t("menu.clear_leaderboard"),
        icon = "fas fa-eraser",
        params = {
            event = "cw-racingapp:Client:ClearLeaderboard",
            args = {
                type = data.type,
                name = data.name,
                RaceId = data.RaceId,
                RaceName = data.RaceName
            }
        }
    }
    menu[#menu + 1] = {
        header = Lang:t("menu.delete_track"),
        icon = "fas fa-trash-can",
        params = {
            event = "cw-racingapp:Client:DeleteTrack",
            args = {
                type = data.type,
                name = data.name,
                RaceId = data.RaceId,
                RaceName = data.RaceName
            }
        }
    }

    menu[#menu + 1] = {
        header = Lang:t("menu.go_back"),
        params = {
            event = "cw-racingapp:Client:ListMyTracks",
            args = {
                type = data.type,
                name = data.name
            }
        }
    }

    if #menu == 2 then
        QBCore.Functions.Notify(Lang:t("primary.no_races_exist"))
        TriggerEvent('cw-racingapp:Client:ListMyTracks', {
            type = data.type,
            name = data.name
        })
        return
    end

    exports['qb-menu']:openMenu(menu)
end)

local function filterTracksByRacer(Tracks)
    local filteredTracks = {}
    for i, track in pairs(Tracks) do      
        if track.Creator == QBCore.Functions.GetPlayerData().citizenid then
            table.insert(filteredTracks, track)
        end
    end
    return filteredTracks
end

RegisterNetEvent("cw-racingapp:Client:ListMyTracks", function(data)
    QBCore.Functions.TriggerCallback('cw-racingapp:server:GetTracks', function(Tracks)
        local menu = {}

        for i, track in pairs(filterTracksByRacer(Tracks)) do      
            menu[#menu + 1] = {
                header = track.RaceName.. ' | '.. track.Distance..'m',
                params = {
                    event = "cw-racingapp:Client:TrackInfo",
                    args = {
                        type = data.type,
                        name = data.name,
                        RaceId = track.RaceId,
                        RaceName = track.RaceName
                    }
                }
            }
        end

        menu[#menu + 1] = {
            header = Lang:t("menu.go_back"),
            params = {
                event = "cw-racingapp:Client:OpenMainMenu",
                args = {
                    type = data.type,
                    name = data.name
                }
            }
        }

        table.sort(menu, function (a,b)
            return a.header < b.header
        end)

        table.insert(menu, 1, {
            header = Lang:t("menu.my_tracks"),
            isMenuHeader = true
        })
        if #menu == 2 then
            QBCore.Functions.Notify(Lang:t("menu.no_tracks_exist"))
            TriggerEvent('cw-racingapp:Client:OpenMainMenu', {
                type = data.type,
                name = data.name
            })
            return
        end
        exports['qb-menu']:openMenu(menu)
    end, class)

    exports['qb-menu']:openMenu(menu)
end)

RegisterNetEvent('cw-racingapp:client:RaceCountdown', function(TotalRacers)
    TriggerServerEvent('cw-racingapp:server:UpdateRaceState', CurrentRaceData.RaceId, true, false)
    SetGpsMultiRouteRender(true)
    CurrentRaceData.TotalRacers = TotalRacers    
    if CurrentRaceData.RaceId ~= nil then
        while Countdown ~= 0 do
            if CurrentRaceData.RaceName ~= nil then
                if Countdown == 10 then
                    --QBCore.Functions.Notify(Lang:t("primary.race_will_start"), 'primary', 2500)
                    updateCountdown(Lang:t("primary.race_will_start"))
                    PlaySound(-1, "slow", "SHORT_PLAYER_SWITCH_SOUND_SET", 0, 0, 1)
                elseif Countdown <= 5 then
                    --QBCore.Functions.Notify(Countdown, 'primary', 500)
                    updateCountdown(Countdown)
                    PlaySound(-1, "slow", "SHORT_PLAYER_SWITCH_SOUND_SET", 0, 0, 1)
                end
                Countdown = Countdown - 1
                FreezeEntityPosition(GetVehiclePedIsIn(PlayerPedId(), true), true)
            else
                break
            end
            Wait(1000)
        end
        if CurrentRaceData.RaceName ~= nil then
            AddPointToGpsMultiRoute(CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint + 1].coords.x,
            CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint + 1].coords.y)
            --QBCore.Functions.Notify(Lang:t("success.race_go"), 'success', 1000)
            updateCountdown(Lang:t("success.race_go"))
            SetBlipScale(CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint + 1].blip, Config.Blips.Generic.Size)
            FreezeEntityPosition(GetVehiclePedIsIn(PlayerPedId(), true), false)
            DoPilePfx()
            if Config.Ghosting.Enabled and CurrentRaceData.Ghosting then
                QBCore.Functions.TriggerCallback('cw-racingapp:server:GetRacers', function(Racers)
                    QBCore.Functions.TriggerCallback('cw-racingapp:Server:getplayers', function(players)
                        if useDebug then
                            print('Doing ghosting stuff')
                            print('PLAYERS', dump(players))
                            print('Racers', dump(Racers))
                        end

                        for index,player in ipairs(players) do
                            if useDebug then
                                print('checking if exists in racers:', player.citizenid)
                                print(Racers[player.citizenid] ~= nil)
                            end
                            if Racers[player.citizenid] then
                                if useDebug then
                                    print('not adding ', player.name)
                                end
                            else
                                Players[#Players+1] = player
                            end
                        end
                        if useDebug then
                            print('PLAYERS AFTER', dump(Players))
                            print('====================')
                        end
                        GhostPlayers()
                    end)
                end, CurrentRaceData.RaceId)
            end
            lapStartTime = GetCloudTimeAsInt()
            startTime = GetCloudTimeAsInt()
            CurrentRaceData.Started = true
            Countdown = 10
        else
            FreezeEntityPosition(GetVehiclePedIsIn(PlayerPedId(), true), false)
            Countdown = 10
        end
    else
        QBCore.Functions.Notify(Lang:t("error.already_in_race"), 'error')
    end
end)

RegisterNetEvent('cw-racingapp:client:PlayerFinish', function(RaceId, Place, RacerName)
    if CurrentRaceData.RaceId ~= nil then
        if CurrentRaceData.RaceId == RaceId then
            QBCore.Functions.Notify(RacerName .. Lang:t("primary.racer_finished_place") .. Place, 'primary', 3500)
        end
    end
end)

RegisterNetEvent('cw-racingapp:client:NotCloseEnough', function(x,y)
    QBCore.Functions.Notify(Lang:t('error.not_close_enough_to_join'), 'error')
    SetNewWaypoint(x, y)
end)

RegisterNetEvent("cw-racingapp:Client:OpenMainMenu", function(data)
    local type = data.type
    local name = data.name
    local info, class, perfRating = '', '', ''
    local subtitle = Lang:t('menu.not_in_a_vehicle')

    local PlayerPed = PlayerPedId()
    local PlayerIsInVehicle = IsPedInAnyVehicle(PlayerPed, false)

    if PlayerIsInVehicle then
        info, class, perfRating = exports['cw-performance']:getVehicleInfo(GetVehiclePedIsIn(PlayerPed, false))
        subtitle = Lang:t('menu.currently_in') .. class .. perfRating.. Lang:t('menu.class_car')
    else
        QBCore.Functions.Notify(Lang:t('menu.not_in_a_vehicle'), 'error')
    end


    exports['qb-menu']:openMenu({{
        header = Lang:t("menu.ready_to_race") .. name .. '?',
        txt = subtitle,
        isMenuHeader = true
    }, {
        header = Lang:t("menu.current_race"),
        txt = Lang:t("menu.current_race_txt"),
        icon = "fas fa-hourglass-start",
        disabled = (CurrentRaceData.RaceId == nil),
        params = {
            event = "cw-racingapp:Client:CurrentRaceMenu",
            args = {
                type = type,
                name = name
            }
        }
    }, {
        header = Lang:t("menu.available_races"),
        txt = Lang:t("menu.available_races"),
        icon = "fas fa-flag-checkered",
        disabled = not Config.Permissions[type].join,
        params = {
            event = "cw-racingapp:Client:AvailableRacesMenu",
            args = {
                type = type,
                name = name
            }
        }
    }, {
        header = Lang:t("menu.race_records"),
        txt = Lang:t("menu.race_records_txt"),
        icon = "fas fa-trophy",
        disabled = not Config.Permissions[type].records,
        params = {
            event = "cw-racingapp:Client:RaceRecordsMenu",
            args = {
                type = type,
                name = name
            }
        }
    }, {
        header = Lang:t("menu.setup_race"),
        txt = "",
        icon = "fas fa-calendar-plus",
        disabled = not Config.Permissions[type].setup,
        params = {
            event = "cw-racingapp:Client:SetupRaceMenu",
            args = {
                type = type,
                name = name
            }
        }
    }, {
        header = Lang:t("menu.create_race"),
        txt = "",
        icon = "fas fa-plus",
        disabled = not Config.Permissions[type].create,
        params = {
            event = "cw-racingapp:Client:CreateRaceMenu",
            args = {
                type = type,
                name = name
            }
        }
    },
    {
        header = Lang:t("menu.my_tracks"),
        txt = "",
        icon = "fas fa-route",
        disabled = not Config.Permissions[type].create,
        params = {
            event = "cw-racingapp:Client:ListMyTracks",
            args = {
                type = type,
                name = name
            }
        }
    }, {
        header = Lang:t("menu.close"),
        txt = "",
        params = {
            event = "qb-menu:client:closeMenu"
        }
    }})

end)

RegisterNetEvent("cw-racingapp:Client:CurrentRaceMenu", function(data)
    if not CurrentRaceData.RaceId then
        return
    end

    local racers = 0
    local maxClass = 'open'
    for _ in pairs(CurrentRaceData.Racers) do
        racers = racers + 1
    end
    if (CurrentRaceData.MaxClass ~= nil and CurrentRaceData.MaxClass ~= "") then
        maxClass = CurrentRaceData.MaxClass
    end

    exports['qb-menu']:openMenu({{
        header = CurrentRaceData.RaceName .. ' | ' .. racers .. Lang:t("menu.racers") .. ' | Class: ' ..
            tostring(maxClass),
        isMenuHeader = true
    }, {
        header = Lang:t("menu.start_race"),
        txt = "",
        icon = "fas fa-play",
        disabled = (not (CurrentRaceData.OrganizerCID == QBCore.Functions.GetPlayerData().citizenid) or
            CurrentRaceData.Started),
        params = {
            isServer = true,
            event = "cw-racingapp:server:StartRace",
            args = CurrentRaceData.RaceId
        }
    }, {
        header = Lang:t("menu.leave_race"),
        txt = "",
        icon = "fas fa-door-open",
        params = {
            isServer = true,
            event = "cw-racingapp:server:LeaveRace",
            args = CurrentRaceData
        }
    }, {
        header = Lang:t("menu.go_back"),
        icon = "fas fa-left-long",
        params = {
            event = "cw-racingapp:Client:OpenMainMenu",
            args = {
                type = data.type,
                name = data.name
            }
        }
    }})
end)

RegisterNetEvent("cw-racingapp:Client:AvailableRacesMenu", function(data)
    QBCore.Functions.TriggerCallback('cw-racingapp:server:GetRaces', function(Races)
        local menu = {{
            header = Lang:t("menu.available_races"),
            isMenuHeader = true
        }}

        for _, race in ipairs(Races) do
            local RaceData = race.RaceData
            local racers = 0
            local PlayerPed = PlayerPedId()
            race.PlayerVehicleEntity = GetVehiclePedIsIn(PlayerPed, false)
            for _ in pairs(RaceData.Racers) do
                racers = racers + 1
            end

            race.RacerName = data.name

                
            local maxClass = 'open'
            if (RaceData.MaxClass ~= nil and RaceData.MaxClass ~= "") then
                maxClass = RaceData.MaxClass
            end
            local text = race.Laps..' lap(s) | ' ..RaceData.Distance.. 'm | ' ..racers.. ' racer(s) | Class: ' ..maxClass
            if race.Ghosting then
                text = text..' | 👻'
                if race.GhostingTime then
                    text = text..' ('..race.GhostingTime..'s)'
                end
            end
            local header = RaceData.RaceName
            if RaceData.BuyIn > 0 then
                local currency = 'Crypto '
                if Config.Options.MoneyType == 'cash' or Config.Options.MoneyType == 'bank' then
                    currency = '$'
                end
                header = header.. ' | '..currency .. RaceData.BuyIn
            end
            menu[#menu + 1] = {
                header = header,
                txt = text,
                disabled = CurrentRaceData.RaceId == RaceData.RaceId,
                params = {
                    isServer = true,
                    event = "cw-racingapp:server:JoinRace",
                    args = race
                }
            }
        end

        menu[#menu + 1] = {
            header = Lang:t("menu.go_back"),
            params = {
                event = "cw-racingapp:Client:OpenMainMenu",
                args = {
                    type = data.type,
                    name = data.name
                }
            }
        }

        if #menu == 2 then
            QBCore.Functions.Notify(Lang:t("primary.no_pending_races"))
            TriggerEvent('cw-racingapp:Client:OpenMainMenu', {
                type = data.type,
                name = data.name
            })
            return
        end

        exports['qb-menu']:openMenu(menu)
    end)
end)

RegisterNetEvent("cw-racingapp:Client:RaceRecordsMenu", function(data)
    local PlayerPed = PlayerPedId()
    local PlayerIsInVehicle = IsPedInAnyVehicle(PlayerPed, false)

    local info, class, perfRating = '', '', ''
    if PlayerIsInVehicle then
        info, class, perfRating = exports['cw-performance']:getVehicleInfo(GetVehiclePedIsIn(PlayerPed, false))
    end

    QBCore.Functions.TriggerCallback('cw-racingapp:server:GetTracks', function(Tracks)
        local menu = {}
        for i, track in pairs(Tracks) do      
            menu[#menu + 1] = {
                header = track.RaceName.. ' | '.. track.Distance..'m',
                params = {
                    event = "cw-racingapp:Client:ClassesList",
                    args = {
                        type = data.type,
                        name = data.name,
                        trackName = track.RaceName 
                    }
                }
            }
        end

        menu[#menu + 1] = {
            header = Lang:t("menu.go_back"),
            params = {
                event = "cw-racingapp:Client:OpenMainMenu",
                args = {
                    type = data.type,
                    name = data.name
                }
            }
        }

        table.sort(menu, function (a,b)
            return a.header < b.header
        end)

        table.insert(menu, 1, {
            header = Lang:t("menu.choose_a_track"),
            isMenuHeader = true
        })
        if #menu == 2 then
            QBCore.Functions.Notify(Lang:t("menu.no_tracks_exist"))
            TriggerEvent('cw-racingapp:Client:OpenMainMenu', {
                type = data.type,
                name = data.name
            })
            return
        end
        exports['qb-menu']:openMenu(menu)
    end, class)

    exports['qb-menu']:openMenu(menu)
end)

local function getKeysSortedByValue(tbl, sortFunction)
    local keys = {}
    for key in pairs(tbl) do
      table.insert(keys, key)
    end
  
    table.sort(keys, function(a, b)
      return sortFunction(tbl[a], tbl[b])
    end)
    if useDebug then
       print('KEYS',dump(keys))
    end
    return keys
  end


RegisterNetEvent("cw-racingapp:Client:ClassesList", function(data)
    local classes = exports['cw-performance']:getPerformanceClasses()
    local sortedClasses = getKeysSortedByValue(classes, function(a, b) return a > b end)

    local menu = {{
        header = Lang:t("menu.choose_a_class"),
        isMenuHeader = true
    }}
    menu[#menu + 1] = {
        header = Lang:t("menu.all"),
        params = {
            event = "cw-racingapp:Client:TrackRecordList",
            args = {
                type = data.type,
                name = data.name,
                trackName = data.trackName,
                class = 'all'
            }
        }
    }

    for value, class in pairs(sortedClasses) do      
        menu[#menu + 1] = {
            header = class,
            params = {
                event = "cw-racingapp:Client:TrackRecordList",
                args = {
                    type = data.type,
                    name = data.name,
                    trackName = data.trackName,
                    class = class
                }
            }
        }
    end

    menu[#menu + 1] = {
        header = Lang:t("menu.go_back"),
        params = {
            event = "cw-racingapp:Client:RaceRecordsMenu",
            args = {
                type = data.type,
                name = data.name
            }
        }
    }

    if #menu == 2 then
        QBCore.Functions.Notify(Lang:t("primary.no_races_exist"))
        TriggerEvent('cw-racingapp:Client:RaceRecordsMenu', {
            type = data.type,
            name = data.name
        })
        return
    end

    exports['qb-menu']:openMenu(menu)
end)

RegisterNetEvent("cw-racingapp:Client:TrackRecordList", function(data)
    QBCore.Functions.TriggerCallback('cw-racingapp:server:GetRacingLeaderboards', function(filteredLeaderboards)
        local headerText = data.trackName..' | '
        if data.class == 'all' then
            headerText = headerText..Lang:t("menu.all")
        else
            headerText = headerText..data.class
        end
        local menu = {{
            header = data.trackName..' | '..data.class,
            isMenuHeader = true
        }}
        if useDebug then
           print(dump(filteredLeaderboards))
        end
        for i, RecordData in pairs(filteredLeaderboards) do
            if useDebug then
               print('RecordData', dump(RecordData), i)
            end
            
            local class = RecordData.Class
            local holder = RecordData.Holder
            local vehicle = RecordData.Vehicle
            local time = RecordData.Time

            if not class then
                class = 'NO DATA AVAILABLE'
            end
            if not holder then
                holder = 'NO DATA AVAILABLE'
            end
            if not vehicle then
                vehicle = 'NO DATA AVAILABLE'
            end
            if not time then
                time = 'NO DATA AVAILABLE'
            end

            local text = ''
            local first = '🥇 '
            local second = '🥈 '
            local third = '🥉 '
            local header = ''
            if i == 1 then
                header = first..holder
            elseif i == 2 then
                header = second..holder
            elseif i == 3 then
                header = third..holder
            else
                header = i..'. '..holder
            end
            text = SecondsToClock(time).. ' | '..vehicle
            if data.class == 'all' then
                text = text.. ' | '..class
            end

            menu[#menu + 1] = {
                header = header,
                text = text,
                disabled = true
            }
        end

        menu[#menu + 1] = {
            header = Lang:t("menu.go_back"),
            params = {
                event = "cw-racingapp:Client:ClassesList",
                args = {
                    type = data.type,
                    name = data.name,
                    trackName = data.trackName 
                }
            }
        }

        if #menu == 2 then
            QBCore.Functions.Notify(Lang:t("primary.no_races_exist"))
            TriggerEvent('cw-racingapp:Client:RaceRecordsMenu', {
                type = data.type,
                name = data.name
            })
            return
        end

        exports['qb-menu']:openMenu(menu)
    end, data.class, data.trackName)
end)

local function toboolean(str)
    local bool = false
    if str == "true" or str == true then
        bool = true
    end
    return bool
end

RegisterNetEvent("cw-racingapp:Client:SetupRaceMenu", function(data)
    QBCore.Functions.TriggerCallback('cw-racingapp:server:GetListedRaces', function(Races)
        local tracks = {{
            value = "none",
            text = Lang:t("menu.choose_a_track")
        }}
        for id, track in pairs(Races) do
            if not track.Waiting then
                tracks[#tracks + 1] = {
                    value = id,
                    text = string.format("%s | %s | %sm", track.RaceName, track.CreatorName, track.Distance)
                }
            end
        end

        if #tracks == 1 then
            QBCore.Functions.Notify(Lang:t("primary.no_available_tracks"))
            TriggerEvent('cw-racingapp:Client:OpenMainMenu', {
                type = data.type,
                name = data.name
            })
            return
        end

        local options = {{
                text = Lang:t("menu.select_track"),
                name = "track",
                type = "select",
                options = tracks
            }, {
                text = Lang:t("menu.number_laps"),
                name = "laps",
                type = "select",
                options = Config.Options.Laps,
                isRequired = true
            },
            {
                text = Lang:t("menu.buyIn"),
                name = "buyIn",
                type = "select",
                options = Config.Options.BuyIns,
                isRequired = true
            }}

        if Config.Ghosting.Enabled then
            table.insert(options, {
                text = Lang:t("menu.useGhosting"),
                name = "ghosting", 
                type = "radio", 
                options = {
                    { value = true, text = Lang:t("menu.yes"), checked = true }, 
                    { value = false, text = Lang:t("menu.no")},
                }})
            table.insert(options, {
                text = Lang:t('menu.ghostingTime'),
                name = "ghostingTime",
                type = "select",
                options = Config.Ghosting.Options
                })
        end
        
        local classes = { {value = '', text = Lang:t('menu.no_class_limit'), number = 9000} }
        for i, class in pairs(Config.Classes) do
            if useDebug then
                print(i, Classes[i])
            end
            classes[#classes+1] = { value = i, text = i, number = Classes[i] }
        end

        table.sort(classes, function(a,b)
            return a.number > b.number
        end)
        
        table.insert(options, {
            text =  Lang:t('menu.max_class'),
            name = "maxClass",
            type = "select",
            options = classes
        })

        local dialog = exports['qb-input']:ShowInput({
            header = Lang:t("menu.racing_setup"),
            submitText = "✓",
            inputs = options
        })
        if useDebug then
            print('selected max class', dialog.maxClass)
        end
        if dialog.maxClass == '' or Config.Classes[dialog.maxClass] then
            if not dialog or dialog.track == "none" then
                TriggerEvent('cw-racingapp:Client:OpenMainMenu', {
                    type = data.type,
                    name = data.name
                })
                return
            end

            local PlayerPed = PlayerPedId()
            local PlayerIsInVehicle = IsPedInAnyVehicle(PlayerPed, false)

            if PlayerIsInVehicle then
                local info, class, perfRating = exports['cw-performance']:getVehicleInfo(GetVehiclePedIsIn(PlayerPed, false))
                if myCarClassIsAllowed(dialog.maxClass, class) then
                    TriggerServerEvent('cw-racingapp:server:SetupRace',
                        dialog.track,
                        tonumber(dialog.laps),
                        data.name,
                        dialog.maxClass,
                        toboolean(dialog.ghosting),
                        tonumber(dialog.ghostingTime),
                        tonumber(dialog.buyIn)
                    )
                else 
                    QBCore.Functions.Notify('Your car is not the correct class', 'error')
                end
            else
                QBCore.Functions.Notify('You are not in a vehicle', 'error')
            end 
        else
            QBCore.Functions.Notify('The class you chose does not exist', 'error')
        end
    end)
end)

RegisterNetEvent("cw-racingapp:Client:CreateRaceMenu", function(data)
    local dialog = exports['qb-input']:ShowInput({
        header = Lang:t("menu.name_track_question"),
        submitText = "✓",
        inputs = {{
            text = Lang:t("menu.name_track"),
            name = "trackname",
            type = "text",
            isRequired = true
        }}
    })

    if not dialog then
        TriggerEvent('cw-racingapp:Client:OpenMainMenu', {
            type = data.type,
            name = data.name
        })
        return
    end

    if #dialog.trackname < Config.MinTrackNameLength then
        QBCore.Functions.Notify(Lang:t("error.name_too_short"), "error")
        TriggerEvent("cw-racingapp:Client:CreateRaceMenu", {
            type = data.type,
            name = data.name
        })
        return
    end

    if #dialog.trackname > Config.MaxTrackNameLength then
        QBCore.Functions.Notify(Lang:t("error.name_too_long"), "error")
        TriggerEvent("cw-racingapp:Client:CreateRaceMenu", {
            type = data.type,
            name = data.name
        })
        return
    end

    QBCore.Functions.TriggerCallback('cw-racingapp:server:IsAuthorizedToCreateRaces',
        function(IsAuthorized, NameAvailable)
            if not IsAuthorized then
                return
            end
            if not NameAvailable then
                QBCore.Functions.Notify(Lang:t("error.race_name_exists"), "error")
                TriggerEvent("cw-racingapp:Client:CreateRaceMenu", {
                    type = data.type,
                    name = data.name
                })
                return
            end

            TriggerServerEvent('cw-racingapp:server:CreateLapRace', dialog.trackname, data.name)
        end, dialog.trackname)
end)

local function indexOf(array, value)
    for i, v in ipairs(array) do
        print(i, value)
        if i == value then
            return i
        end
    end
    return nil
end

function myCarClassIsAllowed(maxClass, myClass)
    if maxClass == nil or maxClass == '' then
        return true
    end
    local myClassIndex = Classes[myClass]
    local maxClassIndex = Classes[maxClass]
    if myClassIndex > maxClassIndex then
        return false
    end

    return true
end

local function racerNameIsValid(name)
    if #name > Config.MinRacerNameLength then
        if #name < Config.MaxRacerNameLength then
            return true
        else
            QBCore.Functions.Notify(Lang:t('error.name_too_long'), "error")
        end
    else
        QBCore.Functions.Notify(Lang:t('error.name_too_short'), "error")
    end
    return false
end

local function hasAuth(tradeType, fobType)
    if tradeType.jobRequirement[fobType] then
        local Player = QBCore.Functions.GetPlayerData()
        local playerHasJob = Config.AllowedJobs[Player.job.name]
        local jobGradeReq = nil
        if useDebug then
           print('Player job: ', Player.job.name)
           print('Allowed jobs: ', dump(Config.AllowedJobs))
        end
        
        if playerHasJob then
            if useDebug then
               print('Player job level: ', Player.job.grade.level)
            end
            if Config.AllowedJobs[Player.job.name] ~= nil then
                jobGradeReq = Config.AllowedJobs[Player.job.name][fobType]
                if useDebug then
                   print('Required job grade: ', jobGradeReq)
                end
                if jobGradeReq ~= nil then
                    if Player.job.grade.level >= jobGradeReq then
                        return true
                    end
                end
            end      
        end
        return false
    else
        return true
    end
end

RegisterNetEvent("cw-racingapp:client:OpenFobInput", function(data)
    local purchaseType = data.purchaseType
    local fobType = data.fobType
    local dialog = exports['qb-input']:ShowInput({
        header = 'Creating a '..fobType..' racing fob',
        submitText = 'Submit',
        inputs = {
            {
                text = 'Racer Name', -- text you want to be displayed as a place holder
                name = "racerName", -- name of the input should be unique otherwise it might override
                type = "text", -- type of the input - number will not allow non-number characters in the field so only accepts 0-9
            },
            {
                text = 'Current Citizen Id (leave empty if for you)', -- text you want to be displayed as a place holder
                name = "racerId", -- name of the input should be unique otherwise it might override
                type = "text", -- type of the input - number will not allow non-number characters in the field so only accepts 0-9
            },
        },
        
    })

    if dialog ~= nil then
        local racerName = dialog["racerName"]
        local racerId = dialog["racerId"]
        local player = QBCore.Functions.GetPlayerData()
        if racerId == '' then
            print('racer id was left empty')
            racerId = GetPlayerServerId(PlayerId())
            print('WHAT THE FUCK ', racerId, dump(player))
        end
        print(racerName, racerId)
        if player.money[purchaseType.moneyType] > purchaseType.racingFobCost then
            if racerNameIsValid(racerName) then
                TriggerEvent('animations:client:EmoteCommandStart', {"idle7"})
                QBCore.Functions.Progressbar("item_check", 'Creating Racing Fob', 2000, false, true, {
                    disableMovement = true,
                    disableCarMovement = true,
                    disableMouse = false,
                    disableCombat = true,
                    }, {
                    }, {}, {}, function() -- Done
                        TriggerServerEvent('cw-racingapp:server:CreateFob', racerId, racerName, fobType, purchaseType)
                        TriggerEvent('animations:client:EmoteCommandStart', {"keyfob"})
                    end, function()
                        TriggerEvent('animations:client:EmoteCommandStart', {"damn"})
                    end)
            else
                TriggerEvent('animations:client:EmoteCommandStart', {"damn"})
            end
        else
            QBCore.Functions.Notify(Lang:t('error.can_not_afford'), "error")
        end
    else
        TriggerEvent('animations:client:EmoteCommandStart', {"c"})
    end
end)

local traderEntity
if Config.Trader.active then
    local trader = Config.Trader
    CreateThread(function()
        local animation
        if trader.animation then
            animation = trader.animation
        else
            animation = "WORLD_HUMAN_STAND_IMPATIENT"
        end
    
        local options = {
            { 
                type = "client",
                event = "cw-racingapp:client:OpenFobInput",
                icon = "fas fa-flag-checkered",
                label = 'Buy a racing fob for '..trader.racingFobCost..' '..trader.moneyType,
                purchaseType = trader,
                fobType = 'basic',
                canInteract = function()
                    return hasAuth(trader,'basic')
                end
            },
            { 
                type = "client",
                event = "cw-racingapp:client:OpenFobInput",
                icon = "fas fa-flag-checkered",
                label = 'Buy a Master racing fob for '..trader.racingFobMasterCost..' '..trader.moneyType,
                purchaseType = trader,
                fobType = 'master',
                canInteract = function()
                    return hasAuth(trader,'master')
                end
            }
        }

        traderEntity = exports['qb-target']:SpawnPed({
            model = trader.model,
            coords = trader.location,
            minusOne = true,
            freeze = true,
            invincible = true,
            blockevents = true,
            scenario = animation,
            target = {
                options = options,
                distance = 3.0 
            },
            spawnNow = true,
            currentpednumber = 4,
        })
        Entities[#Entities+1] = traderEntity
    end)
end

local laptopEntity
if Config.Laptop.active then
    CreateThread(function()        
        local laptop = Config.Laptop
            local options = {
                { 
                    type = "client",
                    event = "cw-racingapp:client:OpenFobInput",
                    icon = "fas fa-flag-checkered",
                    label = 'Buy a racing fob for '..laptop.racingFobCost..' '.. laptop.moneyType,
                    purchaseType = laptop,
                    fobType = 'basic',
                    canInteract = function()
                        return hasAuth(laptop,'basic')
                    end
                },
                { 
                    type = "client",
                    event = "cw-racingapp:client:OpenFobInput",
                    icon = "fas fa-flag-checkered",
                    label = 'Buy a Master racing fob for '..laptop.racingFobMasterCost..' '.. laptop.moneyType,
                    purchaseType = laptop,
                    fobType = 'master',
                    canInteract = function()
                        return hasAuth(laptop,'master')
                    end
                }
            }
            laptopEntity = CreateObject(laptop.model, laptop.location.x, laptop.location.y, laptop.location.z, true,  true, true)
            SetEntityHeading(laptopEntity, laptop.location.w)
            CreateObject(laptopEntity)
            FreezeEntityPosition(laptopEntity, true)
            Entities[#Entities+1] = laptopEntity
            exports['qb-target']:AddTargetEntity(laptopEntity, {
                options = options,
                distance = 3.0 
            })
    end)
end

AddEventHandler('onResourceStop', function (resource)
   if resource ~= GetCurrentResourceName() then return end
   for i, entity in pairs(Entities) do
       print('deleting', entity)
       if DoesEntityExist(entity) then
          DeleteEntity(entity)
       end
    end
end)
