local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Camera = workspace.CurrentCamera

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local HRP = Character:WaitForChild("HumanoidRootPart")

LocalPlayer.CharacterAdded:Connect(function(char)
    Character = char
    HRP = char:WaitForChild("HumanoidRootPart")
end)

-- ==============================================
-- YOUR ORIGINAL ORBIT CODE - COMPLETELY PRESERVED
-- ==============================================

local CFG = {
    VOID_BASE_Y         = 1e10,
    VOID_JITTER_RANGE   = 5000,
    VOID_LOCK_VELOCITY  = true,

    MIN_RADIUS          = 200000,
    MAX_RADIUS          = 12000000000,
    HEIGHT_OFFSET       = 50000,
    ORBIT_SPEED         = 0,
    VERTICAL_WAVE_SPEED = 0.8,
    VERTICAL_WAVE_AMP   = 0.12,
    ELLIPSE_RATIO       = 0.65,

    CAM_LERP_BASE       = 0.10,
    CAM_LERP_SPEED_SCALE= 0.003,
    CAM_MAX_LERP        = 0.35,

    PREDICTION          = 0.18,

    SCORE_DIST_WEIGHT   = 1.0,
    SCORE_HEALTH_WEIGHT = 0.4,
    SCORE_CLOSEST_BONUS = 0.7,
}

local OrbitEnabled          = false
local OrbitConnection       = nil
local orbitAngle            = math.random(0, 360)
local elapsed               = 0
local lastCF                = Camera.CFrame
local currentTarget         = nil
local targetReacquireTimer  = 0
local TARGET_REACQUIRE_INTERVAL = 1.5

local function getVoidCFrame()
    local jx = (math.random() - 0.5) * 2 * CFG.VOID_JITTER_RANGE
    local jz = (math.random() - 0.5) * 2 * CFG.VOID_JITTER_RANGE
    return CFrame.new(100 + jx, CFG.VOID_BASE_Y, jz)
end

local function lockToVoid()
    if not HRP then return end
    HRP.CFrame = getVoidCFrame()
    if CFG.VOID_LOCK_VELOCITY then
        HRP.AssemblyLinearVelocity = Vector3.zero
        HRP.AssemblyAngularVelocity = Vector3.zero
    end
end

local function getOtherHRPs()
    local t = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local h = p.Character:FindFirstChild("HumanoidRootPart")
            if h then t[#t+1] = h end
        end
    end
    return t
end

local function getBestEnemy()
    local best, bestScore = nil, -math.huge
    local others = getOtherHRPs()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LocalPlayer or not plr.Character then continue end
        local hum = plr.Character:FindFirstChildOfClass("Humanoid")
        local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
        if not hum or not hrp or hum.Health <= 0 then continue end

        local dist = (HRP.Position - hrp.Position).Magnitude

        local minOtherDist = math.huge
        for _, o in ipairs(others) do
            if o ~= hrp then
                local d = (hrp.Position - o.Position).Magnitude
                if d < minOtherDist then minOtherDist = d end
            end
        end

        local healthScore = (1 - (hum.Health / math.max(hum.MaxHealth, 1))) * 100

        local score = (-dist * CFG.SCORE_DIST_WEIGHT)
                    + (minOtherDist == math.huge and 0 or minOtherDist * CFG.SCORE_CLOSEST_BONUS)
                    + (healthScore * CFG.SCORE_HEALTH_WEIGHT)

        if score > bestScore then
            bestScore = score
            best = plr.Character
        end
    end
    return best
end

local function updateTarget(dt)
    targetReacquireTimer = targetReacquireTimer + dt
    if currentTarget then
        local hum = currentTarget:FindFirstChildOfClass("Humanoid")
        local hrp = currentTarget:FindFirstChild("HumanoidRootPart")
        if not hum or hum.Health <= 0 or not hrp then
            currentTarget = nil
        end
    end
    if not currentTarget or targetReacquireTimer >= TARGET_REACQUIRE_INTERVAL then
        currentTarget = getBestEnemy()
        targetReacquireTimer = 0
    end
end

local function setCamera(enemy, dt)
    if not enemy then return end
    local head = enemy:FindFirstChild("Head")
    local ehrp = enemy:FindFirstChild("HumanoidRootPart")
    if not head or not ehrp then return end

    orbitAngle = orbitAngle + CFG.ORBIT_SPEED * dt
    elapsed = elapsed + dt

    local rad = math.rad(orbitAngle)
    local vel = ehrp.AssemblyLinearVelocity
    local speed = vel.Magnitude
    local predicted = head.Position + vel * CFG.PREDICTION

    local dist = (HRP.Position - ehrp.Position).Magnitude
    local baseR = math.clamp(dist * 1.2, CFG.MIN_RADIUS, CFG.MAX_RADIUS)
    local radius = math.clamp(baseR + speed * 1200, CFG.MIN_RADIUS, CFG.MAX_RADIUS)

    local vertWave = math.sin(elapsed * CFG.VERTICAL_WAVE_SPEED * math.pi * 2)
    local vertOffset = CFG.HEIGHT_OFFSET + radius * CFG.VERTICAL_WAVE_AMP * vertWave

    local orbitOffset = Vector3.new(
        math.cos(rad) * radius,
        vertOffset,
        math.sin(rad) * radius * CFG.ELLIPSE_RATIO
    )

    local camPos = predicted + orbitOffset
    local cf = CFrame.lookAt(camPos, predicted)

    local lerpT = math.clamp(
        CFG.CAM_LERP_BASE + speed * CFG.CAM_LERP_SPEED_SCALE,
        CFG.CAM_LERP_BASE,
        CFG.CAM_MAX_LERP
    )
    local alpha = 1 - (1 - lerpT) ^ (dt * 60)
    lastCF = lastCF:Lerp(cf, alpha)
    Camera.CFrame = lastCF

    if _G.SilentAim then _G.SilentAim.Target = predicted end
    if _G.RageBot then _G.RageBot.Target = predicted end
end

local function toggleOrbit(state)
    OrbitEnabled = state
    if state then
        lastCF = Camera.CFrame
        OrbitConnection = RunService.RenderStepped:Connect(function(dt)
            lockToVoid()
            updateTarget(dt)
            if currentTarget then
                setCamera(currentTarget, dt)
            end
        end)
    else
        if OrbitConnection then
            OrbitConnection:Disconnect()
            OrbitConnection = nil
        end
        currentTarget = nil
        local hum = Character and Character:FindFirstChildOfClass("Humanoid")
        if hum then Camera.CameraSubject = hum end
    end
end

-- ==============================================
-- XXRO BETA UI - SIMPLE & CLEAN
-- ==============================================

local UIConfig = {
    EnableVoid = false,
    Hotkey = "V",
    VoidMethod = "Quantum",
    QuantumTunneling = false,
    BypassMethod = "Standard",
    ExtremeNetworking = false,
    DriftSpeed = 200,
    DriftChaos = 100,
    VoidAltitude = 100,
    ScramblePosition = false,
    LissajousA = 2,
    LissajousB = 3,
    EnableDesync = false,
    DesyncRate = 18,
    DesyncRadius = 22,
    DodgeEnemies = false,
    EvasionRadius = 88,
    EvasionSpeed = 68,
    EnableGhosting = false,
    GhostingIntensity = 50,
    YDriftRange = 108,
    ScrambleInterval = 12,
    FlickerInterval = 5,
    ForceVerticalEvasion = false,
    GravityWellStrength = 100,
}

local Options = {
    VoidMethod = {"Quantum", "Classic", "Hybrid", "Extreme"},
    BypassMethod = {"Standard", "Advanced", "Extreme"},
    HotkeyOptions = {"V", "G", "H", "X", "Z", "C"},
}

local currentTab = "ORBIT"
local isMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local uiOpen = true

-- Create GUI
local Gui = Instance.new("ScreenGui")
Gui.Name = "XxroBeta"
Gui.ResetOnSpawn = false
Gui.Parent = game:GetService("CoreGui")
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- OPEN/CLOSE BUTTON
local ToggleButton = Instance.new("TextButton")
ToggleButton.Name = "ToggleButton"
ToggleButton.Parent = Gui
ToggleButton.Size = UDim2.new(0, 40, 0, 40)
ToggleButton.Position = UDim2.new(1, -50, 0.5, -20)
ToggleButton.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
ToggleButton.Text = "◀"
ToggleButton.Font = Enum.Font.GothamBold
ToggleButton.TextSize = 20
ToggleButton.TextColor3 = Color3.fromRGB(200, 200, 255)
ToggleButton.BorderSizePixel = 0
ToggleButton.Visible = true
ToggleButton.ZIndex = 10

local ButtonCorner = Instance.new("UICorner")
ButtonCorner.CornerRadius = UDim.new(0, 12)
ButtonCorner.Parent = ToggleButton

-- MAIN FRAME
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Parent = Gui
MainFrame.Size = UDim2.new(0, 280, 0, 400)
MainFrame.Position = UDim2.new(0.5, -140, 0.5, -200)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Visible = true
MainFrame.ZIndex = 5

-- Make UI movable
local function makeDraggable(frame)
    local dragging = false
    local dragInput, dragStart, startPos
    
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end)
    
    frame.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement then
            dragInput = input
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
end

makeDraggable(MainFrame)

-- Corners
local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 16)
MainCorner.Parent = MainFrame

-- Top Bar
local TopBar = Instance.new("Frame")
TopBar.Parent = MainFrame
TopBar.Size = UDim2.new(1, 0, 0, 60)
TopBar.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
TopBar.BorderSizePixel = 0

local TopBarCorner = Instance.new("UICorner")
TopBarCorner.CornerRadius = UDim.new(0, 16)
TopBarCorner.Parent = TopBar

local Title = Instance.new("TextLabel")
Title.Parent = TopBar
Title.Size = UDim2.new(1, 0, 0, 30)
Title.Position = UDim2.new(0, 15, 0, 8)
Title.BackgroundTransparency = 1
Title.Text = "beta xxro"
Title.Font = Enum.Font.GothamBold
Title.TextSize = 20
Title.TextColor3 = Color3.fromRGB(150, 150, 255)
Title.TextXAlignment = Enum.TextXAlignment.Left

local SubTitle = Instance.new("TextLabel")
SubTitle.Parent = TopBar
SubTitle.Size = UDim2.new(1, 0, 0, 20)
SubTitle.Position = UDim2.new(0, 15, 0, 35)
SubTitle.BackgroundTransparency = 1
SubTitle.Text = "the goat is back"
SubTitle.Font = Enum.Font.Gotham
SubTitle.TextSize = 12
SubTitle.TextColor3 = Color3.fromRGB(180, 180, 200)
SubTitle.TextXAlignment = Enum.TextXAlignment.Left

-- Tab Bar
local TabBar = Instance.new("Frame")
TabBar.Parent = MainFrame
TabBar.Size = UDim2.new(1, -20, 0, 40)
TabBar.Position = UDim2.new(0, 10, 0, 70)
TabBar.BackgroundTransparency = 1

local OrbitTab = Instance.new("TextButton")
OrbitTab.Parent = TabBar
OrbitTab.Size = UDim2.new(0, 85, 1, 0)
OrbitTab.Position = UDim2.new(0, 0, 0, 0)
OrbitTab.BackgroundColor3 = Color3.fromRGB(150, 150, 255)
OrbitTab.Text = "ORBIT"
OrbitTab.Font = Enum.Font.GothamBold
OrbitTab.TextSize = 14
OrbitTab.TextColor3 = Color3.new(1, 1, 1)
OrbitTab.BorderSizePixel = 0
OrbitTab.AutoButtonColor = false

local OrbitCorner = Instance.new("UICorner")
OrbitCorner.CornerRadius = UDim.new(0, 8)
OrbitCorner.Parent = OrbitTab

local EvadeTab = Instance.new("TextButton")
EvadeTab.Parent = TabBar
EvadeTab.Size = UDim2.new(0, 85, 1, 0)
EvadeTab.Position = UDim2.new(0, 95, 0, 0)
EvadeTab.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
EvadeTab.Text = "EVADE"
EvadeTab.Font = Enum.Font.GothamBold
EvadeTab.TextSize = 14
EvadeTab.TextColor3 = Color3.fromRGB(180, 180, 200)
EvadeTab.BorderSizePixel = 0
EvadeTab.AutoButtonColor = false

local EvadeCorner = Instance.new("UICorner")
EvadeCorner.CornerRadius = UDim.new(0, 8)
EvadeCorner.Parent = EvadeTab

local AdvTab = Instance.new("TextButton")
AdvTab.Parent = TabBar
AdvTab.Size = UDim2.new(0, 80, 1, 0)
AdvTab.Position = UDim2.new(0, 190, 0, 0)
AdvTab.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
AdvTab.Text = "ADV"
AdvTab.Font = Enum.Font.GothamBold
AdvTab.TextSize = 14
AdvTab.TextColor3 = Color3.fromRGB(180, 180, 200)
AdvTab.BorderSizePixel = 0
AdvTab.AutoButtonColor = false

local AdvCorner = Instance.new("UICorner")
AdvCorner.CornerRadius = UDim.new(0, 8)
AdvCorner.Parent = AdvTab

-- Content Area
local ContentFrame = Instance.new("ScrollingFrame")
ContentFrame.Parent = MainFrame
ContentFrame.Size = UDim2.new(1, -20, 1, -135)
ContentFrame.Position = UDim2.new(0, 10, 0, 120)
ContentFrame.BackgroundTransparency = 1
ContentFrame.ScrollBarThickness = 4
ContentFrame.ScrollBarImageColor3 = Color3.fromRGB(150, 150, 255)
ContentFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
ContentFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
ContentFrame.ScrollingEnabled = true

local ContentList = Instance.new("UIListLayout")
ContentList.Parent = ContentFrame
ContentList.SortOrder = Enum.SortOrder.LayoutOrder
ContentList.Padding = UDim.new(0, 8)

local ContentPadding = Instance.new("UIPadding")
ContentPadding.Parent = ContentFrame
ContentPadding.PaddingTop = UDim.new(0, 5)
ContentPadding.PaddingBottom = UDim.new(0, 10)

-- Clear content function
local function clearContent()
    for _, child in ipairs(ContentFrame:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end
end

-- LOAD ORBIT TAB (YOUR ORIGINAL)
local function loadOrbitTab()
    clearContent()
    
    -- Status indicator
    local statusFrame = Instance.new("Frame")
    statusFrame.Parent = ContentFrame
    statusFrame.Size = UDim2.new(1, 0, 0, 40)
    statusFrame.BackgroundTransparency = 1
    
    local statusDot = Instance.new("Frame")
    statusDot.Parent = statusFrame
    statusDot.Size = UDim2.new(0, 14, 0, 14)
    statusDot.Position = UDim2.new(0, 10, 0.5, -7)
    statusDot.BackgroundColor3 = OrbitEnabled and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)
    
    local dotCorner = Instance.new("UICorner")
    dotCorner.CornerRadius = UDim.new(1, 0)
    dotCorner.Parent = statusDot
    
    local statusText = Instance.new("TextLabel")
    statusText.Parent = statusFrame
    statusText.Size = UDim2.new(1, -30, 1, 0)
    statusText.Position = UDim2.new(0, 30, 0, 0)
    statusText.BackgroundTransparency = 1
    statusText.Text = "Status: " .. (OrbitEnabled and "Enabled" or "Disabled")
    statusText.Font = Enum.Font.Gotham
    statusText.TextSize = 14
    statusText.TextColor3 = Color3.fromRGB(220, 220, 240)
    statusText.TextXAlignment = Enum.TextXAlignment.Left
    
    -- Orbit Level
    local levelFrame = Instance.new("Frame")
    levelFrame.Parent = ContentFrame
    levelFrame.Size = UDim2.new(1, 0, 0, 30)
    levelFrame.BackgroundTransparency = 1
    
    local levelText = Instance.new("TextLabel")
    levelText.Parent = levelFrame
    levelText.Size = UDim2.new(1, -20, 1, 0)
    levelText.Position = UDim2.new(0, 10, 0, 0)
    levelText.BackgroundTransparency = 1
    levelText.Text = "Orbit Level: " .. (OrbitEnabled and "femboy" or "tomboy")
    levelText.Font = Enum.Font.GothamSemibold
    levelText.TextSize = 14
    levelText.TextColor3 = Color3.fromRGB(150, 150, 255)
    levelText.TextXAlignment = Enum.TextXAlignment.Left
    
    -- Orbit Aura Button
    local orbitButton = Instance.new("TextButton")
    orbitButton.Parent = ContentFrame
    orbitButton.Size = UDim2.new(1, 0, 0, 50)
    orbitButton.BackgroundColor3 = OrbitEnabled and Color3.fromRGB(150, 150, 255) or Color3.fromRGB(40, 40, 50)
    orbitButton.Text = "ORBIT AURA : " .. (OrbitEnabled and "ON" or "OFF")
    orbitButton.Font = Enum.Font.GothamBold
    orbitButton.TextSize = 15
    orbitButton.TextColor3 = Color3.new(1, 1, 1)
    orbitButton.BorderSizePixel = 0
    orbitButton.AutoButtonColor = false
    
    local buttonCorner = Instance.new("UICorner")
    buttonCorner.CornerRadius = UDim.new(0, 8)
    buttonCorner.Parent = orbitButton
    
    orbitButton.MouseButton1Click:Connect(function()
        OrbitEnabled = not OrbitEnabled
        toggleOrbit(OrbitEnabled)
        
        statusDot.BackgroundColor3 = OrbitEnabled and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)
        statusText.Text = "Status: " .. (OrbitEnabled and "Enabled" or "Disabled")
        levelText.Text = "Orbit Level: " .. (OrbitEnabled and "femboy" or "tomboy")
        orbitButton.Text = "ORBIT AURA : " .. (OrbitEnabled and "ON" or "OFF")
        
        TweenService:Create(orbitButton, TweenInfo.new(0.25), {
            BackgroundColor3 = OrbitEnabled and Color3.fromRGB(150, 150, 255) or Color3.fromRGB(40, 40, 50)
        }):Play()
    end)
end

-- LOAD EVADE TAB
local function loadEvadeTab()
    clearContent()
    
    local function createSimpleToggle(text, setting)
        local frame = Instance.new("Frame")
        frame.Parent = ContentFrame
        frame.Size = UDim2.new(1, 0, 0, 35)
        frame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = frame
        
        local label = Instance.new("TextLabel")
        label.Parent = frame
        label.Size = UDim2.new(0, 160, 1, 0)
        label.Position = UDim2.new(0, 12, 0, 0)
        label.BackgroundTransparency = 1
        label.Text = text
        label.Font = Enum.Font.Gotham
        label.TextSize = 13
        label.TextColor3 = Color3.fromRGB(220, 220, 240)
        label.TextXAlignment = Enum.TextXAlignment.Left
        
        local toggle = Instance.new("TextButton")
        toggle.Parent = frame
        toggle.Size = UDim2.new(0, 40, 0, 20)
        toggle.Position = UDim2.new(1, -48, 0.5, -10)
        toggle.BackgroundColor3 = UIConfig[setting] and Color3.fromRGB(150, 150, 255) or Color3.fromRGB(50, 50, 60)
        toggle.Text = ""
        toggle.BorderSizePixel = 0
        
        local toggleCorner = Instance.new("UICorner")
        toggleCorner.CornerRadius = UDim.new(1, 0)
        toggleCorner.Parent = toggle
        
        local toggleCircle = Instance.new("Frame")
        toggleCircle.Parent = toggle
        toggleCircle.Size = UDim2.new(0, 16, 0, 16)
        toggleCircle.Position = UIConfig[setting] and UDim2.new(1, -20, 0.5, -8) or UDim2.new(0, 4, 0.5, -8)
        toggleCircle.BackgroundColor3 = Color3.new(1, 1, 1)
        toggleCircle.BorderSizePixel = 0
        
        local circleCorner = Instance.new("UICorner")
        circleCorner.CornerRadius = UDim.new(1, 0)
        circleCorner.Parent = toggleCircle
        
        toggle.MouseButton1Click:Connect(function()
            UIConfig[setting] = not UIConfig[setting]
            toggle.BackgroundColor3 = UIConfig[setting] and Color3.fromRGB(150, 150, 255) or Color3.fromRGB(50, 50, 60)
            toggleCircle.Position = UIConfig[setting] and UDim2.new(1, -20, 0.5, -8) or UDim2.new(0, 4, 0.5, -8)
        end)
    end
    
    createSimpleToggle("Enable Desync", "EnableDesync")
    createSimpleToggle("Dodge Enemies", "DodgeEnemies")
    createSimpleToggle("Enable Ghosting", "EnableGhosting")
end

-- LOAD ADV TAB
local function loadAdvTab()
    clearContent()
    
    local function createSimpleToggle(text, setting)
        local frame = Instance.new("Frame")
        frame.Parent = ContentFrame
        frame.Size = UDim2.new(1, 0, 0, 35)
        frame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = frame
        
        local label = Instance.new("TextLabel")
        label.Parent = frame
        label.Size = UDim2.new(0, 160, 1, 0)
        label.Position = UDim2.new(0, 12, 0, 0)
        label.BackgroundTransparency = 1
        label.Text = text
        label.Font = Enum.Font.Gotham
        label.TextSize = 13
        label.TextColor3 = Color3.fromRGB(220, 220, 240)
        label.TextXAlignment = Enum.TextXAlignment.Left
        
        local toggle = Instance.new("TextButton")
        toggle.Parent = frame
        toggle.Size = UDim2.new(0, 40, 0, 20)
        toggle.Position = UDim2.new(1, -48, 0.5, -10)
        toggle.BackgroundColor3 = UIConfig[setting] and Color3.fromRGB(150, 150, 255) or Color3.fromRGB(50, 50, 60)
        toggle.Text = ""
        toggle.BorderSizePixel = 0
        
        local toggleCorner = Instance.new("UICorner")
        toggleCorner.CornerRadius = UDim.new(1, 0)
        toggleCorner.Parent = toggle
        
        local toggleCircle = Instance.new("Frame")
        toggleCircle.Parent = toggle
        toggleCircle.Size = UDim2.new(0, 16, 0, 16)
        toggleCircle.Position = UIConfig[setting] and UDim2.new(1, -20, 0.5, -8) or UDim2.new(0, 4, 0.5, -8)
        toggleCircle.BackgroundColor3 = Color3.new(1, 1, 1)
        toggleCircle.BorderSizePixel = 0
        
        local circleCorner = Instance.new("UICorner")
        circleCorner.CornerRadius = UDim.new(1, 0)
        circleCorner.Parent = toggleCircle
        
        toggle.MouseButton1Click:Connect(function()
            UIConfig[setting] = not UIConfig[setting]
            toggle.BackgroundColor3 = UIConfig[setting] and Color3.fromRGB(150, 150, 255) or Color3.fromRGB(50, 50, 60)
            toggleCircle.Position = UIConfig[setting] and UDim2.new(1, -20, 0.5, -8) or UDim2.new(0, 4, 0.5, -8)
        end)
    end
    
    createSimpleToggle("Force Vertical", "ForceVerticalEvasion")
end

-- Tab click handlers
OrbitTab.MouseButton1Click:Connect(function()
    currentTab = "ORBIT"
    OrbitTab.BackgroundColor3 = Color3.fromRGB(150, 150, 255)
    OrbitTab.TextColor3 = Color3.new(1, 1, 1)
    EvadeTab.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    EvadeTab.TextColor3 = Color3.fromRGB(180, 180, 200)
    AdvTab.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    AdvTab.TextColor3 = Color3.fromRGB(180, 180, 200)
    loadOrbitTab()
end)

EvadeTab.MouseButton1Click:Connect(function()
    currentTab = "EVADE"
    EvadeTab.BackgroundColor3 = Color3.fromRGB(150, 150, 255)
    EvadeTab.TextColor3 = Color3.new(1, 1, 1)
    OrbitTab.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    OrbitTab.TextColor3 = Color3.fromRGB(180, 180, 200)
    AdvTab.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    AdvTab.TextColor3 = Color3.fromRGB(180, 180, 200)
    loadEvadeTab()
end)

AdvTab.MouseButton1Click:Connect(function()
    currentTab = "ADV"
    AdvTab.BackgroundColor3 = Color3.fromRGB(150, 150, 255)
    AdvTab.TextColor3 = Color3.new(1, 1, 1)
    OrbitTab.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    OrbitTab.TextColor3 = Color3.fromRGB(180, 180, 200)
    EvadeTab.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    EvadeTab.TextColor3 = Color3.fromRGB(180, 180, 200)
    loadAdvTab()
end)

-- Toggle UI open/close
ToggleButton.MouseButton1Click:Connect(function()
    uiOpen = not uiOpen
    MainFrame.Visible = uiOpen
    ToggleButton.Text = uiOpen and "◀" or "▶"
end)

-- Initialize
loadOrbitTab()

-- Hotkey system
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode[UIConfig.Hotkey] then
        UIConfig.EnableVoid = not UIConfig.EnableVoid
    end
end)

print("✅ xxro beta loaded - ORBIT, EVADE, ADV tabs")
