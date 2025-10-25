-- ===========================
-- AUTO FISH V5 - ULTRA AGGRESSIVE HEARTBEAT SPAM
-- SPAM FishingCompleted via RunService.Heartbeat (NO JEDA!)
-- Pattern tetap sama: BaitSpawned → ReplicateTextEffect detection
-- CHANGE: Pake Heartbeat buat spam pure tanpa task.wait delay
-- ===========================

local AutoFishFeature = {}
AutoFishFeature.__index = AutoFishFeature

local logger = _G.Logger and _G.Logger.new("BAF") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")  
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- Network setup
local NetPath = nil
local EquipTool, ChargeFishingRod, RequestFishing, FishingCompleted, FishObtainedNotification, BaitSpawnedEvent, ReplicateTextEffect, CancelFishingInputs

local function initializeRemotes()
    local success = pcall(function()
        NetPath = ReplicatedStorage:WaitForChild("Packages", 5)
            :WaitForChild("_Index", 5)
            :WaitForChild("sleitnick_net@0.2.0", 5)
            :WaitForChild("net", 5)

        EquipTool = NetPath:WaitForChild("RE/EquipToolFromHotbar", 5)
        ChargeFishingRod = NetPath:WaitForChild("RF/ChargeFishingRod", 5)
        RequestFishing = NetPath:WaitForChild("RF/RequestFishingMinigameStarted", 5)
        FishingCompleted = NetPath:WaitForChild("RE/FishingCompleted", 5)
        FishObtainedNotification = NetPath:WaitForChild("RE/ObtainedNewFishNotification", 5)
        BaitSpawnedEvent = NetPath:WaitForChild("RE/BaitSpawned", 5)
        ReplicateTextEffect = NetPath:WaitForChild("RE/ReplicateTextEffect", 5)
        CancelFishingInputs = NetPath:WaitForChild("RF/CancelFishingInputs", 5)

        return true
    end)

    return success
end

-- Feature state
local isRunning = false
local currentMode = "Fast"
local connection = nil
local spamConnection = nil -- Single HEARTBEAT spam
local fishObtainedConnection = nil
local baitSpawnedConnection = nil
local replicateTextConnection = nil
local safetyNetConnection = nil
local controls = {}
local fishingInProgress = false
local remotesInitialized = false
local cancelInProgress = false

-- Spam tracking
local spamActive = false
local spamCounter = 0
local lastSpamTime = 0

-- BaitSpawned counter sejak start
local baitSpawnedCount = 0

-- Tracking untuk deteksi ReplicateTextEffect setelah BaitSpawned
local pendingBaitChecks = {}
local WAIT_WINDOW = 1

-- Safety Net tracking
local lastBaitSpawnedTime = 0
local SAFETY_TIMEOUT = 3
local safetyNetTriggered = false

-- Throttle spam (kirim setiap N frames, 0 = tiap frame)
local SPAM_THROTTLE = 0 -- 0 = spam tiap frame (GACOR MAX!)

-- Rod configs
local FISHING_CONFIGS = {
    ["Fast"] = {
        chargeTime = 0,
        waitBetween = 0,
        rodSlot = 1,
        spamThrottle = 0 -- Tiap frame
    },
    ["Slow"] = {
        chargeTime = 1.0,
        waitBetween = 1,
        rodSlot = 1,
        spamThrottle = 2 -- Tiap 2 frame
    }
}

function AutoFishFeature:Init(guiControls)
    controls = guiControls or {}
    remotesInitialized = initializeRemotes()

    if not remotesInitialized then
        logger:warn("Failed to initialize remotes")
        return false
    end

    self:SetupReplicateTextHook()
    self:SetupBaitSpawnedHook()

    logger:info("Initialized V5 HEARTBEAT SPAM - Pure frame-based spam!")
    return true
end

function AutoFishFeature:SetupReplicateTextHook()
    if not ReplicateTextEffect then
        logger:warn("ReplicateTextEffect not available")
        return
    end

    if replicateTextConnection then
        replicateTextConnection:Disconnect()
    end

    replicateTextConnection = ReplicateTextEffect.OnClientEvent:Connect(function(data)
        if not isRunning then return end
        
        if not data or not data.TextData then 
            return 
        end
        
        if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("Head") then
            return
        end
        
        if data.TextData.AttachTo ~= LocalPlayer.Character.Head then
            return
        end
        
        local currentTime = tick()
        
        -- Mark semua pending checks dalam range waktu
        for id, checkData in pairs(pendingBaitChecks) do
            local timeDiff = currentTime - checkData.timestamp
            if timeDiff >= 0 and timeDiff <= WAIT_WINDOW + 0.2 and not checkData.received then
                checkData.received = true
                checkData.receivedAt = currentTime
                logger:info("✅ ReplicateTextEffect for BaitSpawned #" .. checkData.baitNumber)
            end
        end
    end)

    logger:info("ReplicateTextEffect hook ready")
end

function AutoFishFeature:SetupBaitSpawnedHook()
    if not BaitSpawnedEvent then
        logger:warn("BaitSpawnedEvent not available")
        return
    end

    if baitSpawnedConnection then
        baitSpawnedConnection:Disconnect()
    end

    baitSpawnedConnection = BaitSpawnedEvent.OnClientEvent:Connect(function(player, rodName, position)
        if not isRunning or cancelInProgress then return end
        
        if player ~= LocalPlayer then
            return
        end

        baitSpawnedCount = baitSpawnedCount + 1
        lastBaitSpawnedTime = tick()
        safetyNetTriggered = false
        
        local currentBaitNumber = baitSpawnedCount
        local currentTime = tick()
        local checkId = tostring(currentTime) .. "_" .. currentBaitNumber
        
        logger:info("🎯 BaitSpawned #" .. currentBaitNumber)

        pendingBaitChecks[checkId] = {
            received = false,
            baitNumber = currentBaitNumber,
            timestamp = currentTime,
            receivedAt = nil
        }

        spawn(function()
            task.wait(WAIT_WINDOW)
            
            if not isRunning or cancelInProgress then 
                pendingBaitChecks[checkId] = nil
                return 
            end
            
            local checkData = pendingBaitChecks[checkId]
            if not checkData then 
                return 
            end
            
            if checkData.received then
                logger:info("✅ NORMAL flow #" .. currentBaitNumber)
                pendingBaitChecks[checkId] = nil
            else
                logger:info("🔄 CANCEL #" .. currentBaitNumber)
                pendingBaitChecks[checkId] = nil
                
                if currentBaitNumber == 1 then
                    logger:warn("⚠️ Skip cancel (first bait)")
                    return
                end
                
                self:CancelAndRestart()
            end
        end)
    end)

    logger:info("BaitSpawned hook ready")
end

function AutoFishFeature:StartSafetyNet()
    if safetyNetConnection then
        safetyNetConnection:Disconnect()
    end

    lastBaitSpawnedTime = tick()

    safetyNetConnection = RunService.Heartbeat:Connect(function()
        if not isRunning or cancelInProgress or safetyNetTriggered then return end

        local currentTime = tick()
        local timeSinceLastBait = currentTime - lastBaitSpawnedTime

        if timeSinceLastBait >= SAFETY_TIMEOUT then
            safetyNetTriggered = true
            logger:warn("⚠️ SAFETY NET TRIGGERED!")
            self:SafetyNetCancel()
        end
    end)

    logger:info("🛡️ Safety Net active")
end

function AutoFishFeature:StopSafetyNet()
    if safetyNetConnection then
        safetyNetConnection:Disconnect()
        safetyNetConnection = nil
    end
    lastBaitSpawnedTime = 0
end

function AutoFishFeature:SafetyNetCancel()
    if not CancelFishingInputs or cancelInProgress then return end

    cancelInProgress = true
    logger:info("🛡️ Safety Net cancel...")

    pcall(function()
        CancelFishingInputs:InvokeServer()
    end)
    
    task.wait(0.2)
    
    pcall(function()
        CancelFishingInputs:InvokeServer()
    end)

    fishingInProgress = false
    pendingBaitChecks = {}
    lastBaitSpawnedTime = tick()
    
    task.wait(0.2)

    if isRunning then
        cancelInProgress = false
        safetyNetTriggered = false
        self:ChargeAndCast()
    else
        cancelInProgress = false
    end
end

function AutoFishFeature:CancelAndRestart()
    if not CancelFishingInputs or cancelInProgress then return end

    cancelInProgress = true
    
    logger:info("Cancelling...")

    pcall(function()
        CancelFishingInputs:InvokeServer()
    end)

    fishingInProgress = false
    pendingBaitChecks = {}
    
    task.wait(0.15)

    if isRunning then
        cancelInProgress = false
        self:ChargeAndCast()
    else
        cancelInProgress = false
    end
end

function AutoFishFeature:ChargeAndCast()
    if fishingInProgress or cancelInProgress then return end

    fishingInProgress = true
    local config = FISHING_CONFIGS[currentMode]

    logger:info("⚡ Charge > Cast")

    if not self:ChargeRod(config.chargeTime) then
        logger:warn("Charge failed")
        fishingInProgress = false
        return
    end

    if not self:CastRod() then
        logger:warn("Cast failed")
        fishingInProgress = false
        return
    end

    logger:info("Cast done")
end

function AutoFishFeature:Start(config)
    if isRunning then return end

    if not remotesInitialized then
        logger:warn("Cannot start - remotes not initialized")
        return
    end

    isRunning = true
    currentMode = config.mode or "Fast"
    fishingInProgress = false
    spamActive = false
    spamCounter = 0
    lastSpamTime = 0
    baitSpawnedCount = 0
    pendingBaitChecks = {}
    cancelInProgress = false
    lastBaitSpawnedTime = 0
    safetyNetTriggered = false

    local cfg = FISHING_CONFIGS[currentMode]
    SPAM_THROTTLE = cfg.spamThrottle

    logger:info("🚀 Started V5 HEARTBEAT - Throttle: " .. SPAM_THROTTLE .. " frames")

    self:SetupReplicateTextHook()
    self:SetupBaitSpawnedHook()
    self:SetupFishObtainedListener()
    
    -- Start HEARTBEAT spam (pure frame-based)
    self:StartHeartbeatSpam()
    self:StartSafetyNet()

    spawn(function()
        if not self:EquipRod(cfg.rodSlot) then
            logger:error("Failed to equip rod")
            return
        end

        self:ChargeAndCast()
    end)
end

function AutoFishFeature:Stop()
    if not isRunning then return end

    isRunning = false
    fishingInProgress = false
    spamActive = false
    spamCounter = 0
    baitSpawnedCount = 0
    pendingBaitChecks = {}
    cancelInProgress = false
    lastBaitSpawnedTime = 0
    safetyNetTriggered = false

    self:StopSafetyNet()

    if connection then
        connection:Disconnect()
        connection = nil
    end

    if spamConnection then
        spamConnection:Disconnect()
        spamConnection = nil
    end

    if fishObtainedConnection then
        fishObtainedConnection:Disconnect()
        fishObtainedConnection = nil
    end

    if baitSpawnedConnection then
        baitSpawnedConnection:Disconnect()
        baitSpawnedConnection = nil
    end

    if replicateTextConnection then
        replicateTextConnection:Disconnect()
        replicateTextConnection = nil
    end

    logger:info("⛔ Stopped V5 HEARTBEAT")
end

function AutoFishFeature:SetupFishObtainedListener()
    if not FishObtainedNotification then
        logger:warn("FishObtainedNotification not available")
        return
    end

    if fishObtainedConnection then
        fishObtainedConnection:Disconnect()
    end

    fishObtainedConnection = FishObtainedNotification.OnClientEvent:Connect(function(...)
        if isRunning and not cancelInProgress then
            logger:info("🎣 FISH!")
            
            fishingInProgress = false
            pendingBaitChecks = {}
            safetyNetTriggered = false
            
            task.wait(0.1)
            
            if isRunning and not cancelInProgress then
                self:ChargeAndCast()
            end
        end
    end)

    logger:info("Fish obtained listener ready")
end

function AutoFishFeature:EquipRod(slot)
    if not EquipTool then return false end

    local success = pcall(function()
        EquipTool:FireServer(slot)
    end)

    return success
end

function AutoFishFeature:ChargeRod(chargeTime)
    if not ChargeFishingRod then return false end

    local success = pcall(function()
        return ChargeFishingRod:InvokeServer(math.huge)
    end)

    task.wait(chargeTime)
    return success
end

function AutoFishFeature:CastRod()
    if not RequestFishing then return false end

    local success = pcall(function()
        local y = -139.63
        local power = 0.9999120558411321
        return RequestFishing:InvokeServer(y, power)
    end)

    return success
end

function AutoFishFeature:StartHeartbeatSpam()
    if spamActive then return end

    spamActive = true
    spamCounter = 0
    logger:info("🔥 HEARTBEAT SPAM ACTIVE - NON-STOP!")

    -- Pake Heartbeat biar jalan tiap frame (60 FPS = 60x per detik!)
    spamConnection = RunService.Heartbeat:Connect(function(deltaTime)
        if not spamActive or not isRunning then return end
        
        -- Throttle spam (0 = tiap frame, 1 = tiap 2 frame, dst)
        if SPAM_THROTTLE > 0 then
            spamCounter = spamCounter + 1
            if spamCounter % (SPAM_THROTTLE + 1) ~= 0 then
                return
            end
        end
        
        -- FIRE COMPLETION TIAP FRAME!
        self:FireCompletion()
        
        -- Log spam rate setiap 300 spam
        if spamCounter % 300 == 0 then
            local currentTime = tick()
            local timeDiff = currentTime - lastSpamTime
            local rate = timeDiff > 0 and (300 / timeDiff) or 0
            logger:info("💥 Spam rate: " .. string.format("%.1f", rate) .. "/s")
            lastSpamTime = currentTime
        end
    end)
end

function AutoFishFeature:FireCompletion()
    if not FishingCompleted then return false end

    pcall(function()
        FishingCompleted:FireServer()
    end)

    return true
end

function AutoFishFeature:GetStatus()
    local timeSinceLastBait = lastBaitSpawnedTime > 0 and (tick() - lastBaitSpawnedTime) or 0
    local pendingCount = 0
    for _ in pairs(pendingBaitChecks) do
        pendingCount = pendingCount + 1
    end
    
    return {
        running = isRunning,
        mode = currentMode,
        inProgress = fishingInProgress,
        spamming = spamActive,
        spamCount = spamCounter,
        spamThrottle = SPAM_THROTTLE,
        remotesReady = remotesInitialized,
        listenerReady = fishObtainedConnection ~= nil,
        baitHookReady = baitSpawnedConnection ~= nil,
        replicateTextHookReady = replicateTextConnection ~= nil,
        baitSpawnedCount = baitSpawnedCount,
        pendingChecks = pendingCount,
        cancelInProgress = cancelInProgress,
        safetyNetActive = safetyNetConnection ~= nil,
        safetyNetTriggered = safetyNetTriggered,
        safetyTimeout = SAFETY_TIMEOUT,
        timeSinceLastBait = math.floor(timeSinceLastBait),
        timeRemaining = math.max(0, SAFETY_TIMEOUT - timeSinceLastBait)
    }
end

function AutoFishFeature:SetMode(mode)
    if FISHING_CONFIGS[mode] then
        currentMode = mode
        logger:info("Mode:", mode)
        return true
    end
    return false
end

function AutoFishFeature:GetAnimationInfo()
    return {
        baitHookReady = baitSpawnedConnection ~= nil,
        replicateTextHookReady = replicateTextConnection ~= nil,
        safetyNetActive = safetyNetConnection ~= nil,
        spamMethod = "Heartbeat"
    }
end

function AutoFishFeature:Cleanup()
    logger:info("Cleaning up V5...")
    self:Stop()

    controls = {}
    remotesInitialized = false
end

return AutoFishFeature
