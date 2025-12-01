local spawnedNPCs = {}
local currentTrainJob = nil
local helpNotificationShown = {}
local lastJobStartTime = 0
local PlayerData = {}

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    PlayerData = QBCore.Functions.GetPlayerData()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    PlayerData = {}
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(jobInfo)
    PlayerData.job = jobInfo
end)

local function preloadTrainModels()
    local trainModels = {
        "freight",
        "metrotrain",
        "freightcont1",
        "freightcar",
        "freightcar2",
        "freightcont2",
        "tankercar",
        "freightgrain"
    }
    
    for _, modelName in ipairs(trainModels) do
        local modelHash = GetHashKey(modelName)
        RequestModel(modelHash)
        
        while not HasModelLoaded(modelHash) do
            Citizen.Wait(500)
        end
    end
end

preloadTrainModels()

-- CORRECTION : Nouvelle fonction manageNPC avec la bonne syntaxe ox_target
local function manageNPC(mode, distance)
    if distance < 200.0 then
        if spawnedNPCs[mode] then return end
        
        local npcConfig = Config.Positions[mode].NPC
        local npcCoords = npcConfig.coords
        local npcHeading = npcConfig.heading
        local npcModel = GetHashKey(npcConfig.model)
        
        RequestModel(npcModel)
        while not HasModelLoaded(npcModel) do
            Citizen.Wait(500)
        end
        
        spawnedNPCs[mode] = CreatePed(4, npcModel, npcCoords.x, npcCoords.y, npcCoords.z - 1.0, npcHeading, false, false)
        
        SetEntityInvincible(spawnedNPCs[mode], true)
        SetEntityAsMissionEntity(spawnedNPCs[mode], true, true)
        FreezeEntityPosition(spawnedNPCs[mode], true)
        SetBlockingOfNonTemporaryEvents(spawnedNPCs[mode], true)
        SetPedFleeAttributes(spawnedNPCs[mode], 0, 0)
        
        if Config.TargetSystem then
            -- NOUVELLE MÉTHODE : Utiliser la syntaxe correcte pour ox_target
            if exports.ox_target and exports.ox_target.addLocalEntity then
                exports.ox_target:addLocalEntity(spawnedNPCs[mode], {
                    {
                        name = "qbx_trainjob_" .. mode,
                        event = "qbx_trainjob:client:startJob",
                        icon = "fas fa-train",
                        label = "Start " .. mode:upper() .. " Job",
                        job = Config.Job.name,
                        mode = mode
                    }
                })
            else
                print("^1[ERROR]^0 ox_target not available for NPC")
            end
        end
    else
        if not spawnedNPCs[mode] then return end
        
        if spawnedNPCs[mode] then
            if Config.TargetSystem then
                -- NOUVELLE MÉTHODE : Supprimer la target du NPC
                if exports.ox_target and exports.ox_target.removeLocalEntity then
                    exports.ox_target:removeLocalEntity(spawnedNPCs[mode])
                end
            end
            SetEntityAsMissionEntity(spawnedNPCs[mode], false, false)
            DeleteEntity(spawnedNPCs[mode])
            spawnedNPCs[mode] = nil
        end
    end
end

Citizen.CreateThread(function()
    while not NetworkIsSessionStarted() do
        Wait(500)
    end
    SetTrainsForceDoorsOpen(false)
end)

Citizen.CreateThread(function()
    for mode, position in pairs(Config.Positions) do
        local blip = AddBlipForCoord(position.NPC.coords)
        
        SetBlipSprite(blip, Config.Blips[mode] and Config.Blips[mode].sprite or 795)
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, Config.Blips[mode] and Config.Blips[mode].scale or 0.8)
        SetBlipColour(blip, Config.Blips[mode] and Config.Blips[mode].color or 5)
        SetBlipAsShortRange(blip, true)
        
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(Config.Blips[mode] and Config.Blips[mode].name or "Train Depot")
        EndTextCommandSetBlipName(blip)
    end
end)

-- Thread pour l'entrée dans les trains en tant que passager
Citizen.CreateThread(function()
    while true do
        Wait(0)
        local playerPed = PlayerPedId()
        
        -- Si le joueur n'est pas dans un train et n'est pas en mission train
        if not IsPedInAnyTrain(playerPed) and not currentTrainJob then
            local train = GetClosestTrain(5.0)
            if train then
                -- Afficher l'aide pour entrer dans le train
                if not helpNotificationShown.train_entry then
                    helpNotificationShown.train_entry = true
                    showHelpNotification(Config.Language.enter_any_seat)
                end
                
                -- F pour entrer dans le train
                if IsControlJustPressed(0, 75) then
                    local availableSeat = FindAvailablePublicSeat(train)
                    if availableSeat then
                        if EnterTrainWithPermission(train, availableSeat) then
                            notify(Config.Language.entered_as_passenger, "success")
                        end
                    else
                        notify(Config.Language.no_seat_available, "error")
                    end
                end
            else
                helpNotificationShown.train_entry = false
            end
        else
            helpNotificationShown.train_entry = false
        end
    end
end)

local function createTrainJob(mode)
    local jobData = {}
    
    jobData.startTime = GetCloudTimeAsInt()
    jobData.mode = mode
    jobData.startPos = Config.Positions[mode].coords
    jobData.railPos = Config.Positions[mode].railPos
    
    local trainVariations = Config.Trains[mode].variations
    local randomVariation = trainVariations[math.random(1, #trainVariations)]
    jobData.trainVariation = randomVariation
    
    jobData.train = CreateMissionTrain(
        jobData.trainVariation,
        jobData.railPos.x,
        jobData.railPos.y,
        jobData.railPos.z,
        Config.Positions[mode].direction,
        true,
        true
    )
    
    -- Attendre que le train soit complètement créé
    Wait(1000)

    if DoesEntityExist(jobData.train) then
        -- Configurer les propriétés du train
        SetEntityAsMissionEntity(jobData.train, true, true)
        SetTrainSpeed(jobData.train, 0)
        SetTrainCruiseSpeed(jobData.train, 0)
        SetVehicleFuelLevel(jobData.train, 100.0)
        
        -- DÉSACTIVER COMPLÈTEMENT LE MODE FANTÔME
        SetEntityAlpha(jobData.train, 255, false)
        SetEntityVisible(jobData.train, true, false)
        ResetEntityAlpha(jobData.train)
        
        -- FORCER LES COLLISIONS IMMÉDIATEMENT
        SetEntityCollision(jobData.train, true, true)
        SetEntityCanBeDamaged(jobData.train, true)
        SetEntityInvincible(jobData.train, false)
        
        -- Configurer les wagons
        local carriageIndex = 0
        local carriage = GetTrainCarriage(jobData.train, carriageIndex)
        
        while carriage and DoesEntityExist(carriage) do
            SetEntityAsMissionEntity(carriage, true, true)
            
            -- FORCER L'OPACITÉ ET LES COLLISIONS POUR CHAQUE WAGON
            SetEntityAlpha(carriage, 255, false)
            SetEntityVisible(carriage, true, false)
            ResetEntityAlpha(carriage)
            SetEntityCollision(carriage, true, true)
            SetEntityCanBeDamaged(carriage, true)
            SetEntityInvincible(carriage, false)
            
            carriageIndex = carriageIndex + 1
            carriage = GetTrainCarriage(jobData.train, carriageIndex)
            
            if carriageIndex > 15 then break end
        end
        
        -- FORCER LA PHYSIQUE
        SetEntityDynamic(jobData.train, true)
        SetEntityHasGravity(jobData.train, true)
        SetEntityRecordsCollisions(jobData.train, true)
        
        -- Appeler setTrainCollision pour être sûr
        setTrainCollision(jobData.train, true)
        
        -- DÉVERROUILLER LE TRAIN AU DÉBUT
        LockTrain(jobData.train, false)

        -- ACQUÉRIR LES CLÉS DU TRAIN
        AcquireTrainKeys(jobData.train)
        
        -- Configurer les cibles pour les sièges si le système de target est activé
        if Config.TargetSystem then
            -- ATTENDRE UN PEU AVANT DE CONFIGURER LES TARGETS
            Citizen.Wait(2000)
            SetupTrainSeats(jobData.train)
        end
        
        -- Forcer l'opacité après un délai
        Citizen.SetTimeout(2000, function()
            if DoesEntityExist(jobData.train) then
                setTrainOpaque(jobData.train)
                setTrainCollision(jobData.train, true)
            end
        end)
    end

    local trainNetworkIds = {}
    for i = 1, 6 do
        local carriage = GetTrainCarriage(jobData.train, i)
        if carriage and DoesEntityExist(carriage) then
            NetworkRegisterEntityAsNetworked(carriage)
            Wait(0)
            if DoesEntityExist(carriage) then
                local networkId = NetworkGetNetworkIdFromEntity(carriage)
                if networkId and networkId ~= 0 then
                    table.insert(trainNetworkIds, networkId)
                end
            end
        end
    end
    
    if DoesEntityExist(jobData.train) then
        Wait(0)
        if DoesEntityExist(jobData.train) then
            local trainNetworkId = NetworkGetNetworkIdFromEntity(jobData.train)
            if trainNetworkId and trainNetworkId ~= 0 then
                table.insert(trainNetworkIds, trainNetworkId)
            end
        end
    end
    
    TriggerServerEvent("qbx_trainjob:server:createTrain", trainNetworkIds)
    TriggerEvent('vehiclekeys:client:SetOwner', jobData.train)
    
    jobData.maxSpeed = math.floor(Config.Trains[mode].maxSpeed / 3.6)
    jobData.emergencyBrake = false
    jobData.isInsideTrain = false
    jobData.isDoorOpen = false
    jobData.speed = 0
    jobData.currentStation = 1
    jobData.isStopping = false
    jobData.cam = nil
    
    function jobData.enterTrain(seatIndex)
        local playerPed = PlayerPedId()
        
        -- Si aucun siège spécifié, utiliser le siège conducteur par défaut
        if not seatIndex then
            seatIndex = -1 -- Siège conducteur
        end
        
        -- S'ASSURER QUE LES COLLISIONS SONT ACTIVÉES AVANT D'ENTRER
        if DoesEntityExist(jobData.train) then
            setTrainCollision(jobData.train, true)
            SetEntityCollision(jobData.train, true, true)
        end
        
        -- Vérifier les permissions pour le siège
        local seatName = GetSeatNameFromEntity(jobData.train, seatIndex)
        if not CanUseSeat(seatName) then
            notify(Config.Language.seat_restricted, "error")
            return false
        end
        
        TaskWarpPedIntoVehicle(playerPed, jobData.train, seatIndex)
        jobData.isInsideTrain = true
        
        -- FORCER LES COLLISIONS APRÈS ÊTRE ENTRE DANS LE TRAIN
        Citizen.SetTimeout(500, function()
            if DoesEntityExist(jobData.train) then
                setTrainCollision(jobData.train, true)
            end
        end)
        
        notify(Config.Language.job_started, "primary")
        notify(Config.Language.manual_doors_info, "info")
        notify(Config.Language.lock_instructions, "info")
        return true
    end
    
    function jobData.toggleCamera()
        if jobData.cam then
            DestroyAllCams(true)
            RenderScriptCams(false, false, 0, true, true)
            SetFollowPedCamViewMode(1)
            jobData.cam = nil
        else
            jobData.cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
            SetCamActive(jobData.cam, true)
            RenderScriptCams(true, false, 0, true, true)
        end
    end
    
    function jobData.setMaxSpeed(newMaxSpeed)
        if newMaxSpeed then
            jobData.maxSpeed = math.floor(newMaxSpeed / 3.6)
            if jobData.speed > jobData.maxSpeed then
                jobData.speed = jobData.maxSpeed
                SetTrainCruiseSpeed(jobData.train, jobData.speed)
            end
        else
            jobData.maxSpeed = math.floor(Config.Trains[mode].maxSpeed / 3.6)
        end
    end
    
    function jobData.increaseSpeed()
        if jobData.isDoorOpen or jobData.emergencyBrake or jobData.isStopping then return end
        
        local speedRatio = jobData.speed / jobData.maxSpeed
        local acceleration = 0.2 * (1 - speedRatio)
        jobData.speed = jobData.speed + acceleration
        
        if jobData.speed > jobData.maxSpeed then
            jobData.speed = jobData.maxSpeed
        end
        
        SetTrainCruiseSpeed(jobData.train, jobData.speed)
    end
    
    function jobData.decreaseSpeed()
        if jobData.isDoorOpen or jobData.emergencyBrake or jobData.isStopping then return end
        
        local speedRatio = jobData.speed / jobData.maxSpeed
        local deceleration = 0.04 + (speedRatio * 0.1)
        jobData.speed = jobData.speed - deceleration
        
        if jobData.speed < 0 then
            jobData.speed = 0
        end
        
        SetTrainCruiseSpeed(jobData.train, jobData.speed)
    end
    
    function jobData.toggleEmergencyBrake()
        if jobData.isDoorOpen or jobData.isStopping then return end
        
        jobData.emergencyBrake = not jobData.emergencyBrake
        
        if jobData.emergencyBrake then
            SetTrainCruiseSpeed(jobData.train, 0)
            PlaySound(-1, "TIMER_STOP", "HUD_MINI_GAME_SOUNDSET", 0, 0, 1)
        else
            SetTrainCruiseSpeed(jobData.train, jobData.speed)
            PlaySound(-1, "CHECKPOINT_PERFECT", "HUD_MINI_GAME_SOUNDSET", 0, 0, 1)
        end
    end
    
    jobData.isDoorInMotion = false
    function jobData.toggleDoors()
        if jobData.isDoorInMotion then return end
        
        -- Vérifier si le train a un système de portes
        local model = GetEntityModel(jobData.train)
        local hasDoors = false
        
        -- Vérifier si c'est un train avec portes (métro)
        if model == GetHashKey("metrotrain") or model == GetHashKey("freight") then
            hasDoors = true
        end
        
        if not hasDoors then
            notify("This train doesn't have doors", "info")
            return
        end
        
        if jobData.isDoorOpen then
            jobData.isDoorInMotion = true
            -- Fermer les portes
            SetTrainState(jobData.train, 4) -- État: portes fermées
            
            -- Attendre un peu pour l'animation
            Wait(2000)
            
            jobData.isDoorOpen = false
            jobData.isDoorInMotion = false
            
            -- VERROUILLER LE TRAIN SI CONFIGURÉ
            if Config.LockTrainOnDoorClose then
                LockTrain(jobData.train, true)
                notify(Config.Language.doors_locked, "success")
            else
                notify(Config.Language.doors_closed, "success")
            end
        else
            jobData.isDoorInMotion = true
            -- DÉVERROUILLER LE TRAIN SI CONFIGURÉ
            if Config.LockTrainOnDoorClose then
                LockTrain(jobData.train, false)
            end
            
            -- Ouvrir les portes
            SetTrainState(jobData.train, 2) -- État: portes ouvertes
            
            -- Attendre un peu pour l'animation
            Wait(2000)
            
            jobData.isDoorOpen = true
            jobData.isDoorInMotion = false
            
            notify(Config.Language.doors_opened, "success")
        end
    end
    
    return jobData
end

Citizen.CreateThread(function()
    while not NetworkIsSessionStarted() do
        Wait(500)
    end
    
    Wait(2000)
    local playerCoords = GetEntityCoords(PlayerPedId())
    for mode, position in pairs(Config.Positions) do
        local distance = #(playerCoords - position.NPC.coords)
        if distance < 200.0 then
            manageNPC(mode, distance)
        end
    end
    
    while true do
        local waitTime = 5000
        local playerCoords = GetEntityCoords(PlayerPedId())
        
        for mode, position in pairs(Config.Positions) do
            local distance = #(playerCoords - position.NPC.coords)
            
            if distance < 200.0 then
                manageNPC(mode, distance)
            end
            
            if distance < 50.0 then waitTime = 1000 end
            if distance < 10.0 then waitTime = 0 end
            
            -- SI LE SYSTÈME DE TARGET EST DÉSACTIVÉ, UTILISER L'INTERACTION MANUELLE
            if not Config.TargetSystem then
                if distance < 2.0 then
                    if IsTrainDriver() and IsOnDuty() then
                        if not helpNotificationShown[mode] then
                            helpNotificationShown[mode] = true
                            showHelpNotification(Config.Language.npc_help_notification)
                        end
                        
                        if IsControlJustPressed(0, 38) then
                            local currentTime = GetGameTimer()
                            if lastJobStartTime + 3000 < currentTime then
                                StartTrainJob(mode, position.NPC.coords)
                                lastJobStartTime = currentTime
                            end
                        end
                    else
                        if not helpNotificationShown[mode] then
                            helpNotificationShown[mode] = true
                            if not IsTrainDriver() then
                                showHelpNotification(Config.Language.not_train_driver)
                            else
                                showHelpNotification(Config.Language.on_duty_only)
                            end
                        end
                    end
                else
                    if helpNotificationShown[mode] then
                        helpNotificationShown[mode] = false
                        hideHelpNotification()
                    end
                end
            end
        end
        
        Wait(waitTime)
    end
end)

function EndTrainJob(completed)
    if currentTrainJob then
        TriggerServerEvent("qbx_trainjob:server:completeLine", currentTrainJob.mode, completed)
        if DoesEntityExist(currentTrainJob.train) then
            -- NETTOYER LES TARGETS DES SIÈGES
            CleanupTrainSeats(currentTrainJob.train)
            
            setTrainCollision(currentTrainJob.train, false)
            
            -- Marquer l'entité pour suppression
            SetEntityAsMissionEntity(currentTrainJob.train, false, true)
            
            -- Supprimer le train et ses wagons
            DeleteMissionTrain(currentTrainJob.train)
        end
        
        DestroyAllCams(true)
        RenderScriptCams(false, false, 0, true, true)
        SetFollowPedCamViewMode(1)
        
        SetEntityCoords(PlayerPedId(), Config.Positions[currentTrainJob.mode].endPos)
        
        currentTrainJob = nil
        
        notify(Config.Language.job_ended, "primary")
    end
end


-- FONCTION POUR ACQUÉRIR LES CLÉS (optionnelle mais recommandée)
function AcquireTrainKeys(train)
    if not DoesEntityExist(train) then return end
    
    local plate = GetVehicleNumberPlateText(train)
    if plate then
        -- Donner les clés au joueur (méthode standard pour QB-Core)
        TriggerEvent('vehiclekeys:client:SetOwner', plate)
        
        -- Alternative: Événement serveur pour QB-VehicleKeys
        TriggerServerEvent('qb-vehiclekeys:server:AcquireVehicleKeys', plate)
    end
end

-- Événement pour démarrer le job via le système de target
RegisterNetEvent("qbx_trainjob:client:startJob", function(data)
    if data and data.mode then
        StartTrainJob(data.mode)
    end
end)

-- Événement pour utiliser un siège spécifique via le système de target
RegisterNetEvent("qbx_trainjob:client:useSeat", function(data)
    if not data or not data.seat then return end
    
    local playerPed = PlayerPedId()
    
    -- Trouver le train le plus proche
    local train = GetClosestTrain(5.0)
    if not train then
        notify("No train nearby", "error")
        return
    end
    
    -- Utiliser le siège avec vérification des permissions (nouvelle méthode avec bones)
    if not EnterTrainWithBonePermission(train, data.seat) then
        -- Fallback sur l'ancienne méthode
        local seatIndex = GetSeatIndexFromName(data.seat)
        if seatIndex then
            EnterTrainWithPermission(train, seatIndex)
        else
            notify("Seat not found", "error")
        end
    end
end)

-- Commande pour arrêter la mission en cours (retour au dépôt)
RegisterCommand('stoptrainjob', function()
    if currentTrainJob then
        EndTrainJob(false)
        notify("Train job stopped. Returned to depot.", "success")
    else
        notify("No active train jobs.", "error")
    end
end, false)

-- NOUVELLE COMMANDE : Pour quitter le métier de train
RegisterCommand('exittrainjob', function()
    -- Vérifier si le joueur est actuellement dans le métier train
    if IsTrainDriver() then
        TriggerServerEvent('qbx_trainjob:server:exitTrainJob')
    else
        notify("You are not a train driver.", "error")
    end
end, false)

-- NOUVELLE COMMANDE : Pour verrouiller/déverrouiller le train
RegisterCommand('locktrain', function()
    if currentTrainJob and currentTrainJob.train then
        ToggleTrainLock(currentTrainJob.train)
    else
        -- Vérifier si le joueur est près d'un train
        local train = GetClosestTrain(5.0)
        if train then
            ToggleTrainLock(train)
        else
            notify("No train nearby", "error")
        end
    end
end, false)

-- Raccourci clavier pour verrouiller le train
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        
        -- Touche L pour verrouiller/déverrouiller (par défaut dans GTA)
        if IsControlJustPressed(0, 182) then -- Touche L
            ExecuteCommand("locktrain")
        end
    end
end)

function StartTrainJob(mode, npcCoords)
    if not IsTrainDriver() then
        notify(Config.Language.not_train_driver, "error")
        return
    end
    
    if not IsOnDuty() then
        notify(Config.Language.on_duty_only, "error")
        return
    end
    
    if currentTrainJob then
        EndTrainJob(false)
        return
    end
    
    TriggerServerEvent("qbx_trainjob:server:initiateJob")
    
    DoScreenFadeOut(800)
    Wait(1000)
    
    currentTrainJob = createTrainJob(mode)
    
    if not currentTrainJob then
        DoScreenFadeIn(800)
        return
    end
    
    -- Entrer dans le train en tant que conducteur
    if currentTrainJob.enterTrain(-1) then
        Wait(800)
        DoScreenFadeIn(800)
        
        -- Afficher les informations sur les commandes disponibles
        notify(Config.Language.stop_job_command, "info")
        notify(Config.Language.use_exit_command, "info")
    else
        DoScreenFadeIn(800)
        EndTrainJob(false)
        return
    end
    
    local stations = Config.Stations[mode]
    
    currentTrainJob.setMaxSpeed(stations[currentTrainJob.currentStation].newMaxSpeed)
    
    local missedStationCheck = false
    local frameCount = 0
    local stationArrivalTimes = {}
    
    -- Thread pour la gestion des stations et marqueurs
    Citizen.CreateThread(function()
        while currentTrainJob do
            if currentTrainJob.currentStation > #stations then break end
            
            Wait(0)
            
            if not currentTrainJob then return end
            
            frameCount = frameCount + 1
            
            local stationPos = stations[currentTrainJob.currentStation].pos
            local trainFrontPos = GetOffsetFromEntityInWorldCoords(currentTrainJob.train, 0.0, -30.0, 0.0)
            local trainCoords = GetEntityCoords(currentTrainJob.train)
            local distanceToStation = #(trainCoords - stationPos)
            local frontDistanceToStation = #(trainFrontPos - stationPos)
            
            if distanceToStation <= 10.0 then
                local currentStationData = Config.Stations[mode][currentTrainJob.currentStation]
                if currentStationData.isEnd then
                    EndTrainJob(true)
                    return
                end
            end
            
            if distanceToStation <= 10.0 then
                local currentStationData = Config.Stations[mode][currentTrainJob.currentStation]
                if currentStationData.isSkipping then
                    currentTrainJob.currentStation = currentTrainJob.currentStation + 1
                    local nextStationData = Config.Stations[mode][currentTrainJob.currentStation]
                    currentTrainJob.setMaxSpeed(currentStationData.newMaxSpeed)
                end
            end
            
            if distanceToStation <= 10.0 then
                if not stationArrivalTimes[currentTrainJob.currentStation] then
                    stationArrivalTimes[currentTrainJob.currentStation] = GetCloudTimeAsInt()
                end
            end
            
            if stationArrivalTimes[currentTrainJob.currentStation] then
                local arrivalTime = stationArrivalTimes[currentTrainJob.currentStation]
                if arrivalTime + 10 < GetCloudTimeAsInt() then
                    if not missedStationCheck then
                        local currentStationData = Config.Stations[mode][currentTrainJob.currentStation]
                        if not currentStationData.isSkipping then
                            missedStationCheck = true
                            SetTimeout(2000, function()
                                if not currentTrainJob then return end
                                
                                if not currentTrainJob.isStopping then
                                    local trainCurrentPos = GetEntityCoords(currentTrainJob.train)
                                    local distanceFromStation = #(trainCurrentPos - stationPos)
                                    
                                    if distanceFromStation >= 50.0 then
                                        local stationData = Config.Stations[currentTrainJob.mode][currentTrainJob.currentStation]
                                        if not stationData.isSkipping then
                                            currentTrainJob.currentStation = currentTrainJob.currentStation + 1
                                            local nextStationData = Config.Stations[currentTrainJob.mode][currentTrainJob.currentStation]
                                            
                                            if not nextStationData then
                                                currentTrainJob.currentStation = currentTrainJob.currentStation - 1
                                                return
                                            end
                                            
                                            currentTrainJob.setMaxSpeed(stationData.newMaxSpeed)
                                            notify("You missed the station! Continue to the next stop", "primary")
                                            missedStationCheck = false
                                        end
                                    else
                                        missedStationCheck = false
                                    end
                                else
                                    missedStationCheck = false
                                end
                            end)
                        end
                    end
                end
            end
            
            local currentStationData = Config.Stations[mode][currentTrainJob.currentStation]
            if not currentStationData.isSkipping then
                local stationX = stationPos.x
                local stationY = stationPos.y
                local stationZ = stationPos.z
                local markerWidth = 3.0
                local markerLength = 55.0
                
                local corners = {
                    vector3(stationX - markerWidth / 2, stationY - markerLength / 2, stationZ - 0.9),
                    vector3(stationX + markerWidth / 2, stationY - markerLength / 2, stationZ - 0.9),
                    vector3(stationX + markerWidth / 2, stationY + markerLength / 2, stationZ - 0.9),
                    vector3(stationX - markerWidth / 2, stationY + markerLength / 2, stationZ - 0.9)
                }
                
                local stationHeading = currentStationData.heading or 0.0
                for i = 1, 4 do
                    corners[i] = rotatePoint(stationPos, corners[i], stationHeading)
                end
                
                local markerColor
                if frontDistanceToStation <= 25.0 then
                    markerColor = {0, 255, 0, 40}
                else
                    markerColor = {255, 0, 0, 40}
                end
                
                local topCorners = {
                    vector3(corners[1].x, corners[1].y, corners[1].z + 0.4),
                    vector3(corners[2].x, corners[2].y, corners[2].z + 0.4),
                    vector3(corners[3].x, corners[3].y, corners[3].z + 0.4),
                    vector3(corners[4].x, corners[4].y, corners[4].z + 0.4)
                }
                
                local function drawPolygon(p1, p2, p3, color)
                    DrawPoly(p1.x, p1.y, p1.z, p2.x, p2.y, p2.z, p3.x, p3.y, p3.z, color[1], color[2], color[3], color[4])
                    DrawPoly(p3.x, p3.y, p3.z, p2.x, p2.y, p2.z, p1.x, p1.y, p1.z, color[1], color[2], color[3], color[4])
                end
                
                drawPolygon(corners[1], corners[3], corners[2], markerColor)
                drawPolygon(corners[1], corners[4], corners[3], markerColor)
                drawPolygon(topCorners[1], topCorners[2], topCorners[3], markerColor)
                drawPolygon(topCorners[1], topCorners[3], topCorners[4], markerColor)
                drawPolygon(corners[1], corners[2], topCorners[2], markerColor)
                drawPolygon(corners[1], topCorners[2], topCorners[1], markerColor)
                drawPolygon(corners[4], corners[3], topCorners[3], markerColor)
                drawPolygon(corners[4], topCorners[3], topCorners[4], markerColor)
                drawPolygon(corners[4], topCorners[1], corners[1], markerColor)
                drawPolygon(corners[4], topCorners[4], topCorners[1], markerColor)
                drawPolygon(corners[2], topCorners[3], corners[3], markerColor)
                drawPolygon(corners[2], topCorners[2], topCorners[3], markerColor)
            end
            
            if frameCount >= 2000 then
                frameCount = 0
            end
        end
    end)
    
    -- Thread pour les notifications et assistance
    Citizen.CreateThread(function()
        while currentTrainJob do
            if currentTrainJob.currentStation > #stations then break end
            
            if not currentTrainJob then return end
            
            if currentTrainJob.isInsideTrain then
                local trainSpeed = GetEntitySpeed(currentTrainJob.train)
                if trainSpeed < 5.0 then
                    local startTimePlus30 = currentTrainJob.startTime + 30
                    if startTimePlus30 > GetCloudTimeAsInt() then
                        if not helpNotificationShown.w_s then
                            helpNotificationShown.w_s = true
                            PlaySound(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", 0, 0, 1)
                        end
                        DrawMissionText(Config.Language.mission_text_2, 1000)
                    end
                end
            end
            
            local trainSpeed = GetEntitySpeed(currentTrainJob.train)
            if trainSpeed < 1.0 then
                if not currentTrainJob.isStopping then
                    local trainCoords = GetEntityCoords(currentTrainJob.train)
                    local stationPos = stations[currentTrainJob.currentStation].pos
                    local distanceToStation = #(trainCoords - stationPos)
                    
                    if distanceToStation < 30.0 then
                        DrawMissionText(Config.Language.mission_text_1, 1000)
                    end
                end
            end
            
            Wait(1000)
        end
    end)
    
    -- Thread pour les contrôles et vérifications
    Citizen.CreateThread(function()
        while currentTrainJob do
            if currentTrainJob.currentStation > #stations then break end
            
            local waitTime = 1000
            
            if not currentTrainJob then return end
            
            if currentTrainJob.isInsideTrain then
                if IsPedInAnyTrain(PlayerPedId()) then
                    waitTime = 0
                    
                    -- Désactiver la sortie véhicule normale
                    DisableControlAction(0, 75, true)
                    
                    if IsControlPressed(0, 32) then
                        currentTrainJob.increaseSpeed()
                    end
                    
                    if IsControlPressed(0, 31) then
                        currentTrainJob.decreaseSpeed()
                    end
                    
                    -- Touche G pour ouvrir/fermer les portes (sans restrictions)
                    if IsControlJustPressed(0, 47) then -- Touche G
                        currentTrainJob.toggleDoors()
                    end
                    
                    -- F simple pour sortir du train
                    if IsDisabledControlJustPressed(0, 75) then
                        local playerPed = PlayerPedId()
                        TaskLeaveVehicle(playerPed, currentTrainJob.train, 0)
                        currentTrainJob.isInsideTrain = false
                        notify(Config.Language.exited_train, "primary")
                    end
                end
            else
                -- Le joueur est sorti du train mais le job continue
                waitTime = 0
                
                local playerPed = PlayerPedId()
                local trainCoords = GetEntityCoords(currentTrainJob.train)
                local playerCoords = GetEntityCoords(playerPed)
                local distance = #(playerCoords - trainCoords)
                
                if distance < 5.0 then
                    -- F pour remonter dans le train
                    if IsControlJustPressed(0, 75) then
                        -- Vérifier si le train est verrouillé
                        if IsTrainLocked(currentTrainJob.train) then
                            notify(Config.Language.train_locked, "error")
                        else
                            -- Ré-entrer dans le siège conducteur
                            if currentTrainJob.enterTrain(-1) then
                                notify(Config.Language.reentering_train, "success")
                            end
                        end
                    end
                end
            end
            
            Wait(waitTime)
        end
    end)
    
    -- Vérification PERMANENTE des collisions (plus agressive)
    Citizen.CreateThread(function()
        while currentTrainJob do
            if currentTrainJob.currentStation > #stations then break end
            
            -- Vérifier CONSTAMMENT l'opacité et les collisions
            if currentTrainJob.train and DoesEntityExist(currentTrainJob.train) then
                local alpha = GetEntityAlpha(currentTrainJob.train)
                if alpha < 255 then
                    -- Le train est transparent, corriger IMMÉDIATEMENT
                    setTrainOpaque(currentTrainJob.train)
                end
                
                -- Vérifier SI le train a des collisions
                local collisionDisabled = GetEntityCollisionDisabled(currentTrainJob.train)
                if collisionDisabled then
                    -- Les collisions sont désactivées, les réactiver AGGRESSIVEMENT
                    forceTrainCollisions(currentTrainJob.train)
                end
            end
            
            -- Vérifier TRÈS fréquemment (toutes les 500ms)
            Wait(500)
        end
    end)
end

function rotatePoint(center, point, angle)
    local rad = math.rad(angle)
    local cos = math.cos(rad)
    local sin = math.sin(rad)
    
    local dx = point.x - center.x
    local dy = point.y - center.y
    
    local rotatedX = center.x + (dx * cos - dy * sin)
    local rotatedY = center.y + (dx * sin + dy * cos)
    
    return vector3(rotatedX, rotatedY, point.z)
end

-- MODIFICATION: Remplacer l'événement doorsOpened par une version simplifiée
RegisterNetEvent("qbx_trainjob:client:doorsOpened", function()
    -- Cette fonction ne fait plus rien d'automatique
    -- Les portes sont entièrement contrôlées manuellement par le conducteur
    print("Doors opened manually by driver")
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        if currentTrainJob then
            EndTrainJob(false)
        end
        
        -- Nettoyer les NPCs
        for mode, npc in pairs(spawnedNPCs) do
            if DoesEntityExist(npc) then
                if Config.TargetSystem and exports.ox_target and exports.ox_target.removeLocalEntity then
                    exports.ox_target:removeLocalEntity(npc)
                end
                DeleteEntity(npc)
            end
        end
        spawnedNPCs = {}
    end
end)

print("^2[qbx_trainjob]^0 Client script loaded successfully")