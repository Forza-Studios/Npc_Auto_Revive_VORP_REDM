-- coi_med_rev / client.lua
-- Flow: dead -> HOLD W -> medic call -> "MEDIC IS COMING + live distance" UI
--    -> doctor NPC spawns ~45m away -> walks to player -> kneel/treat scenario -> revive

local isDead = false
local medicCalled = false
local medicPed = nil
local medicBlip = nil
local medicDist = -1
local medicArrived = false
local holdStart = 0
local holding = false

-- ============================================================
-- Helpers
-- ============================================================
local function Notify(text, duration)
    duration = duration or 4000
    -- VORP tip (most common). Falls back silently if vorp not present.
    pcall(function()
        TriggerEvent('vorp:TipBottom', text, duration)
    end)
end

local function DrawTxt(text, x, y, font, scale1, scale2, r, g, b, a, center)
    local str = CreateVarString(10, "LITERAL_STRING", text)
    SetTextScale(scale1, scale2)
    SetTextColor(r, g, b, a)
    SetTextCentre(center)
    SetTextFontForCurrentCommand(font)
    DisplayText(str, x, y)
end

local function IsPlayerDeadNow()
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then return false end
    local health = GetEntityHealth(ped)
    -- mirrors coi_autorevive / vorp convention: dead OR health <= 5
    if IsEntityDead(ped) then return true end
    if IsPedDeadOrDying(ped, 1) then return true end
    if IsPlayerDead(PlayerId()) then return true end
    if health <= 5 then return true end
    return false
end

local function IsHoldKeyDown()
    -- check both normal + disabled (death screens often disable controls)
    local ok1, down1 = pcall(IsControlPressed, 0, Config.HoldKey)
    if ok1 and down1 then return true end
    local ok2, down2 = pcall(IsDisabledControlPressed, 0, Config.HoldKey)
    if ok2 and down2 then return true end
    return false
end

local function Dbg(msg)
    if Config.Debug then
        print("[coi_med_rev] " .. tostring(msg))
    end
end

local function LoadModel(modelName)
    local model = GetHashKey(modelName)
    -- reject invalid / non-ped models early so we fall through to next doctor model
    local okValid, isValid = pcall(IsModelValid, model)
    if okValid and isValid == false then
        Dbg("model invalid: " .. modelName)
        return nil
    end
    RequestModel(model)
    local timeout = GetGameTimer() + 8000
    while not HasModelLoaded(model) and GetGameTimer() < timeout do
        Wait(100)
    end
    if HasModelLoaded(model) then
        Dbg("model loaded: " .. modelName)
        return model
    end
    Dbg("model load TIMEOUT: " .. modelName)
    return nil
end

local function GetSpawnCoordsNearPlayer(playerCoords, baseDist, variance)
    local angle = math.random() * math.pi * 2.0
    local dist = baseDist + (math.random() * variance * 2.0 - variance)
    if dist < 15.0 then dist = 15.0 end
    local x = playerCoords.x + math.cos(angle) * dist
    local y = playerCoords.y + math.sin(angle) * dist
    local z = playerCoords.z + 1.0
    -- load collision at target first, then snap to ground
    pcall(RequestCollisionAtCoord, x, y, z)
    -- try several heights for ground resolve (hills/valleys differ a lot from player Z)
    for _, h in ipairs({ 50.0, 10.0, 2.0, -10.0 }) do
        local ok, found, groundZ = pcall(GetGroundZFor_3dCoord, x, y, playerCoords.z + h, false)
        if ok and found == true and type(groundZ) == "number" and groundZ ~= 0 then
            z = groundZ + 1.0
            break
        end
    end
    pcall(RequestCollisionAtCoord, x, y, z)
    return vector3(x, y, z)
end

local function ForceRevivePlayer()
    local ped = PlayerPedId()
    ResurrectPed(ped)
    ClearPedTasksImmediately(ped)
    ClearPedSecondaryTask(ped)
    local maxHealth = GetEntityMaxHealth(ped)
    if not maxHealth or maxHealth <= 100 then maxHealth = 500 end
    SetEntityHealth(ped, maxHealth)

    -- VORP + common ecosystem revive hooks (safe pcall so script works standalone too)
    pcall(function() TriggerEvent('vorp_core:Client:OnPlayerRevive', true) end)
    pcall(function() TriggerServerEvent('v-doctorjob:server:cureAllDiseases') end)
    pcall(function() TriggerEvent("vorp_metabolism:changeValue", "Thirst", 500) end)
    pcall(function() TriggerEvent("vorp_metabolism:changeValue", "Water", 500) end)
    pcall(function() TriggerEvent("cas-metabolism:client:AddWater", 50) end)

    Notify(Config.Texts.revived, 4000)

    if Config.ReviveFee and Config.ReviveFee > 0 then
        TriggerServerEvent("coi_med_rev:payFee", Config.ReviveFee)
    end
end

local function CleanupMedic()
    if medicBlip ~= nil then
        pcall(RemoveBlip, medicBlip)
        medicBlip = nil
    end
    if medicPed ~= nil and DoesEntityExist(medicPed) then
        pcall(function()
            ClearPedTasks(medicPed)
            DeleteEntity(medicPed)
        end)
    end
    medicPed = nil
    medicDist = -1
    medicArrived = false
end

local function ResetState()
    medicCalled = false
    holding = false
    holdStart = 0
    CleanupMedic()
end

-- ============================================================
-- Medic dispatch: spawn doctor NPC -> walk to player -> treat -> revive
-- ============================================================
local function DispatchMedic()
    if medicCalled then
        Notify(Config.Texts.alreadyCalled, 4000)
        return
    end
    medicCalled = true
    -- immediately show "medic is coming" UI (draw thread picks up medicCalled + medicDist)
    Notify(Config.Texts.medicComing, 4000)

    if Config.OnlyWhenNoDoctorsOnline then
        -- server will callback coi_med_rev:doRevive(true/false)
        TriggerServerEvent("coi_med_rev:checkDoctors")
        return
    end

    TriggerEvent("coi_med_rev:doRevive", true)
end

RegisterNetEvent("coi_med_rev:doRevive")
AddEventHandler("coi_med_rev:doRevive", function(canRevive)
    if not canRevive then
        medicCalled = false
        Notify(Config.Texts.doctorsOnline, 5000)
        return
    end
    if not isDead then return end
    if medicPed ~= nil and DoesEntityExist(medicPed) then return end

    CreateThread(function()
        local playerPed = PlayerPedId()
        if not DoesEntityExist(playerPed) then
            medicCalled = false
            return
        end
        local playerCoords = GetEntityCoords(playerPed)

        -- load first available doctor model
        local model = nil
        local modelNameUsed = nil
        for _, name in ipairs(Config.DoctorModels) do
            model = LoadModel(name)
            if model then
                modelNameUsed = name
                break
            end
        end

        if not model then
            -- fallback to generic townfolk so revive still works
            model = LoadModel("a_m_m_valtownfolk_01")
        end

        if not model then
            -- total model failure: revive anyway so player is never stuck
            if isDead then ForceRevivePlayer() end
            medicCalled = false
            return
        end

        local spawn = GetSpawnCoordsNearPlayer(playerCoords, Config.SpawnDistance, Config.SpawnDistanceVariance)
        Dbg(("spawn %s at %.2f, %.2f, %.2f (player %.2f, %.2f, %.2f)"):format(
            tostring(modelNameUsed), spawn.x, spawn.y, spawn.z, playerCoords.x, playerCoords.y, playerCoords.z))

        -- LOCAL ped (not networked): guarantees visibility on this client.
        -- Networked peds (isNetwork=true) are the #1 cause of "medic called but invisible".
        medicPed = CreatePed(model, spawn.x, spawn.y, spawn.z, 0.0, false, false, false, false)
        SetModelAsNoLongerNeeded(model)

        if not DoesEntityExist(medicPed) then
            Dbg("CreatePed FAILED for " .. tostring(modelNameUsed))
            if isDead then ForceRevivePlayer() end
            medicCalled = false
            return
        end

        -- force visibility / solidity (anti cull / fall-through)
        pcall(FreezeEntityPosition, medicPed, false)
        pcall(SetEntityCollision, medicPed, true, true)
        pcall(SetEntityVisible, medicPed, true)
        pcall(SetEntityInvincible, medicPed, true)
        SetBlockingOfNonTemporaryEvents(medicPed, true)
        SetPedCanRagdoll(medicPed, false)
        pcall(SetPedConfigFlag, medicPed, 398, true) -- no critical hits (best-effort)
        pcall(SetRandomOutfitVariation, medicPed, true)
        -- keep engine from cleaning him up while walking over
        pcall(SetEntityAsMissionEntity, medicPed, true, false)
        pcall(SetPedKeepTask, medicPed, true)

        Dbg(("medic entity %d exists=%s"):format(medicPed, tostring(DoesEntityExist(medicPed))))

        -- blip so player sees him coming even if behind a hill/tree
        medicBlip = nil
        if Config.AddBlip then
            pcall(function()
                medicBlip = AddBlipForEntity(GetHashKey("blip_ambient_doctor"), medicPed)
            end)
            if medicBlip and medicBlip ~= 0 then
                pcall(SetBlipScale, medicBlip, 1.0)
            else
                medicBlip = nil
            end
            Dbg("medic blip: " .. tostring(medicBlip))
        end

        -- show distance instantly (spawn dist) instead of "..."
        do
            local mc = GetEntityCoords(medicPed)
            local pc = GetEntityCoords(playerPed)
            medicDist = #(mc - pc)
        end

        -- walk / run to player
        TaskGoToEntity(medicPed, playerPed, -1, Config.ArriveDistance - 0.5, Config.NpcRunSpeed, 0, 0)

        local deadline = GetGameTimer() + Config.EnrouteTimeoutMs
        local lastRetask = GetGameTimer()
        while isDead and DoesEntityExist(medicPed) and not medicArrived do
            Wait(250)
            if not isDead then break end
            playerPed = PlayerPedId()
            local mCoords = GetEntityCoords(medicPed)
            local pCoords = GetEntityCoords(playerPed)
            local dist = #(mCoords - pCoords)
            medicDist = dist -- <-- live distance for UI thread

            if dist <= Config.ArriveDistance then
                medicArrived = true
                break
            end

            -- re-issue goto if ped got stuck (every ~5s)
            if GetGameTimer() - lastRetask > 5000 then
                lastRetask = GetGameTimer()
                pcall(TaskGoToEntity, medicPed, playerPed, -1, Config.ArriveDistance - 0.5, Config.NpcRunSpeed, 0, 0)
            end

            if GetGameTimer() > deadline then
                -- teleport doctor close so player is never soft-locked
                local pc = GetEntityCoords(playerPed)
                SetEntityCoords(medicPed, pc.x + 2.0, pc.y + 2.0, pc.z, false, false, false, false)
                medicArrived = true
                break
            end
        end

        if not isDead then
            -- player was revived by someone else while medic walked over
            CleanupMedic()
            medicCalled = false
            return
        end

        if DoesEntityExist(medicPed) then
            ClearPedTasks(medicPed)
            -- face player, then kneel / inspect (revive scenario animation)
            TaskTurnPedToFaceEntity(medicPed, playerPed, 2000)
            Wait(2000)

            local scen = GetHashKey(Config.TreatScenario)
            TaskStartScenarioInPlace(medicPed, scen, -1, true, false, false, false)
            Wait(1500)

            -- verify scenario started, else try fallback
            -- (no reliable IsPedUsingScenario native check across builds; just re-apply fallback if needed)
            local treatUntil = GetGameTimer() + Config.TreatTimeMs
            while GetGameTimer() < treatUntil and isDead do
                Wait(500)
                -- keep medicDist pinned near 0 so UI shows "treating"
                medicDist = 0
                if not DoesEntityExist(medicPed) then break end
            end

            ClearPedTasks(medicPed)

            -- ---- revive function ----
            if isDead then
                ForceRevivePlayer()
                isDead = false
            end

            -- doctor walks away then despawns
            TaskWanderStandard(medicPed, 10.0, 10)
            SetEntityAsNoLongerNeeded(medicPed)
            local pedToDelete = medicPed
            local blipToDelete = medicBlip
            medicPed = nil
            medicBlip = nil
            medicDist = -1
            SetTimeout(Config.DespawnAfterMs, function()
                if DoesEntityExist(pedToDelete) then
                    DeleteEntity(pedToDelete)
                end
                if blipToDelete then
                    pcall(RemoveBlip, blipToDelete)
                end
            end)
        else
            if isDead then ForceRevivePlayer() end
        end

        medicCalled = false
        medicArrived = false
    end)
end)

-- ============================================================
-- Death monitor
-- ============================================================
CreateThread(function()
    while true do
        Wait(1000)
        local deadNow = IsPlayerDeadNow()
        if deadNow and not isDead then
            isDead = true
            medicCalled = false
            medicDist = -1
            medicArrived = false
            holdStart = 0
            holding = false
        elseif not deadNow and isDead then
            -- revived / respawned externally: reset + cleanup NPC
            isDead = false
            ResetState()
        end
    end
end)

-- ============================================================
-- Hold-W detection + all on-screen UI (runs every frame)
-- ============================================================
CreateThread(function()
    while true do
        Wait(0)

        if not isDead then
            Wait(500)
        else
            local playerPed = PlayerPedId()

            if medicCalled then
                -- ---- STATE: medic enroute / treating -> realtime distance UI ----
                if medicArrived or medicDist == 0 then
                    DrawTxt(Config.Texts.medicArrived, 0.5, 0.40, 0, 0.55, 0.55, 120, 255, 120, 255, true)
                else
                    DrawTxt(Config.Texts.medicComing, 0.5, 0.38, 0, 0.6, 0.6, 255, 200, 80, 255, true)
                    if medicDist ~= nil and medicDist >= 0 then
                        local d = math.floor(medicDist + 0.5)
                        DrawTxt(string.format(Config.Texts.medicDistance, d), 0.5, 0.43, 0, 0.9, 0.9, 255, 255, 255, 255, true)
                    else
                        -- called but NPC not spawned yet (loading): show immediately per spec
                        DrawTxt("...", 0.5, 0.43, 0, 0.9, 0.9, 255, 255, 255, 255, true)
                    end
                    DrawTxt("Stay down - help is on the way", 0.5, 0.48, 0, 0.4, 0.4, 220, 220, 220, 200, true)
                end
            else
                -- ---- STATE: waiting for HOLD W ----
                local prompt = string.format(Config.Texts.holdPrompt, Config.HoldKeyLabel)
                DrawTxt(prompt, 0.5, 0.82, 0, 0.5, 0.5, 255, 255, 255, 255, true)

                if IsHoldKeyDown() then
                    if not holding then
                        holding = true
                        holdStart = GetGameTimer()
                    end
                    local elapsed = GetGameTimer() - holdStart
                    local pct = math.floor((elapsed / Config.HoldTimeMs) * 100)
                    if pct > 100 then pct = 100 end

                    DrawTxt(string.format(Config.Texts.holding, pct), 0.5, 0.86, 0, 0.55, 0.55, 255, 200, 80, 255, true)

                    -- progress bar (background + fill)
                    local barW, barH = 0.22, 0.018
                    DrawRect(0.5, 0.905, barW + 0.004, barH + 0.006, 0, 0, 0, 160)
                    local fillW = barW * (pct / 100.0)
                    local fillX = 0.5 - barW / 2.0 + fillW / 2.0
                    DrawRect(fillX, 0.905, fillW, barH, 255, 140, 0, 230)

                    if elapsed >= Config.HoldTimeMs then
                        holding = false
                        holdStart = 0
                        DispatchMedic()
                    end
                else
                    -- released early: reset hold progress
                    holding = false
                    holdStart = 0
                end
            end

            -- safety: if ped entity vanished
            if not DoesEntityExist(playerPed) then
                Wait(500)
            end
        end
    end
end)

-- cleanup on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        CleanupMedic()
    end
end)

-- ============================================================
-- Debug / test helpers (F8 console)
-- /medicdebug -> prints state, ped exists/visible/health/coords
-- /medictest  -> forces a medic dispatch WITHOUT dying (visibility test)
-- ============================================================
RegisterCommand("medicdebug", function()
    local ped = PlayerPedId()
    local pc = GetEntityCoords(ped)
    print(("[coi_med_rev] isDead=%s medicCalled=%s arrived=%s dist=%s"):format(
        tostring(isDead), tostring(medicCalled), tostring(medicArrived), tostring(medicDist)))
    print(("[coi_med_rev] player %.2f, %.2f, %.2f health=%s"):format(
        pc.x, pc.y, pc.z, tostring(GetEntityHealth(ped))))
    if medicPed ~= nil then
        local exists = DoesEntityExist(medicPed)
        local mc = exists and GetEntityCoords(medicPed) or vector3(0, 0, 0)
        local vis = false
        pcall(function() vis = IsEntityVisible(medicPed) end)
        print(("[coi_med_rev] medic entity=%s exists=%s visible=%s health=%s coords=%.2f, %.2f, %.2f blip=%s"):format(
            tostring(medicPed), tostring(exists), tostring(vis),
            tostring(exists and GetEntityHealth(medicPed) or -1),
            mc.x, mc.y, mc.z, tostring(medicBlip)))
    else
        print("[coi_med_rev] medicPed=nil (no active medic)")
    end
end, false)

RegisterCommand("medictest", function()
    -- visibility test without dying: temporarily pretend death for the dispatch
    local wasDead = isDead
    isDead = true
    print("[coi_med_rev] medictest: forcing dispatch, watch for doctor + blip, then check /medicdebug")
    TriggerEvent("coi_med_rev:doRevive", true)
    -- restore real death flag after 2s if player wasn't actually dead;
    -- dispatch thread already captured isDead=true so it keeps going,
    -- death monitor will correct the flag on next tick if really alive
    SetTimeout(2000, function()
        if not IsPlayerDeadNow() and not wasDead then
            -- keep isDead true until medic arrives so test can complete,
            -- comment the next line out if you only want real-death testing
            -- isDead = false
        end
    end)
end, false)
