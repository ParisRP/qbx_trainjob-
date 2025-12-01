QQBCore = nil
local PlayerData = {}
local trainDoorStates = {} -- Nouveau: État des portes des trains

if Config.Framework == "QBCore" then
    QBCore = exports["qb-core"]:GetCoreObject()
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    PlayerData = QBCore.Functions.GetPlayerData()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    PlayerData = {}
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(jobInfo)
    PlayerData.job = jobInfo
end)

function IsTrainDriver()
    return PlayerData.job and PlayerData.job.name == Config.Job.name
end

function IsOnDuty()
    return PlayerData.job and PlayerData.job.onduty
end

function showHelpNotification(text)
    if Config.Framework == "QBCore" then
        QBCore.Functions.Notify(text, "primary", 3000)
    end
end

function hideHelpNotification()
end

function startProgress(duration, text)
    if Config.Framework == "QBCore" then
        QBCore.Functions.Progressbar("train_wait", text, duration * 1000, false, true, {
            disableMovement = false,
            disableCarMovement = false,
            disableMouse = false,
            disableCombat = true,
        }, {}, {}, {}, function()
        end)
    else
        showProgress(text, duration)
    end
end

function notify(text, type)
    if Config.Framework == "QBCore" then
        QBCore.Functions.Notify(text, type)
    end
end

-- CORRECTION : Utiliser la bonne syntaxe pour ox_target
function addTarget(entity, name, mode)
    if Config.TargetSystem then
        -- Vérifier si ox_target est disponible
        if exports.ox_target and exports.ox_target.addLocalEntity then
            exports.ox_target:addLocalEntity(entity, {
                {
                    name = name,
                    event = "qbx_trainjob:client:startJob",
                    icon = "fas fa-train",
                    label = "Start " .. mode:upper() .. " Job",
                    job = Config.Job.name,
                    mode = mode
                }
            })
        else
            print("^1[ERROR]^0 ox_target not available or addLocalEntity export not found")
        end
    end
end

function removeTarget(entity, name)
    if Config.TargetSystem then
        if exports.ox_target and exports.ox_target.removeLocalEntity then
            exports.ox_target:removeLocalEntity(entity, name)
        end
    end
end

function DrawMissionText(msg, time)
    ClearPrints()
    BeginTextCommandPrint('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandPrint(time, true)
end

function showProgress(text, duration)
    if not text or not duration then return end

    Citizen.CreateThread(function()
        for i = 0, duration do
            Citizen.Wait(1000)
            DrawMissionText(text .. " ~r~(" .. (duration - i) .. "s)~s~", 1000)
        end
    end)
end

-- ============================================
-- FONCTIONS DE GESTION DES SIÈGES
-- ============================================

function CanUseSeat(seatName)
    local seatsConfig = Config.Seats
    
    -- Vérifier si c'est un siège public
    for _, publicSeat in ipairs(seatsConfig.publicSeats) do
        if publicSeat == seatName then
            return true
        end
    end
    
    -- Vérifier si c'est un siège réservé au métier
    for _, jobSeat in ipairs(seatsConfig.jobSeats) do
        if jobSeat == seatName then
            return IsTrainDriver() and IsOnDuty()
        end
    end
    
    -- Par défaut, autoriser l'accès
    return true
end

function GetSeatNameFromEntity(entity, seatIndex)
    local model = GetEntityModel(entity)
    
    -- Pour les trains, déterminer le nom du siège basé sur l'index et la position
    if GetVehicleType(entity) == 'train' then
        local seatMap = {
            [-1] = "seat_dside_f",  -- Siège conducteur
            [0] = "seat_pside_f",   -- Siège passager avant
            [1] = "seat_dside_r",   -- Siège arrière conducteur
            [2] = "seat_pside_r",   -- Siège arrière passager
            [3] = "seat_dside_r1",  -- Siège arrière conducteur rangée 1
            [4] = "seat_pside_r1",  -- Siège arrière passager rangée 1
            [5] = "seat_dside_r2",  -- Siège arrière conducteur rangée 2
            [6] = "seat_pside_r2",  -- Siège arrière passager rangée 2
            [7] = "seat_dside_r3",  -- Siège arrière conducteur rangée 3
            [8] = "seat_pside_r3"   -- Siège arrière passager rangée 3
        }
        
        return seatMap[seatIndex] or "unknown_seat"
    end
    
    return "unknown_seat"
end

function GetSeatIndexFromName(seatName)
    local seatMap = {
        ["seat_dside_f"] = -1,
        ["seat_pside_f"] = 0,
        ["seat_dside_r"] = 1,
        ["seat_pside_r"] = 2,
        ["seat_dside_r1"] = 3,
        ["seat_pside_r1"] = 4,
        ["seat_dside_r2"] = 5,
        ["seat_pside_r2"] = 6,
        ["seat_dside_r3"] = 7,
        ["seat_pside_r3"] = 8
    }
    
    return seatMap[seatName]
end

-- NOUVELLE FONCTION : Obtenir l'index de siège via GetEntityBoneIndexByName
function GetSeatIndexFromBoneName(train, seatName)
    if not DoesEntityExist(train) then
        return nil
    end
    
    -- Mapping des noms d'os vers les index de siège
    local boneSeatMap = {
        ["seat_dside_f"] = -1,  -- Siège conducteur
        ["seat_pside_f"] = 0,   -- Siège passager avant
        ["seat_dside_r"] = 1,   -- Siège arrière conducteur
        ["seat_pside_r"] = 2,   -- Siège arrière passager
        ["seat_dside_r1"] = 3,  -- Siège arrière conducteur rangée 1
        ["seat_pside_r1"] = 4,  -- Siège arrière passager rangée 1
        ["seat_dside_r2"] = 5,  -- Siège arrière conducteur rangée 2
        ["seat_pside_r2"] = 6,  -- Siège arrière passager rangée 2
        ["seat_dside_r3"] = 7,  -- Siège arrière conducteur rangée 3
        ["seat_pside_r3"] = 8   -- Siège arrière passager rangée 3
    }
    
    -- Vérifier si l'os existe
    local boneIndex = GetEntityBoneIndexByName(train, seatName)
    if boneIndex ~= -1 then
        return boneSeatMap[seatName]
    end
    
    -- Si l'os n'existe pas, essayer avec des noms alternatifs
    local alternativeNames = {
        ["seat_dside_f"] = {"seat_dsidefront", "driver_seat"},
        ["seat_pside_f"] = {"seat_psidefront", "passenger_seat"},
        ["seat_dside_r"] = {"seat_dsiderear", "driver_rear"},
        ["seat_pside_r"] = {"seat_psiderear", "passenger_rear"}
    }
    
    if alternativeNames[seatName] then
        for _, altName in ipairs(alternativeNames[seatName]) do
            boneIndex = GetEntityBoneIndexByName(train, altName)
            if boneIndex ~= -1 then
                return boneSeatMap[seatName]
            end
        end
    end
    
    return nil
end

function GetClosestTrain(maxDistance)
    local playerCoords = GetEntityCoords(PlayerPedId())
    local vehicles = GetGamePool('CVehicle')
    
    for _, vehicle in ipairs(vehicles) do
        if DoesEntityExist(vehicle) and GetVehicleType(vehicle) == 'train' then
            local vehicleCoords = GetEntityCoords(vehicle)
            local distance = #(playerCoords - vehicleCoords)
            
            if distance <= (maxDistance or 10.0) then
                return vehicle
            end
        end
    end
    
    return nil
end

-- MODIFICATION: Supprimer la vérification de siège occupé
function EnterTrainWithPermission(train, seatIndex)
    local playerPed = PlayerPedId()
    
    if not DoesEntityExist(train) then
        notify("Train not found", "error")
        return false
    end
    
    -- Vérifier si le train est verrouillé
    if IsTrainLocked(train) then
        notify(Config.Language.train_locked, "error")
        return false
    end
    
    -- Obtenir le nom du siège
    local seatName = GetSeatNameFromEntity(train, seatIndex)
    
    -- Vérifier les permissions
    if not CanUseSeat(seatName) then
        notify(Config.Language.seat_restricted, "error")
        return false
    end
    
    -- SUPPRIMÉ: Vérification si le siège est libre
    
    -- S'asseoir dans le siège
    TaskWarpPedIntoVehicle(playerPed, train, seatIndex)
    
    -- Si c'est un siège réservé au métier, vérifier qu'on est en service
    local isJobSeat = false
    for _, jobSeat in ipairs(Config.Seats.jobSeats) do
        if jobSeat == seatName then
            isJobSeat = true
            break
        end
    end
    
    if isJobSeat and (not IsTrainDriver() or not IsOnDuty()) then
        -- Éjecter le joueur si il n'a pas la permission
        Citizen.Wait(1000)
        TaskLeaveVehicle(playerPed, train, 0)
        notify(Config.Language.seat_restricted, "error")
        return false
    end
    
    return true
end

-- MODIFICATION: Supprimer la vérification de siège occupé
function EnterTrainWithBonePermission(train, seatName)
    local playerPed = PlayerPedId()
    
    if not DoesEntityExist(train) then
        notify("Train not found", "error")
        return false
    end
    
    -- Vérifier si le train est verrouillé
    if IsTrainLocked(train) then
        notify(Config.Language.train_locked, "error")
        return false
    end
    
    -- Vérifier les permissions
    if not CanUseSeat(seatName) then
        notify(Config.Language.seat_restricted, "error")
        return false
    end
    
    -- Obtenir l'index du siège via le nom de l'os
    local seatIndex = GetSeatIndexFromBoneName(train, seatName)
    if not seatIndex then
        -- Fallback sur l'ancienne méthode
        seatIndex = GetSeatIndexFromName(seatName)
        if not seatIndex then
            notify("Seat not available", "error")
            return false
        end
    end
    
    -- SUPPRIMÉ: Vérification si le siège est libre
    
    -- S'asseoir dans le siège
    TaskWarpPedIntoVehicle(playerPed, train, seatIndex)
    
    -- Si c'est un siège réservé au métier, vérifier qu'on est en service
    local isJobSeat = false
    for _, jobSeat in ipairs(Config.Seats.jobSeats) do
        if jobSeat == seatName then
            isJobSeat = true
            break
        end
    end
    
    if isJobSeat and (not IsTrainDriver() or not IsOnDuty()) then
        -- Éjecter le joueur si il n'a pas la permission
        Citizen.Wait(1000)
        TaskLeaveVehicle(playerPed, train, 0)
        notify(Config.Language.seat_restricted, "error")
        return false
    end
    
    return true
end

function FindAvailablePublicSeat(train)
    local publicSeats = Config.Seats.publicSeats
    
    for _, seatName in ipairs(publicSeats) do
        -- Essayer d'abord avec la méthode par nom d'os
        local seatIndex = GetSeatIndexFromBoneName(train, seatName)
        if seatIndex then
            return seatIndex
        end
        
        -- Fallback sur l'ancienne méthode
        if not seatIndex then
            seatIndex = GetSeatIndexFromName(seatName)
            if seatIndex then
                return seatIndex
            end
        end
    end
    
    return nil
end

-- CORRECTION : Utiliser la bonne syntaxe pour ox_target avec les sièges
function SetupTrainSeats(train)
    if not Config.TargetSystem or not DoesEntityExist(train) then return end
    
    -- Vérifier si ox_target est disponible
    if not exports.ox_target or not exports.ox_target.addLocalEntity then
        print("^1[ERROR]^0 ox_target not available for train seats")
        return
    end
    
    -- Configurer les sièges publics
    for _, seatName in ipairs(Config.Seats.publicSeats) do
        local seatIndex = GetSeatIndexFromBoneName(train, seatName) or GetSeatIndexFromName(seatName)
        if seatIndex then
            exports.ox_target:addLocalEntity(train, {
                {
                    name = "train_seat_" .. seatName,
                    event = "qbx_trainjob:client:useSeat",
                    icon = "fas fa-chair",
                    label = "Sit down",
                    seat = seatName,
                    canInteract = function()
                        return not IsPedInAnyVehicle(PlayerPedId(), false) and not IsTrainLocked(train)
                    end
                }
            })
        end
    end
    
    -- Configurer les sièges réservés au métier
    for _, seatName in ipairs(Config.Seats.jobSeats) do
        local seatIndex = GetSeatIndexFromBoneName(train, seatName) or GetSeatIndexFromName(seatName)
        if seatIndex then
            exports.ox_target:addLocalEntity(train, {
                {
                    name = "train_seat_job_" .. seatName,
                    event = "qbx_trainjob:client:useSeat",
                    icon = "fas fa-chair",
                    label = "Sit down (Reserved for staff)",
                    seat = seatName,
                    canInteract = function()
                        return IsTrainDriver() and IsOnDuty() and not IsPedInAnyVehicle(PlayerPedId(), false) and not IsTrainLocked(train)
                    end
                }
            })
        end
    end
end

-- CORRECTION : Utiliser la bonne syntaxe pour nettoyer les targets
function CleanupTrainSeats(train)
    if not Config.TargetSystem or not DoesEntityExist(train) then return end
    
    if exports.ox_target and exports.ox_target.removeLocalEntity then
        -- Supprimer toutes les targets du train
        exports.ox_target:removeLocalEntity(train)
    end
end

function setTrainCollision(train, enabled)
    if not DoesEntityExist(train) then 
        return 
    end
    
    -- FORCER L'OPACITÉ COMPLÈTE
    SetEntityAlpha(train, 255, false)
    SetEntityVisible(train, true, false)
    ResetEntityAlpha(train)
    
    -- DÉSACTIVER TOUT MODE FANTÔME (méthode alternative)
    SetLocalPlayerAsGhost(false)
    
    -- ACTIVER/DÉSACTIVER LES COLLISIONS POUR LE TRAIN PRINCIPAL
    SetEntityCollision(train, enabled, enabled)
    SetEntityCanBeDamaged(train, enabled)
    SetEntityInvincible(train, not enabled)
    SetEntityDynamic(train, enabled)
    SetEntityHasGravity(train, enabled)
    SetEntityRecordsCollisions(train, enabled)
    
    -- FORCER LA MISE À JOUR IMMÉDIATE
    FreezeEntityPosition(train, false)
    SetEntityVelocity(train, 0.0, 0.0, 0.0)
    
    -- Configurer les wagons
    local carriageIndex = 0
    local carriage = GetTrainCarriage(train, carriageIndex)
    
    while carriage and DoesEntityExist(carriage) do
        -- Forcer l'opacité
        SetEntityAlpha(carriage, 255, false)
        SetEntityVisible(carriage, true, false)
        ResetEntityAlpha(carriage)
        
        -- Activer les collisions
        SetEntityCollision(carriage, enabled, enabled)
        SetEntityCanBeDamaged(carriage, enabled)
        SetEntityInvincible(carriage, not enabled)
        SetEntityDynamic(carriage, enabled)
        SetEntityHasGravity(carriage, enabled)
        
        carriageIndex = carriageIndex + 1
        carriage = GetTrainCarriage(train, carriageIndex)
        
        -- Sécurité pour éviter une boucle infinie
        if carriageIndex > 20 then break end
    end
end

function setTrainOpaque(train)
    if not DoesEntityExist(train) then return end
    
    -- Forcer l'opacité complète du train
    SetEntityAlpha(train, 255, false)
    SetEntityVisible(train, true, false)
    ResetEntityAlpha(train)
    
    -- Configurer les wagons
    local carriageIndex = 0
    local carriage = GetTrainCarriage(train, carriageIndex)
    
    while carriage and DoesEntityExist(carriage) do
        SetEntityAlpha(carriage, 255, false)
        SetEntityVisible(carriage, true, false)
        ResetEntityAlpha(carriage)
        
        carriageIndex = carriageIndex + 1
        carriage = GetTrainCarriage(train, carriageIndex)
        
        if carriageIndex > 15 then break end
    end
    
    -- Forcer le rendu
    SetEntityRenderScorched(train, false)
end

function enableTrainPhysics(train)
    if not DoesEntityExist(train) then return end
    
    -- Activer la physique complète
    SetEntityDynamic(train, true)
    SetEntityHasGravity(train, true)
    SetEntityCollision(train, true, true)
    
    -- Désactiver le mode "fantôme"
    SetEntityVisible(train, true)
    SetEntityAlpha(train, 255, 0)
    
    -- Configurer les wagons
    local carriageIndex = 0
    local carriage = GetTrainCarriage(train, carriageIndex)
    
    while carriage and DoesEntityExist(carriage) do
        SetEntityDynamic(carriage, true)
        SetEntityHasGravity(carriage, true)
        SetEntityCollision(carriage, true, true)
        SetEntityVisible(carriage, true)
        SetEntityAlpha(carriage, 255, 0)
        
        carriageIndex = carriageIndex + 1
        carriage = GetTrainCarriage(train, carriageIndex)
        
        if carriageIndex > 15 then break end
    end
end

function forceTrainCollisions(train)
    if not DoesEntityExist(train) then return end
    
    -- Méthode agressive pour forcer les collisions
    for i = 1, 5 do
        setTrainCollision(train, true)
        
        -- Forcer la mise à jour physique
        SetEntityCollision(train, true, true)
        SetEntityRecordsCollisions(train, true)
        
        -- Désactiver tout mode fantôme
        SetLocalPlayerAsGhost(false)
        
        -- Vérifier les wagons
        local carriageIndex = 0
        local carriage = GetTrainCarriage(train, carriageIndex)
        
        while carriage and DoesEntityExist(carriage) do
            SetEntityCollision(carriage, true, true)
            SetEntityRecordsCollisions(carriage, true)
            
            carriageIndex = carriageIndex + 1
            carriage = GetTrainCarriage(train, carriageIndex)
            
            if carriageIndex > 15 then break end
        end
        
        Wait(50)
    end
end

-- ============================================
-- NOUVELLES FONCTIONS POUR LE SYSTÈME DE PORTES ET VERROUILLAGE
-- ============================================

-- NOUVELLE FONCTION: Vérifier si un train est verrouillé
function IsTrainLocked(train)
    if not DoesEntityExist(train) then return false end
    
    local netId = NetworkGetNetworkIdFromEntity(train)
    return trainDoorStates[netId] or false
end

-- NOUVELLE FONCTION: Verrouiller/Déverrouiller le train - VERSION CORRIGÉE
function LockTrain(train, locked)
    if not DoesEntityExist(train) then return end
    
    -- Stocker l'état de verrouillage
    local netId = NetworkGetNetworkIdFromEntity(train)
    
    if locked then
        trainDoorStates[netId] = true
        notify(Config.Language.train_locked, "success")
    else
        trainDoorStates[netId] = false
        notify(Config.Language.train_unlocked, "success")
    end
    
    -- 1. Première méthode: Essayer avec les exports standard
    local success = false
    
    -- Méthode pour QBX Core (la plus courante)
    if not success then
        local plate = GetVehicleNumberPlateText(train)
        if plate then
            -- qbx_vehiclekeys utilise généralement cette méthode
            TriggerServerEvent('qb-vehiclekeys:server:AcquireVehicleKeys', plate)
            success = true
        end
    end
    
    -- 2. Méthode ox_doorlock si disponible
    if not success and exports.ox_doorlock then
        -- Pour ox_doorlock, nous devons trouver la porte du train
        -- Comme alternative, on peut utiliser une méthode générique
        print("^2[qbx_trainjob]^0 ox_doorlock detected")
        success = true
    end
    
    -- 3. Méthode vehiclekeys standard (qb-vehiclekeys)
    if not success and exports['vehiclekeys'] then
        if locked then
            exports['vehiclekeys']:setVehicleLocked(train, 2) -- Verrouillé
        else
            exports['vehiclekeys']:setVehicleLocked(train, 1) -- Déverrouillé
        end
        success = true
    end
    
    -- 4. Méthode qb-vehiclekeys standard
    if not success and exports['qb-vehiclekeys'] then
        if exports['qb-vehiclekeys'].setVehicleLock then
            exports['qb-vehiclekeys']:setVehicleLock(train, locked)
        end
        success = true
    end
    
    -- 5. Méthode native GTA V (fallback garantie)
    if locked then
        SetVehicleDoorsLocked(train, 2) -- Verrouillé
        SetVehicleDoorsLockedForAllPlayers(train, true)
    else
        SetVehicleDoorsLocked(train, 1) -- Déverrouillé
        SetVehicleDoorsLockedForAllPlayers(train, false)
    end
    
    -- 6. Émettre un son de verrouillage
    if locked then
        PlaySoundFrontend(-1, "Remote_Control_Close", "PI_Menu_Sounds", true)
    else
        PlaySoundFrontend(-1, "Remote_Control_Close", "PI_Menu_Sounds", true)
    end
    
    -- 7. Optionnel: Forcer la mise à jour des clés
    local playerPed = PlayerPedId()
    if GetPedInVehicleSeat(train, -1) == playerPed then
        TriggerEvent('vehiclekeys:client:SetOwner', GetVehicleNumberPlateText(train))
    end
    
    -- Journal pour débogage
    print(string.format("^2[qbx_trainjob]^0 Train %s: %s (Native method used)", netId, locked and "LOCKED" or "UNLOCKED"))
end

-- NOUVELLE FONCTION: Basculer l'état de verrouillage
function ToggleTrainLock(train)
    if not DoesEntityExist(train) then return end
    
    local netId = NetworkGetNetworkIdFromEntity(train)
    local currentState = trainDoorStates[netId] or false
    
    if currentState then
        LockTrain(train, false)
    else
        LockTrain(train, true)
    end
end

-- NOUVELLE FONCTION: Vérifier et acquérir les clés du train
function AcquireTrainKeys(train)
    if not DoesEntityExist(train) then return end
    
    local plate = GetVehicleNumberPlateText(train)
    if plate then
        -- Essayer différentes méthodes pour obtenir les clés
        if exports['vehiclekeys'] then
            TriggerEvent('vehiclekeys:client:SetOwner', plate)
        elseif exports['qb-vehiclekeys'] then
            TriggerServerEvent('qb-vehiclekeys:server:AcquireVehicleKeys', plate)
        else
            -- Méthode par défaut
            TriggerEvent('vehiclekeys:client:SetOwner', plate)
        end
    end
end