-- Smoke test outside the game: loads every TOC file against a fake WoW API with a
-- controllable clock and plays through sessions (login, money, XP, level-up, reload, new
-- login, reset, max level). Run from the addon folder: lua Tests/smoke_test.lua
local unpack = table.unpack or unpack
_G.unpack = unpack

-- Generic fake widget: known getters return sensible values, everything else is a no-op.
local GETTERS = {
    GetStringWidth = 50, GetStringHeight = 12, GetEffectiveScale = 1, GetWidth = 1920, GetHeight = 1080,
    GetLeft = 100, GetTop = 800, GetRight = 400, GetBottom = 100, GetFrameLevel = 1, IsShown = false,
    IsEnabled = true, IsVisible = true,
}
local scripts = setmetatable({}, { __mode = "k" })
local function mock(kind)
    local o = { _kind = kind, _shown = kind ~= "Frame" and true or true }
    return setmetatable(o, { __index = function(t, k)
        if type(k) ~= "string" or not k:match("^%u") then return nil end -- fields: nil, like real frames
        if k == "SetScript" then return function(self, name, fn) scripts[self] = scripts[self] or {}; scripts[self][name] = fn end end
        if k == "HookScript" then return function() end end
        if k == "GetScript" then return function(self, name) return scripts[self] and scripts[self][name] end end
        if k == "Show" then return function(self) self._shown = true; local f = scripts[self] and scripts[self].OnShow; if f then f(self) end end end
        if k == "Hide" then return function(self) local was = self._shown; self._shown = false; local f = was and scripts[self] and scripts[self].OnHide; if f then f(self) end end end
        if k == "SetShown" then return function(self, v) if v then self:Show() else self:Hide() end end end
        if k == "IsShown" then return function(self) return self._shown end end
        if k == "SetColorTexture" or k == "SetTextColor" or k == "SetVertexColor" then
            return function(_, r, g, b, a)
                for i, v in ipairs({ r, g, b }) do assert(type(v) == "number", k .. ": component " .. i .. " is " .. type(v)) end
                assert(a == nil or type(a) == "number", k .. ": alpha is " .. type(a))
            end
        end
        if k == "SetFont" then return function() return true end end
        if k == "SetText" then return function(self, v) self._text = v end end
        if k == "GetText" then return function(self) return self._text or "" end end
        if k == "GetFont" then return function() return "Fonts\\FRIZQT__.TTF", 12 end end
        if k == "CreateTexture" or k == "CreateFontString" or k == "CreateLine" then return function() return mock(k) end end
        if GETTERS[k] ~= nil then local v = GETTERS[k]; return function() return v end end
        return function() end
    end })
end

CreateFrame = function(kind, name) local f = mock(kind); f._shown = true; if name then _G[name] = f end; return f end
UIParent = mock("Frame")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) print("[chat] " .. m) end }
UISpecialFrames = {}
SlashCmdList = {}
strjoin = function(sep, ...) return table.concat({ ... }, sep) end
tostringall = function(...) local t = { ... } for i = 1, select("#", ...) do t[i] = tostring(t[i]) end return unpack(t, 1, select("#", ...)) end
strsplit = function(sep, s) local t = {} for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do t[#t + 1] = part end return unpack(t) end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
strlower, strupper, tinsert, tremove, sort, floor, ceil, min, max, format = string.lower, string.upper, table.insert, table.remove, table.sort, math.floor, math.ceil, math.min, math.max, string.format
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
date = os.date
local now = 1000000
time = function() return now end
CopyTable = function(t) local c = {} for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end return c end
local errors = {}
geterrorhandler = function() return function(e) errors[#errors + 1] = e; print("ERROR: " .. tostring(e)) end end
C_Timer = { After = function(_, fn) fn() end }
C_AddOns = { GetAddOnMetadata = function() return "test" end }
C_Timer.NewTicker = function() return { Cancel = function() end } end
GetPhysicalScreenSize = function() return 2560, 1440 end
IsShiftKeyDown = function() return false end
GetCursorPosition = function() return 500, 500 end
BreakUpLargeNumbers = function(n) return tostring(n) end
RAID_CLASS_COLORS = { DRUID = { r = 1, g = 0.49, b = 0.04 } }

-- The player: controllable money / XP / level.
local P = { money = 1000, xp = 100, xpMax = 1000, level = 2, maxLevel = 20 }
UnitGUID = function() return "Player-1-A" end
UnitName = function() return "Allemano", "Moo" end
UnitClass = function() return "Druid", "DRUID", 11 end
UnitLevel = function() return P.level end
UnitXP = function() return P.xp end
UnitXPMax = function() return P.xpMax end
GetMoney = function() return P.money end
GetMaxPlayerLevel = function() return P.maxLevel end

local ST = {}
for line in io.lines("SessionTracker.toc") do
    line = line:gsub("\r", "")
    if line ~= "" and not line:match("^#") then assert(loadfile((line:gsub("\\", "/"))))("SessionTracker", ST) end
end

local function fire(event, ...)
    for f, s in pairs(scripts) do if s.OnEvent then s.OnEvent(f, event, ...) end end
end
local function step(name, fn)
    local ok, err = pcall(fn)
    print((ok and "ok   " or "FAIL ") .. name .. (ok and "" or (": " .. tostring(err))))
    if not ok then errors[#errors + 1] = err end
end
local function cur() return ST.db.chars["Player-1-A"].current end
local function history() return ST.db.chars["Player-1-A"].history end
local function rowText(i) return _G.SessionTrackerFrame.rows[i].value._text end

step("login starts a session and shows the window", function()
    fire("ADDON_LOADED", "SessionTracker")
    fire("PLAYER_ENTERING_WORLD", true, false)
    assert(cur() and cur().startMoney == 1000, "no session")
    assert(_G.SessionTrackerFrame._shown, "window not shown")
end)
step("money and XP", function()
    now = now + 1800
    P.money = 21000
    fire("PLAYER_MONEY")
    P.xp = 300
    fire("PLAYER_XP_UPDATE", "player")
    local s = ST.Session.Stats()
    assert(s.gold == 20000, "gold " .. s.gold)
    assert(math.abs(s.goldPerHour - 40000) < 1, "gold/h " .. tostring(s.goldPerHour))
    assert(s.xpGained == 200, "xp " .. s.xpGained)
    assert(math.abs(s.timeToLevel - (700 / 400 * 3600)) < 1, "time to level " .. tostring(s.timeToLevel))
    ST.Window.Refresh()
    assert(rowText(2):find("2") and rowText(2):find("g"), "gold row: " .. tostring(rowText(2)))
end)
step("level-up counts the rest of the old level", function()
    P.xp = 900
    fire("PLAYER_XP_UPDATE", "player")
    P.level, P.xp, P.xpMax = 3, 50, 1400
    fire("PLAYER_LEVEL_UP", 3)
    local s = ST.Session.Stats()
    assert(s.xpGained == 800 + 100 + 50, "xp across level-up " .. s.xpGained)
    assert(s.levels == 1, "levels " .. s.levels)
end)
step("losing money shows as minus", function()
    P.money = 500
    fire("PLAYER_MONEY")
    ST.Window.Refresh()
    assert(ST.Session.Stats().gold == -500, "gold")
    assert(rowText(2):find("%-"), "no minus: " .. tostring(rowText(2)))
end)
step("reload keeps the session", function()
    local start = cur().start
    fire("PLAYER_LOGOUT")
    now = now + 5
    fire("ADDON_LOADED", "SessionTracker")
    fire("PLAYER_ENTERING_WORLD", false, true)
    assert(cur().start == start and cur().xpGained == 950, "session lost on reload")
end)
step("logout does not read money", function()
    P.money = 0
    fire("PLAYER_LOGOUT")
    assert(cur().money == 500, "money read at logout")
    P.money = 500
end)
step("new login archives the old session", function()
    now = now + 3600
    fire("PLAYER_ENTERING_WORLD", true, false)
    assert(#history() == 1, "history " .. #history())
    assert(history()[1].money == -500 and history()[1].xpGained == 950 and history()[1].levels == 1, "archived values")
    assert(cur().xpGained == 0 and cur().startLevel == 3, "new session not fresh")
end)
step("without login info: quiet for long = new session", function()
    now = now + 120
    fire("PLAYER_ENTERING_WORLD")
    assert(#history() == 1, "short quiet gap should keep the session")
    now = now + 3600
    fire("PLAYER_ENTERING_WORLD")
    assert(#history() == 2, "long quiet gap should start a new session")
end)
step("reset", function()
    now = now + 90
    SlashCmdList.SESSIONTRACKER("reset")
    assert(#history() == 3 and cur().start == now, "reset did not archive/start")
end)
step("max level", function()
    P.level = 20
    fire("PLAYER_XP_UPDATE", "player")
    ST.Window.Refresh()
    assert(ST.Session.Stats().maxLevel, "not max level")
    assert(rowText(6) == "max level", "next level row: " .. tostring(rowText(6)))
    assert(not _G.SessionTrackerFrame.track._shown, "level bar still shown")
end)
step("hide and show", function()
    SlashCmdList.SESSIONTRACKER("")
    assert(not _G.SessionTrackerFrame._shown and ST.db.window.shown == false, "not hidden")
    fire("PLAYER_ENTERING_WORLD", false, true)
    assert(not _G.SessionTrackerFrame._shown, "came back after reload although hidden")
    SlashCmdList.SESSIONTRACKER("")
    assert(_G.SessionTrackerFrame._shown, "not shown again")
end)
step("title menu", function()
    local realOpen, items = ST.Widgets.OpenMenu, nil
    ST.Widgets.OpenMenu = function(list) items = list end
    for f, s in pairs(scripts) do if s.OnMouseUp and s.OnDragStart then s.OnMouseUp(f, "RightButton") end end
    ST.Widgets.OpenMenu = realOpen
    assert(items and #items == 4, "menu not opened")
end)
step("slash errors", function() SlashCmdList.SESSIONTRACKER("errors") end)

print(#errors == 0 and "ALL OK" or (#errors .. " error(s)"))
os.exit(#errors == 0 and 0 or 1)
