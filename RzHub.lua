-- Rz Hub — Egg Steal Edition
-- Executor: Synapse X / Delta / Arceus / Solara
-- loadstring(game:HttpGet("SEU_RAW_AQUI"))()

if _G.RzHubLoaded then
    pcall(function() _G.RzHub:Destroy() end)
end
_G.RzHubLoaded = true

local Players  = game:GetService("Players")
local RS       = game:GetService("ReplicatedStorage")
local UIS      = game:GetService("UserInputService")
local Tween    = game:GetService("TweenService")
local CoreGui  = game:GetService("CoreGui")
local lp       = Players.LocalPlayer

-- ============================================================
-- CONFIG PERSISTENTE
-- ============================================================
local CONFIG_PATH = "RzHub_EggSteal.json"
local defaults = {
    MIN_SCORE   = 1500,
    AUTO_STEAL  = true,
    COOLDOWN_MS = 2200,
    SCAN_MS     = 800,
    DRY_RUN     = false,
    EGG_FOLDER  = "Eggs",
    REMOTE_NAME = "StealEgg",
    NOTIFY      = true,
    THEME       = "dark",
}
local Config = {}
for k, v in pairs(defaults) do Config[k] = v end

local function saveConfig()
    if not writefile then return end
    pcall(function() writefile(CONFIG_PATH, game:GetService("HttpService"):JSONEncode(Config)) end)
end
local function loadConfig()
    if not (isfile and readfile) then return end
    if not isfile(CONFIG_PATH) then return end
    pcall(function()
        local data = game:GetService("HttpService"):JSONDecode(readfile(CONFIG_PATH))
        for k, v in pairs(data) do if Config[k] ~= nil then Config[k] = v end end
    end)
end
loadConfig()

local RarityWeights = {
    common=1, uncommon=2.5, rare=6, epic=15,
    legendary=40, mythic=100, secret=250, event=180
}

local State = {
    eggs = {}, lastSteal = 0, stolen = 0,
    failures = 0, paused = false, log = {},
    connections = {},
}

-- ============================================================
-- TEMA
-- ============================================================
local Theme = {
    bg       = Color3.fromRGB(18, 18, 22),
    bg2      = Color3.fromRGB(26, 26, 32),
    bg3      = Color3.fromRGB(38, 38, 46),
    accent   = Color3.fromRGB(120, 80, 255),
    accent2  = Color3.fromRGB(80, 200, 255),
    text     = Color3.fromRGB(230, 230, 240),
    textDim  = Color3.fromRGB(140, 140, 155),
    success  = Color3.fromRGB(80, 220, 130),
    danger   = Color3.fromRGB(255, 90, 90),
    warn     = Color3.fromRGB(255, 190, 80),
}

-- ============================================================
-- UTIL UI
-- ============================================================
local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end
local function corner(parent, r)
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 6); c.Parent = parent; return c
end
local function stroke(parent, color, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color or Theme.bg3; s.Thickness = thickness or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = parent
    return s
end
local function padding(parent, p)
    local u = Instance.new("UIPadding")
    u.PaddingLeft = UDim.new(0, p); u.PaddingRight = UDim.new(0, p)
    u.PaddingTop = UDim.new(0, p); u.PaddingBottom = UDim.new(0, p)
    u.Parent = parent
    return u
end

-- ============================================================
-- GUI RAIZ
-- ============================================================
local gui = new("ScreenGui", {
    Name = "RzHub",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
pcall(function() gui.Parent = CoreGui end)
if not gui.Parent then gui.Parent = lp:WaitForChild("PlayerGui") end

-- janela principal
local win = new("Frame", {
    Size = UDim2.new(0, 560, 0, 380),
    Position = UDim2.new(0.5, -280, 0.5, -190),
    BackgroundColor3 = Theme.bg,
    BorderSizePixel = 0,
    Active = true,
}, gui)
corner(win, 10); stroke(win, Theme.bg3, 1)

-- topbar
local top = new("Frame", {
    Size = UDim2.new(1, 0, 0, 36),
    BackgroundColor3 = Theme.bg2,
    BorderSizePixel = 0,
}, win)
corner(top, 10)
new("Frame", {
    Size = UDim2.new(1, 0, 0, 12),
    Position = UDim2.new(0, 0, 0, 24),
    BackgroundColor3 = Theme.bg2,
    BorderSizePixel = 0,
}, top)

new("TextLabel", {
    Size = UDim2.new(0, 200, 1, 0),
    Position = UDim2.new(0, 14, 0, 0),
    BackgroundTransparency = 1,
    Text = "Rz Hub",
    TextColor3 = Theme.text,
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    TextXAlignment = Enum.TextXAlignment.Left,
}, top)

local tag = new("TextLabel", {
    Size = UDim2.new(0, 120, 0, 20),
    Position = UDim2.new(0, 90, 0, 8),
    BackgroundColor3 = Theme.accent,
    Text = " EGG STEAL ",
    TextColor3 = Color3.new(1,1,1),
    Font = Enum.Font.GothamBold,
    TextSize = 10,
}, top)
corner(tag, 4)

local function iconBtn(parent, xpos, symbol, onClick)
    local b = new("TextButton", {
        Size = UDim2.new(0, 26, 0, 26),
        Position = UDim2.new(1, xpos, 0, 5),
        BackgroundColor3 = Theme.bg3,
        Text = symbol,
        TextColor3 = Theme.text,
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        AutoButtonColor = false,
    }, parent)
    corner(b, 4)
    b.MouseButton1Click:Connect(onClick)
    return b
end

local minimizeBtn = iconBtn(top, -64, "—", function() end)
local closeBtn = iconBtn(top, -32, "×", function()
    for _, c in pairs(State.connections) do pcall(function() c:Disconnect() end) end
    gui:Destroy()
end)

-- drag
local dragging, dragStart, startPos
top.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = i.Position
        startPos = win.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
        local d = i.Position - dragStart
        win.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + d.X,
            startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)

-- ============================================================
-- SIDEBAR DE ABAS
-- ============================================================
local sidebar = new("Frame", {
    Size = UDim2.new(0, 130, 1, -46),
    Position = UDim2.new(0, 10, 0, 44),
    BackgroundColor3 = Theme.bg2,
    BorderSizePixel = 0,
}, win)
corner(sidebar, 8)

local tabList = new("Frame", {
    Size = UDim2.new(1, -10, 1, -10),
    Position = UDim2.new(0, 5, 0, 5),
    BackgroundTransparency = 1,
}, sidebar)
local tabLayout = new("UIListLayout", { Padding = UDim.new(0, 4) }, tabList)

local pages = {}
local activeTab = nil

local function createTab(name)
    local btn = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundColor3 = Theme.bg,
        Text = "  " .. name,
        TextColor3 = Theme.textDim,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        AutoButtonColor = false,
    }, tabList)
    corner(btn, 6)

    local page = new("ScrollingFrame", {
        Size = UDim2.new(1, -150, 1, -56),
        Position = UDim2.new(0, 148, 0, 44),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, win)
    local layout = new("UIListLayout", { Padding = UDim.new(0, 6) }, page)
    pages[name] = page

    local function activate()
        for n, p in pairs(pages) do p.Visible = (n == name) end
        for _, c in ipairs(tabList:GetChildren()) do
            if c:IsA("TextButton") then
                c.TextColor3 = (c.Text:sub(3) == name) and Theme.text or Theme.textDim
                c.BackgroundColor3 = (c.Text:sub(3) == name) and Theme.bg3 or Theme.bg
            end
        end
        activeTab = name
    end
    btn.MouseButton1Click:Connect(activate)
    if not activeTab then activate() end
    return page
end

-- ============================================================
-- WIDGETS (estilo Chilli Hub)
-- ============================================================
local Widgets = {}

function Widgets.section(parent, title)
    local f = new("Frame", {
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundTransparency = 1,
    }, parent)
    new("TextLabel", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = title:upper(),
        TextColor3 = Theme.textDim,
        Font = Enum.Font.GothamBold,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, f)
    return f
end

function Widgets.toggle(parent, opts)
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = Theme.bg2,
        BorderSizePixel = 0,
    }, parent)
    corner(row, 6)

    new("TextLabel", {
        Size = UDim2.new(1, -70, 1, 0),
        Position = UDim2.new(0, 12, 0, 0),
        BackgroundTransparency = 1,
        Text = opts.text,
        TextColor3 = Theme.text,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)

    local sw = new("Frame", {
        Size = UDim2.new(0, 42, 0, 22),
        Position = UDim2.new(1, -52, 0.5, -11),
        BackgroundColor3 = Theme.bg3,
        BorderSizePixel = 0,
    }, row)
    corner(sw, 11)
    local knob = new("Frame", {
        Size = UDim2.new(0, 18, 0, 18),
        Position = UDim2.new(0, 2, 0.5, -9),
        BackgroundColor3 = Theme.textDim,
        BorderSizePixel = 0,
    }, sw)
    corner(knob, 9)

    local on = opts.default == true
    local function apply(anim)
        local goalSw = on and Theme.accent or Theme.bg3
        local goalKnob = UDim2.new(0, on and 22 or 2, 0.5, -9)
        if anim then
            Tween:Create(sw, TweenInfo.new(0.15), { BackgroundColor3 = goalSw }):Play()
            Tween:Create(knob, TweenInfo.new(0.15), { Position = goalKnob, BackgroundColor3 = on and Color3.new(1,1,1) or Theme.textDim }):Play()
        else
            sw.BackgroundColor3 = goalSw
            knob.Position = goalKnob
            knob.BackgroundColor3 = on and Color3.new(1,1,1) or Theme.textDim
        end
    end
    apply(false)

    local hit = new("TextButton", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
    }, row)
    hit.MouseButton1Click:Connect(function()
        on = not on
        apply(true)
        if opts.callback then task.spawn(opts.callback, on) end
    end)
    return { set = function(v) on = v; apply(true) end, get = function() return on end }
end

function Widgets.slider(parent, opts)
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 44),
        BackgroundColor3 = Theme.bg2,
        BorderSizePixel = 0,
    }, parent)
    corner(row, 6)

    new("TextLabel", {
        Size = UDim2.new(1, -100, 0, 18),
        Position = UDim2.new(0, 12, 0, 4),
        BackgroundTransparency = 1,
        Text = opts.text,
        TextColor3 = Theme.text,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)

    local valLbl = new("TextLabel", {
        Size = UDim2.new(0, 80, 0, 18),
        Position = UDim2.new(1, -92, 0, 4),
        BackgroundTransparency = 1,
        Text = tostring(opts.default),
        TextColor3 = Theme.accent2,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, row)

    local bar = new("Frame", {
        Size = UDim2.new(1, -24, 0, 6),
        Position = UDim2.new(0, 12, 0, 30),
        BackgroundColor3 = Theme.bg3,
        BorderSizePixel = 0,
    }, row)
    corner(bar, 3)
    local fill = new("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = Theme.accent,
        BorderSizePixel = 0,
    }, bar)
    corner(fill, 3)
    local knob = new("Frame", {
        Size = UDim2.new(0, 12, 0, 12),
        Position = UDim2.new(0, -6, 0.5, -6),
        BackgroundColor3 = Color3.new(1,1,1),
        BorderSizePixel = 0,
        ZIndex = 2,
    }, fill)
    corner(knob, 6)

    local value = opts.default or 0
    local min, max = opts.min or 0, opts.max or 100
    local function setVal(v, fire)
        v = math.clamp(v, min, max)
        value = v
        local pct = (v - min) / (max - min)
        fill.Size = UDim2.new(pct, 0, 1, 0)
        valLbl.Text = opts.format and opts.format(v) or tostring(math.floor(v))
        if fire and opts.callback then task.spawn(opts.callback, v) end
    end
    setVal(value, false)

    local dragging = false
    local function updateFromPos(x)
        local abs = bar.AbsolutePosition.X
        local size = bar.AbsoluteSize.X
        local pct = math.clamp((x - abs) / size, 0, 1)
        setVal(min + pct * (max - min), true)
    end
    bar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true; updateFromPos(i.Position.X)
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
            updateFromPos(i.Position.X)
        end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
    return { set = function(v) setVal(v, true) end, get = function() return value end }
end

function Widgets.dropdown(parent, opts)
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = Theme.bg2,
        BorderSizePixel = 0,
        ClipsDescendants = true,
    }, parent)
    corner(row, 6)

    new("TextLabel", {
        Size = UDim2.new(1, -100, 0, 34),
        Position = UDim2.new(0, 12, 0, 0),
        BackgroundTransparency = 1,
        Text = opts.text,
        TextColor3 = Theme.text,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)

    local current = new("TextLabel", {
        Size = UDim2.new(0, 130, 0, 22),
        Position = UDim2.new(1, -142, 0, 6),
        BackgroundColor3 = Theme.bg3,
        Text = "  " .. tostring(opts.default or opts.options[1]),
        TextColor3 = Theme.text,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    corner(current, 4)

    local optionsList = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        Position = UDim2.new(0, 0, 0, 38),
        BackgroundTransparency = 1,
    }, row)
    local optLayout = new("UIListLayout", { Padding = UDim.new(0, 3) }, optionsList)

    local expanded = false
    local buttons = {}
    for _, opt in ipairs(opts.options) do
        local b = new("TextButton", {
            Size = UDim2.new(1, 0, 0, 24),
            BackgroundColor3 = Theme.bg3,
            Text = "  " .. tostring(opt),
            TextColor3 = Theme.text,
            Font = Enum.Font.Gotham,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
            AutoButtonColor = false,
        }, optionsList)
        corner(b, 4)
        table.insert(buttons, b)
        b.MouseButton1Click:Connect(function()
            current.Text = "  " .. tostring(opt)
            expanded = false
            row.Size = UDim2.new(1, 0, 0, 34)
            if opts.callback then task.spawn(opts.callback, opt) end
        end)
    end

    current.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            expanded = not expanded
            local target = expanded and (38 + #opts.options * 27 + 4) or 34
            Tween:Create(row, TweenInfo.new(0.18), { Size = UDim2.new(1, 0, 0, target) }):Play()
        end
    end)
    return { get = function() return current.Text:sub(3) end }
end

function Widgets.button(parent, opts)
    local btn = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = opts.color or Theme.accent,
        Text = opts.text,
        TextColor3 = Color3.new(1,1,1),
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        AutoButtonColor = false,
    }, parent)
    corner(btn, 6)
    btn.MouseButton1Click:Connect(function()
        if opts.callback then task.spawn(opts.callback) end
    end)
    return btn
end

function Widgets.label(parent, text, color)
    return new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = color or Theme.textDim,
        Font = Enum.Font.Code,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, parent)
end

-- ============================================================
-- NOTIFICAÇÃO TOAST
-- ============================================================
local notifHolder = new("Frame", {
    Size = UDim2.new(0, 260, 0, 0),
    Position = UDim2.new(1, -280, 0, 60),
    BackgroundTransparency = 1,
}, gui)
local notifLayout = new("UIListLayout", { Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Top }, notifHolder)

local function notify(title, text, dur)
    if not Config.NOTIFY then return end
    dur = dur or 3
    local n = new("Frame", {
        Size = UDim2.new(1, 0, 0, 56),
        BackgroundColor3 = Theme.bg2,
        BorderSizePixel = 0,
    }, notifHolder)
    corner(n, 6); stroke(n, Theme.accent, 1)

    local accent = new("Frame", {
        Size = UDim2.new(0, 4, 1, 0),
        BackgroundColor3 = Theme.accent,
        BorderSizePixel = 0,
    }, n)
    corner(accent, 6)

    new("TextLabel", {
        Size = UDim2.new(1, -16, 0, 18),
        Position = UDim2.new(0, 12, 0, 6),
        BackgroundTransparency = 1,
        Text = title,
        TextColor3 = Theme.text,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, n)
    new("TextLabel", {
        Size = UDim2.new(1, -16, 0, 28),
        Position = UDim2.new(0, 12, 0, 24),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = Theme.textDim,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, n)

    task.delay(dur, function()
        if n and n.Parent then
            Tween:Create(n, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
            task.wait(0.3)
            n:Destroy()
        end
    end)
end

-- ============================================================
-- LÓGICA DE ROUBO
-- ============================================================
local StealRemote
local function findStealRemote()
    local exact = RS:FindFirstChild(Config.REMOTE_NAME, true)
    if exact and exact:IsA("RemoteEvent") then return exact end
    for _, d in ipairs(RS:GetDescendants()) do
        if d:IsA("RemoteEvent") then
            local n = d.Name:lower()
            if n:find("steal") or n:find("roub") or n:find("take") then
                return d
            end
        end
    end
    return nil
end
StealRemote = findStealRemote()

local function scrapeEggs()
    local folder = RS:FindFirstChild(Config.EGG_FOLDER, true)
    if not folder then return {} end
    local out = {}
    for _, child in ipairs(folder:GetChildren()) do
        local rarity = child:GetAttribute("Rarity")
        local value  = child:GetAttribute("Value") or child:GetAttribute("Price") or child:GetAttribute("Worth")
        if rarity or value then
            table.insert(out, {
                id = child.Name, name = child.Name,
                rarity = rarity or "common",
                value = tonumber(value) or 0, ref = child,
            })
        end
    end
    return out
end

local function scoreEgg(egg)
    local w 
