-- ===========================
-- AUTO FISH V5 - ULTRA SPEED (NO DELAY)
-- Strategy: MAXIMUM SPEED - Cast non-stop, harvest constantly
-- No BaitSpawned waiting, no delays, pure spam
-- Let server handle everything, we just spam requests
-- WARNING: Paling aggressive, bisa unstable di beberapa server
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
local castConnection = nil
local fishObtainedConnection = nil
local controls = {}
local remotesInitialized = false

-- Tracking
local totalFishHarvested = 0
local lastFishTime = 0
local consecutiveFish = 0
local castLoopActive = false
local completionSpamActive = false

-- Rod configs
local FISHING_CONFIGS = {
    ["Ultra"] = {
        rodSlot = 1,
        castDelay = 0,  -- ZERO delay antar cast
        spamDelay = 0.003,  -- 3ms spam (ULTRA fast)
        burstCasts = 15,  -- Cast 15x berturut-turut
        burstWait = 0.2,  -- Tunggu 0.2s setelah burst
        chargeTime = 0
    },
    ["Insane"] = {
        rodSlot = 1,
        castDelay = 0,
        spamDelay = 0.001,  -- 1ms spam (INSANE)
        burstCasts = 20,
        burstWait = 0.15,
        chargeTime = 0
    },
    ["Fast"] = {
        rodSlot = 1,
        castDelay = 0,  -- ZERO delay antar cast
        spamDelay = 0.003,  -- 3ms spam (ULTRA fast)
        burstCasts = 15,  -- Cast 15x berturut-turut
        burstWait = 0.2,  -- Tunggu 0.2s setelah burst
        chargeTime = 0
    },
    ["Stable"] = {
        rodSlot = 1,
        castDelay = 0.05,
        spamDelay = 0.02,
        burstCasts = 5,
        burstWait = 0.5,
        chargeTime = 0
    }
}

function AutoFishFeature:Init(guiControls)
    controls = guiControls or {}
    remotesInitialized = initializeRemotes()

    if not remotesInitialized then
        logger:warn("Failed to initialize remotes")
        return false
    end

    logger:info("Initialized V5 (ULTRA SPEED) - Maximum performance mode")
    return true
end

function AutoFishFeature:Start(config)
    if isRunning then return end

    if not remotesInitialized then
        logger:warn("Cannot start - remotes not initialized")
        return
    end

    isRunning = true
    currentMode = config.mode or "Ultra"
    totalFishHarvested = 0
    lastFishTime = 0
    consecutiveFish = 0
    castLoopActive = false
    completionSpamActive = false

    local cfg = FISHING_CONFIGS[currentMode]

    logger:info("🚀 Started V5 (ULTRA) - Mode: " .. currentMode)
    logger:info("⚡ Cast delay: " .. (cfg.castDelay * 1000) .. "ms | Spam: " .. (cfg.spamDelay * 1000) .. "ms")
    logger:info("💥 Burst: " .. cfg.burstCasts .. " casts, wait " .. cfg.burstWait .. "s")
    logger:info("🔥 NO SAFETY CHECKS - Pure speed!")

    self:SetupFishObtainedListener()
    
    -- Start completion spam immediately
    self:StartCompletionSpam(cfg.spamDelay)
    
    -- Equip rod
    spawn(function()
        if not self:EquipRod(cfg.rodSlot) then
            logger:error("Failed to equip rod")
            return
        end

        task.wait(0.2)
        
        -- Start casting loop
        self:StartCastingLoop()
    end)
end

function AutoFishFeature:StartCastingLoop()
    if castLoopActive then return end
    
    castLoopActive = true
    local config = FISHING_CONFIGS[currentMode]
    
    logger:info("🎣 Starting ULTRA casting loop...")
    
    spawn(function()
        while castLoopActive and isRunning do
            -- BURST: Cast multiple kali super cepat
            for i = 1, config.burstCasts do
                if not isRunning or not castLoopActive then break end
                
                -- Charge + Cast (no waiting)
                pcall(function()
                    if ChargeFishingRod then
                        ChargeFishingRod:InvokeServer(math.huge)
                    end
                end)
                
                -- Cast immediately
                pcall(function()
                    if RequestFishing then
                        local y = -139.63
                        local power = 0.9999120558411321
                        RequestFishing:InvokeServer(y, power)
                    end
                end)
                
                -- Minimal delay if configured
                if config.castDelay > 0 then
                    task.wait(config.castDelay)
                end
            end
            
            -- Wait setelah burst
            if config.burstWait > 0 and isRunning and castLoopActive then
                task.wait(config.burstWait)
            end
        end
        
        logger:info("Casting loop stopped")
    end)
end

function AutoFishFeature:Stop()
    if not isRunning then return end

    isRunning = false
    castLoopActive = false
    completionSpamActive = false

    if spamConnection then
        spamConnection:Disconnect()
        spamConnection = nil
    end

    if castConnection then
        castConnection:Disconnect()
        castConnection = nil
    end

    if fishObtainedConnection then
        fishObtainedConnection:Disconnect()
        fishObtainedConnection = nil
    end

    logger:info("⛔ Stopped - Total fish: " .. totalFishHarvested)
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
        if not isRunning then return end
        
        totalFishHarvested = totalFishHarvested + 1
        
        local currentTime = tick()
        local timeSinceLastFish = currentTime - lastFishTime
        
        -- Track consecutive fish (within 2 seconds)
        if lastFishTime > 0 and timeSinceLastFish < 2 then
            consecutiveFish = consecutiveFish + 1
            logger:info("🎣 FISH #" .. consecutiveFish .. " (Δ" .. string.format("%.3f", timeSinceLastFish) .. "s) [Total: " .. totalFishHarvested .. "]")
        else
            consecutiveFish = 1
            logger:info("🎣 FISH OBTAINED! [Total: " .. totalFishHarvested .. "]")
        end
        
        lastFishTime = currentTime
        
        -- NO RECAST - casting loop handles everything
    end)

    logger:info("Fish listener ready (passive mode)")
end

function AutoFishFeature:EquipRod(slot)
    if not EquipTool then return false end
    return pcall(function() EquipTool:FireServer(slot) end)
end

function AutoFishFeature:StartCompletionSpam(delay)
    if completionSpamActive then return end

    completionSpamActive = true
    logger:info("🔥 ULTRA FishingCompleted spam started (" .. (delay * 1000) .. "ms delay)")

    spawn(function()
        while completionSpamActive and isRunning do
            if FishingCompleted then
                pcall(function()
                    FishingCompleted:FireServer()
                end)
            end
            task.wait(delay)
        end
        logger:info("Completion spam stopped")
    end)
end

function AutoFishFeature:GetStatus()
    return {
        running = isRunning,
        mode = currentMode,
        remotesReady = remotesInitialized,
        castLoopActive = castLoopActive,
        completionSpamActive = completionSpamActive,
        totalFishHarvested = totalFishHarvested,
        consecutiveFish = consecutiveFish,
        lastFishTime = lastFishTime > 0 and string.format("%.2f", tick() - lastFishTime) or "N/A"
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

function AutoFishFeature:Cleanup()
    logger:info("Cleaning up V5 ULTRA...")
    self:Stop()
    controls = {}
    remotesInitialized = false
end

-- Compatibility functions
function AutoFishFeature:GetAnimationInfo()
    return {
        castLoopActive = castLoopActive,
        completionSpamActive = completionSpamActive
    }
end

return AutoFishFeature
