# AXUI

UI library for Roblox executor scripts. Handles window, tabs, controls, theming, config persistence, and search — you write game logic.

Built for executor environments. Tested on JJSploit, Solara, and others. Handles missing APIs, broken `AutomaticSize`, and executor-specific quirks internally.

## Setup

```lua
local AXUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/YOUR_URL/AXUI.lua"))()

local window = AXUI:CreateWindow({
    title = "My Menu",
    accent = "Green",
})

local tab = window:Tab("AIM", "🎯")
local group = tab:Group("Aimbot")

group:Toggle("Enabled", "Aimbot", false, function(v)
    print("Aimbot:", v)
end)

group:Slider("FOV", "FOV", { min = 0, max = 360, default = 120, unit = "°" }, function(v)
    print("FOV:", v)
end)

group:Dropdown("Part", "Target", {"Head", "Torso"}, "Head", function(v)
    print("Part:", v)
end)
```

## Controls

### Toggle
```lua
group:Toggle(id, label, default, callback, subText?)
```

### Slider
```lua
group:Slider(id, label, {
    min = 0,
    max = 100,
    step = 1,         -- optional, default 1
    default = 50,
    unit = "%",        -- optional
    decimals = 0,      -- optional
}, callback)
```

### Dropdown
```lua
group:Dropdown(id, label, options, default, callback)

-- update options later:
window.Controls["MyDropdown"].setOptions({"New", "Options"})
```

### Button
```lua
group:Button(id, label, buttonText, isDanger, callback)

-- with confirmation (shows "SURE?" before firing):
group:Button(id, label, "DELETE", true, callback, true)
```

### Keybind
```lua
group:Keybind(id, label, "RightShift", function(key)
    print("Rebound to:", key)
end)
```

### Color Picker
```lua
group:ColorPicker(id, label, Color3.fromRGB(255, 0, 0), function(color)
    print("New color:", color)
end)
```
Opens a popup with HSV square, hue bar, hex input, and preset swatches.

### Text Input
```lua
group:TextInput(id, label, "default", "placeholder...", function(text)
    print("Input:", text)
end)
```

### Separator
```lua
group:Separator()
```

### Label
```lua
group:Label("StatusLabel", "Waiting...", Color3.fromRGB(255, 200, 60))

-- update later:
window.Controls["StatusLabel"].setValue("Active")
window.Controls["StatusLabel"].setColor(Color3.fromRGB(80, 255, 120))
```

## Window Config

Every field is optional.

```lua
AXUI:CreateWindow({
    -- window
    title         = "My Menu",
    subtitle      = "by You",
    version       = "v1.0",
    accent        = "Green",         -- or Color3
    width         = 842,
    height        = 580,

    -- header elements
    logoText      = "X",
    showFPS       = true,
    showConnected = true,
    connectedText = "CONNECTED",
    showOnline    = true,
    onlineText    = nil,             -- nil = auto random count

    -- sidebar
    sidebarLabel  = "CATEGORIES",
    panicText     = "PANIC",
    panicIcon     = "⚠",
    hintText      = "",

    -- search
    searchPlaceholder = "Search features…",

    -- keybinds
    menuKey       = "RightShift",
    panicKey      = "Insert",
    screenshotKey = "F8",

    -- toasts
    toastOnLoad   = true,
    loadToastText = nil,             -- nil = auto
    panicToastText = "All features disabled",

    -- config persistence
    configFolder  = "MyScript",
    configFile    = "config.json",
})
```

Set string fields to `""` to hide that element. Set boolean fields to `false` to disable.

## Window Methods

```lua
window:Toast("Hello")                  -- show toast
window:Toast("Error!", true)           -- danger toast
window:SetVisible(false)               -- hide window
window:SetAccent("Cyan")               -- change theme
window:SetAccent(Color3.new(1, 0, 0))  -- custom color
window:SaveConfig()                    -- save to file
window:LoadConfig()                    -- load from file
window:SwitchTab("AIM")               -- switch active tab
window:OnPanic(function() end)         -- hook into panic
window:OnUnload(function() end)        -- hook into close/destroy
window:Destroy()                       -- full cleanup
```

## Reading State

```lua
-- get current value of any control
local fov = window.State.FOV

-- get/set through Controls table
local ctrl = window.Controls.Enabled
local isOn = ctrl.getValue()
ctrl.setValue(true)          -- fires callback
ctrl.setValue(true, true)    -- silent, no callback
```

## Accent Presets

`"Green"`, `"Cyan"`, `"Magenta"`, `"Red"`, `"Orange"` — or pass any `Color3`.

## Tab Badges

Toggle counts per tab update automatically. When a toggle is turned on, its tab's badge increments. Turns off, decrements. Zero hides the badge.

## Notes

- Config save/load requires `isfolder`, `makefolder`, `readfile`, `writefile`
- Color picker values serialize to `{R, G, B}` in config JSON automatically
- Search indexes both label text and subText
- Panic resets all toggles to `false` and fires their callbacks
- RichText is supported in the window title
