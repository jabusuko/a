-- ===========================
-- AUTO FISH V5 - PURE SPAM (ORIGINAL FAST METHOD)
-- Strategy: Cast non-stop + Spam completion non-stop
-- NO queue, NO burst, NO waiting - just spam everything
-- Recast IMMEDIATELY after every fish
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
local spamConnection = nil
local fishObtainedConnection = nil
local baitSpawnedConnection = nil
local replicateTextConnection = nil
local safetyNetConnection = nil
local controls = {}
local fishingInProgress = false
local remotesInitialized = false
local cancelInProgress = false

-- Tracking
local spamActive = false
local baitSpawnedCount = 0
local pendingBaitChecks = {}
local WAIT_WINDOW = 1.0
local lastBaitSpawnedTime = 0
local SAFETY_TIMEOUT = 10
local safetyNetTriggered = false
local totalFish = 0

-- Rod configs
local FISHING_CONFIGS = {
    ["Fast"] = {
        chargeTime = 0,
        rodSlot = 1,
        spamDelay = 0.001,  -- Ultra cepat
        recastDelay = 0
    },
    ["Turbo"] = {
        chargeTime = 0,
        rodSlot = 1,
        spamDelay = 0.005,  -- Lebih cepat
        recastDelay = 0
    },
    ["Ultra"] = {
        chargeTime = 0,
        rodSlot = 1,
        spamDelay = 0.001,  -- Ultra cepat
        recastDelay = 0
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

    logger:info("Initialized V5 - Pure spam method")
    return true
end

function AutoFishFeature:SetupReplicateTextHook()
    if not ReplicateTextEffect then return end

    if replicateTextConnection then
        replicateTextConnection:Disconnect()
    end

    replicateTextConnection = ReplicateTextEffect.OnClientEvent:Connect(function(data)
        if not isRunning then return end
        if not data or not data.TextData then return end
        if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("Head") then return end
        if data.TextData.AttachTo ~= LocalPlayer.Character.Head then return end
        
        local currentTime = tick()
        
        for id, checkData in pairs(pendingBaitChecks) do
            local timeDiff = currentTime - checkData.timestamp
            if timeDiff >= 0 and timeDiff <= WAIT_WINDOW + 0.2 and not checkData.received then
                checkData.received = true
                checkData.receivedAt = currentTime
            end
        end
    end)
end

function AutoFishFeature:SetupBaitSpawnedHook()
    if not BaitSpawnedEvent then return end

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
            if not checkData then return end
            
            if not checkData.received then
                pendingBaitChecks[checkId] = nil
                self:CancelAndRecast()
            else
                pendingBaitChecks[checkId] = nil
            end
        end)
    end)
end

function AutoFishFeature:StartSafetyNet()
    if safetyNetConnection then
        safetyNetConnection:Disconnect()
    end

    lastBaitSpawnedTime = tick()

    safetyNetConnection = RunService.Heartbeat:Connect(function()
        if not isRunning or cancelInProgress or safetyNetTriggered then return end

        local timeSinceLastBait = tick() - lastBaitSpawnedTime

        if timeSinceLastBait >= SAFETY_TIMEOUT then
            safetyNetTriggered = true
            logger:warn("⚠️ Safety Net triggered")
            self:CancelAndRecast()
        end
    end)
end

function AutoFishFeature:StopSafetyNet()
    if safetyNetConnection then
        safetyNetConnection:Disconnect()
        safetyNetConnection = nil
    end
end

function AutoFishFeature:CancelAndRecast()
    if cancelInProgress then return end
    cancelInProgress = true

    pcall(function()
        if CancelFishingInputs then
            CancelFishingInputs:InvokeServer()
        end
    end)

    fishingInProgress = false
    pendingBaitChecks = {}
    lastBaitSpawnedTime = tick()
    safetyNetTriggered = false
    
    cancelInProgress = false
    
    if isRunning then
        self:ChargeAndCast()
    end
end

function AutoFishFeature:ChargeAndCast()
    if fishingInProgress or cancelInProgress then return end

    fishingInProgress = true
    local config = FISHING_CONFIGS[currentMode]

    -- Charge
    pcall(function()
        if ChargeFishingRod then
            ChargeFishingRod:InvokeServer(math.huge)
        end
    end)

    if config.chargeTime > 0 then
        task.wait(config.chargeTime)
    end

    -- Cast
    pcall(function()
        if RequestFishing then
            local y = -139.63
            local power = 0.9999120558411321
            RequestFishing:InvokeServer(y, power)
        end
    end)
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
    totalFish = 0

    local cfg = FISHING_CONFIGS[currentMode]

    logger:info("🚀 Started - Mode: " .. currentMode)
    logger:info("⚡ Spam: " .. (cfg.spamDelay * 1000) .. "ms | Recast: INSTANT")

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

        self:ChargeAndCast()
    end)
end

function AutoFishFeature:Stop()
    if not isRunning then return end

    isRunning = false
    fishingInProgress = false
    spamActive = false
    cancelInProgress = false

    self:StopSafetyNet()

    if spamConnection then spamConnection:Disconnect() spamConnection = nil end
    if fishObtainedConnection then fishObtainedConnection:Disconnect() fishObtainedConnection = nil end
    if baitSpawnedConnection then baitSpawnedConnection:Disconnect() baitSpawnedConnection = nil end
    if replicateTextConnection then replicateTextConnection:Disconnect() replicateTextConnection = nil end

    logger:info("⛔ Stopped - Total: " .. totalFish)
end

function AutoFishFeature:SetupFishObtainedListener()
    if not FishObtainedNotification then return end

    if fishObtainedConnection then
        fishObtainedConnection:Disconnect()
    end

    fishObtainedConnection = FishObtainedNotification.OnClientEvent:Connect(function(...)
        if not isRunning or cancelInProgress then return end
        
        totalFish = totalFish + 1
        logger:info("🎣 Fish #" .. totalFish)
        
        fishingInProgress = false
        pendingBaitChecks = {}
        safetyNetTriggered = false
        
        local config = FISHING_CONFIGS[currentMode]
        
        -- INSTANT recast (no delay)
        if config.recastDelay > 0 then
            task.wait(config.recastDelay)
        end
        
        if isRunning and not cancelInProgress then
            self:ChargeAndCast()
        end
    end)
end

function AutoFishFeature:EquipRod(slot)
    if not EquipTool then return false end
    return pcall(function() EquipTool:FireServer(slot) end)
end

function AutoFishFeature:StartCompletionSpam(delay)
    if spamActive then return end

    spamActive = true
    logger:info("🔥 Spam started")

    spawn(function()
        while spamActive and isRunning do
            pcall(function()
                if FishingCompleted then
                    FishingCompleted:FireServer()
                end
            end)
            task.wait(delay)
        end
    end)
end

function AutoFishFeature:GetStatus()
    return {
        running = isRunning,
        mode = currentMode,
        totalFish = totalFish,
        baitCount = baitSpawnedCount,
        spamming = spamActive
    }
end

function AutoFishFeature:SetMode(mode)
    if FISHING_CONFIGS[mode] then
        currentMode = mode
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
    self:Stop()
    controls = {}
    remotesInitialized = false
end

return AutoFishFeature
