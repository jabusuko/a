-- ===========================
-- AUTO FISH V5 - CONSISTENT SPAM FIX
-- Fix: Improved timing, better error recovery, fallback recast
-- Ensures continuous fishing without random pauses
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
local watchdogConnection = nil
local controls = {}
local remotesInitialized = false

-- Tracking
local spamActive = false
local baitSpawnedCount = 0
local pendingBaitChecks = {}
local WAIT_WINDOW = 1.0
local lastBaitSpawnedTime = 0
local lastCastAttemptTime = 0
local lastFishObtainedTime = 0
local SAFETY_TIMEOUT = 5  -- Reduced from 10
local totalFish = 0
local consecutiveCastFails = 0

-- Rod configs
local FISHING_CONFIGS = {
    ["Fast"] = {
        chargeTime = 0,
        rodSlot = 1,
        spamDelay = 0.01,
        recastDelay = 0,
        postFishDelay = 0.05  -- Small delay after fish for server sync
    },
    ["Turbo"] = {
        chargeTime = 0,
        rodSlot = 1,
        spamDelay = 0.005,
        recastDelay = 0,
        postFishDelay = 0.03
    },
    ["Ultra"] = {
        chargeTime = 0,
        rodSlot = 1,
        spamDelay = 0.001,
        recastDelay = 0,
        postFishDelay = 0.01
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

    logger:info("Initialized V5 - Consistent spam with watchdog")
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
        if not isRunning then return end
        if player ~= LocalPlayer then return end

        baitSpawnedCount = baitSpawnedCount + 1
        lastBaitSpawnedTime = tick()
        consecutiveCastFails = 0  -- Reset fail counter
        
        local currentBaitNumber = baitSpawnedCount
        local currentTime = tick()
        local checkId = tostring(currentTime) .. "_" .. currentBaitNumber

        pendingBaitChecks[checkId] = {
            received = false,
            baitNumber = currentBaitNumber,
            timestamp = currentTime
        }

        spawn(function()
            task.wait(WAIT_WINDOW)
            
            if not isRunning then 
                pendingBaitChecks[checkId] = nil
                return 
            end
            
            local checkData = pendingBaitChecks[checkId]
            if not checkData then return end
            
            if not checkData.received then
                logger:info("🔄 Bad cast detected, recasting...")
                pendingBaitChecks[checkId] = nil
                self:ForceRecast()
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
        if not isRunning then return end

        local timeSinceLastBait = tick() - lastBaitSpawnedTime

        if timeSinceLastBait >= SAFETY_TIMEOUT then
            logger:warn("⚠️ Safety net: No bait for " .. math.floor(timeSinceLastBait) .. "s")
            lastBaitSpawnedTime = tick()  -- Reset to prevent spam
            self:ForceRecast()
        end
    end)
end

function AutoFishFeature:StartWatchdog()
    if watchdogConnection then
        watchdogConnection:Disconnect()
    end

    -- Watchdog: Ensures we're always trying to fish
    watchdogConnection = RunService.Heartbeat:Connect(function()
        if not isRunning then return end

        local currentTime = tick()
        local timeSinceLastCast = currentTime - lastCastAttemptTime
        local timeSinceLastFish = currentTime - lastFishObtainedTime

        -- If no cast attempt in 3 seconds AND no fish in 3 seconds = stuck
        if timeSinceLastCast > 3 and timeSinceLastFish > 3 then
            logger:warn("🔧 Watchdog: Detected stuck state, forcing recast")
            self:ForceRecast()
        end
    end)
end

function AutoFishFeature:StopWatchdog()
    if watchdogConnection then
        watchdogConnection:Disconnect()
        watchdogConnection = nil
    end
end

function AutoFishFeature:StopSafetyNet()
    if safetyNetConnection then
        safetyNetConnection:Disconnect()
        safetyNetConnection = nil
    end
end

function AutoFishFeature:ForceRecast()
    -- Cancel current fishing if any
    pcall(function()
        if CancelFishingInputs then
            CancelFishingInputs:InvokeServer()
        end
    end)

    pendingBaitChecks = {}
    lastBaitSpawnedTime = tick()
    
    task.wait(0.05)  -- Minimal delay for server
    
    if isRunning then
        self:ChargeAndCast()
    end
end

function AutoFishFeature:ChargeAndCast()
    local config = FISHING_CONFIGS[currentMode]
    lastCastAttemptTime = tick()

    -- Charge
    local chargeSuccess = pcall(function()
        if ChargeFishingRod then
            ChargeFishingRod:InvokeServer(math.huge)
        end
    end)

    if not chargeSuccess then
        consecutiveCastFails = consecutiveCastFails + 1
        logger:warn("⚠️ Charge failed (" .. consecutiveCastFails .. ")")
        
        if consecutiveCastFails >= 3 then
            logger:warn("Multiple charge fails, retrying in 0.5s")
            task.wait(0.5)
            consecutiveCastFails = 0
        end
        return false
    end

    if config.chargeTime > 0 then
        task.wait(config.chargeTime)
    end

    -- Cast
    local castSuccess = pcall(function()
        if RequestFishing then
            local y = -139.63
            local power = 0.9999120558411321
            RequestFishing:InvokeServer(y, power)
        end
    end)

    if not castSuccess then
        consecutiveCastFails = consecutiveCastFails + 1
        logger:warn("⚠️ Cast failed (" .. consecutiveCastFails .. ")")
        
        if consecutiveCastFails >= 3 then
            logger:warn("Multiple cast fails, retrying in 0.5s")
            task.wait(0.5)
            consecutiveCastFails = 0
        end
        return false
    end

    consecutiveCastFails = 0
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
    spamActive = false
    baitSpawnedCount = 0
    pendingBaitChecks = {}
    lastBaitSpawnedTime = 0
    lastCastAttemptTime = 0
    lastFishObtainedTime = 0
    totalFish = 0
    consecutiveCastFails = 0

    local cfg = FISHING_CONFIGS[currentMode]

    logger:info("🚀 Started V5 - Mode: " .. currentMode)
    logger:info("⚡ Spam: " .. (cfg.spamDelay * 1000) .. "ms | Safety: " .. SAFETY_TIMEOUT .. "s")
    logger:info("🔧 Watchdog enabled for consistency")

    self:SetupReplicateTextHook()
    self:SetupBaitSpawnedHook()
    self:SetupFishObtainedListener()
    
    self:StartCompletionSpam(cfg.spamDelay)
    self:StartSafetyNet()
    self:StartWatchdog()

    spawn(function()
        if not self:EquipRod(cfg.rodSlot) then
            logger:error("Failed to equip rod")
            return
        end

        task.wait(0.2)
        self:ChargeAndCast()
    end)
end

function AutoFishFeature:Stop()
    if not isRunning then return end

    isRunning = false
    spamActive = false

    self:StopSafetyNet()
    self:StopWatchdog()

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
        if not isRunning then return end
        
        totalFish = totalFish + 1
        lastFishObtainedTime = tick()
        
        local timeSinceLastFish = lastFishObtainedTime - (lastFishObtainedTime - 1)
        logger:info("🎣 Fish #" .. totalFish)
        
        pendingBaitChecks = {}
        consecutiveCastFails = 0
        
        local config = FISHING_CONFIGS[currentMode]
        
        -- Small post-fish delay for server sync
        if config.postFishDelay and config.postFishDelay > 0 then
            task.wait(config.postFishDelay)
        end
        
        -- Recast delay
        if config.recastDelay and config.recastDelay > 0 then
            task.wait(config.recastDelay)
        end
        
        if isRunning then
            local success = self:ChargeAndCast()
            
            -- If cast failed, force recast after short delay
            if not success then
                task.wait(0.2)
                if isRunning then
                    self:ForceRecast()
                end
            end
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
    logger:info("🔥 Completion spam started")

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
    local timeSinceLastCast = lastCastAttemptTime > 0 and (tick() - lastCastAttemptTime) or 0
    local timeSinceLastFish = lastFishObtainedTime > 0 and (tick() - lastFishObtainedTime) or 0
    local timeSinceLastBait = lastBaitSpawnedTime > 0 and (tick() - lastBaitSpawnedTime) or 0
    
    return {
        running = isRunning,
        mode = currentMode,
        totalFish = totalFish,
        baitCount = baitSpawnedCount,
        spamming = spamActive,
        consecutiveFails = consecutiveCastFails,
        timeSinceLastCast = string.format("%.1f", timeSinceLastCast),
        timeSinceLastFish = string.format("%.1f", timeSinceLastFish),
        timeSinceLastBait = string.format("%.1f", timeSinceLastBait)
    }
end

function AutoFishFeature:SetMode(mode)
    if FISHING_CONFIGS[mode] then
        currentMode = mode
        logger:info("Mode changed: " .. mode)
        return true
    end
    return false
end

function AutoFishFeature:GetAnimationInfo()
    return {
        baitHookReady = baitSpawnedConnection ~= nil,
        replicateTextHookReady = replicateTextConnection ~= nil,
        safetyNetActive = safetyNetConnection ~= nil,
        watchdogActive = watchdogConnection ~= nil
    }
end

function AutoFishFeature:Cleanup()
    self:Stop()
    controls = {}
    remotesInitialized = false
end

return AutoFishFeature
