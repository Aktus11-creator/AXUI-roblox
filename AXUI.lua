--[[
    AXUI · v1.1
    UI library for Roblox executor scripts

    ═══════════════════════════════════════════════
    CHANGELOG (v1.0 -> v1.1)
    ═══════════════════════════════════════════════

        - Fixed row labels colliding with slider/dropdown/keybind/etc. controls
          on narrow windows (labels now reserve fixed space per control type
          instead of a flat 0.6 scale width)
        - Fixed window corners rendering square despite UICorner on the outer
          frame (header/sidebar/content now round only their true outer corner
          and stay square on interior seams)
        - Fixed group subcategory headers (e.g. "AIMBOT", "ESP") disappearing
          during search even when rows inside them matched
        - Removed tab sidebar badges (enabled-feature count per tab)
        - Fixed features continuing to run after unload/close — unload now
          turns every toggle off first, same as panic does
        - Fixed toggles not re-coloring after SetAccent() until manually
          re-toggled (added a refreshTheme hook, wired into SetAccent)
        - Smoothed toast animations: synced fade + slide with Quint easing
          on entrance/exit, instead of an instant-appear + linear slide
        - Added named config profiles: SaveConfig(name?)/LoadConfig(name?)/
          ListConfigs()/DeleteConfig(name), stored under configFolder/profiles/
          with a manifest index; omitting name keeps the original single-file
          behavior
        - Reworked theme refresh into an accent-bound registry (bindAccent()/
          accentStroke()) covering every unconditionally-accent-colored element
          (rows, sliders, dropdowns, keybinds, header/sidebar/search chrome,
          etc.), not just toggles — SetAccent() now updates all of it live
        - Fixed window dragging having no bounds check; it's now clamped to
          the screen so it can't be dragged fully off-screen
        - Search now checks every tab, not just the active one, and shows
          "TAB · GROUP" context on cross-tab matches; switching tabs while
          searching clears the search box first
        - Added collapsible groups (accordion): click a group header to
          collapse/expand it (chevron indicator); a search auto-expands
          matches without losing the user's manual collapse preference
        - Refined toast slide: Position now eases on Back/Out (slight
          overshoot-and-settle) separately from the Quint/Out fade, with more
          travel distance, so it reads as a deliberate slide-in

    ═══════════════════════════════════════════════
    QUICK START
    ═══════════════════════════════════════════════

        local AXUI = loadstring(game:HttpGet("url/AXUI.lua"))()
        local window = AXUI:CreateWindow({ title = "My Menu" })
        local tab   = window:Tab("AIM", "🎯")
        local group = tab:Group("Aimbot")
        group:Toggle("Enabled", "Aimbot", false, function(v) end)

    ═══════════════════════════════════════════════
    FULL CONFIG (all optional)
    ═══════════════════════════════════════════════

        AXUI:CreateWindow({
            -- window
            title         = "My Menu",       -- RichText supported
            subtitle      = "by You",        -- below title (set "" to hide)
            version       = "v1.0",          -- version pill (set "" to hide pill)
            accent        = "Green",         -- preset name or Color3
            width         = 842,
            height        = 580,

            -- header elements (set false to hide entirely)
            logoText      = "X",             -- text inside logo square
            showFPS       = true,            -- FPS/ping readout
            showConnected = true,            -- pulsing dot + "CONNECTED"
            connectedText = "CONNECTED",     -- custom connected text
            showOnline    = true,            -- online pill
            onlineText    = nil,             -- nil = auto "ONLINE · 247", or custom string

            -- sidebar
            sidebarLabel  = "CATEGORIES",    -- top of sidebar (set "" to hide)
            panicText     = "PANIC",         -- panic button text (set "" to hide button)
            panicIcon     = "⚠",             -- emoji before panic text
            hintText      = "",              -- below panic button

            -- search
            searchPlaceholder = "Search features…",

            -- keybinds
            menuKey       = "RightShift",
            panicKey      = "Insert",
            screenshotKey = "F8",

            -- toasts
            toastOnLoad   = true,            -- show "loaded" toast
            loadToastText = nil,             -- nil = auto "{title} loaded · Press {key}"
            panicToastText= "All features disabled",

            -- config persistence
            configFolder  = "AXUI_Config",
            configFile    = "config.json",
        })

    ═══════════════════════════════════════════════
    CONTROLS
    ═══════════════════════════════════════════════

        group:Toggle(id, label, default, callback, subText?)
        group:Slider(id, label, {min, max, step?, default, unit?, decimals?}, callback)
        group:Dropdown(id, label, options, default, callback)
        group:Button(id, label, buttonText, isDanger?, callback, confirm?)
        group:Keybind(id, label, defaultKey, callback)
        group:ColorPicker(id, label, defaultColor3, callback, subText?)
        group:TextInput(id, label, default, placeholder?, callback)
        group:Separator()
        group:Label(id?, text, color?)

    ═══════════════════════════════════════════════
    WINDOW API
    ═══════════════════════════════════════════════

        window:Tab(name, icon)          -- create a sidebar tab
        window:Toast(message, isDanger?)
        window:SetVisible(bool)
        window:IsVisible() -> bool
        window:SetAccent(colorOrName)
        window:SaveConfig()
        window:LoadConfig()
        window:OnPanic(callback)
        window:OnUnload(callback)
        window:SwitchTab(name)
        window:Destroy()

        window.State                    -- { id = value }
        window.Controls                 -- { id = {getValue, setValue, type, row} }
        window.Theme                    -- live theme color table
        window.FPSLabel                 -- header FPS label instance
        window.WindowScale              -- UIScale instance

]]

local AXUI = {}

-- ═══════════════════════════════════════════════
-- SERVICES
-- ═══════════════════════════════════════════════
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local HttpService      = game:GetService("HttpService")
local Stats            = game:GetService("Stats")
local GuiService       = game:GetService("GuiService")
local LocalPlayer      = Players.LocalPlayer
local Camera           = game:GetService("Workspace").CurrentCamera

-- ═══════════════════════════════════════════════
-- ACCENT PRESETS
-- ═══════════════════════════════════════════════
local ACCENT_PRESETS = {
    Green   = Color3.fromRGB(57, 255, 20),
    Cyan    = Color3.fromRGB(0, 229, 255),
    Magenta = Color3.fromRGB(255, 45, 212),
    Red     = Color3.fromRGB(255, 59, 59),
    Orange  = Color3.fromRGB(255, 138, 0),
}
AXUI.ACCENT_PRESETS = ACCENT_PRESETS

-- ═══════════════════════════════════════════════
-- SHARED HELPERS
-- ═══════════════════════════════════════════════
local FONT = Enum.Font.Code

local function new(class, props, parent)
    local obj = Instance.new(class)
    for k, v in pairs(props) do
        if k ~= "Parent" then
            if k == "AutomaticSize" or k == "AutomaticCanvasSize" or k == "TextTruncate" then
                pcall(function() obj[k] = v end)
            else
                obj[k] = v
            end
        end
    end
    obj.Parent = props.Parent or parent
    return obj
end

local function corner(obj, radius)
    return new("UICorner", { CornerRadius = UDim.new(0, radius), Parent = obj })
end

local function stroke(obj, color, thickness, transparency)
    return new("UIStroke", {
        Color = color,
        Thickness = thickness or 1,
        Transparency = transparency or 0.78,
        Parent = obj,
    })
end

-- Rounds ALL 4 corners of `obj` with the given radius, then patches over the
-- corners listed in `squareCorners` (each: "TopLeft"/"TopRight"/"BottomLeft"/"BottomRight")
-- with a small solid square in `patchColor`. Use this for panels that sit flush against
-- an outer rounded window on some edges but butt up against sibling panels on others —
-- e.g. a header that should be rounded on top but square on the bottom where the
-- sidebar/content begin. Without this, ClipsDescendants only clips to a rectangle;
-- it does NOT mask children to the rounded shape, so square-cornered sibling frames
-- drawn flush to the window edge visually square off what should be a rounded corner.
local function squareCorners(obj, radius, patchColor, squareCornerList)
    corner(obj, radius)
    local ANCHORS = {
        TopLeft     = { Vector2.new(0, 0), UDim2.new(0, 0, 0, 0) },
        TopRight    = { Vector2.new(1, 0), UDim2.new(1, 0, 0, 0) },
        BottomLeft  = { Vector2.new(0, 1), UDim2.new(0, 0, 1, 0) },
        BottomRight = { Vector2.new(1, 1), UDim2.new(1, 0, 1, 0) },
    }
    for _, key in ipairs(squareCornerList) do
        local a = ANCHORS[key]
        if a then
            new("Frame", {
                AnchorPoint = a[1],
                Position = a[2],
                Size = UDim2.new(0, radius, 0, radius),
                BackgroundColor3 = patchColor,
                BorderSizePixel = 0,
                ZIndex = (obj.ZIndex or 1),
                Parent = obj,
            })
        end
    end
end

local function tweenObj(obj, time, props, style, dir)
    if not obj or not obj.Parent then return nil end
    local ok, t = pcall(function()
        local ti = TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
        local tw = TweenService:Create(obj, ti, props)
        tw:Play()
        return tw
    end)
    return ok and t or nil
end

local HAS_AUTOSIZE = pcall(function()
    local t = Instance.new("Frame"); t.AutomaticSize = Enum.AutomaticSize.Y; t:Destroy()
end)

-- ═══════════════════════════════════════════════
-- COLOR HELPERS (for ColorPicker)
-- ═══════════════════════════════════════════════
local function color3ToHex(c)
    return string.format("#%02X%02X%02X",
        math.clamp(math.round(c.R * 255), 0, 255),
        math.clamp(math.round(c.G * 255), 0, 255),
        math.clamp(math.round(c.B * 255), 0, 255))
end

local function hexToColor3(hex)
    hex = hex:gsub("#", "")
    if #hex ~= 6 then return nil end
    local r = tonumber(hex:sub(1, 2), 16)
    local g = tonumber(hex:sub(3, 4), 16)
    local b = tonumber(hex:sub(5, 6), 16)
    if not r or not g or not b then return nil end
    return Color3.fromRGB(r, g, b)
end

local function color3ToHSV(c)
    local h, s, v = Color3.toHSV(c)
    return h, s, v
end

-- ═══════════════════════════════════════════════
-- AXUI:CreateWindow
-- ═══════════════════════════════════════════════
function AXUI:CreateWindow(config)
    config = config or {}
    local WIN_TITLE    = config.title or "Menu"
    local WIN_SUBTITLE = config.subtitle or ""
    local WIN_VERSION  = config.version or "v1.0"
    local WIN_W        = config.width or 842
    local WIN_H        = config.height or 580
    local HEADER_H     = 46
    local SIDEBAR_W    = 194
    local SEARCH_H     = 49
    local BODY_H       = WIN_H - HEADER_H

    -- header element config
    local CFG_LOGO_TEXT       = config.logoText or "X"
    local CFG_SHOW_FPS        = (config.showFPS ~= false) and WIN_W >= 480
    local CFG_SHOW_CONNECTED  = (config.showConnected ~= false) and WIN_W >= 620
    local CFG_CONNECTED_TEXT  = config.connectedText or "CONNECTED"
    local CFG_SHOW_ONLINE     = (config.showOnline ~= false) and WIN_W >= 700
    local CFG_ONLINE_TEXT     = config.onlineText -- nil = auto

    -- sidebar config
    local CFG_SIDEBAR_LABEL   = config.sidebarLabel or "CATEGORIES"
    local CFG_PANIC_TEXT      = config.panicText or "PANIC"
    local CFG_PANIC_ICON      = config.panicIcon or "⚠"
    local CFG_HINT_TEXT       = config.hintText or ""

    -- search
    local CFG_SEARCH_PH       = config.searchPlaceholder or "Search features…"

    -- toasts
    local CFG_TOAST_ON_LOAD   = config.toastOnLoad ~= false
    local CFG_LOAD_TOAST      = config.loadToastText -- nil = auto
    local CFG_PANIC_TOAST     = config.panicToastText or "All features disabled"

    -- ───────────────────────────────────────────
    -- THEME
    -- ───────────────────────────────────────────
    local Theme = {}
    local function setAccent(color)
        if type(color) == "string" then color = ACCENT_PRESETS[color] or ACCENT_PRESETS.Green end
        Theme.ACCENT      = color
        Theme.ACCENT_DIM  = color
        Theme.PANEL_BG    = Color3.fromRGB(7, 13, 9)
        Theme.PANEL_BG_2  = Color3.fromRGB(10, 17, 12)
        Theme.HEADER_BG   = Color3.fromRGB(14, 23, 18)
        Theme.SIDEBAR_BG  = Color3.fromRGB(8, 13, 10)
        Theme.ROW_BG      = Color3.fromRGB(255, 255, 255)
        Theme.ROW_BG_TR   = 0.978
        Theme.TEXT         = Color3.fromRGB(230, 246, 236)
        Theme.TEXT_DIM     = Color3.fromRGB(126, 154, 135)
        Theme.TEXT_FAINT   = Color3.fromRGB(94, 122, 103)
        Theme.DANGER       = Color3.fromRGB(255, 133, 133)
        Theme.SECTION_HDR  = Color3.fromRGB(127, 174, 140)
        Theme.LineSoft     = Color3.fromRGB(40, 55, 45)
    end
    setAccent(config.accent or "Green")

    -- ───────────────────────────────────────────
    -- STATE MANAGEMENT
    -- ───────────────────────────────────────────
    local State     = {}
    local Controls  = {}
    local Callbacks = {}

    local function setState(id, value, silent)
        State[id] = value
        if not silent and Callbacks[id] then
            pcall(Callbacks[id], value)
        end
    end

    -- ───────────────────────────────────────────
    -- SCREENGUI
    -- ───────────────────────────────────────────
    local screenGui = new("ScreenGui", {
        Name = "AXUI_Window",
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        IgnoreGuiInset = true,
    })
    local parentTo
    pcall(function() parentTo = (gethui or function() end)() end)
    if not parentTo then pcall(function() if syn and syn.protect_gui then syn.protect_gui(screenGui) end; parentTo = game:GetService("CoreGui") end) end
    if not parentTo then parentTo = LocalPlayer:WaitForChild("PlayerGui", 5) end
    screenGui.Parent = parentTo or LocalPlayer:FindFirstChildOfClass("PlayerGui")

    -- ───────────────────────────────────────────
    -- ACCENT-BOUND REGISTRY
    -- ───────────────────────────────────────────
    -- Anything colored with Theme.ACCENT at creation time only gets that color once —
    -- Color3 is a value type, not a live reference, so when Theme.ACCENT changes later
    -- (via SetAccent), already-created instances keep the OLD color until something
    -- explicitly re-applies it. bindAccent()/accentStroke() register instances here so
    -- SetAccent() can do a single pass and refresh everything that's UNCONDITIONALLY
    -- accent-colored, instead of a small hand-picked list.
    -- Only use these for elements whose color is ALWAYS Theme.ACCENT with no other
    -- condition (on/off state, danger flag, selected/hover state, etc). Conditional
    -- coloring needs its own refreshTheme closure in Controls[id] instead (see
    -- makeToggle), since blindly overwriting it here would be wrong whenever the
    -- condition currently evaluates to something other than accent.
    local accentBindings = {}

    local function bindAccent(instance, prop)
        instance[prop] = Theme.ACCENT
        table.insert(accentBindings, { instance = instance, prop = prop })
        return instance
    end

    local function accentStroke(obj, thickness, transparency)
        local s = stroke(obj, Theme.ACCENT, thickness, transparency)
        bindAccent(s, "Color")
        return s
    end

    -- ───────────────────────────────────────────
    -- WINDOW FRAME
    -- ───────────────────────────────────────────
    local window = new("Frame", {
        Name = "Window",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0, WIN_W, 0, WIN_H),
        BackgroundColor3 = Theme.PANEL_BG,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = screenGui,
    })
    corner(window, 14)
    accentStroke(window, 1, 0.78)
    local windowScale = new("UIScale", { Scale = 1, Parent = window })

    -- ───────────────────────────────────────────
    -- HEADER BAR
    -- ───────────────────────────────────────────
    local header = new("Frame", {
        Name = "Header",
        Size = UDim2.new(1, 0, 0, HEADER_H),
        BackgroundColor3 = Theme.HEADER_BG,
        BorderSizePixel = 0, ZIndex = 5,
        Parent = window,
    })
    squareCorners(header, 14, Theme.HEADER_BG, { "BottomLeft", "BottomRight" })
    -- bottom border
    bindAccent(new("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 0, 1, 0),
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.ACCENT,
        BackgroundTransparency = 0.78,
        BorderSizePixel = 0, ZIndex = 5,
        Parent = header,
    }), "BackgroundColor3")

    -- logo square
    local logoBox = new("Frame", {
        Position = UDim2.new(0, 14, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        Size = UDim2.new(0, 22, 0, 22),
        BackgroundColor3 = Theme.ACCENT,
        BorderSizePixel = 0, ZIndex = 6,
        Parent = header,
    })
    bindAccent(logoBox, "BackgroundColor3")
    corner(logoBox, 5)
    new("TextLabel", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = CFG_LOGO_TEXT, TextColor3 = Color3.new(0, 0, 0),
        TextSize = 14, Font = Enum.Font.GothamBold,
        ZIndex = 7, Parent = logoBox,
    })

    -- title
    local titleLabel = new("TextLabel", {
        Position = UDim2.new(0, 44, 0, 8),
        Size = UDim2.new(0, 200, 0, 16),
        BackgroundTransparency = 1,
        RichText = true,
        Text = WIN_TITLE,
        TextColor3 = Theme.TEXT,
        TextSize = 15, Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 6, Parent = header,
    })

    -- subtitle
    if WIN_SUBTITLE ~= "" then
        new("TextLabel", {
            Position = UDim2.new(0, 44, 0, 26),
            Size = UDim2.new(0, 80, 0, 12),
            BackgroundTransparency = 1,
            Text = WIN_SUBTITLE, TextColor3 = Theme.TEXT_DIM,
            TextSize = 10, Font = FONT,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 6, Parent = header,
        })
    end

    -- version pill
    local vPill
    if WIN_VERSION ~= "" then
        vPill = new("Frame", {
            Position = UDim2.new(0, 130, 0, 26),
            Size = UDim2.new(0, 32, 0, 14),
            BackgroundTransparency = 1,
            BorderSizePixel = 0, ZIndex = 6,
            Parent = header,
        })
        corner(vPill, 7)
        accentStroke(vPill, 1, 0.78)
        local versionLabel = new("TextLabel", {
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            Text = WIN_VERSION, TextColor3 = Theme.ACCENT,
            TextSize = 9, Font = FONT,
            ZIndex = 7, Parent = vPill,
        })
        bindAccent(versionLabel, "TextColor3")
    end

    -- FPS / Ping readout
    local fpsLabel = new("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0, 200, 0, 14),
        BackgroundTransparency = 1,
        Text = "60 FPS · 0 ms",
        TextColor3 = Theme.TEXT_DIM,
        TextSize = 11, Font = FONT,
        Visible = CFG_SHOW_FPS,
        ZIndex = 6, Parent = header,
    })

    -- CONNECTED indicator
    local connDot
    if CFG_SHOW_CONNECTED then
        connDot = new("Frame", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -220, 0.5, 0),
            Size = UDim2.new(0, 6, 0, 6),
            BackgroundColor3 = Theme.ACCENT,
            BorderSizePixel = 0, ZIndex = 6,
            Parent = header,
        })
        corner(connDot, 3)
        bindAccent(connDot, "BackgroundColor3")
        bindAccent(new("TextLabel", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -166, 0.5, 0),
            Size = UDim2.new(0, 50, 0, 14),
            BackgroundTransparency = 1,
            Text = CFG_CONNECTED_TEXT, TextColor3 = Theme.ACCENT,
            TextSize = 9, Font = FONT,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 6, Parent = header,
        }), "TextColor3")
    end

    -- ONLINE pill
    local onlineLabel
    if CFG_SHOW_ONLINE then
        local onlinePill = new("Frame", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -90, 0.5, 0),
            Size = UDim2.new(0, 70, 0, 18),
            BackgroundTransparency = 1,
            BorderSizePixel = 0, ZIndex = 6,
            Parent = header,
        })
        corner(onlinePill, 9)
        accentStroke(onlinePill, 1, 0.78)
        local olText = CFG_ONLINE_TEXT or ("ONLINE · " .. tostring(math.random(180, 400)))
        onlineLabel = new("TextLabel", {
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            Text = olText, TextColor3 = Theme.ACCENT,
            TextSize = 8, Font = FONT,
            ZIndex = 7, Parent = onlinePill,
        })
        bindAccent(onlineLabel, "TextColor3")
    end

    -- minimize button
    local minBtn = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -42, 0.5, 0),
        Size = UDim2.new(0, 24, 0, 24),
        BackgroundColor3 = Theme.PANEL_BG_2,
        BorderSizePixel = 0, AutoButtonColor = false,
        Text = "—", TextColor3 = Theme.TEXT_DIM,
        TextSize = 14, Font = FONT,
        ZIndex = 8, Parent = header,
    })
    corner(minBtn, 8)
    minBtn.MouseEnter:Connect(function() tweenObj(minBtn, 0.1, { BackgroundColor3 = Color3.fromRGB(35, 45, 38), TextColor3 = Theme.TEXT }) end)
    minBtn.MouseLeave:Connect(function() tweenObj(minBtn, 0.1, { BackgroundColor3 = Theme.PANEL_BG_2, TextColor3 = Theme.TEXT_DIM }) end)

    -- close button
    local closeBtn = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.new(0, 24, 0, 24),
        BackgroundColor3 = Theme.PANEL_BG_2,
        BorderSizePixel = 0, AutoButtonColor = false,
        Text = "X", TextColor3 = Theme.TEXT_DIM,
        TextSize = 13, Font = Enum.Font.GothamBold,
        ZIndex = 8, Parent = header,
    })
    corner(closeBtn, 8)
    closeBtn.MouseEnter:Connect(function() tweenObj(closeBtn, 0.1, { BackgroundColor3 = Color3.fromRGB(60, 20, 20), TextColor3 = Theme.DANGER }) end)
    closeBtn.MouseLeave:Connect(function() tweenObj(closeBtn, 0.1, { BackgroundColor3 = Theme.PANEL_BG_2, TextColor3 = Theme.TEXT_DIM }) end)

    -- ───────────────────────────────────────────
    -- DRAGGING
    -- ───────────────────────────────────────────
    do
        local dragArea = new("TextButton", {
            Name = "DragArea",
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            Text = "", AutoButtonColor = false,
            ZIndex = 4, Parent = header,
        })
        local dragging, dragStart, startPos
        dragArea.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true; dragStart = input.Position; startPos = window.Position
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local delta = input.Position - dragStart
                -- Resolve to an absolute pixel target (folding in whatever scale
                -- component the starting position had) before clamping, since
                -- clamping mixed scale+offset UDim2 values directly isn't meaningful.
                local viewport = screenGui.AbsoluteSize
                local rawX = startPos.X.Scale * viewport.X + startPos.X.Offset + delta.X
                local rawY = startPos.Y.Scale * viewport.Y + startPos.Y.Offset + delta.Y

                -- window is center-anchored (0.5, 0.5), so its edges sit half its
                -- size away from its Position on each side.
                local halfW = window.AbsoluteSize.X / 2
                local halfH = window.AbsoluteSize.Y / 2
                local minX, maxX = halfW, viewport.X - halfW
                local minY, maxY = halfH, viewport.Y - halfH
                if minX > maxX then minX, maxX = maxX, minX end -- window wider than viewport
                if minY > maxY then minY, maxY = maxY, minY end -- window taller than viewport

                local clampedX = math.clamp(rawX, minX, maxX)
                local clampedY = math.clamp(rawY, minY, maxY)
                window.Position = UDim2.new(0, clampedX, 0, clampedY)
            end
        end)
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)
    end

    -- ───────────────────────────────────────────
    -- SIDEBAR
    -- ───────────────────────────────────────────
    local sidebar = new("Frame", {
        Name = "Sidebar",
        Position = UDim2.new(0, 0, 0, HEADER_H),
        Size = UDim2.new(0, SIDEBAR_W, 0, BODY_H),
        BackgroundColor3 = Theme.SIDEBAR_BG,
        BorderSizePixel = 0, ZIndex = 3,
        Parent = window,
    })
    squareCorners(sidebar, 14, Theme.SIDEBAR_BG, { "TopLeft", "TopRight", "BottomRight" })
    -- right border
    bindAccent(new("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.new(0, 1, 1, 0),
        BackgroundColor3 = Theme.ACCENT,
        BackgroundTransparency = 0.92,
        BorderSizePixel = 0, ZIndex = 4,
        Parent = sidebar,
    }), "BackgroundColor3")

    -- sidebar label
    if CFG_SIDEBAR_LABEL ~= "" then
        new("TextLabel", {
            Position = UDim2.new(0, 16, 0, 14),
            Size = UDim2.new(1, -32, 0, 12),
            BackgroundTransparency = 1,
            Text = CFG_SIDEBAR_LABEL:upper():gsub(".", "%0 "):sub(1, -2),
            TextColor3 = Theme.TEXT_FAINT,
            TextSize = 10, Font = FONT,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 4, Parent = sidebar,
        })
    end

    local navList = new("Frame", {
        Position = UDim2.new(0, 8, 0, 34),
        Size = UDim2.new(1, -16, 1, -34 - 70),
        BackgroundTransparency = 1,
        ZIndex = 4, Parent = sidebar,
    })
    new("UIListLayout", {
        Padding = UDim.new(0, 2),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = navList,
    })

    -- Panic button at bottom of sidebar
    local panicBtn
    if CFG_PANIC_TEXT ~= "" then
        panicBtn = new("TextButton", {
            AnchorPoint = Vector2.new(0.5, 1),
            Position = UDim2.new(0.5, 0, 1, -30),
            Size = UDim2.new(1, -24, 0, 30),
            BackgroundColor3 = Theme.DANGER,
            BackgroundTransparency = 0.9,
            BorderSizePixel = 0, AutoButtonColor = false,
            Text = (CFG_PANIC_ICON ~= "" and (CFG_PANIC_ICON .. " ") or "") .. CFG_PANIC_TEXT,
            TextColor3 = Theme.DANGER,
            TextSize = 11, Font = Enum.Font.GothamBold,
            ZIndex = 5, Parent = sidebar,
        })
        corner(panicBtn, 10)
        stroke(panicBtn, Theme.DANGER, 1, 0.6)
    end

    -- hint text
    local hintLabel
    if CFG_HINT_TEXT ~= "" then
        hintLabel = new("TextLabel", {
            AnchorPoint = Vector2.new(0.5, 1),
            Position = UDim2.new(0.5, 0, 1, -8),
            Size = UDim2.new(1, -16, 0, 12),
            BackgroundTransparency = 1,
            Text = CFG_HINT_TEXT,
            TextColor3 = Theme.TEXT_FAINT,
            TextSize = 8, Font = FONT,
            ZIndex = 4, Parent = sidebar,
        })
    end

    -- ───────────────────────────────────────────
    -- CONTENT AREA
    -- ───────────────────────────────────────────
    local contentFrame = new("Frame", {
        Name = "Content",
        Position = UDim2.new(0, SIDEBAR_W, 0, HEADER_H),
        Size = UDim2.new(1, -SIDEBAR_W, 0, BODY_H),
        BackgroundColor3 = Theme.PANEL_BG,
        BorderSizePixel = 0, ClipsDescendants = true,
        ZIndex = 2, Parent = window,
    })
    squareCorners(contentFrame, 14, Theme.PANEL_BG, { "TopLeft", "TopRight", "BottomLeft" })

    -- search bar area
    local searchBar = new("Frame", {
        Size = UDim2.new(1, 0, 0, SEARCH_H),
        BackgroundTransparency = 1,
        BorderSizePixel = 0, ZIndex = 3,
        Parent = contentFrame,
    })
    bindAccent(new("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 0, 1, 0),
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.ACCENT,
        BackgroundTransparency = 0.92,
        BorderSizePixel = 0, ZIndex = 3,
        Parent = searchBar,
    }), "BackgroundColor3")

    -- search input
    local searchField = new("Frame", {
        Position = UDim2.new(0, 14, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        Size = UDim2.new(0, 260, 0, 28),
        BackgroundColor3 = Theme.PANEL_BG_2,
        BorderSizePixel = 0, ZIndex = 4,
        Parent = searchBar,
    })
    corner(searchField, 8)
    accentStroke(searchField, 1, 0.92)
    new("TextLabel", {
        Position = UDim2.new(0, 8, 0, 0),
        Size = UDim2.new(0, 14, 1, 0),
        BackgroundTransparency = 1,
        Text = "🔍", TextSize = 12, Font = FONT,
        TextColor3 = Theme.TEXT_FAINT,
        ZIndex = 5, Parent = searchField,
    })
    local searchBox = new("TextBox", {
        Position = UDim2.new(0, 28, 0, 0),
        Size = UDim2.new(1, -36, 1, 0),
        BackgroundTransparency = 1,
        PlaceholderText = CFG_SEARCH_PH,
        PlaceholderColor3 = Theme.TEXT_FAINT,
        Text = "", TextColor3 = Theme.TEXT,
        TextSize = 11, Font = FONT,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        ZIndex = 5, Parent = searchField,
    })

    -- active tab label (right side of search bar)
    local activeTabLabel = new("TextLabel", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -16, 0.5, 0),
        Size = UDim2.new(0, 120, 0, 16),
        BackgroundTransparency = 1,
        Text = "", TextColor3 = Theme.ACCENT,
        TextSize = 13, Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Right,
        ZIndex = 4, Parent = searchBar,
    })
    bindAccent(activeTabLabel, "TextColor3")

    -- scroll container
    local contentScroll = new("ScrollingFrame", {
        Position = UDim2.new(0, 0, 0, SEARCH_H),
        Size = UDim2.new(1, 0, 1, -SEARCH_H),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = Theme.ACCENT,
        ScrollBarImageTransparency = 0.6,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ZIndex = 2, Parent = contentFrame,
    })
    bindAccent(contentScroll, "ScrollBarImageColor3")
    new("UIPadding", {
        PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14),
        PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
        Parent = contentScroll,
    })
    local contentLayout = new("UIListLayout", {
        Padding = UDim.new(0, 16),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = contentScroll,
    })
    -- safety-net canvas growth
    contentLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        local layoutH = contentLayout.AbsoluteContentSize.Y + 20
        local curH = contentScroll.CanvasSize.Y.Offset
        if layoutH > curH then
            contentScroll.CanvasSize = UDim2.new(0, 0, 0, layoutH)
        end
    end)

    -- ───────────────────────────────────────────
    -- TOAST SYSTEM
    -- ───────────────────────────────────────────
    local toastStack = new("Frame", {
        Name = "Toasts",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -16, 1, -16),
        Size = UDim2.new(0, 280, 0, 400),
        BackgroundTransparency = 1,
        ZIndex = 10, Parent = screenGui,
    })
    new("UIListLayout", {
        Padding = UDim.new(0, 6),
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = toastStack,
    })

    local function toast(message, isDanger)
        local t = new("Frame", {
            Size = UDim2.new(1, 0, 0, 36),
            BackgroundColor3 = Theme.PANEL_BG_2,
            BorderSizePixel = 0,
            BackgroundTransparency = 1, ClipsDescendants = true,
            ZIndex = 11, Parent = toastStack,
        })
        corner(t, 10)
        local tStroke = stroke(t, Theme.ACCENT, 1, 1)
        local accentBar = new("Frame", {
            Size = UDim2.new(0, 3, 1, 0),
            BackgroundColor3 = isDanger and Theme.DANGER or Theme.ACCENT,
            BackgroundTransparency = 1,
            BorderSizePixel = 0, ZIndex = 12, Parent = t,
        })
        local dotF = new("Frame", {
            Position = UDim2.new(0, 12, 0.5, 0),
            AnchorPoint = Vector2.new(0, 0.5),
            Size = UDim2.new(0, 5, 0, 5),
            BackgroundColor3 = isDanger and Theme.DANGER or Theme.ACCENT,
            BackgroundTransparency = 1,
            BorderSizePixel = 0, ZIndex = 12, Parent = t,
        })
        corner(dotF, 3)
        local textLbl = new("TextLabel", {
            Position = UDim2.new(0, 24, 0, 0),
            Size = UDim2.new(1, -32, 1, 0),
            BackgroundTransparency = 1,
            Text = message, TextColor3 = Theme.TEXT,
            TextTransparency = 1,
            TextSize = 11, Font = FONT,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            ZIndex = 12, Parent = t,
        })

        -- Entrance: the SLIDE is now its own tween with a slight Back/Out overshoot
        -- (settles a touch past 0 then eases back) so it reads as a deliberate slide-in
        -- rather than a flat glide. Fade runs alongside on its own Quint/Out curve —
        -- Back easing overshoots past the target value, which looks fine for Position
        -- but would cause a visible transparency flicker if applied to fade too.
        t.Position = UDim2.new(1, 50, 0, 0)
        tweenObj(t, 0.45, { Position = UDim2.new(0, 0, 0, 0) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
        tweenObj(t, 0.3, { BackgroundTransparency = 0 }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
        tweenObj(tStroke, 0.3, { Transparency = 0.85 }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
        tweenObj(accentBar, 0.3, { BackgroundTransparency = 0 }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
        tweenObj(dotF, 0.3, { BackgroundTransparency = 0 }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
        tweenObj(textLbl, 0.3, { TextTransparency = 0 }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

        task.delay(2.6, function()
            if t and t.Parent then
                tweenObj(t, 0.3, { Position = UDim2.new(1, 50, 0, 0), BackgroundTransparency = 1 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
                tweenObj(tStroke, 0.3, { Transparency = 1 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
                tweenObj(accentBar, 0.3, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
                tweenObj(dotF, 0.3, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
                tweenObj(textLbl, 0.3, { TextTransparency = 1 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
                task.wait(0.32)
                if t and t.Parent then t:Destroy() end
            end
        end)
    end

    -- ───────────────────────────────────────────
    -- GROUP BUILDER
    -- ───────────────────────────────────────────
    local allGroups  = {}
    local groupOrder = 0
    local controlOrder = 0

    -- ───────────────────────────────────────────
    -- MANUAL CANVAS SIZING
    -- ───────────────────────────────────────────
    local function recalcGroupHeights()
        local searching = searchBox.Text ~= ""
        local visibleH, visibleCount = 0, 0
        for _, g in ipairs(allGroups) do
            local section = g.section
            -- A group collapsed by the user renders as header-height-only, UNLESS
            -- a search is active (search always shows full matched content
            -- regardless of the user's collapsed preference).
            local userCollapsed = section:GetAttribute("UserCollapsed")
            local effectivelyCollapsed = userCollapsed and not searching
            local totalH, childCount = 0, 0
            if effectivelyCollapsed then
                local hdr = section:FindFirstChild("GroupHeader")
                totalH = hdr and hdr.Size.Y.Offset or 20
                childCount = 1
            else
                for _, child in ipairs(section:GetChildren()) do
                    if (child:IsA("Frame") or child:IsA("TextButton")) and child.Visible then
                        childCount = childCount + 1
                        totalH = totalH + child.Size.Y.Offset
                    end
                end
                totalH = totalH + math.max(0, childCount - 1) * 4
            end
            section.Size = UDim2.new(1, 0, 0, totalH)
            if section.Visible then
                visibleH = visibleH + totalH
                visibleCount = visibleCount + 1
            end
        end
        local canvasH = visibleH + math.max(0, visibleCount - 1) * 16 + 20 + 10
        contentScroll.CanvasSize = UDim2.new(0, 0, 0, canvasH)
    end

    local function makeGroup(title)
        groupOrder = groupOrder + 1
        local section = new("Frame", {
            Name = "Group_" .. title,
            Size = UDim2.new(1, 0, 0, 20),
            BackgroundTransparency = 1,
            LayoutOrder = groupOrder,
            Visible = false,
            Parent = contentScroll,
        })
        new("UIListLayout", {
            Padding = UDim.new(0, 4),
            SortOrder = Enum.SortOrder.LayoutOrder,
            Parent = section,
        })
        -- header row with fading line (shows the subcategory, e.g. "AIMBOT")
        -- Named so the search filter can recognize it and keep it visible whenever
        -- this group has a matching result, instead of hiding it like a normal row.
        local hdr = new("Frame", {
            Name = "GroupHeader",
            Size = UDim2.new(1, 0, 0, 20),
            BackgroundTransparency = 1, LayoutOrder = 0,
            Parent = section,
        })
        local headerLabel = new("TextLabel", {
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 1,
            Text = title:upper(), TextColor3 = Theme.SECTION_HDR,
            TextSize = 10, Font = FONT,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = hdr,
        })
        local line = new("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 0, 0.5, 0),
            Size = UDim2.new(1, 0, 0, 1),
            BackgroundColor3 = Theme.SECTION_HDR,
            BackgroundTransparency = 0.7,
            BorderSizePixel = 0, ZIndex = 0,
            Parent = hdr,
        })
        new("UIGradient", {
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.3),
                NumberSequenceKeypoint.new(0.3, 0.7),
                NumberSequenceKeypoint.new(1, 1),
            }),
            Parent = line,
        })

        -- Collapsible (accordion) support. UserCollapsed is the user's manual
        -- preference from clicking the header; it's stored as an attribute (not a
        -- plain local) so both this click handler and the search filter elsewhere
        -- can read/write it. Search always shows matches regardless of this flag —
        -- collapse only applies when there's no active search query.
        section:SetAttribute("UserCollapsed", false)
        local chevron = new("TextLabel", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.new(0, 14, 0, 14),
            BackgroundTransparency = 1,
            Text = "▾", TextColor3 = Theme.SECTION_HDR,
            TextSize = 9, Font = FONT,
            ZIndex = 1, Parent = hdr,
        })
        local hdrBtn = new("TextButton", {
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
            ZIndex = 2, Parent = hdr,
        })
        hdrBtn.MouseButton1Click:Connect(function()
            local newCollapsed = not section:GetAttribute("UserCollapsed")
            section:SetAttribute("UserCollapsed", newCollapsed)
            chevron.Text = newCollapsed and "▸" or "▾"
            -- Don't fight an active search: if the user is mid-search, rows are
            -- being shown/hidden by match state, not collapse state. The collapsed
            -- preference still gets saved above and takes effect once the search
            -- is cleared.
            if searchBox.Text == "" then
                for _, child in ipairs(section:GetChildren()) do
                    if child:IsA("Frame") and child.Name ~= "GroupHeader" then
                        child.Visible = not newCollapsed
                    end
                end
            end
            recalcGroupHeights()
        end)

        return section, headerLabel
    end

    -- ───────────────────────────────────────────
    -- TAB SYSTEM
    -- ───────────────────────────────────────────
    local tabButtons = {}
    local tabOrder   = 0
    local activeTab  = nil

    local function switchTab(name)
        activeTab = name
        activeTabLabel.Text = name
        for tname, data in pairs(tabButtons) do
            local active = tname == name
            if active then
                tweenObj(data.btn, 0.15, { BackgroundColor3 = Theme.ACCENT, BackgroundTransparency = 0.86 })
                data.indicator.Visible = true
                data.indicator.BackgroundColor3 = Theme.ACCENT
                data.icon.TextColor3 = Theme.ACCENT
                data.label.TextColor3 = Theme.ACCENT
                data.label.Font = Enum.Font.GothamBold
            else
                tweenObj(data.btn, 0.15, { BackgroundTransparency = 1 })
                data.indicator.Visible = false
                data.icon.TextColor3 = Theme.TEXT_DIM
                data.label.TextColor3 = Theme.TEXT_DIM
                data.label.Font = FONT
            end
        end
        for _, g in ipairs(allGroups) do
            g.section.Visible = (g.tab == name)
        end
        recalcGroupHeights()
        contentScroll.CanvasPosition = Vector2.new(0, 0)
    end

    local function createSidebarButton(name, icon)
        tabOrder = tabOrder + 1
        local btn = new("TextButton", {
            Size = UDim2.new(1, 0, 0, 34),
            BackgroundColor3 = Theme.ACCENT,
            BackgroundTransparency = 1,
            BorderSizePixel = 0, AutoButtonColor = false,
            Text = "", LayoutOrder = tabOrder,
            ZIndex = 5, Parent = navList,
        })
        corner(btn, 9)
        bindAccent(btn, "BackgroundColor3")

        local indicator = new("Frame", {
            Position = UDim2.new(0, 0, 0.5, 0),
            AnchorPoint = Vector2.new(0, 0.5),
            Size = UDim2.new(0, 2, 0, 22),
            BackgroundColor3 = Theme.ACCENT,
            BorderSizePixel = 0, Visible = false,
            ZIndex = 6, Parent = btn,
        })
        corner(indicator, 1)

        local iconLbl = new("TextLabel", {
            Position = UDim2.new(0, 12, 0, 0),
            Size = UDim2.new(0, 20, 1, 0),
            BackgroundTransparency = 1,
            Text = icon or "•",
            TextColor3 = Theme.TEXT_DIM,
            TextSize = 14, Font = FONT,
            ZIndex = 6, Parent = btn,
        })

        local lbl = new("TextLabel", {
            Position = UDim2.new(0, 36, 0, 0),
            Size = UDim2.new(1, -60, 1, 0),
            BackgroundTransparency = 1,
            Text = name, TextColor3 = Theme.TEXT_DIM,
            TextSize = 11, Font = FONT,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 6, Parent = btn,
        })

        tabButtons[name] = { btn = btn, indicator = indicator, icon = iconLbl, label = lbl }

        btn.MouseButton1Click:Connect(function()
            if searchBox.Text ~= "" then searchBox.Text = "" end
            switchTab(name)
        end)
        btn.MouseEnter:Connect(function()
            if activeTab ~= name then tweenObj(btn, 0.1, { BackgroundTransparency = 0.92 }) end
        end)
        btn.MouseLeave:Connect(function()
            if activeTab ~= name then tweenObj(btn, 0.1, { BackgroundTransparency = 1 }) end
        end)
    end

    -- ───────────────────────────────────────────
    -- CONTROL FACTORIES
    -- ───────────────────────────────────────────
    -- reservedWidth = fixed px width (from the right edge) that this row's control needs.
    -- The label is sized as "100% - reservedWidth" instead of a flat 0.6 scale, so it always
    -- leaves exact room for the control regardless of how narrow the window/row is. It just
    -- truncates with an ellipsis (TextTruncate.AtEnd) instead of drawing underneath the control.
    local DEFAULT_RESERVED_WIDTH = 100

    local function makeRow(parent, label, subText, reservedWidth)
        label = tostring(label or "???")
        reservedWidth = reservedWidth or DEFAULT_RESERVED_WIDTH
        controlOrder = controlOrder + 1
        local row = new("Frame", {
            Size = UDim2.new(1, 0, 0, 38),
            BackgroundColor3 = Theme.ROW_BG,
            BackgroundTransparency = Theme.ROW_BG_TR,
            BorderSizePixel = 0,
            LayoutOrder = controlOrder,
            Parent = parent,
        })
        corner(row, 10)
        accentStroke(row, 1, 0.93)
        new("UIPadding", {
            PaddingLeft = UDim.new(0, 11), PaddingRight = UDim.new(0, 11),
            PaddingTop = UDim.new(0, 0), PaddingBottom = UDim.new(0, 0),
            Parent = row,
        })
        local labelY = subText and -4 or 0
        -- Size = (100% of content width) - reservedWidth, floored so it never goes to 0/negative.
        local labelSize = UDim2.new(1, -reservedWidth, 0, 14)
        new("TextLabel", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 0, 0.5, labelY),
            Size = labelSize,
            BackgroundTransparency = 1,
            Text = label, TextColor3 = Theme.TEXT,
            TextSize = 11, Font = FONT,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = row,
        })
        if subText then
            new("TextLabel", {
                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, 0, 0.5, 8),
                Size = UDim2.new(1, -reservedWidth, 0, 10),
                BackgroundTransparency = 1,
                Text = subText, TextColor3 = Theme.TEXT_FAINT,
                TextSize = 9, Font = FONT,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = row,
            })
        end
        pcall(function() row:SetAttribute("SearchLabel", string.lower(label) .. " " .. string.lower(subText or "")) end)
        return row
    end

    -- ──── TOGGLE ────
    local function makeToggle(parent, id, label, default, onChange, subText)
        local row = makeRow(parent, label, subText, 54) -- 42px track + gap
        local track = new("Frame", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.new(0, 42, 0, 22),
            BackgroundColor3 = Color3.fromRGB(60, 60, 60),
            BorderSizePixel = 0, Parent = row,
        })
        corner(track, 11)
        local trackStroke = stroke(track, Theme.ACCENT, 1, 0.85)
        local knob = new("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 3, 0.5, 0),
            Size = UDim2.new(0, 16, 0, 16),
            BackgroundColor3 = Color3.fromRGB(180, 180, 180),
            BorderSizePixel = 0, Parent = track,
        })
        corner(knob, 8)

        local value = default or false
        State[id] = value
        Callbacks[id] = onChange

        -- Reads Theme.ACCENT live each call (Theme is a shared table whose fields
        -- SetAccent mutates in place), so calling this again after a theme change
        -- re-colors this toggle without needing it to be flipped off/on.
        local function applyVisual()
            if value then
                tweenObj(track, 0.15, { BackgroundColor3 = Theme.ACCENT })
                tweenObj(trackStroke, 0.15, { Color = Theme.ACCENT, Transparency = 0.3 })
                tweenObj(knob, 0.15, { Position = UDim2.new(1, -19, 0.5, 0), BackgroundColor3 = Color3.fromRGB(15, 15, 15) })
            else
                tweenObj(track, 0.15, { BackgroundColor3 = Color3.fromRGB(60, 60, 60) })
                tweenObj(trackStroke, 0.15, { Color = Theme.ACCENT, Transparency = 0.85 })
                tweenObj(knob, 0.15, { Position = UDim2.new(0, 3, 0.5, 0), BackgroundColor3 = Color3.fromRGB(180, 180, 180) })
            end
        end
        applyVisual()

        local clickArea = new("TextButton", {
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
            ZIndex = 2, Parent = row,
        })
        clickArea.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                value = not value; State[id] = value; applyVisual()
                if onChange then pcall(onChange, value) end
            end
        end)

        Controls[id] = {
            type = "toggle", row = row,
            getValue = function() return value end,
            setValue = function(v, silent)
                value = v; State[id] = v; applyVisual()
                if not silent and onChange then pcall(onChange, v) end
            end,
            refreshTheme = function() applyVisual() end,
        }
        return row
    end

    -- ──── SLIDER ────
    local function makeSlider(parent, id, label, cfg, onChange)
        local min      = cfg.min or 0
        local max      = cfg.max or 100
        local step     = cfg.step or 1
        local default  = cfg.default or min
        local unit     = cfg.unit or ""
        local decimals = cfg.decimals or 0

        local row = makeRow(parent, label, nil, 140) -- 120px track + 45px value label + gap
        local trackFrame = new("Frame", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.new(0, 120, 0, 10),
            BackgroundColor3 = Color3.fromRGB(30, 30, 30),
            BorderSizePixel = 0, Parent = row,
        })
        corner(trackFrame, 5)
        accentStroke(trackFrame, 1, 0.9)
        local fill = new("Frame", {
            Size = UDim2.new(0, 0, 1, 0),
            BackgroundColor3 = Theme.ACCENT,
            BackgroundTransparency = 0.4,
            BorderSizePixel = 0, Parent = trackFrame,
        })
        bindAccent(fill, "BackgroundColor3")
        corner(fill, 5)
        local handle = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0, 0, 0.5, 0),
            Size = UDim2.new(0, 14, 0, 14),
            BackgroundColor3 = Theme.ACCENT,
            BorderSizePixel = 0, ZIndex = 3, Parent = trackFrame,
        })
        bindAccent(handle, "BackgroundColor3")
        corner(handle, 7)
        local valLabel = new("TextLabel", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -130, 0.5, 0),
            Size = UDim2.new(0, 45, 0, 12),
            BackgroundTransparency = 1,
            Text = "", TextColor3 = Theme.ACCENT,
            TextSize = 10, Font = FONT,
            TextXAlignment = Enum.TextXAlignment.Right,
            Parent = row,
        })
        bindAccent(valLabel, "TextColor3")

        local value = default
        State[id] = value; Callbacks[id] = onChange

        local function applyValue(v)
            v = math.clamp(v, min, max)
            v = math.floor(v / step + 0.5) * step
            local mult = 10 ^ decimals
            v = math.floor(v * mult + 0.5) / mult
            value = v; State[id] = v
            local pct = (v - min) / (max - min)
            fill.Size = UDim2.new(pct, 0, 1, 0)
            handle.Position = UDim2.new(pct, 0, 0.5, 0)
            valLabel.Text = string.format("%." .. decimals .. "f%s", v, unit)
        end
        applyValue(value)

        local dragging = false
        local inputBtn = new("TextButton", {
            Size = UDim2.new(1, 20, 1, 20),
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, -10, 0.5, 0),
            BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
            ZIndex = 4, Parent = trackFrame,
        })
        local function updateFromInput(posX)
            local pct = math.clamp((posX - trackFrame.AbsolutePosition.X) / trackFrame.AbsoluteSize.X, 0, 1)
            applyValue(min + pct * (max - min))
            if onChange then pcall(onChange, value) end
        end
        inputBtn.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true; updateFromInput(input.Position.X)
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                updateFromInput(input.Position.X)
            end
        end)
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
        end)

        Controls[id] = {
            type = "slider", row = row,
            getValue = function() return value end,
            setValue = function(v, silent) applyValue(v); if not silent and onChange then pcall(onChange, v) end end,
        }
        return row
    end

    -- forward declaration: color picker's close function is defined further down,
    -- but dropdown needs to call it too (so opening one closes the other)
    local closeActivePopup

    -- ──── DROPDOWN ────
    local activeDropdownList = nil
    local function closeActiveDropdown()
        if activeDropdownList and activeDropdownList.frame and activeDropdownList.frame.Parent then
            activeDropdownList.frame:Destroy()
        end
        if activeDropdownList then activeDropdownList.isOpenRef.value = false end
        activeDropdownList = nil
    end

    local function makeDropdown(parent, id, label, options, default, onChange)
        local row = makeRow(parent, label, nil, 110) -- 100px button + gap
        local value = default or options[1]
        State[id] = value; Callbacks[id] = onChange

        local btn = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.new(0, 100, 0, 22),
            BackgroundColor3 = Theme.PANEL_BG_2,
            BorderSizePixel = 0, AutoButtonColor = false,
            Text = tostring(value), TextColor3 = Theme.TEXT,
            TextSize = 10, Font = FONT,
            TextTruncate = Enum.TextTruncate.AtEnd,
            ZIndex = 3, Parent = row,
        })
        corner(btn, 5)
        accentStroke(btn, 1, 0.85)
        new("TextLabel", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -4, 0.5, 0),
            Size = UDim2.new(0, 12, 0, 12),
            BackgroundTransparency = 1,
            Text = "▾", TextColor3 = Theme.TEXT_DIM,
            TextSize = 10, Font = FONT,
            ZIndex = 4, Parent = btn,
        })

        local isOpenRef = { value = false }
        local listFrame -- built fresh each open, parented to screenGui (top-level, never clipped/shadowed)

        local function buildOptions(frame)
            for _, c in ipairs(frame:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
            for i, opt in ipairs(options) do
                local optBtn = new("TextButton", {
                    Size = UDim2.new(1, 0, 0, 24),
                    BackgroundColor3 = (opt == value) and Theme.ACCENT or Theme.PANEL_BG_2,
                    BackgroundTransparency = (opt == value) and 0.85 or 0,
                    BorderSizePixel = 0, AutoButtonColor = false,
                    Text = "  " .. tostring(opt),
                    TextColor3 = (opt == value) and Theme.ACCENT or Theme.TEXT_DIM,
                    TextSize = 10, Font = FONT,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    LayoutOrder = i, ZIndex = 101, Parent = frame,
                })
                optBtn.MouseEnter:Connect(function() tweenObj(optBtn, 0.1, { BackgroundTransparency = 0.8, BackgroundColor3 = Theme.ACCENT }) end)
                optBtn.MouseLeave:Connect(function()
                    local sel = opt == value
                    tweenObj(optBtn, 0.1, { BackgroundTransparency = sel and 0.85 or 0, BackgroundColor3 = sel and Theme.ACCENT or Theme.PANEL_BG_2 })
                end)
                optBtn.InputBegan:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        value = opt; State[id] = value; btn.Text = tostring(opt)
                        closeActiveDropdown()
                        if onChange then pcall(onChange, value) end
                    end
                end)
            end
            frame.Size = UDim2.new(0, 100, 0, #options * 24)
        end

        local function openDropdown()
            closeActiveDropdown() -- close any other open dropdown first
            closeActivePopup() -- also close any open color picker

            local frame = new("Frame", {
                BackgroundColor3 = Theme.PANEL_BG_2,
                BorderSizePixel = 0,
                Size = UDim2.new(0, 100, 0, #options * 24),
                ZIndex = 100, Parent = screenGui,
            })
            corner(frame, 5)
            stroke(frame, Theme.ACCENT, 1, 0.8)
            new("UIListLayout", { Padding = UDim.new(0, 0), SortOrder = Enum.SortOrder.LayoutOrder, Parent = frame })

            local absPos = btn.AbsolutePosition
            local absSize = btn.AbsoluteSize
            frame.Position = UDim2.new(0, absPos.X + absSize.X - 100, 0, absPos.Y + absSize.Y + 2)

            buildOptions(frame)
            listFrame = frame
            isOpenRef.value = true
            activeDropdownList = { frame = frame, isOpenRef = isOpenRef }
        end

        btn.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                if isOpenRef.value then
                    closeActiveDropdown()
                else
                    openDropdown()
                end
            end
        end)

        Controls[id] = {
            type = "dropdown", row = row,
            getValue = function() return value end,
            setValue = function(v, silent) value = v; State[id] = v; btn.Text = tostring(v); if not silent and onChange then pcall(onChange, v) end end,
            setOptions = function(newOpts) options = newOpts end,
        }
        return row
    end

    -- ──── BUTTON ────
    local function makeButton(parent, id, label, btnText, danger, onClick, confirmOpts)
        local row = makeRow(parent, label, nil, 70) -- 56px button + gap
        btnText = btnText or "BTN"
        local bg = danger and Color3.fromRGB(40, 12, 12) or Theme.ACCENT
        local bgTr = danger and 0.6 or 0.88
        local textC = danger and Theme.DANGER or Theme.ACCENT

        local btn = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.new(0, 56, 0, 22),
            BackgroundColor3 = bg,
            BackgroundTransparency = bgTr,
            BorderSizePixel = 0, AutoButtonColor = false,
            Text = btnText:upper(), TextColor3 = textC,
            TextSize = 9, Font = Enum.Font.GothamBold,
            ZIndex = 3, Parent = row,
        })
        corner(btn, 6)
        local btnStroke = stroke(btn, textC, 1, 0.7)
        if not danger then
            bindAccent(btn, "BackgroundColor3")
            bindAccent(btn, "TextColor3")
            bindAccent(btnStroke, "Color")
        end

        -- confirmation state
        local confirming = false
        local origText = btnText:upper()

        btn.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                if confirmOpts and not confirming then
                    confirming = true
                    btn.Text = "SURE?"
                    btn.TextColor3 = Theme.DANGER
                    task.delay(2, function()
                        if confirming then
                            confirming = false
                            btn.Text = origText; btn.TextColor3 = danger and Theme.DANGER or Theme.ACCENT
                        end
                    end)
                    return
                end
                confirming = false
                btn.Text = origText; btn.TextColor3 = danger and Theme.DANGER or Theme.ACCENT
                if onClick then pcall(onClick) end
            end
        end)
        btn.MouseEnter:Connect(function() tweenObj(btn, 0.1, { BackgroundTransparency = bgTr - 0.15 }) end)
        btn.MouseLeave:Connect(function() tweenObj(btn, 0.1, { BackgroundTransparency = bgTr }) end)

        Controls[id] = { type = "button", row = row }
        return row
    end

    -- ──── KEYBIND ────
    local function makeKeybind(parent, id, label, defaultKey, onBind)
        local row = makeRow(parent, label, nil, 74) -- 60px capture button + gap
        local currentKey = defaultKey
        State[id] = currentKey; Callbacks[id] = onBind

        local cap = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.new(0, 60, 0, 24),
            BackgroundColor3 = Theme.PANEL_BG_2,
            BorderSizePixel = 0, AutoButtonColor = false,
            Text = currentKey and tostring(currentKey) or "None",
            TextColor3 = Theme.ACCENT,
            TextSize = 10, Font = FONT,
            ZIndex = 3, Parent = row,
        })
        corner(cap, 4)
        bindAccent(cap, "TextColor3")
        local capStroke = stroke(cap, Theme.ACCENT, 1, 0.78)
        bindAccent(capStroke, "Color")
        bindAccent(new("Frame", {
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new(0, 0, 1, 0),
            Size = UDim2.new(1, 0, 0, 2),
            BackgroundColor3 = Theme.ACCENT,
            BackgroundTransparency = 0.6,
            BorderSizePixel = 0, ZIndex = 4, Parent = cap,
        }), "BackgroundColor3")

        local listening = false
        cap.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                listening = true; cap.Text = "..."; capStroke.Transparency = 0.3
            end
        end)
        UserInputService.InputBegan:Connect(function(input)
            if not listening then return end
            if input.UserInputType == Enum.UserInputType.Keyboard then
                listening = false; currentKey = input.KeyCode.Name
                State[id] = currentKey; cap.Text = currentKey
                cap.TextColor3 = Theme.ACCENT; capStroke.Transparency = 0.78
                if onBind then pcall(onBind, currentKey) end
            end
        end)

        Controls[id] = {
            type = "keybind", row = row,
            getValue = function() return currentKey end,
            setValue = function(v, silent)
                currentKey = v; State[id] = v
                cap.Text = v and tostring(v) or "None"
                if not silent and onBind then pcall(onBind, v) end
            end,
        }
        return row
    end

    -- ──── COLOR PICKER ────
    local activePickerPopup = nil
    closeActivePopup = function()
        if activePickerPopup and activePickerPopup.Parent then
            activePickerPopup:Destroy()
        end
        activePickerPopup = nil
    end

    local function makeColorPicker(parent, id, label, default, onChange, subText)
        local row = makeRow(parent, label, subText, 40) -- 26px swatch + gap
        local value = default or Color3.fromRGB(255, 255, 255)
        State[id] = value; Callbacks[id] = onChange

        local h, s, v = color3ToHSV(value)

        -- preview swatch
        local swatch = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.new(0, 26, 0, 18),
            BackgroundColor3 = value,
            BorderSizePixel = 0, AutoButtonColor = false,
            Text = "", ZIndex = 3, Parent = row,
        })
        corner(swatch, 5)
        accentStroke(swatch, 1, 0.7)

        local function setColor(newColor)
            value = newColor; State[id] = newColor
            swatch.BackgroundColor3 = newColor
            h, s, v = color3ToHSV(newColor)
            if onChange then pcall(onChange, newColor) end
        end

        swatch.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end

            -- if this swatch's own popup is already open, just close it
            if activePickerPopup and activePickerPopup:GetAttribute("OwnerId") == id then
                closeActivePopup()
                return
            end

            -- close any other open popup (and any open dropdown, since they can visually collide)
            closeActivePopup()
            closeActiveDropdown()

            -- build picker popup on screenGui (not clipped by scroll)
            local popup = new("Frame", {
                Size = UDim2.new(0, 200, 0, 230),
                BackgroundColor3 = Theme.PANEL_BG,
                BorderSizePixel = 0,
                ZIndex = 100,
                Parent = screenGui,
            })
            corner(popup, 10)
            stroke(popup, Theme.ACCENT, 1, 0.5)
            activePickerPopup = popup
            popup:SetAttribute("OwnerId", id)

            -- position near swatch
            local absPos = swatch.AbsolutePosition
            local absSize = swatch.AbsoluteSize
            popup.Position = UDim2.new(0, absPos.X - 170, 0, absPos.Y + absSize.Y + 4)

            new("UIPadding", {
                PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
                PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
                Parent = popup,
            })

            -- ── SV SQUARE ──
            local svSize = 140
            local svFrame = new("Frame", {
                Size = UDim2.new(0, svSize, 0, svSize),
                BackgroundColor3 = Color3.fromHSV(h, 1, 1),
                BorderSizePixel = 0, ClipsDescendants = true,
                ZIndex = 101, Parent = popup,
            })
            corner(svFrame, 6)
            -- white overlay (left to right)
            local whiteOL = new("Frame", {
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundColor3 = Color3.new(1, 1, 1),
                BorderSizePixel = 0, ZIndex = 102, Parent = svFrame,
            })
            new("UIGradient", {
                Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0),
                    NumberSequenceKeypoint.new(1, 1),
                }),
                Parent = whiteOL,
            })
            -- black overlay (top to bottom)
            local blackOL = new("Frame", {
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundColor3 = Color3.new(0, 0, 0),
                BorderSizePixel = 0, ZIndex = 103, Parent = svFrame,
            })
            new("UIGradient", {
                Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 1),
                    NumberSequenceKeypoint.new(1, 0),
                }),
                Rotation = 90,
                Parent = blackOL,
            })
            -- SV cursor
            local svCursor = new("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Size = UDim2.new(0, 10, 0, 10),
                BackgroundTransparency = 1,
                BorderSizePixel = 0, ZIndex = 105, Parent = svFrame,
            })
            corner(svCursor, 5)
            stroke(svCursor, Color3.new(1, 1, 1), 2, 0)

            local function updateSVCursor()
                svCursor.Position = UDim2.new(s, 0, 1 - v, 0)
            end
            updateSVCursor()

            -- SV interaction
            local svBtn = new("TextButton", {
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
                ZIndex = 106, Parent = svFrame,
            })
            local svDragging = false
            local function updateSV(posX, posY)
                s = math.clamp((posX - svFrame.AbsolutePosition.X) / svFrame.AbsoluteSize.X, 0, 1)
                v = 1 - math.clamp((posY - svFrame.AbsolutePosition.Y) / svFrame.AbsoluteSize.Y, 0, 1)
                updateSVCursor()
                setColor(Color3.fromHSV(h, s, v))
                if hexBox then hexBox.Text = color3ToHex(value) end
            end
            svBtn.InputBegan:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                    svDragging = true; updateSV(i.Position.X, i.Position.Y)
                end
            end)
            UserInputService.InputChanged:Connect(function(i)
                if svDragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                    updateSV(i.Position.X, i.Position.Y)
                end
            end)
            UserInputService.InputEnded:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then svDragging = false end
            end)

            -- ── HUE BAR ──
            local hueBar = new("Frame", {
                Position = UDim2.new(0, svSize + 8, 0, 0),
                Size = UDim2.new(0, 18, 0, svSize),
                BackgroundColor3 = Color3.new(1, 1, 1),
                BorderSizePixel = 0, ClipsDescendants = true,
                ZIndex = 101, Parent = popup,
            })
            corner(hueBar, 4)
            new("UIGradient", {
                Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 1, 1)),
                    ColorSequenceKeypoint.new(1/6, Color3.fromHSV(1/6, 1, 1)),
                    ColorSequenceKeypoint.new(2/6, Color3.fromHSV(2/6, 1, 1)),
                    ColorSequenceKeypoint.new(3/6, Color3.fromHSV(3/6, 1, 1)),
                    ColorSequenceKeypoint.new(4/6, Color3.fromHSV(4/6, 1, 1)),
                    ColorSequenceKeypoint.new(5/6, Color3.fromHSV(5/6, 1, 1)),
                    ColorSequenceKeypoint.new(1, Color3.fromHSV(0, 1, 1)),
                }),
                Rotation = 90,
                Parent = hueBar,
            })
            -- hue indicator
            local hueIndicator = new("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Size = UDim2.new(1, 4, 0, 4),
                BackgroundTransparency = 1,
                BorderSizePixel = 0, ZIndex = 103, Parent = hueBar,
            })
            stroke(hueIndicator, Color3.new(1, 1, 1), 2, 0)

            local function updateHueCursor()
                hueIndicator.Position = UDim2.new(0.5, 0, h, 0)
            end
            updateHueCursor()

            local hueBtn = new("TextButton", {
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
                ZIndex = 104, Parent = hueBar,
            })
            local hueDragging = false
            local function updateHue(posY)
                h = math.clamp((posY - hueBar.AbsolutePosition.Y) / hueBar.AbsoluteSize.Y, 0, 0.999)
                updateHueCursor()
                svFrame.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
                setColor(Color3.fromHSV(h, s, v))
                if hexBox then hexBox.Text = color3ToHex(value) end
            end
            hueBtn.InputBegan:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                    hueDragging = true; updateHue(i.Position.Y)
                end
            end)
            UserInputService.InputChanged:Connect(function(i)
                if hueDragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                    updateHue(i.Position.Y)
                end
            end)
            UserInputService.InputEnded:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then hueDragging = false end
            end)

            -- ── HEX INPUT ──
            local hexRow = new("Frame", {
                Position = UDim2.new(0, 0, 0, svSize + 8),
                Size = UDim2.new(1, 0, 0, 22),
                BackgroundTransparency = 1,
                ZIndex = 101, Parent = popup,
            })
            new("TextLabel", {
                Size = UDim2.new(0, 30, 1, 0),
                BackgroundTransparency = 1,
                Text = "HEX", TextColor3 = Theme.TEXT_DIM,
                TextSize = 9, Font = FONT,
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = 102, Parent = hexRow,
            })
            local hexBox = new("TextBox", {
                Position = UDim2.new(0, 32, 0, 0),
                Size = UDim2.new(0, 70, 1, 0),
                BackgroundColor3 = Theme.PANEL_BG_2,
                BorderSizePixel = 0,
                Text = color3ToHex(value), TextColor3 = Theme.TEXT,
                TextSize = 10, Font = FONT,
                ClearTextOnFocus = false,
                ZIndex = 102, Parent = hexRow,
            })
            corner(hexBox, 4)
            stroke(hexBox, Theme.ACCENT, 1, 0.85)

            hexBox.FocusLost:Connect(function()
                local c = hexToColor3(hexBox.Text)
                if c then
                    h, s, v = color3ToHSV(c)
                    updateSVCursor(); updateHueCursor()
                    svFrame.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
                    setColor(c)
                else
                    hexBox.Text = color3ToHex(value)
                end
            end)

            -- ── PRESETS ──
            local presets = {
                Color3.fromRGB(255, 0, 0),    Color3.fromRGB(255, 138, 0),
                Color3.fromRGB(255, 255, 0),  Color3.fromRGB(57, 255, 20),
                Color3.fromRGB(0, 229, 255),  Color3.fromRGB(0, 100, 255),
                Color3.fromRGB(139, 92, 246), Color3.fromRGB(255, 45, 212),
                Color3.fromRGB(255, 255, 255),Color3.fromRGB(255, 180, 200),
            }
            local presetRow = new("Frame", {
                Position = UDim2.new(0, 0, 0, svSize + 34),
                Size = UDim2.new(1, 0, 0, 20),
                BackgroundTransparency = 1,
                ZIndex = 101, Parent = popup,
            })
            new("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal,
                Padding = UDim.new(0, 4),
                Parent = presetRow,
            })
            for _, pc in ipairs(presets) do
                local pb = new("TextButton", {
                    Size = UDim2.new(0, 14, 0, 14),
                    BackgroundColor3 = pc,
                    BorderSizePixel = 0, AutoButtonColor = false,
                    Text = "", ZIndex = 102, Parent = presetRow,
                })
                corner(pb, 3)
                pb.InputBegan:Connect(function(i)
                    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                        h, s, v = color3ToHSV(pc)
                        updateSVCursor(); updateHueCursor()
                        svFrame.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
                        setColor(pc)
                        hexBox.Text = color3ToHex(pc)
                    end
                end)
            end

            -- ── CLOSE BUTTON ──
            local closeP = new("TextButton", {
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, 2, 0, -2),
                Size = UDim2.new(0, 18, 0, 18),
                BackgroundColor3 = Theme.PANEL_BG_2,
                BorderSizePixel = 0, AutoButtonColor = false,
                Text = "X", TextColor3 = Theme.TEXT_DIM,
                TextSize = 10, Font = Enum.Font.GothamBold,
                ZIndex = 108, Parent = popup,
            })
            corner(closeP, 4)
            closeP.InputBegan:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                    closeActivePopup()
                end
            end)
        end)

        Controls[id] = {
            type = "colorpicker", row = row,
            getValue = function() return value end,
            setValue = function(c, silent)
                value = c; State[id] = c
                swatch.BackgroundColor3 = c
                h, s, v = color3ToHSV(c)
                if not silent and onChange then pcall(onChange, c) end
            end,
        }
        return row
    end

    -- ──── TEXT INPUT ────
    local function makeTextInput(parent, id, label, default, placeholder, onChange)
        local row = makeRow(parent, label, nil, 114) -- 100px input box + gap
        local value = default or ""
        State[id] = value; Callbacks[id] = onChange

        local box = new("TextBox", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.new(0, 100, 0, 22),
            BackgroundColor3 = Theme.PANEL_BG_2,
            BorderSizePixel = 0,
            Text = value, TextColor3 = Theme.TEXT,
            PlaceholderText = placeholder or "",
            PlaceholderColor3 = Theme.TEXT_FAINT,
            TextSize = 10, Font = FONT,
            TextXAlignment = Enum.TextXAlignment.Left,
            ClearTextOnFocus = false,
            ZIndex = 3, Parent = row,
        })
        corner(box, 5)
        accentStroke(box, 1, 0.85)
        new("UIPadding", {
            PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
            Parent = box,
        })

        box.FocusLost:Connect(function()
            value = box.Text; State[id] = value
            if onChange then pcall(onChange, value) end
        end)

        Controls[id] = {
            type = "textinput", row = row,
            getValue = function() return value end,
            setValue = function(v, silent)
                value = v; State[id] = v; box.Text = v
                if not silent and onChange then pcall(onChange, v) end
            end,
        }
        return row
    end

    -- ──── SEPARATOR ────
    local function makeSeparator(parent)
        controlOrder = controlOrder + 1
        local sep = new("Frame", {
            Size = UDim2.new(1, 0, 0, 8),
            BackgroundTransparency = 1,
            LayoutOrder = controlOrder,
            Parent = parent,
        })
        bindAccent(new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.5, 0),
            Size = UDim2.new(1, -20, 0, 1),
            BackgroundColor3 = Theme.ACCENT,
            BackgroundTransparency = 0.85,
            BorderSizePixel = 0, Parent = sep,
        }), "BackgroundColor3")
        return sep
    end

    -- ──── LABEL ────
    local function makeLabel(parent, id, text, color)
        controlOrder = controlOrder + 1
        local row = new("Frame", {
            Size = UDim2.new(1, 0, 0, 24),
            BackgroundTransparency = 1,
            LayoutOrder = controlOrder,
            Parent = parent,
        })
        local lbl = new("TextLabel", {
            Size = UDim2.new(1, -22, 1, 0),
            Position = UDim2.new(0, 11, 0, 0),
            BackgroundTransparency = 1,
            Text = text, TextColor3 = color or Theme.TEXT_DIM,
            TextSize = 10, Font = FONT,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = row,
        })
        pcall(function() row:SetAttribute("SearchLabel", string.lower(text)) end)

        if id then
            Controls[id] = {
                type = "label", row = row,
                getValue = function() return lbl.Text end,
                setValue = function(v) lbl.Text = v end,
                setColor = function(c) lbl.TextColor3 = c end,
            }
        end
        return row
    end

    -- ───────────────────────────────────────────
    -- SEARCH FILTERING
    -- ───────────────────────────────────────────
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        local query = searchBox.Text:lower()
        for _, g in ipairs(allGroups) do
            if query == "" then
                -- restore normal tab-scoped browsing: only the active tab's groups show.
                -- Reset every group's children (regardless of tab) back to their
                -- USER-CHOSEN collapsed state, not just "visible" — otherwise clearing
                -- a search would un-collapse anything the user had manually collapsed.
                g.section.Visible = (g.tab == activeTab)
                local userCollapsed = g.section:GetAttribute("UserCollapsed")
                for _, child in ipairs(g.section:GetChildren()) do
                    if child:IsA("Frame") and child.Name ~= "GroupHeader" then
                        child.Visible = not userCollapsed
                    end
                end
                if g.headerLabel then g.headerLabel.Text = g.title:upper() end
            else
                -- global search: check every group regardless of which tab it's on
                local anyVisible = false
                for _, child in ipairs(g.section:GetChildren()) do
                    if child:IsA("Frame") and child.Name ~= "GroupHeader" then
                        local sl = child:GetAttribute("SearchLabel") or ""
                        local match = sl:find(query, 1, true) ~= nil
                        child.Visible = match
                        if match then anyVisible = true end
                    end
                end
                g.section.Visible = anyVisible
                -- keep the subcategory header visible above its matched rows instead
                -- of hiding it along with the non-matching ones
                local hdr = g.section:FindFirstChild("GroupHeader")
                if hdr then hdr.Visible = anyVisible end
                -- a cross-tab result loses its "which tab is this under" context, so
                -- prefix the header with the tab name during search (e.g. "AIM · AIMBOT")
                if g.headerLabel then
                    g.headerLabel.Text = anyVisible and (g.tab:upper() .. " · " .. g.title:upper()) or g.title:upper()
                end
            end
        end
        recalcGroupHeights()
    end)

    -- ───────────────────────────────────────────
    -- CONFIG SAVE / LOAD
    -- ───────────────────────────────────────────
    local CONFIG_FOLDER = config.configFolder or "AXUI_Config"
    local CONFIG_FILE   = CONFIG_FOLDER .. "/" .. (config.configFile or "config.json")
    local PROFILES_DIR   = CONFIG_FOLDER .. "/profiles"
    local PROFILES_INDEX = PROFILES_DIR .. "/_index.json"

    -- Strips path separators and ".." before a name ever touches the filesystem,
    -- so a bad/malicious profile name can't write outside the config folder.
    local function sanitizeProfileName(name)
        name = tostring(name or "")
        name = name:gsub("[/\\]", "")
        name = name:gsub("%.%.", "")
        name = name:match("^%s*(.-)%s*$") or ""
        return name
    end

    local function ensureProfilesDir()
        pcall(function()
            if not isfolder(CONFIG_FOLDER) then makefolder(CONFIG_FOLDER) end
            if not isfolder(PROFILES_DIR) then makefolder(PROFILES_DIR) end
        end)
    end

    -- The manifest lists known profile names. Used instead of listfiles()/directory
    -- scanning, since not every executor implements directory listing reliably —
    -- a manifest file keeps this portable across executors.
    local function readProfileIndex()
        if not isfile or not isfile(PROFILES_INDEX) then return {} end
        local ok, json = pcall(readfile, PROFILES_INDEX)
        if not ok then return {} end
        local ok2, list = pcall(function() return HttpService:JSONDecode(json) end)
        if ok2 and type(list) == "table" then return list end
        return {}
    end

    local function writeProfileIndex(list)
        pcall(function()
            local json = HttpService:JSONEncode(list)
            writefile(PROFILES_INDEX, json)
        end)
    end

    local function addToProfileIndex(name)
        local list = readProfileIndex()
        for _, n in ipairs(list) do
            if n == name then return end
        end
        table.insert(list, name)
        writeProfileIndex(list)
    end

    local function removeFromProfileIndex(name)
        local list = readProfileIndex()
        for i, n in ipairs(list) do
            if n == name then table.remove(list, i); break end
        end
        writeProfileIndex(list)
    end

    local function gatherConfigData()
        local data = {}
        for id, ctrl in pairs(Controls) do
            if ctrl.type == "toggle" or ctrl.type == "slider" or ctrl.type == "dropdown" or ctrl.type == "keybind" or ctrl.type == "textinput" then
                data[id] = State[id]
            elseif ctrl.type == "colorpicker" then
                local c = State[id]
                if typeof(c) == "Color3" then
                    data[id] = { R = c.R, G = c.G, B = c.B }
                end
            end
        end
        return data
    end

    local function applyConfigData(data)
        for id, val in pairs(data) do
            local ctrl = Controls[id]
            if ctrl and ctrl.setValue then
                if ctrl.type == "colorpicker" and type(val) == "table" then
                    pcall(ctrl.setValue, Color3.new(val.R or 0, val.G or 0, val.B or 0))
                else
                    pcall(ctrl.setValue, val)
                end
            end
        end
    end

    -- name is optional: omitting it keeps the original single-file behavior
    -- (CONFIG_FILE), so existing scripts calling SaveConfig()/LoadConfig() with no
    -- arguments are unaffected. Passing a name saves/loads a separate named
    -- profile file instead.
    local function saveConfig(name)
        if not isfolder or not writefile then toast("File API not available", true); return end
        local data = gatherConfigData()
        local ok, json = pcall(function() return HttpService:JSONEncode(data) end)
        if not ok then return end
        if name then
            name = sanitizeProfileName(name)
            if name == "" then toast("Invalid profile name", true); return end
            ensureProfilesDir()
            pcall(function() writefile(PROFILES_DIR .. "/" .. name .. ".json", json) end)
            addToProfileIndex(name)
            toast("Saved profile \"" .. name .. "\"")
        else
            pcall(function() if not isfolder(CONFIG_FOLDER) then makefolder(CONFIG_FOLDER) end end)
            pcall(function() writefile(CONFIG_FILE, json) end)
            toast("Config saved")
        end
    end

    local function loadConfig(name)
        if not isfile or not readfile then toast("File API not available", true); return end
        local path = CONFIG_FILE
        if name then
            name = sanitizeProfileName(name)
            if name == "" then toast("Invalid profile name", true); return end
            path = PROFILES_DIR .. "/" .. name .. ".json"
        end
        if not isfile(path) then
            toast(name and ("Profile \"" .. name .. "\" not found") or "No config found", true)
            return
        end
        local ok, json = pcall(function() return readfile(path) end)
        if not ok then return end
        local ok2, data = pcall(function() return HttpService:JSONDecode(json) end)
        if not ok2 or type(data) ~= "table" then return end
        applyConfigData(data)
        toast(name and ("Loaded profile \"" .. name .. "\"") or "Config loaded")
    end

    local function listConfigs()
        return readProfileIndex()
    end

    local function deleteConfig(name)
        name = sanitizeProfileName(name)
        if name == "" then toast("Invalid profile name", true); return false end
        local path = PROFILES_DIR .. "/" .. name .. ".json"
        if isfile and isfile(path) and delfile then
            pcall(function() delfile(path) end)
        end
        removeFromProfileIndex(name)
        toast("Deleted profile \"" .. name .. "\"")
        return true
    end

    -- ───────────────────────────────────────────
    -- PANIC SYSTEM
    -- ───────────────────────────────────────────
    local panicCallbacks = {}

    local function doPanic()
        window.Visible = false
        for id, ctrl in pairs(Controls) do
            if ctrl.type == "toggle" then ctrl.setValue(false, false) end
        end
        for _, cb in ipairs(panicCallbacks) do pcall(cb) end
        toast(CFG_PANIC_TOAST, true)
    end
    if panicBtn then panicBtn.MouseButton1Click:Connect(doPanic) end

    -- ───────────────────────────────────────────
    -- UNLOAD SYSTEM
    -- ───────────────────────────────────────────
    local unloadCallbacks = {}
    local unloaded = false

    local function fullUnload()
        unloaded = true
        -- Turn every toggle off first (updates State AND fires each callback with false),
        -- same as doPanic. Without this, a feature loop that polls window.State.X or only
        -- reacts to the onChange callback would never be told to stop, and would keep
        -- running after the menu itself is destroyed below.
        for id, ctrl in pairs(Controls) do
            if ctrl.type == "toggle" then ctrl.setValue(false, false) end
        end
        for _, cb in ipairs(unloadCallbacks) do pcall(cb) end
        task.wait(0.1)
        if screenGui and screenGui.Parent then screenGui:Destroy() end
        toast = function() end
    end

    closeBtn.MouseButton1Click:Connect(fullUnload)

    -- ───────────────────────────────────────────
    -- MINIMIZE
    -- ───────────────────────────────────────────
    local minimized = false
    minBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        if minimized then
            tweenObj(window, 0.2, { Size = UDim2.new(0, WIN_W, 0, HEADER_H) })
            sidebar.Visible = false; contentFrame.Visible = false
        else
            tweenObj(window, 0.2, { Size = UDim2.new(0, WIN_W, 0, WIN_H) })
            task.delay(0.15, function() sidebar.Visible = true; contentFrame.Visible = true end)
        end
    end)

    -- ───────────────────────────────────────────
    -- MOUSE UNLOCK ON MENU OPEN
    -- ───────────────────────────────────────────
    local prevMouseBehavior, prevMouseIcon, mouseSaved

    local function setWindowVisible(vis)
        window.Visible = vis
        if vis then
            if not mouseSaved then
                prevMouseBehavior = UserInputService.MouseBehavior
                prevMouseIcon = UserInputService.MouseIconEnabled
                mouseSaved = true
            end
            pcall(function()
                UserInputService.MouseBehavior = Enum.MouseBehavior.Default
                UserInputService.MouseIconEnabled = true
            end)
        else
            if mouseSaved then
                pcall(function()
                    UserInputService.MouseBehavior = prevMouseBehavior
                    UserInputService.MouseIconEnabled = prevMouseIcon
                end)
                mouseSaved = false
            end
        end
    end

    -- ───────────────────────────────────────────
    -- KEYBIND HANDLING (menu toggle, panic)
    -- ───────────────────────────────────────────
    local menuKeyName     = config.menuKey or "RightShift"
    local panicKeyName    = config.panicKey or "Insert"
    local screenshotKey   = config.screenshotKey or "F8"

    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        local key = input.KeyCode.Name
        -- check State for rebound keys, fall back to defaults
        local mk = State.MenuKey or menuKeyName
        local pk = State.PanicKey or panicKeyName
        local sk = State.ScreenshotKey or screenshotKey
        if key == mk then setWindowVisible(not window.Visible); return end
        if key == pk then doPanic(); return end
        if key == sk then
            local ctrl = Controls.ScreenshotMode
            if ctrl then
                local nv = not ctrl.getValue()
                ctrl.setValue(nv)
                toast(nv and "Screenshot mode ON" or "Screenshot mode OFF")
            end
        end
    end)

    -- ───────────────────────────────────────────
    -- FPS / PING LOOP
    -- ───────────────────────────────────────────
    do
        local frameCount, lastTick, fps = 0, tick(), 60
        RunService.RenderStepped:Connect(function()
            if unloaded then return end
            frameCount = frameCount + 1
            if tick() - lastTick >= 1 then fps = frameCount; frameCount = 0; lastTick = tick() end
            local ping = 0
            pcall(function() ping = math.floor(LocalPlayer:GetNetworkPing() * 1000) end)
            fpsLabel.Text = string.format("%d FPS · %d ms", fps, ping)
        end)
        -- pulsing connected dot
        if connDot then
            task.spawn(function()
                while not unloaded do
                    tweenObj(connDot, 0.8, { BackgroundTransparency = 0.5 }); task.wait(0.8)
                    tweenObj(connDot, 0.8, { BackgroundTransparency = 0 }); task.wait(0.8)
                end
            end)
        end
    end

    -- ───────────────────────────────────────────
    -- WINDOW API
    -- ───────────────────────────────────────────
    local Window = {}
    Window.State      = State
    Window.Controls   = Controls
    Window.Callbacks  = Callbacks
    Window.Theme      = Theme
    Window.ScreenGui  = screenGui
    Window.FPSLabel   = fpsLabel
    Window.WindowScale= windowScale
    Window.Unloaded   = false

    function Window:Tab(name, icon)
        -- create sidebar button on first call
        if not tabButtons[name] then
            createSidebarButton(name, icon)
        end

        local Tab = {}
        function Tab:Group(title)
            local section, headerLabel = makeGroup(title)
            table.insert(allGroups, { tab = name, section = section, title = title, headerLabel = headerLabel })

            -- activate first tab automatically
            if not activeTab then switchTab(name) end

            local Group = {}

            function Group:Toggle(id, label, default, callback, subText)
                makeToggle(section, id, label, default, callback, subText)
                recalcGroupHeights()
            end

            function Group:Slider(id, label, cfg, callback)
                makeSlider(section, id, label, cfg, callback)
                recalcGroupHeights()
            end

            function Group:Dropdown(id, label, options, default, callback)
                makeDropdown(section, id, label, options, default, callback)
                recalcGroupHeights()
            end

            function Group:Button(id, label, btnText, danger, callback, confirm)
                makeButton(section, id, label, btnText, danger, callback, confirm)
                recalcGroupHeights()
            end

            function Group:Keybind(id, label, defaultKey, callback)
                makeKeybind(section, id, label, defaultKey, callback)
                recalcGroupHeights()
            end

            function Group:ColorPicker(id, label, default, callback, subText)
                makeColorPicker(section, id, label, default, callback, subText)
                recalcGroupHeights()
            end

            function Group:TextInput(id, label, default, placeholder, callback)
                makeTextInput(section, id, label, default, placeholder, callback)
                recalcGroupHeights()
            end

            function Group:Separator()
                makeSeparator(section)
                recalcGroupHeights()
            end

            function Group:Label(id, text, color)
                makeLabel(section, id, text, color)
                recalcGroupHeights()
            end

            return Group
        end

        return Tab
    end

    function Window:Toast(msg, isDanger) toast(msg, isDanger) end
    function Window:SetVisible(v) setWindowVisible(v) end
    function Window:IsVisible() return window.Visible end
    function Window:Destroy() fullUnload() end
    function Window:SaveConfig(name) saveConfig(name) end
    function Window:LoadConfig(name) loadConfig(name) end
    function Window:ListConfigs() return listConfigs() end
    function Window:DeleteConfig(name) return deleteConfig(name) end

    function Window:SetAccent(color)
        setAccent(color)
        -- One pass over every unconditionally-accent-colored element registered via
        -- bindAccent()/accentStroke() during creation (rows, strokes, sliders,
        -- dropdowns, keybinds, the header/sidebar/search chrome, etc.) instead of a
        -- small hand-picked list.
        for _, b in ipairs(accentBindings) do
            pcall(function() b.instance[b.prop] = Theme.ACCENT end)
        end
        -- Active-tab indicator/icon/label are conditional (only the active tab gets
        -- accent color, inactive ones stay TEXT_DIM), so they can't live in the static
        -- registry above — handled here same as before.
        for _, data in pairs(tabButtons) do
            if data.indicator.Visible then
                data.indicator.BackgroundColor3 = Theme.ACCENT
                data.icon.TextColor3 = Theme.ACCENT
                data.label.TextColor3 = Theme.ACCENT
            end
        end
        -- Re-apply the new theme to any control whose colored elements are
        -- state-dependent (e.g. a toggle's on/off track color) rather than always
        -- accent, so switching themes updates them immediately instead of waiting
        -- for the user to re-toggle each one.
        for _, ctrl in pairs(Controls) do
            if ctrl.refreshTheme then pcall(ctrl.refreshTheme) end
        end
    end

    function Window:OnPanic(cb)
        table.insert(panicCallbacks, cb)
    end

    function Window:OnUnload(cb)
        table.insert(unloadCallbacks, cb)
    end

    function Window:SwitchTab(name) switchTab(name) end

    function Window:UpdateHint(text) if hintLabel then hintLabel.Text = text end end

    -- show window
    window.Visible = true
    if CFG_TOAST_ON_LOAD then
        local menuKeyDisplay = config.menuKey or "RShift"
        local loadMsg = CFG_LOAD_TOAST or (WIN_TITLE:gsub("<.->", "") .. " loaded · Press " .. menuKeyDisplay)
        toast(loadMsg)
    end

    return Window
end

return AXUI
