--[[
    fly.lua — universal flight for Roblox places (No Salpiques included)
    ofx

    Toggle F. WASD relative to the camera, Space up, LeftCtrl down, Shift boost.
    Two drive modes: BodyVelocity (default, looks natural) and anchored CFrame
    (for places whose controller or anti-cheat fights physics).
    noClip stops you snagging on obby geometry. Everything is restored on unload.

    Keybinds are read from real input, so the place's own movement handler
    keeps working the moment you land.
]]

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local CONFIG = {
    toggleKey     = Enum.KeyCode.F,
    mode          = "velocity",   -- "velocity" | "anchor"
    speed         = 70,           -- studs/s horizontal
    verticalSpeed = 55,           -- studs/s vertical
    boost         = 2.5,          -- Shift multiplier
    response      = 0.06,         -- seconds to reach target velocity
    maxForce      = 1e6,
    noClip        = true,
    platformStand = true,         -- kills the falling state while airborne
    autoRestart   = false,        -- keep flying after respawn
    showGui       = true,
}

local KEYMAP = {
    [Enum.KeyCode.W]            = "W",
    [Enum.KeyCode.A]            = "A",
    [Enum.KeyCode.S]            = "S",
    [Enum.KeyCode.D]            = "D",
    [Enum.KeyCode.Space]        = "Space",
    [Enum.KeyCode.LeftControl]  = "Ctrl",
    [Enum.KeyCode.RightControl] = "Ctrl",
    [Enum.KeyCode.LeftShift]    = "Shift",
    [Enum.KeyCode.RightShift]   = "Shift",
}

local pressed = { W = false, A = false, S = false, D = false, Space = false, Ctrl = false, Shift = false }

local state = {
    flying     = false,
    hrp        = nil,
    bodyVel    = nil,
    savedAnch  = false,
    savedColl  = {},
    nextNoClip = 0,
    restored   = true,
}

local ui = { status = nil, flyRow = nil, noclipRow = nil, modeRow = nil, speedLabel = nil }

----------------------------------------------------------------------
-- rig
----------------------------------------------------------------------

local function getRig()
    local char = LocalPlayer.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return nil end
    return char, hrp, hum
end

local function clearInput()
    for k in pairs(pressed) do pressed[k] = false end
end

----------------------------------------------------------------------
-- input axes
----------------------------------------------------------------------

local function flatUnit(v)
    local flat = Vector3.new(v.X, 0, v.Z)
    if flat.Magnitude < 1e-3 then return nil end
    return flat.Unit
end

local function desiredVelocity()
    local cam = workspace.CurrentCamera
    if not cam then return Vector3.zero end
    local cf = cam.CFrame

    local forward = flatUnit(cf.LookVector) or flatUnit(cf.UpVector) or Vector3.new(0, 0, -1)
    local right   = flatUnit(cf.RightVector) or Vector3.new(1, 0, 0)

    local dir = Vector3.zero
    if pressed.W then dir = dir + forward end
    if pressed.S then dir = dir - forward end
    if pressed.D then dir = dir + right end
    if pressed.A then dir = dir - right end
    if dir.Magnitude > 1 then dir = dir.Unit end

    local mult = pressed.Shift and CONFIG.boost or 1
    local vertical = (pressed.Space and 1 or 0) - (pressed.Ctrl and 1 or 0)

    return dir * (CONFIG.speed * mult) + Vector3.new(0, vertical * CONFIG.verticalSpeed * mult, 0)
end

----------------------------------------------------------------------
-- noclip
----------------------------------------------------------------------

local function noclipOn(char)
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") and part.CanCollide then
            state.savedColl[part] = true
            part.CanCollide = false
        end
    end
end

local function noclipOff()
    for part in pairs(state.savedColl) do
        if part and part.Parent then
            pcall(function() part.CanCollide = true end)
        end
    end
    state.savedColl = {}
end

----------------------------------------------------------------------
-- drive
----------------------------------------------------------------------

local function ensureBody(hrp)
    if CONFIG.mode ~= "velocity" then return end
    if state.bodyVel and state.bodyVel.Parent == hrp then return end
    if state.bodyVel then state.bodyVel:Destroy() end
    local bv = Instance.new("BodyVelocity")
    bv.Name = "ofxFlyVelocity"
    bv.MaxForce = Vector3.new(CONFIG.maxForce, CONFIG.maxForce, CONFIG.maxForce)
    bv.P = 1250
    bv.Velocity = Vector3.zero
    bv.Parent = hrp
    state.bodyVel = bv
end

local function dropBody()
    if state.bodyVel then
        state.bodyVel:Destroy()
        state.bodyVel = nil
    end
end

local function restore()
    if state.restored then return end
    local _, hrp = getRig()
    dropBody()

    -- only touch the rig this session started with; a respawned character is already clean
    local owned = state.hrp and state.hrp.Parent and hrp == state.hrp
    if owned then
        pcall(function()
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            if CONFIG.mode == "anchor" then hrp.Anchored = state.savedAnch end
        end)
        local hum = hrp.Parent:FindFirstChildOfClass("Humanoid")
        if hum and CONFIG.platformStand then
            hum.PlatformStand = false
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
        end
    end

    noclipOff()
    state.hrp = nil
    state.restored = true
end

local function start()
    local _, hrp, hum = getRig()
    if not hrp or not hum or state.flying then return end

    state.flying = true
    state.hrp = hrp
    state.restored = false
    clearInput()

    if CONFIG.platformStand then
        hum.PlatformStand = true
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end)
    end

    if CONFIG.mode == "anchor" then
        state.savedAnch = hrp.Anchored
        hrp.Anchored = true
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    else
        ensureBody(hrp)
    end

    if CONFIG.noClip and hrp.Parent then noclipOn(hrp.Parent) end

    if ui.status then ui.status.Text = "flying  " .. CONFIG.mode end
end

local function stop()
    state.flying = false
    clearInput()
    restore()
    if ui.status then ui.status.Text = "idle" end
end

----------------------------------------------------------------------
-- main loop
----------------------------------------------------------------------

RunService.RenderStepped:Connect(function(dt)
    if not state.flying then return end

    local char, hrp, hum = getRig()
    if not char or not hrp or not hum or hum.Health <= 0 then
        stop()
        return
    end

    if CONFIG.platformStand and not hum.PlatformStand then
        hum.PlatformStand = true
    end

    if CONFIG.noClip and os.clock() >= state.nextNoClip then
        state.nextNoClip = os.clock() + 0.2
        noclipOn(char)
    end

    local target = desiredVelocity()

    if CONFIG.mode == "anchor" then
        hrp.CFrame = hrp.CFrame + target * dt
    else
        if not state.bodyVel or state.bodyVel.Parent ~= hrp then
            ensureBody(hrp)
            if not state.bodyVel then return end
        end
        local alpha = 1 - math.exp(-dt / math.max(CONFIG.response, 1e-3))
        state.bodyVel.Velocity = state.bodyVel.Velocity:Lerp(target, alpha)
    end
end)

----------------------------------------------------------------------
-- gui
----------------------------------------------------------------------

local function guiParent()
    local ok, hui = pcall(function() return gethui and gethui() end)
    if ok and hui then return hui end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local function paint(row, on)
    local label = row:FindFirstChildOfClass("TextLabel")
    if label then
        label.TextColor3 = on and Color3.fromRGB(120, 230, 160) or Color3.fromRGB(150, 150, 160)
    end
    row.BackgroundColor3 = on and Color3.fromRGB(30, 46, 36) or Color3.fromRGB(26, 26, 30)
end

local function addRow(parent, y, label, onClick)
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, -16, 0, 24)
    row.Position = UDim2.new(0, 8, 0, y)
    row.BackgroundColor3 = Color3.fromRGB(26, 26, 30)
    row.BorderSizePixel = 0
    row.AutoButtonColor = false
    row.Text = ""
    row.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = row

    local text = Instance.new("TextLabel")
    text.Size = UDim2.new(1, -12, 1, 0)
    text.Position = UDim2.new(0, 8, 0, 0)
    text.BackgroundTransparency = 1
    text.Font = Enum.Font.Code
    text.TextSize = 13
    text.TextXAlignment = Enum.TextXAlignment.Left
    text.TextColor3 = Color3.fromRGB(230, 230, 236)
    text.Text = label
    text.Parent = row

    row.MouseButton1Click:Connect(onClick)
    return row
end

local function addStepper(parent, y, text, onMinus, onPlus)
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, -16, 0, 24)
    bar.Position = UDim2.new(0, 8, 0, y)
    bar.BackgroundColor3 = Color3.fromRGB(26, 26, 30)
    bar.BorderSizePixel = 0
    bar.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = bar

    local minus = Instance.new("TextButton")
    minus.Size = UDim2.new(0, 26, 1, 0)
    minus.BackgroundColor3 = Color3.fromRGB(32, 32, 38)
    minus.BorderSizePixel = 0
    minus.Font = Enum.Font.Code
    minus.TextSize = 14
    minus.TextColor3 = Color3.fromRGB(230, 230, 236)
    minus.Text = "-"
    minus.ZIndex = 2
    minus.Parent = bar

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -56, 1, 0)
    label.Position = UDim2.new(0, 28, 0, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Code
    label.TextSize = 12
    label.TextColor3 = Color3.fromRGB(200, 200, 210)
    label.Text = text
    label.ZIndex = 2
    label.Parent = bar

    local plus = Instance.new("TextButton")
    plus.Size = UDim2.new(0, 26, 1, 0)
    plus.Position = UDim2.new(1, -26, 0, 0)
    plus.BackgroundColor3 = Color3.fromRGB(32, 32, 38)
    plus.BorderSizePixel = 0
    plus.Font = Enum.Font.Code
    plus.TextSize = 14
    plus.TextColor3 = Color3.fromRGB(230, 230, 236)
    plus.Text = "+"
    plus.ZIndex = 2
    plus.Parent = bar

    minus.MouseButton1Click:Connect(onMinus)
    plus.MouseButton1Click:Connect(onPlus)
    return label
end

local function buildGui()
    if not CONFIG.showGui then return end

    local parent = guiParent()
    local old = parent:FindFirstChild("ofxFly")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "ofxFly"
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 1000
    gui.Parent = parent

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 208, 0, 196)
    frame.Position = UDim2.new(0, 16, 0, 90)
    frame.BackgroundColor3 = Color3.fromRGB(17, 17, 20)
    frame.BackgroundTransparency = 0.1
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -16, 0, 20)
    title.Position = UDim2.new(0, 8, 0, 6)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.Code
    title.TextSize = 14
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextColor3 = Color3.fromRGB(240, 240, 246)
    title.Text = "ofx fly"
    title.Parent = frame

    ui.status = Instance.new("TextLabel")
    ui.status.Size = UDim2.new(1, -16, 0, 16)
    ui.status.Position = UDim2.new(0, 8, 0, 26)
    ui.status.BackgroundTransparency = 1
    ui.status.Font = Enum.Font.Code
    ui.status.TextSize = 11
    ui.status.TextXAlignment = Enum.TextXAlignment.Left
    ui.status.TextColor3 = Color3.fromRGB(130, 130, 145)
    ui.status.Text = "idle"
    ui.status.Parent = frame

    ui.flyRow = addRow(frame, 48, "fly     off", function()
        if state.flying then stop() else start() end
        paint(ui.flyRow, state.flying)
        ui.flyRow:FindFirstChildOfClass("TextLabel").Text = "fly     " .. (state.flying and "on" or "off")
    end)

    ui.noclipRow = addRow(frame, 76, "noclip  " .. (CONFIG.noClip and "on" or "off"), function()
        CONFIG.noClip = not CONFIG.noClip
        paint(ui.noclipRow, CONFIG.noClip)
        ui.noclipRow:FindFirstChildOfClass("TextLabel").Text = "noclip  " .. (CONFIG.noClip and "on" or "off")
        if not CONFIG.noClip then noclipOff() end
    end)
    paint(ui.noclipRow, CONFIG.noClip)

    ui.modeRow = addRow(frame, 104, "mode    " .. CONFIG.mode, function()
        if CONFIG.mode == "velocity" then
            if state.flying then stop() end
            CONFIG.mode = "anchor"
        else
            if state.flying then stop() end
            CONFIG.mode = "velocity"
        end
        ui.modeRow:FindFirstChildOfClass("TextLabel").Text = "mode    " .. CONFIG.mode
    end)

    ui.speedLabel = addStepper(frame, 132, string.format("speed %d", CONFIG.speed), function()
        CONFIG.speed = math.max(10, CONFIG.speed - 10)
        CONFIG.verticalSpeed = math.max(10, CONFIG.verticalSpeed - 5)
        ui.speedLabel.Text = string.format("speed %d", CONFIG.speed)
    end, function()
        CONFIG.speed = math.min(400, CONFIG.speed + 10)
        CONFIG.verticalSpeed = math.min(300, CONFIG.verticalSpeed + 5)
        ui.speedLabel.Text = string.format("speed %d", CONFIG.speed)
    end)

    local hint = Instance.new("TextLabel")
    hint.Size = UDim2.new(1, -16, 0, 32)
    hint.Position = UDim2.new(0, 8, 0, 160)
    hint.BackgroundTransparency = 1
    hint.Font = Enum.Font.Code
    hint.TextSize = 10
    hint.TextWrapped = true
    hint.TextXAlignment = Enum.TextXAlignment.Left
    hint.TextYAlignment = Enum.TextYAlignment.Top
    hint.TextColor3 = Color3.fromRGB(120, 120, 132)
    hint.Text = "f toggle   wasd space ctrl shift"
    hint.Parent = frame
end

----------------------------------------------------------------------
-- keys / lifecycle
----------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, processed)
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if UserInputService:GetFocusedTextBox() then return end

    local slot = KEYMAP[input.KeyCode]
    if slot then
        pressed[slot] = true
        return
    end

    if input.KeyCode == CONFIG.toggleKey and not processed then
        if state.flying then stop() else start() end
        if ui.flyRow then
            paint(ui.flyRow, state.flying)
            ui.flyRow:FindFirstChildOfClass("TextLabel").Text = "fly     " .. (state.flying and "on" or "off")
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    local slot = KEYMAP[input.KeyCode]
    if slot then pressed[slot] = false end
end)

UserInputService.WindowFocusReleased:Connect(function()
    clearInput()
end)

LocalPlayer.CharacterAdded:Connect(function()
    stop()
    if CONFIG.autoRestart then
        task.wait(1.5)
        start()
        if ui.flyRow then
            paint(ui.flyRow, state.flying)
            ui.flyRow:FindFirstChildOfClass("TextLabel").Text = "fly     " .. (state.flying and "on" or "off")
        end
    end
end)

if getgenv then
    getgenv().ofxFly = {
        state  = state,
        config = CONFIG,
        start  = start,
        stop   = stop,
        toggle = function() if state.flying then stop() else start() end end,
    }
end

buildGui()