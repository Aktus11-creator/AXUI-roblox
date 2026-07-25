# AXUI Boot

Terminal-style loading screen with executor detection and capability scanning.

## What it does

- Detects the active executor by name
- Scans 15 executor capabilities (Drawing API, hookmetamethod, file system, etc.)
- Reads environment info (player, game, server, FPS, ping)
- Reports namecall hook and Drawing API readiness
- Passes all detection data to your callback

## Usage

```lua
local Boot = loadstring(game:HttpGet("https://raw.githubusercontent.com/YOUR_URL/AXUIBoot.lua"))()

Boot.Run({
    title = "MY SCRIPT",
}, function(info)
    -- info.executor        string
    -- info.capabilities    table
    -- info.available       number
    -- info.missing         number
    -- info.hookReady       bool
    -- info.drawReady       bool
    -- info.fps             number
    -- info.ping            number

    -- load your script here
end)
```

## Config

All fields optional. Read the source for the full list.
