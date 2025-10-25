-- ===========================
-- AUTO FISH V5 - QUEUE HARVEST SYSTEM
-- Strategi: Cast multiple kali → build queue → harvest sekaligus
-- Flow: Cast no-delay untuk isi queue → Spam completion → dapet banyak sekaligus
-- Pattern: BaitSpawned tanpa ReplicateTextEffect = cancel (detection tetap jalan)
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
local spamConnection = nil
local fishObtainedConnection = nil
local baitSpawnedConnection = nil
local replicateTextConnection = nil
local safetyNetConnection = nil
local controls = {}
local fishingInProgress = false
local remotesInitialized = false
local cancelInProgress = false

-- Queue system tracking
local castQueue = 0  -- Counter untuk berapa kali cast
local harvestMode = false  -- Apakah sedang dalam mode harvest
local totalFishHarvested = 0

-- Spam tracking
local spamActive = false

-- BaitSpawned counter
local baitSpawnedCount = 0

-- Detection tracking
local pendingBaitChecks = {}
local WAIT_WINDOW = 1.0

-- Safety Net tracking
local lastBaitSpawnedTime = 0
local SAFETY_TIMEOUT = 3
local safetyNetTriggered = false

-- Rod configs
local FISHING_CONFIGS = {
    ["Fast"] = {
        chargeTime = 0,
        rodSlot = 1,
        spamDelay = 0.01,  -- Spam completion delay
        queueSize = 5,  -- Berapa kali cast sebelum harvest
        queueDelay = 0,  -- Delay antar cast saat build queue (ZERO untuk max speed)
        harvestWait = 0.5,  -- Tunggu setelah queue penuh sebelum harvest
        postHarvestDelay = 0.2  -- Delay setelah dapat fish sebelum mulai queue lagi
    },
    ["Turbo"] = {
        chargeTime = 0,
        rodSlot = 1,
        spamDelay = 0.005,
        queueSize = 8,  -- Queue lebih banyak
        queueDelay = 0,
        harvestWait = 0.3,
        postHarvestDelay = 0.1
    },
    ["Balanced"] = {
        chargeTime = 0,
        rodSlot = 1,
        spamDelay = 0.02,
        queueSize = 3,
        queueDelay = 0.05,
        harvestWait = 0.4,
        postHarvestDelay = 0.15
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

    logger:info("Initialized V5 (QUEUE HARVEST) - Multi-cast then harvest")
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
        
        if not data or not data.TextData then return end
        if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("Head") then return end
        if data.TextData.AttachTo ~= LocalPlayer.Character.Head then return end
        
        local currentTime = tick()
        
        -- Mark semua pending checks
        for id, checkData in pairs(pendingBaitChecks) do
            local timeDiff = currentTime - checkData.timestamp
            if timeDiff >= 0 and timeDiff <= WAIT_WINDOW + 0.2 and not checkData.received then
                checkData.received = true
                checkData.receivedAt = currentTime
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
        if player ~= LocalPlayer then return end

        baitSpawnedCount = baitSpawnedCount + 1
        lastBaitSpawnedTime = tick()
        safetyNetTriggered = false
        
        local currentBaitNumber = baitSpawnedCount
        local currentTime = tick()
        local checkId = tostring(currentTime) .. "_" .. currentBaitNumber

        -- Setup check untuk detection
        pendingBaitChecks[checkId] = {
            received = false,
            baitNumber = currentBaitNumber,
            timestamp = currentTime,
            receivedAt = nil
        }

        -- Check setelah WAIT_WINDOW
        spawn(function()
            task.wait(WAIT_WINDOW)
            
            if not isRunning or cancelInProgress then 
                pendingBaitChecks[checkId] = nil
                return 
            end
            
            local checkData = pendingBaitChecks[checkId]
            if not checkData then return end
            
            if checkData.received then
                -- Normal cast, continue
                pendingBaitChecks[checkId] = nil
            else
                -- Bad cast, cancel dan restart queue
                logger:info("🔄 BaitSpawned #" .. currentBaitNumber .. " ALONE - Restarting queue!")
                pendingBaitChecks[checkId] = nil
                castQueue = 0  -- Reset queue counter
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
            logger:warn("⚠️ SAFETY NET: No BaitSpawned for " .. math.floor(timeSinceLastBait) .. "s")
            castQueue = 0  -- Reset queue
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
    logger:info("🛡️ Safety Net: Cancelling...")

    pcall(function()
        return CancelFishingInputs:InvokeServer()
    end)
    
    task.wait(0.1)
    
    pcall(function()
        return CancelFishingInputs:InvokeServer()
    end)

    fishingInProgress = false
    pendingBaitChecks = {}
    lastBaitSpawnedTime = tick()
    harvestMode = false
    
    task.wait(0.1)

    if isRunning then
        cancelInProgress = false
        safetyNetTriggered = false
        self:StartQueueCycle()
    else
        cancelInProgress = false
    end
end

function AutoFishFeature:CancelAndRestart()
    if not CancelFishingInputs or cancelInProgress then return end

    cancelInProgress = true

    pcall(function()
        return CancelFishingInputs:InvokeServer()
    end)

    fishingInProgress = false
    pendingBaitChecks = {}
    harvestMode = false
    
    task.wait(0.08)

    if isRunning then
        cancelInProgress = false
        self:StartQueueCycle()
    else
        cancelInProgress = false
    end
end

function AutoFishFeature:StartQueueCycle()
    if fishingInProgress or cancelInProgress then return end
    
    local config = FISHING_CONFIGS[currentMode]
    castQueue = 0
    harvestMode = false
    
    logger:info("🔄 Starting queue cycle - Target: " .. config.queueSize .. " casts")
    
    -- PHASE 1: Build queue dengan cast multiple kali
    spawn(function()
        for i = 1, config.queueSize do
            if not isRunning or cancelInProgress then break end
            
            logger:info("📤 Cast #" .. i .. "/" .. config.queueSize .. " (Building queue)")
            
            if not self:ChargeAndCast() then
                logger:warn("Cast #" .. i .. " failed")
                break
            end
            
            castQueue = castQueue + 1
            
            -- Delay antar cast (kalo ada)
            if config.queueDelay > 0 and i < config.queueSize then
                task.wait(config.queueDelay)
            end
        end
        
        -- PHASE 2: Queue penuh, tunggu sebentar lalu harvest
        if castQueue >= config.queueSize and isRunning and not cancelInProgress then
            logger:info("✅ Queue FULL (" .. castQueue .. " casts) - Waiting " .. config.harvestWait .. "s before harvest")
            task.wait(config.harvestWait)
            
            if isRunning and not cancelInProgress then
                harvestMode = true
                logger:info("🌾 HARVEST MODE: Spam completion to collect all fish!")
                -- Spam sudah jalan dari awal, tinggal tunggu fish masuk
            end
        end
    end)
end

function AutoFishFeature:ChargeAndCast()
    local config = FISHING_CONFIGS[currentMode]

    if not self:ChargeRod(config.chargeTime) then
        return false
    end

    if not self:CastRod() then
        return false
    end

    return true
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
    baitSpawnedCount = 0
    pendingBaitChecks = {}
    cancelInProgress = false
    lastBaitSpawnedTime = 0
    safetyNetTriggered = false
    castQueue = 0
    harvestMode = false
    totalFishHarvested = 0

    local cfg = FISHING_CONFIGS[currentMode]

    logger:info("🚀 Started V5 (QUEUE HARVEST) - Mode: " .. currentMode)
    logger:info("📋 Strategy: Cast " .. cfg.queueSize .. "x (no delay) → Wait " .. cfg.harvestWait .. "s → Harvest all!")
    logger:info("🔥 Spam delay: " .. (cfg.spamDelay * 1000) .. "ms")

    self:SetupReplicateTextHook()
    self:SetupBaitSpawnedHook()
    self:SetupFishObtainedListener()
    
    self:StartCompletionSpam(cfg.spamDelay)
    self:StartSafetyNet()

    spawn(function()
        if not self:EquipRod(cfg.rodSlot) then
            logger:error("Failed to equip rod")
            return
        end

        task.wait(0.2)
        self:StartQueueCycle()
    end)
end

function AutoFishFeature:Stop()
    if not isRunning then return end

    isRunning = false
    fishingInProgress = false
    spamActive = false
    baitSpawnedCount = 0
    pendingBaitChecks = {}
    cancelInProgress = false
    lastBaitSpawnedTime = 0
    safetyNetTriggered = false
    castQueue = 0
    harvestMode = false

    self:StopSafetyNet()

    if connection then connection:Disconnect() connection = nil end
    if spamConnection then spamConnection:Disconnect() spamConnection = nil end
    if fishObtainedConnection then fishObtainedConnection:Disconnect() fishObtainedConnection = nil end
    if baitSpawnedConnection then baitSpawnedConnection:Disconnect() baitSpawnedConnection = nil end
    if replicateTextConnection then replicateTextConnection:Disconnect() replicateTextConnection = nil end

    logger:info("⛔ Stopped - Total fish harvested: " .. totalFishHarvested)
end

function AutoFishFeature:SetupFishObtainedListener()
    if not FishObtainedNotification then
        logger:warn("FishObtainedNotification not available")
        return
    end

    if fishObtainedConnection then
        fishObtainedConnection:Disconnect()
    end

    local harvestBatch = 0

    fishObtainedConnection = FishObtainedNotification.OnClientEvent:Connect(function(...)
        if not isRunning or cancelInProgress then return end
        
        totalFishHarvested = totalFishHarvested + 1
        
        if harvestMode then
            harvestBatch = harvestBatch + 1
            logger:info("🎣 HARVESTED #" .. harvestBatch .. " (Total: " .. totalFishHarvested .. ")")
        else
            logger:info("🎣 Fish obtained (Total: " .. totalFishHarvested .. ")")
        end
        
        -- Check kalo masih ada fish yang datang (harvest mode)
        -- Kalo udah beberapa detik ga ada fish, mulai queue baru
        spawn(function()
            local lastHarvest = harvestBatch
            task.wait(0.8)  -- Tunggu 0.8s
            
            -- Kalo ga ada fish baru dalam 0.8s, berarti harvest selesai
            if lastHarvest == harvestBatch and harvestMode then
                logger:info("✅ Harvest complete! Got " .. harvestBatch .. " fish. Starting new queue...")
                
                harvestMode = false
                harvestBatch = 0
                fishingInProgress = false
                pendingBaitChecks = {}
                
                local config = FISHING_CONFIGS[currentMode]
                if config.postHarvestDelay > 0 then
                    task.wait(config.postHarvestDelay)
                end
                
                if isRunning and not cancelInProgress then
                    self:StartQueueCycle()
                end
            end
        end)
    end)

    logger:info("Fish obtained listener ready (Harvest detection)")
end

function AutoFishFeature:EquipRod(slot)
    if not EquipTool then return false end
    return pcall(function() EquipTool:FireServer(slot) end)
end

function AutoFishFeature:ChargeRod(chargeTime)
    if not ChargeFishingRod then return false end
    
    local success = pcall(function()
        return ChargeFishingRod:InvokeServer(math.huge)
    end)
    
    if chargeTime > 0 then
        task.wait(chargeTime)
    end
    
    return success
end

function AutoFishFeature:CastRod()
    if not RequestFishing then return false end

    return pcall(function()
        local y = -139.63
        local power = 0.9999120558411321
        return RequestFishing:InvokeServer(y, power)
    end)
end

function AutoFishFeature:StartCompletionSpam(delay)
    if spamActive then return end

    spamActive = true
    logger:info("🔥 FishingCompleted spam started (NON-STOP)")

    spawn(function()
        while spamActive and isRunning do
            self:FireCompletion()
            task.wait(delay)
        end
    end)
end

function AutoFishFeature:FireCompletion()
    if not FishingCompleted then return false end
    pcall(function() FishingCompleted:FireServer() end)
    return true
end

function AutoFishFeature:GetStatus()
    local timeSinceLastBait = lastBaitSpawnedTime > 0 and (tick() - lastBaitSpawnedTime) or 0
    local pendingCount = 0
    for _ in pairs(pendingBaitChecks) do pendingCount = pendingCount + 1 end
    
    return {
        running = isRunning,
        mode = currentMode,
        inProgress = fishingInProgress,
        spamming = spamActive,
        remotesReady = remotesInitialized,
        castQueue = castQueue,
        harvestMode = harvestMode,
        totalFishHarvested = totalFishHarvested,
        baitSpawnedCount = baitSpawnedCount,
        pendingChecks = pendingCount,
        cancelInProgress = cancelInProgress,
        safetyNetActive = safetyNetConnection ~= nil,
        timeSinceLastBait = math.floor(timeSinceLastBait)
    }
end

function AutoFishFeature:SetMode(mode)
    if FISHING_CONFIGS[mode] then
        currentMode = mode
        logger:info("Mode changed:", mode)
        return true
    end
    return false
end

function AutoFishFeature:GetAnimationInfo()
    return {
        baitHookReady = baitSpawnedConnection ~= nil,
        replicateTextHookReady = replicateTextConnection ~= nil,
        safetyNetActive = safetyNetConnection ~= nil
    }
end

function AutoFishFeature:Cleanup()
    logger:info("Cleaning up V5...")
    self:Stop()
    controls = {}
    remotesInitialized = false
end

return AutoFishFeature
