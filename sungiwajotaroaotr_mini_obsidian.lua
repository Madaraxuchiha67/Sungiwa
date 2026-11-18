--// AoT:R Mini  |  Obsidian UI
--// Options: Auto M1 (stops when mission ends) | Auto Retry | Auto Force Retry 15s
--//          Auto Close UI 5s | Config save/load

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VIM               = game:GetService("VirtualInputManager")
local GuiService        = game:GetService("GuiService")
local UserInputService  = game:GetService("UserInputService")

repeat task.wait() until game:IsLoaded() and Players.LocalPlayer
local player = Players.LocalPlayer

-- stop old copies if you execute twice
local token = {}
_G.AotrMiniToken = token
local function Alive() return _G.AotrMiniToken == token end

--------------------------------------------------------------------
-- SETTINGS (edit here)
--------------------------------------------------------------------
local M1_DELAY            = 0.25   -- seconds between M1 clicks
local FORCE_RETRY_DELAY   = 15     -- seconds after mission completed
local AUTO_CLOSE_DELAY    = 5      -- seconds before the UI hides itself
local CONFIG_FOLDER       = "AotrMini"

-- titles shown on the end screen (add more if your wave screen says something else)
local DONE_TITLES = {
    ["MISSION COMPLETED"] = true,
    ["RAID COMPLETED"]    = true,
    ["WAVE COMPLETED"]    = true,
}

--------------------------------------------------------------------
-- OBSIDIAN UI
--------------------------------------------------------------------
local repo         = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library      = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Window = Library:CreateWindow({
    Title = "AoT:R Mini",
    Footer = "Attack on Titan: Revolution",
    NotifySide = "Right",
    ShowCustomCursor = false,
    Size = UDim2.fromOffset(520, 400),
    Center = true,
    AutoShow = true,
})

local Tabs = {
    Main     = Window:AddTab("Main"),
    Settings = Window:AddTab("Settings"),
}

--------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------
local State = {
    m1        = false,
    retry     = false,
    forceNow  = false,   -- Auto Force Retry (15s)
    autoClose = false,
    done      = false,   -- mission / raid / wave completed screen is up
    doneAt    = 0,
}

--------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------
local function guiVisible(obj)
    local cur = obj
    while cur and cur ~= game do
        if cur:IsA("GuiObject") and not cur.Visible then return false end
        if cur:IsA("ScreenGui") and not cur.Enabled then return false end
        cur = cur.Parent
    end
    return true
end

local function getRewards()
    local pg = player:FindFirstChild("PlayerGui")
    local iface = pg and pg:FindFirstChild("Interface")
    local rewards = iface and iface:FindFirstChild("Rewards")
    local main = rewards and rewards:FindFirstChild("Main")
    return rewards, main
end

local function getRetryButton()
    local _, main = getRewards()
    local info = main and main:FindFirstChild("Info")
    local infoMain = info and info:FindFirstChild("Main")
    local buttons = infoMain and infoMain:FindFirstChild("Buttons")
    return buttons and buttons:FindFirstChild("Retry")
end

local function retryVisible()
    local rewards, main = getRewards()
    local btn = getRetryButton()
    return btn ~= nil
        and rewards and rewards.Visible
        and main and main.Visible
        and btn.Visible
        and btn.AbsoluteSize.Magnitude > 10
end

-- fallback: look for the "MISSION COMPLETED" style title text
local function titleVisible()
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then return false end
    for _, d in ipairs(pg:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            local t = tostring(d.Text or ""):gsub("<[^>]->", "")
            t = t:gsub("^%s+", ""):gsub("%s+$", "")
            if DONE_TITLES[t:upper()] and guiVisible(d) then return true end
        end
    end
    return false
end

local function missionCompleted()
    local ok, res = pcall(function()
        return retryVisible() or titleVisible()
    end)
    return ok and res or false
end

local function clickAt(x, y)
    VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
    task.wait(0.03)
    VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
end

local function clickM1()
    local cam = workspace.CurrentCamera
    local size = cam and cam.ViewportSize or Vector2.new(800, 600)
    clickAt(size.X / 2, size.Y / 2)
end

local function clickRetry()
    local btn = getRetryButton()
    if not btn then return end
    local pos, size = btn.AbsolutePosition, btn.AbsoluteSize
    local inset = GuiService:GetGuiInset()
    local x = pos.X + size.X / 2
    local y = pos.Y + size.Y / 2 + inset.Y
    clickAt(x, y)
end

local function fireForceRetry()
    task.spawn(function()
        pcall(function()
            ReplicatedStorage:WaitForChild("Assets", 10)
                :WaitForChild("Remotes", 10)
                :WaitForChild("GET", 10)
                :InvokeServer("Functions", "Retry", "Add")
        end)
    end)
end

local function titansAlive()
    local titans = workspace:FindFirstChild("Titans")
    return titans ~= nil and #titans:GetChildren() > 0
end

local function charAlive()
    local char = player.Character
    local hum = char and char:FindFirstChildWhichIsA("Humanoid")
    return hum ~= nil and hum.Health > 0
end

--------------------------------------------------------------------
-- UI CONTROLS
--------------------------------------------------------------------
local Farm = Tabs.Main:AddLeftGroupbox("Farming")
local Util = Tabs.Main:AddRightGroupbox("Utilities")

Farm:AddToggle("AutoM1", {
    Text = "Auto Click M1",
    Default = false,
    Tooltip = "Clicks M1 while titans are alive. Stops when the mission / raid / wave is completed.",
    Callback = function(v) State.m1 = v end,
})
Farm:AddLabel("Stops automatically on the\nmission / raid / wave completed screen.", true)

Farm:AddToggle("AutoRetry", {
    Text = "Auto Retry",
    Default = false,
    Tooltip = "Presses Retry as soon as the completed screen shows.",
    Callback = function(v) State.retry = v end,
})

Farm:AddToggle("AutoForceRetry", {
    Text = "Auto Force Retry (15s)",
    Default = false,
    Tooltip = "Fires Force Retry 15 seconds after the mission is completed.",
    Callback = function(v) State.forceNow = v end,
})

Util:AddToggle("AutoCloseUI", {
    Text = "Auto Close UI (5s)",
    Default = false,
    Tooltip = "Hides the menu 5 seconds after it opens. Press your menu key to bring it back.",
    Callback = function(v)
        State.autoClose = v
        if v then
            task.delay(AUTO_CLOSE_DELAY, function()
                if Alive() and State.autoClose and Library.Toggled then
                    pcall(function() Library:Toggle() end)
                end
            end)
        end
    end,
})

Util:AddButton({
    Text = "Force Retry now",
    Func = fireForceRetry,
})

--------------------------------------------------------------------
-- LOOPS
--------------------------------------------------------------------

-- watcher: tracks the completed screen once, everything else reads State.done
task.spawn(function()
    while Alive() do
        local done = missionCompleted()
        if done and not State.done then
            State.done = true
            State.doneAt = os.clock()
        elseif not done and State.done then
            State.done = false
        end
        task.wait(0.4)
    end
end)

-- Auto M1: only while a mission is running, never on the completed screen
task.spawn(function()
    while Alive() do
        if State.m1 and not State.done and charAlive() and titansAlive() then
            pcall(clickM1)
            task.wait(M1_DELAY)
        else
            task.wait(0.2)
        end
    end
end)

-- Auto Retry
task.spawn(function()
    while Alive() do
        if State.retry and State.done and retryVisible() then
            task.wait(0.3)
            if State.retry and State.done and retryVisible() then
                pcall(clickRetry)
                task.wait(2)
            end
        end
        task.wait(0.25)
    end
end)

-- Auto Force Retry: once, FORCE_RETRY_DELAY seconds after the completed screen appears
task.spawn(function()
    local firedFor = nil
    while Alive() do
        if State.forceNow and State.done then
            if firedFor ~= State.doneAt and os.clock() - State.doneAt >= FORCE_RETRY_DELAY then
                firedFor = State.doneAt
                fireForceRetry()
            end
        end
        task.wait(0.5)
    end
end)

--------------------------------------------------------------------
-- MOBILE / REOPEN BUTTON (since the UI can auto close)
--------------------------------------------------------------------
pcall(function()
    local gui = Instance.new("ScreenGui")
    gui.Name = "AotrMiniToggle"
    gui.ResetOnSpawn = false
    gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.fromOffset(44, 44)
    btn.Position = UDim2.new(1, -54, 0, 10)
    btn.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 18
    btn.Text = "A"
    btn.Parent = gui
    Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0)

    btn.MouseButton1Click:Connect(function()
        Library:Toggle()
        if Library.Toggled and State.autoClose then
            task.delay(AUTO_CLOSE_DELAY, function()
                if Alive() and State.autoClose and Library.Toggled then
                    pcall(function() Library:Toggle() end)
                end
            end)
        end
    end)

    task.spawn(function()
        while Alive() do task.wait(1) end
        gui:Destroy()
    end)
end)

--------------------------------------------------------------------
-- SETTINGS: menu key + theme + CONFIG SAVE/LOAD
--------------------------------------------------------------------
pcall(function()
    local menu = Tabs.Settings:AddRightGroupbox("Menu")
    menu:AddLabel("Menu keybind"):AddKeyPicker("MenuKeybind", {
        Default = "LeftControl", NoUI = true, Text = "Menu keybind",
    })
    Library.ToggleKeybind = Library.Options.MenuKeybind
end)

local function safe(name, fn)
    local ok, err = pcall(fn)
    if not ok then warn("[AotrMini] " .. name .. " failed: " .. tostring(err)) end
end

safe("ThemeManager", function()
    ThemeManager:SetLibrary(Library)
    ThemeManager:SetFolder(CONFIG_FOLDER)
end)
safe("SaveManager", function()
    SaveManager:SetLibrary(Library)
    SaveManager:IgnoreThemeSettings()
    SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
    SaveManager:SetFolder(CONFIG_FOLDER)
    SaveManager:BuildConfigSection(Tabs.Settings)   -- create / save / load / autoload config
end)
safe("ThemeTab", function() ThemeManager:ApplyToTab(Tabs.Settings) end)
safe("Autoload", function() SaveManager:LoadAutoloadConfig() end)

-- sync state with whatever the loaded config set (callbacks may not fire on load)
safe("Sync", function()
    local T = Library.Toggles
    State.m1        = T.AutoM1.Value
    State.retry     = T.AutoRetry.Value
    State.forceNow  = T.AutoForceRetry.Value
    State.autoClose = T.AutoCloseUI.Value
    if State.autoClose then
        task.delay(AUTO_CLOSE_DELAY, function()
            if Alive() and State.autoClose and Library.Toggled then
                pcall(function() Library:Toggle() end)
            end
        end)
    end
end)

Library:Notify({
    Title = "AoT:R Mini",
    Description = "Loaded. Menu key: LeftCtrl, or tap the round button.",
    Time = 4,
})
