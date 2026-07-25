--[[
    AXUI Boot · v1.0
    Terminal-style loading screen with executor detection

    Usage:
        local Boot = loadstring(game:HttpGet("url/Boot.lua"))()
        Boot.Run({
            title = "MY SCRIPT",
            subtitle = "SYSTEM INIT",
        }, function(info)
            -- info.executor, info.hookReady, info.drawReady, etc.
            loadstring(game:HttpGet("url/main.lua"))()
        end)
]]

local Boot = {}

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService      = game:GetService("HttpService")
local Workspace        = game:GetService("Workspace")
local LocalPlayer      = Players.LocalPlayer
local Camera           = Workspace.CurrentCamera

-- ═══════════════════════════════════════════════
-- EXECUTOR DETECTION
-- ═══════════════════════════════════════════════
local function detectExecutor()
    local idOk, idResult = pcall(function()
        if identifyexecutor then return identifyexecutor() end
        return nil
    end)
    if idOk and idResult and idResult ~= "" then return idResult end

    local checks = {
        { "Synapse X",   function() return syn and syn.protect_gui end },
        { "Synapse Z",   function() return syn and not syn.protect_gui end },
        { "Script-Ware", function() return identifyexecutor and identifyexecutor():find("Script%-Ware") end },
        { "Fluxus",      function() return fluxus and fluxus.queue_on_teleport end },
        { "KRNL",        function() return KRNL_LOADED or krnl end },
        { "Solara",      function() return identifyexecutor and identifyexecutor():find("Solara") end },
        { "JJSploit",    function() return identifyexecutor and identifyexecutor():find("JJSploit") end },
        { "Electron",    function() return identifyexecutor and identifyexecutor():find("Electron") end },
        { "Arceus X",    function() return identifyexecutor and identifyexecutor():find("Arceus") end },
        { "Hydrogen",    function() return identifyexecutor and identifyexecutor():find("Hydrogen") end },
        { "Codex",       function() return identifyexecutor and identifyexecutor():find("Codex") end },
        { "Delta",       function() return identifyexecutor and identifyexecutor():find("Delta") end },
        { "Vegax",       function() return identifyexecutor and identifyexecutor():find("Vegax") end },
        { "Wave",        function() return identifyexecutor and identifyexecutor():find("Wave") end },
        { "Zorara",      function() return identifyexecutor and identifyexecutor():find("Zorara") end },
    }
    for _, c in ipairs(checks) do
        local ok, r = pcall(c[2])
        if ok and r then return c[1] end
    end
    return "Unknown"
end

-- ═══════════════════════════════════════════════
-- CAPABILITY SCAN
-- ═══════════════════════════════════════════════
local function scanCapabilities()
    local caps = {}
    local function check(name, fn)
        local ok, result = pcall(fn)
        table.insert(caps, { name = name, available = ok and result and true or false })
    end
    check("hookmetamethod",        function() return hookmetamethod ~= nil end)
    check("getrawmetatable",       function() return getrawmetatable ~= nil end)
    check("newcclosure",           function() return newcclosure ~= nil end)
    check("getnamecallmethod",     function() return getnamecallmethod ~= nil end)
    check("Drawing API",           function() return Drawing and Drawing.new and true end)
    check("setreadonly",           function() return setreadonly ~= nil or make_writeable ~= nil end)
    check("gethui",                function() return gethui ~= nil end)
    check("firetouchinterest",     function() return firetouchinterest ~= nil end)
    check("queue_on_teleport",     function() return queue_on_teleport ~= nil or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport) end)
    check("setclipboard",          function() return setclipboard ~= nil end)
    check("isfolder / makefolder", function() return isfolder ~= nil and makefolder ~= nil end)
    check("readfile / writefile",  function() return readfile ~= nil and writefile ~= nil end)
    check("HttpGet",               function() return game.HttpGet ~= nil end)
    check("getgenv",               function() return getgenv ~= nil end)
    check("VirtualInputManager",   function() return game:GetService("VirtualInputManager") ~= nil end)
    return caps
end

-- ═══════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════
local function new(class, props, parent)
    local obj = Instance.new(class)
    for k, v in pairs(props) do
        if k ~= "Parent" then
            if k == "AutomaticSize" or k == "AutomaticCanvasSize" then
                pcall(function() obj[k] = v end)
            else obj[k] = v end
        end
    end
    obj.Parent = props.Parent or parent
    return obj
end

local function tween(obj, time, props)
    if not obj or not obj.Parent then return end
    pcall(function()
        TweenService:Create(obj, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
    end)
end

-- ═══════════════════════════════════════════════
-- Boot.Run(config, onComplete)
--
-- config (all optional):
--   title          = "LOADING"         -- main title (RichText ok)
--   subtitle       = "INITIALIZING"    -- below title
--   buildText      = "v1.0"            -- top right
--   credits        = ""                -- bottom center (empty = hidden)
--   accentColor    = Color3 green      -- main accent
--   bgColor        = Color3 dark       -- background
--   panelColor     = Color3 dark green -- center panel
--   showScanlines  = true              -- CRT effect
--   showCorners    = true              -- corner "+" markers
--   logPrefix      = "boot loader"     -- first log line
--   launchText     = "launching..."    -- final log
--   completedText  = "BOOT COMPLETE"   -- completion message
-- ═══════════════════════════════════════════════
function Boot.Run(config, onComplete)
    -- handle Boot.Run(callback) shorthand
    if type(config) == "function" then
        onComplete = config; config = {}
    end
    config = config or {}

    -- theme
    local ACCENT     = config.accentColor or Color3.fromRGB(57, 255, 20)
    local ACCENT_DIM = Color3.fromRGB(
        math.floor(ACCENT.R * 130), math.floor(ACCENT.G * 130), math.floor(ACCENT.B * 130))
    local ACCENT_FAINT = Color3.fromRGB(
        math.floor(ACCENT.R * 75), math.floor(ACCENT.G * 75), math.floor(ACCENT.B * 75))
    local BG_DARK    = config.bgColor or Color3.fromRGB(5, 8, 6)
    local BG_PANEL   = config.panelColor or Color3.fromRGB(8, 14, 10)
    local TEXT_DIM   = Color3.fromRGB(80, 120, 85)
    local TEXT_FAINT = Color3.fromRGB(40, 60, 42)
    local FONT       = Enum.Font.Code

    -- text config
    local TITLE         = config.title or "LOADING"
    local SUBTITLE      = config.subtitle or "SYSTEM INITIALIZATION"
    local BUILD_TEXT    = config.buildText or "v1.0"
    local CREDITS       = config.credits or ""
    local LOG_PREFIX    = config.logPrefix or "boot loader"
    local LAUNCH_TEXT   = config.launchText or "launching..."
    local COMPLETE_TEXT = config.completedText or "BOOT COMPLETE"
    local SHOW_SCANLINES = config.showScanlines ~= false
    local SHOW_CORNERS   = config.showCorners ~= false

    -- hex helpers for RichText
    local function toHex(c) return string.format("#%02x%02x%02x", math.floor(c.R*255), math.floor(c.G*255), math.floor(c.B*255)) end
    local accentHex = toHex(ACCENT)
    local dimHex    = toHex(TEXT_DIM)
    local faintHex  = toHex(TEXT_FAINT)
    local function colorWrap(text, hex) return '<font color="' .. hex .. '">' .. text .. '</font>' end
    local function greenText(t) return colorWrap(t, accentHex) end
    local function dimText(t)   return colorWrap(t, dimHex) end
    local function yellowText(t) return colorWrap(t, "#ffc83c") end
    local function redText(t)   return colorWrap(t, "#ff3c3c") end
    local function cyanText(t)  return colorWrap(t, "#00e5ff") end

    -- screen gui
    local screenGui = new("ScreenGui", {
        Name = "AXUIBoot",
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        IgnoreGuiInset = true,
        DisplayOrder = 999,
    })
    local parentTo
    pcall(function() parentTo = (gethui or function() end)() end)
    if not parentTo then pcall(function() if syn and syn.protect_gui then syn.protect_gui(screenGui) end; parentTo = game:GetService("CoreGui") end) end
    if not parentTo then parentTo = LocalPlayer:WaitForChild("PlayerGui", 5) end
    screenGui.Parent = parentTo or LocalPlayer:FindFirstChildOfClass("PlayerGui")

    -- full screen overlay
    local overlay = new("Frame", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = BG_DARK,
        BorderSizePixel = 0, ZIndex = 1,
        Parent = screenGui,
    })

    -- scanlines
    if SHOW_SCANLINES then
        local sl = new("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, ZIndex = 2, ClipsDescendants = true, Parent = overlay })
        for i = 0, 40 do
            new("Frame", {
                Position = UDim2.new(0, 0, 0, i * 24),
                Size = UDim2.new(1, 0, 0, 1),
                BackgroundColor3 = ACCENT,
                BackgroundTransparency = 0.95,
                BorderSizePixel = 0, ZIndex = 2, Parent = sl,
            })
        end
    end

    -- center panel
    local panel = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0, 520, 0, 420),
        BackgroundColor3 = BG_PANEL,
        BackgroundTransparency = 0.15,
        BorderSizePixel = 0, ZIndex = 3,
        Parent = overlay,
    })
    new("UICorner", { CornerRadius = UDim.new(0, 12) }, panel)
    new("UIStroke", { Color = ACCENT, Thickness = 1, Transparency = 0.6, Parent = panel })
    new("UIPadding", {
        PaddingLeft = UDim.new(0, 24), PaddingRight = UDim.new(0, 24),
        PaddingTop = UDim.new(0, 20), PaddingBottom = UDim.new(0, 20),
        Parent = panel,
    })

    -- title
    new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 22),
        BackgroundTransparency = 1, RichText = true,
        Text = TITLE, TextColor3 = ACCENT,
        TextSize = 22, Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 5, Parent = panel,
    })
    new("TextLabel", {
        Position = UDim2.new(0, 0, 0, 26),
        Size = UDim2.new(1, 0, 0, 14),
        BackgroundTransparency = 1,
        Text = SUBTITLE, TextColor3 = TEXT_DIM,
        TextSize = 10, Font = FONT,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 5, Parent = panel,
    })

    -- build info (top right)
    if BUILD_TEXT ~= "" then
        new("TextLabel", {
            AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
            Size = UDim2.new(0, 100, 0, 14), BackgroundTransparency = 1,
            Text = BUILD_TEXT, TextColor3 = ACCENT_DIM,
            TextSize = 9, Font = FONT, TextXAlignment = Enum.TextXAlignment.Right,
            ZIndex = 5, Parent = panel,
        })
    end
    new("TextLabel", {
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 14),
        Size = UDim2.new(0, 100, 0, 14), BackgroundTransparency = 1,
        Text = os.date("%Y.%m.%d"), TextColor3 = TEXT_FAINT,
        TextSize = 9, Font = FONT, TextXAlignment = Enum.TextXAlignment.Right,
        ZIndex = 5, Parent = panel,
    })

    -- divider
    new("Frame", {
        Position = UDim2.new(0, 0, 0, 54),
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = ACCENT, BackgroundTransparency = 0.7,
        BorderSizePixel = 0, ZIndex = 4, Parent = panel,
    })

    -- terminal log area
    local logFrame = new("ScrollingFrame", {
        Position = UDim2.new(0, 0, 0, 62),
        Size = UDim2.new(1, 0, 0, 220),
        BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 2, ScrollBarImageColor3 = ACCENT_DIM,
        ScrollBarImageTransparency = 0.5,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ZIndex = 4, Parent = panel,
    })
    local logLayout = new("UIListLayout", {
        Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = logFrame,
    })

    local logOrder = 0
    local function addLog(text, color, prefix)
        logOrder = logOrder + 1
        color = color or ACCENT_DIM; prefix = prefix or ">"
        new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1, RichText = true,
            Text = colorWrap(prefix, faintHex) .. " " .. text,
            TextColor3 = color, TextSize = 10, Font = FONT,
            TextXAlignment = Enum.TextXAlignment.Left,
            LayoutOrder = logOrder, ZIndex = 5, Parent = logFrame,
        })
        pcall(function() logFrame.CanvasPosition = Vector2.new(0, logLayout.AbsoluteContentSize.Y) end)
    end

    -- progress bar
    local progressFrame = new("Frame", {
        Position = UDim2.new(0, 0, 0, 292), Size = UDim2.new(1, 0, 0, 6),
        BackgroundColor3 = Color3.fromRGB(15, 25, 18),
        BorderSizePixel = 0, ZIndex = 4, Parent = panel,
    })
    new("UICorner", { CornerRadius = UDim.new(0, 3) }, progressFrame)
    new("UIStroke", { Color = ACCENT_FAINT, Thickness = 1, Transparency = 0.5, Parent = progressFrame })

    local progressFill = new("Frame", {
        Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = ACCENT,
        BackgroundTransparency = 0.3, BorderSizePixel = 0,
        ZIndex = 5, Parent = progressFrame,
    })
    new("UICorner", { CornerRadius = UDim.new(0, 3) }, progressFill)
    new("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(0.5, 0),
            NumberSequenceKeypoint.new(1, 0.5),
        }), Parent = progressFill,
    })

    local progressLabel = new("TextLabel", {
        Position = UDim2.new(0, 0, 0, 302), Size = UDim2.new(1, 0, 0, 14),
        BackgroundTransparency = 1, Text = "INITIALIZING...",
        TextColor3 = ACCENT_DIM, TextSize = 9, Font = FONT,
        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5, Parent = panel,
    })
    local progressPct = new("TextLabel", {
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 302),
        Size = UDim2.new(0, 40, 0, 14), BackgroundTransparency = 1,
        Text = "0%", TextColor3 = ACCENT, TextSize = 9, Font = FONT,
        TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5, Parent = panel,
    })

    -- info bar
    local infoBar = new("Frame", {
        Position = UDim2.new(0, 0, 0, 326), Size = UDim2.new(1, 0, 0, 42),
        BackgroundColor3 = BG_DARK, BackgroundTransparency = 0.5,
        BorderSizePixel = 0, ZIndex = 4, Parent = panel,
    })
    new("UICorner", { CornerRadius = UDim.new(0, 6) }, infoBar)
    new("UIPadding", {
        PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
        PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), Parent = infoBar,
    })
    local infoLeft = new("TextLabel", {
        Size = UDim2.new(0.5, 0, 1, 0), BackgroundTransparency = 1, RichText = true,
        Text = "...", TextColor3 = TEXT_DIM, TextSize = 9, Font = FONT,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
        ZIndex = 5, Parent = infoBar,
    })
    local infoRight = new("TextLabel", {
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.new(0.5, 0, 1, 0), BackgroundTransparency = 1, RichText = true,
        Text = "...", TextColor3 = TEXT_DIM, TextSize = 9, Font = FONT,
        TextXAlignment = Enum.TextXAlignment.Right, TextYAlignment = Enum.TextYAlignment.Top,
        ZIndex = 5, Parent = infoBar,
    })

    -- corner markers
    if SHOW_CORNERS then
        for _, c in ipairs({
            { UDim2.new(0,8,0,8), Vector2.new(0,0) },
            { UDim2.new(1,-8,0,8), Vector2.new(1,0) },
            { UDim2.new(0,8,1,-8), Vector2.new(0,1) },
            { UDim2.new(1,-8,1,-8), Vector2.new(1,1) },
        }) do
            new("TextLabel", {
                AnchorPoint = c[2], Position = c[1],
                Size = UDim2.new(0, 12, 0, 12), BackgroundTransparency = 1,
                Text = "+", TextColor3 = ACCENT_FAINT,
                TextSize = 12, Font = FONT, ZIndex = 3, Parent = overlay,
            })
        end
    end

    -- credits
    if CREDITS ~= "" then
        new("TextLabel", {
            AnchorPoint = Vector2.new(0.5, 1),
            Position = UDim2.new(0.5, 0, 1, -12),
            Size = UDim2.new(0, 300, 0, 14), BackgroundTransparency = 1,
            Text = CREDITS, TextColor3 = TEXT_FAINT,
            TextSize = 9, Font = FONT, ZIndex = 3, Parent = overlay,
        })
    end

    -- progress helper
    local function setProgress(pct, text)
        tween(progressFill, 0.3, { Size = UDim2.new(pct / 100, 0, 1, 0) })
        progressPct.Text = math.floor(pct) .. "%"
        if text then progressLabel.Text = text end
    end

    -- ═══════════════════════════════════════════════
    -- BOOT SEQUENCE
    -- ═══════════════════════════════════════════════
    task.spawn(function()
        setProgress(0, "STARTING BOOT SEQUENCE...")
        task.wait(0.3)
        addLog(LOG_PREFIX .. " v1.0", ACCENT_DIM, "[*]")
        task.wait(0.15)
        addLog("initializing system scan...", TEXT_DIM, "[*]")
        task.wait(0.2)

        -- executor detection
        setProgress(10, "DETECTING EXECUTOR...")
        task.wait(0.3)
        addLog("probing executor environment...", TEXT_DIM, "[>]")
        task.wait(0.4)
        local executor = detectExecutor()
        if executor == "Unknown" then
            addLog("executor: " .. redText("UNKNOWN") .. " " .. dimText("(limited features)"), Color3.fromRGB(255, 200, 60), "[!]")
        else
            addLog("executor: " .. greenText(executor) .. " " .. dimText("detected"), ACCENT, "[+]")
        end
        task.wait(0.2)

        -- capability scan
        setProgress(25, "SCANNING CAPABILITIES...")
        task.wait(0.2)
        addLog("running capability scan...", TEXT_DIM, "[>]")
        task.wait(0.3)
        local caps = scanCapabilities()
        local available, missing = 0, 0
        for i, cap in ipairs(caps) do
            if cap.available then
                available = available + 1
                addLog("  " .. greenText("[OK]") .. "  " .. cap.name, ACCENT_DIM, " ")
            else
                missing = missing + 1
                addLog("  " .. redText("[--]") .. "  " .. cap.name, TEXT_DIM, " ")
            end
            task.wait(0.06)
            setProgress(25 + (45 * i / #caps))
        end
        task.wait(0.2)
        addLog(string.format("scan complete: %s available, %s missing",
            greenText(tostring(available)),
            missing > 0 and yellowText(tostring(missing)) or dimText("0")),
            ACCENT_DIM, "[*]")
        task.wait(0.2)

        -- environment info
        setProgress(75, "READING ENVIRONMENT...")
        task.wait(0.2)
        addLog("", TEXT_DIM, " ")
        addLog("gathering environment data...", TEXT_DIM, "[>]")
        task.wait(0.2)
        local playerName = LocalPlayer.DisplayName .. " (" .. LocalPlayer.Name .. ")"
        local gameId = tostring(game.PlaceId)
        local serverId = tostring(game.JobId):sub(1, 12) .. "..."
        local playerCount = #Players:GetPlayers()
        local maxPlayers = Players.MaxPlayers

        addLog("player:  " .. cyanText(playerName), ACCENT_DIM, "[i]"); task.wait(0.1)
        addLog("game:    " .. cyanText(gameId), ACCENT_DIM, "[i]"); task.wait(0.1)
        addLog("server:  " .. dimText(serverId), ACCENT_DIM, "[i]"); task.wait(0.1)
        addLog("players: " .. cyanText(tostring(playerCount)) .. dimText("/" .. tostring(maxPlayers)), ACCENT_DIM, "[i]"); task.wait(0.1)

        -- FPS estimate
        local frames = 0; local t0 = tick()
        local conn = RunService.RenderStepped:Connect(function() frames = frames + 1 end)
        task.wait(0.5); conn:Disconnect()
        local estFPS = math.floor(frames / (tick() - t0))
        addLog("fps:     " .. (estFPS >= 30 and greenText(tostring(estFPS)) or yellowText(tostring(estFPS))), ACCENT_DIM, "[i]"); task.wait(0.1)

        local ping = 0
        pcall(function() ping = math.floor(LocalPlayer:GetNetworkPing() * 1000) end)
        addLog("ping:    " .. (ping < 100 and greenText(tostring(ping) .. "ms") or yellowText(tostring(ping) .. "ms")), ACCENT_DIM, "[i]"); task.wait(0.1)

        infoLeft.Text = string.format(
            '<font color="%s">%s</font>\n<font color="%s">Place %s · %d/%d players</font>',
            accentHex, executor, dimHex, gameId, playerCount, maxPlayers)
        infoRight.Text = string.format(
            '<font color="%s">%d FPS</font> · <font color="%s">%dms</font>\n<font color="%s">%d/%d capabilities</font>',
            accentHex, estFPS, dimHex, ping, dimHex, available, available + missing)

        setProgress(90, "PREPARING PAYLOAD...")
        task.wait(0.3)

        -- critical system checks
        local hookReady = false
        pcall(function() hookReady = hookmetamethod and getrawmetatable and newcclosure and true end)
        addLog("namecall hook: " .. (hookReady and greenText("READY") or (yellowText("UNAVAILABLE") .. " " .. dimText("(limited)"))), hookReady and ACCENT or Color3.fromRGB(255, 200, 60), hookReady and "[+]" or "[!]"); task.wait(0.15)

        local drawReady = false
        pcall(function() drawReady = Drawing and Drawing.new and true end)
        addLog("drawing API:   " .. (drawReady and greenText("READY") or (yellowText("UNAVAILABLE") .. " " .. dimText("(limited)"))), drawReady and ACCENT or Color3.fromRGB(255, 200, 60), drawReady and "[+]" or "[!]"); task.wait(0.15)

        setProgress(100, COMPLETE_TEXT)
        task.wait(0.2)
        addLog("", TEXT_DIM, " ")
        addLog(greenText(COMPLETE_TEXT), ACCENT, "[*]")
        addLog(LAUNCH_TEXT, ACCENT_DIM, "[>]")
        task.wait(0.6)

        -- fade out with flash
        local flash = new("Frame", {
            Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = ACCENT,
            BackgroundTransparency = 1, ZIndex = 10, Parent = screenGui,
        })
        tween(flash, 0.15, { BackgroundTransparency = 0.85 }); task.wait(0.15)
        tween(flash, 0.4, { BackgroundTransparency = 1 })
        tween(panel, 0.5, { BackgroundTransparency = 1 })
        tween(overlay, 0.6, { BackgroundTransparency = 1 })
        for _, desc in ipairs(screenGui:GetDescendants()) do
            if desc:IsA("TextLabel") or desc:IsA("TextBox") then tween(desc, 0.4, { TextTransparency = 1 })
            elseif desc:IsA("Frame") then tween(desc, 0.4, { BackgroundTransparency = 1 })
            elseif desc:IsA("UIStroke") then tween(desc, 0.4, { Transparency = 1 }) end
        end
        task.wait(0.7)
        if screenGui and screenGui.Parent then screenGui:Destroy() end

        if onComplete then
            pcall(onComplete, {
                executor = executor, capabilities = caps,
                available = available, missing = missing,
                hookReady = hookReady, drawReady = drawReady,
                fps = estFPS, ping = ping,
            })
        end
    end)
end

return Boot
