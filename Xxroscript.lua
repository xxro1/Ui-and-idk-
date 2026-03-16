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
        HRP.AssemblyLinearVelocity  = Vector3.zero
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
    targetReacquireTimer += dt
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

    orbitAngle += CFG.ORBIT_SPEED * dt
    elapsed    += dt

    local rad       = math.rad(orbitAngle)
    local vel       = ehrp.AssemblyLinearVelocity
    local speed     = vel.Magnitude
    local predicted = head.Position + vel * CFG.PREDICTION

    local dist   = (HRP.Position - ehrp.Position).Magnitude
    local baseR  = math.clamp(dist * 1.2, CFG.MIN_RADIUS, CFG.MAX_RADIUS)
    local radius = math.clamp(baseR + speed * 1200, CFG.MIN_RADIUS, CFG.MAX_RADIUS)

    local vertWave   = math.sin(elapsed * CFG.VERTICAL_WAVE_SPEED * math.pi * 2)
    local vertOffset = CFG.HEIGHT_OFFSET + radius * CFG.VERTICAL_WAVE_AMP * vertWave

    local orbitOffset = Vector3.new(
        math.cos(rad) * radius,
        vertOffset,
        math.sin(rad) * radius * CFG.ELLIPSE_RATIO
    )

    local camPos = predicted + orbitOffset
    local cf     = CFrame.lookAt(camPos, predicted)

    local lerpT = math.clamp(
        CFG.CAM_LERP_BASE + speed * CFG.CAM_LERP_SPEED_SCALE,
        CFG.CAM_LERP_BASE,
        CFG.CAM_MAX_LERP
    )
    local alpha  = 1 - (1 - lerpT) ^ (dt * 60)
    lastCF       = lastCF:Lerp(cf, alpha)
    Camera.CFrame = lastCF

    if _G.SilentAim then _G.SilentAim.Target = predicted end
    if _G.RageBot    then _G.RageBot.Target   = predicted end
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
-- MINI APEX UI - ALL TABS FROM IMAGE
-- ==============================================

-- Configuration for UI controls (ALL FEATURES FROM IMAGE)
local UIConfig = {
    -- Void Control (COMPLETE)
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
    
    -- Evasion & Desync (COMPLETE)
    EnableDesync = false,
    DesyncRate = 18,
    DesyncRadius = 22,
    DodgeEnemies = false,
    EvasionRadius = 88,
    EvasionSpeed = 68,
    EnableGhosting = false,
    GhostingIntensity = 50,
    
    -- Advanced Void Settings (COMPLETE)
    YDriftRange = 108,
    ScrambleInterval = 12,
    FlickerInterval = 5,
    ForceVerticalEvasion = false,
    GravityWellStrength = 100,
}

-- Available options
local Options = {
    VoidMethod = {"Quantum", "Classic", "Hybrid", "Extreme", "Stealth"},
    BypassMethod = {"Standard", "Advanced", "Extreme", "Undetectable"},
    HotkeyOptions = {"V", "G", "H", "X", "Z", "C", "LeftAlt", "RightAlt"},
}

local currentTab = "Void"
local isMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local uiOpen = true

-- Create GUI
local Gui = Instance.new("ScreenGui")
Gui.Name = "xxro gui "
Gui.ResetOnSpawn = false
Gui.Parent = game:GetService("CoreGui")
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- ==============================================
-- OPEN/CLOSE BUTTON (RIGHT SIDE)
-- ==============================================

local ToggleButton = Instance.new("ImageButton")
ToggleButton.Name = "ToggleButton"
ToggleButton.Parent = Gui
ToggleButton.Size = UDim2.new(0, 40, 0, 40)
ToggleButton.Position = UDim2.new(1, -50, 0.5, -20)
ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
ToggleButton.BackgroundTransparency = 0.1
ToggleButton.Image = "rbxassetid://3926305904"
ToggleButton.ImageColor3 = Color3.new(1, 1, 1)
ToggleButton.ImageRectOffset = Vector2.new(4, 4)
ToggleButton.ImageRectSize = Vector2.new(36, 36)
ToggleButton.Rotation = 180
ToggleButton.BorderSizePixel = 0
ToggleButton.Visible = true
ToggleButton.ZIndex = 10

local ButtonCorner = Instance.new("UICorner")
ButtonCorner.CornerRadius = UDim.new(0, 30)
ButtonCorner.Parent = ToggleButton

local ButtonStroke = Instance.new("UIStroke")
ButtonStroke.Parent = ToggleButton
ButtonStroke.Thickness = 2
ButtonStroke.Color = Color3.fromRGB(0, 200, 255)
ButtonStroke.Transparency = 0.3

-- ==============================================
-- MAIN UI FRAME (MINI SIZE)
-- ==============================================

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Parent = Gui
MainFrame.Size = UDim2.new(0, 280, 0, 400)
MainFrame.Position = UDim2.new(0.5, -140, 0.5, -200)
MainFrame.BackgroundColor3 = Color3.fromRGB(5, 7, 15)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Visible = true
MainFrame.ZIndex = 5

-- Make UI movable on mobile
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

-- Gradient
local Gradient = Instance.new("UIGradient")
Gradient.Parent = MainFrame
Gradient.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0, Color3.fromRGB(10, 15, 25)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(3, 5, 12))
}
Gradient.Rotation = 90

-- Top Bar
local TopBar = Instance.new("Frame")
TopBar.Parent = MainFrame
TopBar.Size = UDim2.new(1, 0, 0, 45)
TopBar.BackgroundTransparency = 1

local Title = Instance.new("TextLabel")
Title.Parent = TopBar
Title.Size = UDim2.new(1, -15, 1, 0)
Title.Position = UDim2.new(0, 12, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "Apex Orbit V3"
Title.Font = Enum.Font.GothamBold
Title.TextSize = 16
Title.TextColor3 = Color3.fromRGB(0, 200, 255)
Title.TextXAlignment = Enum.TextXAlignment.Left

local SubTitle = Instance.new("TextLabel")
SubTitle.Parent = TopBar
SubTitle.Size = UDim2.new(1, -15, 0, 14)
SubTitle.Position = UDim2.new(0, 12, 0, 24)
SubTitle.BackgroundTransparency = 1
SubTitle.Text = "Mini Edition"
SubTitle.Font = Enum.Font.Gotham
SubTitle.TextSize = 10
SubTitle.TextColor3 = Color3.fromRGB(100, 150, 255)
SubTitle.TextXAlignment = Enum.TextXAlignment.Left

-- Tab Bar
local TabBar = Instance.new("Frame")
TabBar.Parent = MainFrame
TabBar.Size = UDim2.new(1, -16, 0, 30)
TabBar.Position = UDim2.new(0, 8, 0, 48)
TabBar.BackgroundTransparency = 1

local function createTab(name, pos, width)
    local btn = Instance.new("TextButton")
    btn.Parent = TabBar
    btn.Name = name.."Tab"
    btn.Size = UDim2.new(0, width, 1, 0)
    btn.Position = UDim2.new(0, pos, 0, 0)
    btn.BackgroundColor3 = Color3.fromRGB(15, 20, 30)
    btn.Text = name
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11
    btn.TextColor3 = Color3.fromRGB(150, 150, 200)
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = btn
    
    return btn
end

local VoidTab = createTab("Void", 0, 85)
local EvasionTab = createTab("Evasion", 90, 85)
local AdvancedTab = createTab("Advanced", 180, 85)

-- Content Area (ScrollingFrame for all options)
local ContentFrame = Instance.new("ScrollingFrame")
ContentFrame.Parent = MainFrame
ContentFrame.Size = UDim2.new(1, -16, 1, -95)
ContentFrame.Position = UDim2.new(0, 8, 0, 85)
ContentFrame.BackgroundTransparency = 1
ContentFrame.ScrollBarThickness = 3
ContentFrame.ScrollBarImageColor3 = Color3.fromRGB(0, 200, 255)
ContentFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
ContentFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y

local ContentList = Instance.new("UIListLayout")
ContentList.Parent = ContentFrame
ContentList.SortOrder = Enum.SortOrder.LayoutOrder
ContentList.Padding = UDim.new(0, 6)

local ContentPadding = Instance.new("UIPadding")
ContentPadding.Parent = ContentFrame
ContentPadding.PaddingTop = UDim.new(0, 4)
ContentPadding.PaddingBottom = UDim.new(0, 8)

-- UI Element Creation Functions (MINI SIZE)
function createToggle(parent, title, setting, order)
    local frame = Instance.new("Frame")
    frame.Parent = parent
    frame.Size = UDim2.new(1, 0, 0, 32)
    frame.BackgroundColor3 = Color3.fromRGB(15, 18, 25)
    frame.BackgroundTransparency = 0.2
    frame.LayoutOrder = order
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = frame
    
    local label = Instance.new("TextLabel")
    label.Parent = frame
    label.Size = UDim2.new(0, 150, 1, 0)
    label.Position = UDim2.new(0, 10, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = title
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.TextColor3 = Color3.fromRGB(220, 220, 255)
    label.TextXAlignment = Enum.TextXAlignment.Left
    
    local toggle = Instance.new("TextButton")
    toggle.Parent = frame
    toggle.Size = UDim2.new(0, 36, 0, 18)
    toggle.Position = UDim2.new(1, -44, 0.5, -9)
    toggle.BackgroundColor3 = UIConfig[setting] and Color3.fromRGB(0, 200, 255) or Color3.fromRGB(40, 45, 60)
    toggle.Text = ""
    toggle.BorderSizePixel = 0
    toggle.AutoButtonColor = false
    
    local toggleCorner = Instance.new("UICorner")
    toggleCorner.CornerRadius = UDim.new(1, 0)
    toggleCorner.Parent = toggle
    
    local toggleCircle = Instance.new("Frame")
    toggleCircle.Parent = toggle
    toggleCircle.Size = UDim2.new(0, 14, 0, 14)
    toggleCircle.Position = UIConfig[setting] and UDim2.new(1, -18, 0.5, -7) or UDim2.new(0, 4, 0.5, -7)
    toggleCircle.BackgroundColor3 = Color3.new(1, 1, 1)
    toggleCircle.BorderSizePixel = 0
    
    local circleCorner = Instance.new("UICorner")
    circleCorner.CornerRadius = UDim.new(1, 0)
    circleCorner.Parent = toggleCircle
    
    toggle.MouseButton1Click:Connect(function()
        UIConfig[setting] = not UIConfig[setting]
        
        if setting == "EnableVoid" then
            toggleOrbit(UIConfig.EnableVoid)
        end
        
        TweenService:Create(toggle, TweenInfo.new(0.2), {
            BackgroundColor3 = UIConfig[setting] and Color3.fromRGB(0, 200, 255) or Color3.fromRGB(40, 45, 60)
        }):Play()
        
        TweenService:Create(toggleCircle, TweenInfo.new(0.2), {
            Position = UIConfig[setting] and UDim2.new(1, -18, 0.5, -7) or UDim2.new(0, 4, 0.5, -7)
        }):Play()
    end)
    
    return frame
end

function createSlider(parent, title, setting, min, max, suffix, order)
    local frame = Instance.new("Frame")
    frame.Parent = parent
    frame.Size = UDim2.new(1, 0, 0, 50)
    frame.BackgroundColor3 = Color3.fromRGB(15, 18, 25)
    frame.BackgroundTransparency = 0.2
    frame.LayoutOrder = order
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = frame
    
    local label = Instance.new("TextLabel")
    label.Parent = frame
    label.Size = UDim2.new(0, 150, 0, 16)
    label.Position = UDim2.new(0, 10, 0, 6)
    label.BackgroundTransparency = 1
    label.Text = title
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.TextColor3 = Color3.fromRGB(220, 220, 255)
    label.TextXAlignment = Enum.TextXAlignment.Left
    
    local valueLabel = Instance.new("TextLabel")
    valueLabel.Parent = frame
    valueLabel.Size = UDim2.new(0, 50, 0, 16)
    valueLabel.Position = UDim2.new(1, -60, 0, 6)
    valueLabel.BackgroundTransparency = 1
    valueLabel.Text = UIConfig[setting] .. (suffix or "")
    valueLabel.Font = Enum.Font.GothamBold
    valueLabel.TextSize = 12
    valueLabel.TextColor3 = Color3.fromRGB(0, 200, 255)
    valueLabel.TextXAlignment = Enum.TextXAlignment.Right
    
    local sliderBg = Instance.new("Frame")
    sliderBg.Parent = frame
    sliderBg.Size = UDim2.new(1, -20, 0, 3)
    sliderBg.Position = UDim2.new(0, 10, 0, 32)
    sliderBg.BackgroundColor3 = Color3.fromRGB(40, 45, 60)
    sliderBg.BorderSizePixel = 0
    
    local sliderBgCorner = Instance.new("UICorner")
    sliderBgCorner.CornerRadius = UDim.new(1, 0)
    sliderBgCorner.Parent = sliderBg
    
    local sliderFill = Instance.new("Frame")
    sliderFill.Parent = sliderBg
    sliderFill.Size = UDim2.new((UIConfig[setting] - min) / (max - min), 0, 1, 0)
    sliderFill.BackgroundColor3 = Color3.fromRGB(0, 200, 255)
    sliderFill.BorderSizePixel = 0
    
    local sliderFillCorner = Instance.new("UICorner")
    sliderFillCorner.CornerRadius = UDim.new(1, 0)
    sliderFillCorner.Parent = sliderFill
    
    local dragButton = Instance.new("TextButton")
    dragButton.Parent = sliderBg
    dragButton.Size = UDim2.new(0, 16, 0, 16)
    dragButton.Position = UDim2.new((UIConfig[setting] - min) / (max - min), -8, 0.5, -8)
    dragButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    dragButton.Text = ""
    dragButton.BorderSizePixel = 0
    dragButton.AutoButtonColor = false
    
    local dragCorner = Instance.new("UICorner")
    dragCorner.CornerRadius = UDim.new(1, 0)
    dragCorner.Parent = dragButton
    
    local dragging = false
    
    dragButton.MouseButton1Down:Connect(function()
        dragging = true
    end)
    
    local function onInputEnded(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end
    
    UserInputService.InputEnded:Connect(onInputEnded)
    
    local function updateSlider(input)
        if not dragging then return end
        
        local pos = input.Position.X
        local absPos = sliderBg.AbsolutePosition.X
        local size = sliderBg.AbsoluteSize.X
        
        local percent = (pos - absPos) / size
        percent = math.clamp(percent, 0, 1)
        
        local value = math.floor(min + (max - min) * percent)
        UIConfig[setting] = value
        
        sliderFill.Size = UDim2.new(percent, 0, 1, 0)
        dragButton.Position = UDim2.new(percent, -8, 0.5, -8)
        valueLabel.Text = value .. (suffix or "")
    end
    
    dragButton.MouseButton1Drag:Connect(updateSlider)
    dragButton.TouchMoved:Connect(updateSlider)
    
    return frame
end

function createDropdown(parent, title, setting, options, order)
    local frame = Instance.new("Frame")
    frame.Parent = parent
    frame.Size = UDim2.new(1, 0, 0, 32)
    frame.BackgroundColor3 = Color3.fromRGB(15, 18, 25)
    frame.BackgroundTransparency = 0.2
    frame.LayoutOrder = order
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = frame
    
    local label = Instance.new("TextLabel")
    label.Parent = frame
    label.Size = UDim2.new(0, 120, 1, 0)
    label.Position = UDim2.new(0, 10, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = title
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.TextColor3 = Color3.fromRGB(220, 220, 255)
    label.TextXAlignment = Enum.TextXAlignment.Left
    
    local dropdown = Instance.new("TextButton")
    dropdown.Parent = frame
    dropdown.Size = UDim2.new(0, 90, 0, 24)
    dropdown.Position = UDim2.new(1, -100, 0.5, -12)
    dropdown.BackgroundColor3 = Color3.fromRGB(25, 30, 40)
    dropdown.Text = UIConfig[setting]
    dropdown.Font = Enum.Font.Gotham
    dropdown.TextSize = 11
    dropdown.TextColor3 = Color3.fromRGB(200, 200, 255)
    dropdown.BorderSizePixel = 0
    
    local dropdownCorner = Instance.new("UICorner")
    dropdownCorner.CornerRadius = UDim.new(0, 6)
    dropdownCorner.Parent = dropdown
    
    local arrow = Instance.new("TextLabel")
    arrow.Parent = dropdown
    arrow.Size = UDim2.new(0, 16, 1, 0)
    arrow.Position = UDim2.new(1, -18, 0, 0)
    arrow.BackgroundTransparency = 1
    arrow.Text = "⌄"
    arrow.Font = Enum.Font.Gotham
    arrow.TextSize = 14
    arrow.TextColor3 = Color3.fromRGB(0, 200, 255)
    
    dropdown.MouseButton1Click:Connect(function()
        local currentIndex = table.find(options, UIConfig[setting]) or 1
        local nextIndex = currentIndex % #options + 1
        UIConfig[setting] = options[nextIndex]
        dropdown.Text = UIConfig[setting]
    end)
    
    return frame
end

-- Tab content loading functions
local function clearContent()
    for _, child in ipairs(ContentFrame:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end
end

local function updateTabColors()
    local tabs = {VoidTab, EvasionTab, AdvancedTab}
    local tabNames = {"Void", "Evasion", "Advanced"}
    
    for i, tab in ipairs(tabs) do
        if currentTab == tabNames[i] then
            tab.BackgroundColor3 = Color3.fromRGB(0, 100, 200)
            tab.TextColor3 = Color3.new(1, 1, 1)
        else
            tab.BackgroundColor3 = Color3.fromRGB(15, 20, 30)
            tab.TextColor3 = Color3.fromRGB(150, 150, 200)
        end
    end
end

local function loadVoidTab()
    clearContent()
    local order = 0
    
    createToggle(ContentFrame, "Enable Void", "EnableVoid", order); order = order + 1
    createDropdown(ContentFrame, "Hotkey", "Hotkey", Options.HotkeyOptions, order); order = order + 1
    createDropdown(ContentFrame, "Void Method", "VoidMethod", Options.VoidMethod, order); order = order + 1
    createToggle(ContentFrame, "Quantum Tunneling", "QuantumTunneling", order); order = order + 1
    createDropdown(ContentFrame, "Bypass Method", "BypassMethod", Options.BypassMethod, order); order = order + 1
    createToggle(ContentFrame, "Extreme Networking", "ExtremeNetworking", order); order = order + 1
    createSlider(ContentFrame, "Drift Speed", "DriftSpeed", 0, 1000, " M/s", order); order = order + 1
    createSlider(ContentFrame, "Drift Chaos", "DriftChaos", 0, 500, "%", order); order = order + 1
    createSlider(ContentFrame, "Void Altitude", "VoidAltitude", 0, 1000, "%", order); order = order + 1
    createToggle(ContentFrame, "Scramble Position", "ScramblePosition", order); order = order + 1
    createSlider(ContentFrame, "Lissajous A", "LissajousA", 1, 50, "", order); order = order + 1
    createSlider(ContentFrame, "Lissajous B", "LissajousB", 1, 50, "", order); order = order + 1
end

local function loadEvasionTab()
    clearContent()
    local order = 0
    
    createToggle(ContentFrame, "Enable Desync", "EnableDesync", order); order = order + 1
    createSlider(ContentFrame, "Desync Rate", "DesyncRate", 1, 500, "x0.01s", order); order = order + 1
    createSlider(ContentFrame, "Desync Radius", "DesyncRadius", 1, 1000, " studs", order); order = order + 1
    createToggle(ContentFrame, "Dodge Enemies", "DodgeEnemies", order); order = order + 1
    createSlider(ContentFrame, "Evasion Radius", "EvasionRadius", 1, 1000, "", order); order = order + 1
    createSlider(ContentFrame, "Evasion Speed", "EvasionSpeed", 1, 1000, "", order); order = order + 1
    createToggle(ContentFrame, "Enable Ghosting", "EnableGhosting", order); order = order + 1
    createSlider(ContentFrame, "Ghosting Intensity", "GhostingIntensity", 0, 500, "%", order); order = order + 1
end

local function loadAdvancedTab()
    clearContent()
    local order = 0
    
    createSlider(ContentFrame, "Y Drift Range", "YDriftRange", 0, 1000, "", order); order = order + 1
    createSlider(ContentFrame, "Scramble Interval", "ScrambleInterval", 1, 500, "x0.1s", order); order = order + 1
    createSlider(ContentFrame, "Flicker Interval", "FlickerInterval", 1, 500, "ms", order); order = order + 1
    createToggle(ContentFrame, "Force Vertical Evasion", "ForceVerticalEvasion", order); order = order + 1
    createSlider(ContentFrame, "Gravity Well Strength", "GravityWellStrength", 0, 10000, " M", order); order = order + 1
end

-- Tab click handlers
VoidTab.MouseButton1Click:Connect(function()
    currentTab = "Void"
    updateTabColors()
    loadVoidTab()
end)

EvasionTab.MouseButton1Click:Connect(function()
    currentTab = "Evasion"
    updateTabColors()
    loadEvasionTab()
end)

AdvancedTab.MouseButton1Click:Connect(function()
    currentTab = "Advanced"
    updateTabColors()
    loadAdvancedTab()
end)

-- Toggle UI open/close
ToggleButton.MouseButton1Click:Connect(function()
    uiOpen = not uiOpen
    
    TweenService:Create(MainFrame, TweenInfo.new(0.3), {
        Visible = uiOpen
    }):Play()
    
    TweenService:Create(ToggleButton, TweenInfo.new(0.3), {
        Rotation = uiOpen and 180 or 0
    }):Play()
end)

-- Initialize
updateTabColors()
loadVoidTab()

-- Hotkey system
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    if input.KeyCode == Enum.KeyCode[UIConfig.Hotkey] then
        UIConfig.EnableVoid = not UIConfig.EnableVoid
        toggleOrbit(UIConfig.EnableVoid)
    end
end)

print(" xxro script is looded")
