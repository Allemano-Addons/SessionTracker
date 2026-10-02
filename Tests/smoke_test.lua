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
local scripts = {} -- strong: real frames are kept alive by their parent, mocks are not
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
        if k == "CreateTexture" or k == "CreateFontString" or k == "CreateLine" then
            return function(self) local m = mock(k); m._parent = self; return m end
        end
        -- Geometry and layers used by W.Round / W.RoundBorder (same as AltBoard's test).
        if k == "GetParent" then return function(self) return self._parent or UIParent end end
        if k == "GetNumPoints" then return function() return 0 end end
        if k == "GetSize" then return function() return 0, 0 end end
        if k == "GetDrawLayer" then return function() return "ARTWORK", 0 end end
        if k == "GetAlpha" then return function() return 1 end end
        if k == "SetTexture" then return function() return true end end
        if GETTERS[k] ~= nil then local v = GETTERS[k]; return function() return v end end
        return function() end
    end })
end

CreateFrame = function(kind, name, parent) local f = mock(kind); f._shown = true; f._parent = parent; if name then _G[name] = f end; return f end
UIParent = mock("Frame")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) print("[chat] " .. m) end }
UISpecialFrames = {}
SlashCmdList = {}
strjoin = function(sep, ...) return table.concat({ ... }, sep) end
tostringall = function(...) local t = { ... } for i = 1, select("#", ...) do t[i] = tostring(t[i]) end return unpack(t, 1, select("#", ...)) end
strsplit = function(sep, s) local t = {} for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do t[#t + 1] = part end return unpack(t) end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
abs = math.abs
strlower, strupper, tinsert, tremove, sort, floor, ceil, min, max, format = string.lower, string.upper, table.insert, table.remove, table.sort, math.floor, math.ceil, math.min, math.max, string.format
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
date = os.date
local now = 1790000000
time = function() return now end
CopyTable = function(t) local c = {} for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end return c end
local errors = {}
geterrorhandler = function() return function(e) errors[#errors + 1] = e; print("ERROR: " .. tostring(e)) end end
-- Timers: 0 s (next frame) and long safety timers wait for runQueued(); the rest run at once.
local queued = {}
C_Timer = { After = function(d, fn) if d == 0 or d >= 10 then queued[#queued + 1] = fn else fn() end end }
local function runQueued() local q = queued; queued = {}; for _, fn in ipairs(q) do fn() end end
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
GetRealZoneText = function() return P.zone or "The Barrens" end
-- Ledger: world state the addon looks at.
local W_ = { instance = false, itype = "none", repairAll = 0, sendMoney = 0, inbox = {}, invoice = {} }
IsInInstance = function() return W_.instance, W_.itype end
CanMerchantRepair = function() return W_.repairAll > 0 end
GetRepairAllCost = function() return W_.repairAll end
GetSendMailMoney = function() return W_.sendMoney end
GetInboxHeaderInfo = function(i) local m = W_.inbox[i]; return nil, nil, m and m.sender, nil, m and m.money end
GetInboxInvoiceInfo = function(i) return W_.invoice[i] end
GetRewardMoney = function() return 0 end
local lootSlots = {}
GetNumLootItems = function() return #lootSlots end
LootSlotHasItem = function(i) return lootSlots[i] ~= nil end
GetLootSlotLink = function(i) return lootSlots[i] and lootSlots[i].link end
GetLootSlotInfo = function(i) return nil, nil, lootSlots[i] and lootSlots[i].qty, lootSlots[i] and lootSlots[i].rarity end
GetItemInfo = function(link)
    local quality = link == "[Epic Sword]" and 4 or 1
    local price = link == "[Linen Cloth]" and 13 or (link == "[Epic Sword]" and 500 or 0)
    return nil, nil, quality, nil, nil, nil, nil, nil, nil, nil, price
end
COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience."
FACTION_STANDING_INCREASED = "Reputation with %s increased by %d."
FACTION_STANDING_DECREASED = "Reputation with %s decreased by %d."
TakeInboxMoney = function() end
AutoLootMailItem = function() end
RepairAllItems = function() end
SendMail = function() end
hooksecurefunc = function(name, fn)
    local orig = _G[name]
    _G[name] = function(...) local a = orig(...); fn(...); return a end
end
-- /played: requests are counted; the chat frames print through ChatFrame_DisplayTimePlayed.
local playedRequests, chatPrints = 0, 0
RequestTimePlayed = function() playedRequests = playedRequests + 1 end
ChatFrame_DisplayTimePlayed = function() chatPrints = chatPrints + 1 end

local ST = {}
for line in io.lines("AllemanoLedger.toc") do
    line = line:gsub("\r", "")
    if line ~= "" and not line:match("^#") then assert(loadfile((line:gsub("\\", "/"))))("AllemanoLedger", ST) end
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
local function rowText(i) return _G.AllemanoLedgerFrame.rows[i].value._text end

step("login starts a session and shows the window", function()
    fire("ADDON_LOADED", "AllemanoLedger")
    fire("PLAYER_ENTERING_WORLD", true, false)
    assert(cur() and cur().startMoney == 1000, "no session")
    assert(_G.AllemanoLedgerFrame._shown, "window not shown")
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
    fire("ADDON_LOADED", "AllemanoLedger")
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
    assert(not _G.AllemanoLedgerFrame.track:IsShown(), "level bar still shown")
end)
step("hide and show", function()
    SlashCmdList.SESSIONTRACKER("")
    assert(not _G.AllemanoLedgerFrame._shown and ST.db.window.shown == false, "not hidden")
    fire("PLAYER_ENTERING_WORLD", false, true)
    assert(not _G.AllemanoLedgerFrame._shown, "came back after reload although hidden")
    SlashCmdList.SESSIONTRACKER("")
    assert(_G.AllemanoLedgerFrame._shown, "not shown again")
end)
step("title menu", function()
    local realOpen, items = ST.Widgets.OpenMenu, nil
    ST.Widgets.OpenMenu = function(list) items = list end
    for f, s in pairs(scripts) do if s.OnMouseUp and s.OnDragStart then s.OnMouseUp(f, "RightButton") end end
    ST.Widgets.OpenMenu = realOpen
    assert(items and #items == 6, "menu not opened: " .. tostring(ST.errors[#ST.errors] and ST.errors[#ST.errors].msg))
    for _, it in ipairs(items) do assert(it.text ~= "Level times", "Level times still in the menu") end
end)
step("slash errors", function() SlashCmdList.SESSIONTRACKER("errors") end)

-- Level times.
local function c() return ST.db.chars["Player-1-A"] end
step("login learns the start of the current level, chat line hidden", function()
    runQueued()
    P.level, P.xp, P.xpMax = 5, 100, 1000
    local before = playedRequests
    fire("PLAYER_ENTERING_WORLD", true, false)
    assert(playedRequests == before + 1, "no /played request at login")
    fire("TIME_PLAYED_MSG", 5000, 600)
    ChatFrame_DisplayTimePlayed() -- the chat frames print during the same event
    assert(chatPrints == 0, "our /played request was printed in chat")
    runQueued()
    ChatFrame_DisplayTimePlayed() -- the player's own /played later
    assert(chatPrints == 1, "the player's own /played was hidden")
    assert(c().levelStart.level == 5 and c().levelStart.playedTotal == 4400, "level start wrong")
    now = now + 300
    assert(ST.Levels.CurrentLevelTime() == 900, "current level time " .. tostring(ST.Levels.CurrentLevelTime()))
end)
step("ding logs the level that ended", function()
    P.level = 6
    fire("PLAYER_LEVEL_UP", 6)
    now = now + 10
    fire("TIME_PLAYED_MSG", 5310, 10)
    runQueued()
    local e = c().levelLog[5]
    assert(e and e.played == 900, "level 5 played " .. tostring(e and e.played))
    assert(e.wall == nil and e.zone == "The Barrens", "wall/zone")
    assert(c().levelStart.level == 6 and c().levelStart.playedTotal == 5300, "new level start")
end)
step("second ding has real time too", function()
    now = now + 7200
    P.level = 7
    fire("PLAYER_LEVEL_UP", 7)
    fire("TIME_PLAYED_MSG", 5300 + 2000, 0)
    runQueued()
    local e = c().levelLog[6]
    assert(e.played == 2000 and e.wall == 7210, "level 6: " .. tostring(e.played) .. " / " .. tostring(e.wall))
    local list = ST.Levels.List()
    assert(#list == 3 and list[3].current and list[3].level == 7, "list")
end)
step("two levels at once", function()
    P.level = 9
    fire("PLAYER_LEVEL_UP", 8)
    fire("PLAYER_LEVEL_UP", 9)
    fire("TIME_PLAYED_MSG", 8000, 0)
    runQueued()
    assert(c().levelLog[7].played == nil and c().levelLog[8].played == nil, "in-between levels should have no played time")
    assert(c().levelStart.level == 9 and c().levelStart.playedTotal == 8000, "start of level 9")
end)
step("level times window and the This level row", function()
    ST.Window.Refresh()
    assert(rowText(7) and rowText(7) ~= "...", "This level row: " .. tostring(rowText(7)))
    local hit = _G.AllemanoLedgerFrame.levelTimesButton
    scripts[hit].OnEnter(hit)
    scripts[hit].OnClick(hit)
    local f = _G.AllemanoLedgerLevelsFrame
    assert(f and f._shown, "level times window not shown")
    local rows = 0
    for _, row in ipairs(f.rows) do if row._shown and row.entry then rows = rows + 1 end end
    assert(rows == 4, "rows " .. rows) -- finished levels only (5, 6, 7, 8), newest first
    assert(f.rows[1].entry.level == 8, "newest level should be first")
    scripts[f.rows[1]].OnEnter(f.rows[1])
    SlashCmdList.SESSIONTRACKER("levels")
    assert(not f._shown, "did not close")
end)

-- Settings.
local main = function() return _G.AllemanoLedgerFrame end
step("settings window opens and every control works", function()
    SlashCmdList.SESSIONTRACKER("settings")
    local f = _G.AllemanoLedgerSettingsFrame
    assert(f and f._shown, "settings not shown")
    -- Click every toggle twice (off and back on).
    local toggles = 0
    for b, s in pairs(scripts) do
        if s.OnClick and rawget(b, "track") and rawget(b, "knob") then
            s.OnClick(b)
            s.OnClick(b)
            toggles = toggles + 1
        end
    end
    assert(toggles == 7 + 3, "toggles found: " .. toggles)
    SlashCmdList.SESSIONTRACKER("settings")
    assert(not f._shown, "settings did not close")
end)
step("row switched off disappears, window gets shorter", function()
    main():Show()
    ST.Window.Refresh()
    local full = main().rowsH
    ST.db.settings.rows.gold = false
    ST:SetSetting("rows", ST.db.settings.rows)
    assert(not main().rows[2].label._shown and not main().rows[2].value._shown, "gold row still shown")
    assert(main().rowsH == full - 22, "height " .. main().rowsH .. " vs " .. full)
    ST.db.settings.rows.thisLevel = false
    ST:SetSetting("rows", ST.db.settings.rows)
    assert(not main().levelTimesButton._shown, "click area of a hidden row still shown")
    ST.db.settings.rows.gold, ST.db.settings.rows.thisLevel = true, true
    ST:SetSetting("rows", ST.db.settings.rows)
end)
step("level bar setting", function()
    P.level = 9
    ST:SetSetting("levelBar", false)
    assert(not main().track:IsShown(), "bar shown although off")
    ST:SetSetting("levelBar", true)
    assert(main().track:IsShown(), "bar not back")
end)
step("hide in combat", function()
    ST:SetSetting("hideInCombat", true)
    fire("PLAYER_REGEN_DISABLED")
    assert(not main()._shown, "not hidden in combat")
    fire("PLAYER_REGEN_ENABLED")
    assert(main()._shown and ST.db.window.shown ~= false, "not back after combat")
    ST:SetSetting("hideInCombat", false)
    fire("PLAYER_REGEN_DISABLED")
    assert(main()._shown, "hidden although the setting is off")
end)
step("manual sessions go on over logins, counting online time only", function()
    ST:SetSetting("newSession", "manual")
    local s0 = cur()
    local before = #history()
    now = now + 600
    ST.Session.Stats() -- the ticker keeps lastSeen current
    local online = ST.Session.Stats().elapsed
    fire("PLAYER_LOGOUT")
    now = now + 5000 -- offline
    fire("PLAYER_ENTERING_WORLD", true, false)
    assert(cur() == s0 and #history() == before, "a new session started")
    now = now + 30
    assert(ST.Session.Stats().elapsed == online + 30, "offline time counted: " .. ST.Session.Stats().elapsed .. " vs " .. (online + 30))
    ST:SetSetting("newSession", "login")
    fire("PLAYER_LOGOUT")
    now = now + 100
    fire("PLAYER_ENTERING_WORLD", true, false)
    assert(cur() ~= s0 and #history() == before + 1, "login mode should start a new session")
    assert(history()[1].duration == online + 30, "archived duration " .. tostring(history()[1].duration))
end)

-- Level times: the "Levels" button, no ESC, stays open over reloads, X closes it.
step("Levels button toggles level times", function()
    local b = main().levelsButton
    assert(b, "no Levels button")
    scripts[b].OnClick(b)
    local f = _G.AllemanoLedgerLevelsFrame
    assert(f._shown and ST.LevelsUI.IsOpen(), "not opened by the button: " .. tostring(ST.errors[#ST.errors] and ST.errors[#ST.errors].msg))
    for _, name in ipairs(UISpecialFrames) do
        assert(name ~= "AllemanoLedgerLevelsFrame", "ESC would close level times")
    end
    scripts[b].OnClick(b)
    assert(not f._shown and not ST.LevelsUI.IsOpen(), "not closed by the button")
end)
step("level times stays open over a reload, X closes it", function()
    ST.LevelsUI.SetShown(true)
    local f = _G.AllemanoLedgerLevelsFrame
    f:Hide() -- the UI going away on /reload
    fire("PLAYER_ENTERING_WORLD", false, true)
    assert(f._shown, "not reopened after reload")
    -- The X is the CloseButton in its title bar.
    local closed = false
    for btn, s in pairs(scripts) do
        if not closed and s.OnClick and rawget(btn, "text") and btn.text._text == "x" and f._shown then
            s.OnClick(btn)
            if not f._shown then closed = true end
        end
    end
    local xs = 0
    for btn, s in pairs(scripts) do if s.OnClick and rawget(btn, "text") and btn.text._text == "x" then xs = xs + 1 end end
    assert(closed and not ST.LevelsUI.IsOpen(), "X did not close it (x buttons: " .. xs .. ", shown " .. tostring(f._shown) .. ")")
    fire("PLAYER_ENTERING_WORLD", false, true)
    assert(not f._shown, "came back although closed")
end)

-- ===========================================================================
-- Allemano Ledger: where the gold came from
-- ===========================================================================
local function today_() return c().days[ST.Ledger.DayKey()] end
-- Click every button that matches (a snapshot first: clicking builds frames, and adding keys to
-- `scripts` while walking it would make the walk undefined).
local function clickAll(match)
    local found = {}
    for btn, s in pairs(scripts) do
        if s.OnClick and match(btn) then found[#found + 1] = btn end
    end
    for _, btn in ipairs(found) do scripts[btn].OnClick(btn) end
    return #found
end
step("Ledger: resync after the earlier tests", function()
    P.zone = nil
    P.money = 100000
    fire("PLAYER_ENTERING_WORLD", false, true)
    ST.db.chars["Player-2-B"] = { name = "Mirelle", class = "MAGE", history = {}, days = {} } -- another own character
    assert(cur().inc and cur().exp, "no tallies")
end)
step("Ledger: vendor sale, repair and purchase", function()
    local inc0 = (cur().inc.vendor or 0)
    fire("MERCHANT_SHOW")
    P.money = P.money + 500; fire("PLAYER_MONEY")
    assert(cur().inc.vendor == inc0 + 500, "vendor income " .. tostring(cur().inc.vendor))
    W_.repairAll = 300
    fire("MERCHANT_UPDATE")
    P.money = P.money - 300; fire("PLAYER_MONEY")
    assert(cur().exp.repair == 300, "repair " .. tostring(cur().exp.repair))
    P.money = P.money - 50; fire("PLAYER_MONEY")
    assert(cur().exp.vendor == 50, "purchase " .. tostring(cur().exp.vendor))
    -- Repair All pressed: even a different amount (a discount) is a repair.
    RepairAllItems()
    P.money = P.money - 120; fire("PLAYER_MONEY")
    assert(cur().exp.repair == 420, "repair via hook " .. tostring(cur().exp.repair))
    fire("MERCHANT_CLOSED")
    W_.repairAll = 0
end)
step("Ledger: quest reward and loot coins", function()
    fire("QUEST_TURNED_IN", 1, 100, 700)
    P.money = P.money + 700; fire("PLAYER_MONEY")
    assert(cur().inc.quest == 700, "quest " .. tostring(cur().inc.quest))
    lootSlots = { { link = "[Linen Cloth]", qty = 4 } }
    fire("LOOT_OPENED")
    P.money = P.money + 40; fire("PLAYER_MONEY")
    assert(cur().inc.loot == 40, "loot " .. tostring(cur().inc.loot))
    fire("LOOT_SLOT_CLEARED", 1)
    assert(cur().lootValue == 52 and cur().items == 4, "loot value " .. tostring(cur().lootValue))
    fire("LOOT_CLOSED")
    lootSlots = {}
end)
step("Ledger: mail from your own character is a transfer, AH proceeds are income", function()
    fire("MAIL_SHOW")
    W_.inbox[1] = { sender = "Mirelle", money = 1000 }
    TakeInboxMoney(1)
    P.money = P.money + 1000; fire("PLAYER_MONEY")
    assert(cur().xfer == 1000 and not cur().inc.mail, "transfer in: " .. tostring(cur().xfer))
    assert(today_().xferIn == 1000, "day transfer")
    W_.inbox[2] = { sender = "Auction House", money = 2000 }
    W_.invoice[2] = "seller"
    TakeInboxMoney(2)
    P.money = P.money + 2000; fire("PLAYER_MONEY")
    assert(cur().inc.ah == 2000, "ah " .. tostring(cur().inc.ah))
    -- Sending 500 to the alt costs 30 postage on top.
    W_.sendMoney = 500
    fire("MAIL_SEND_INFO_UPDATE")
    SendMail("Mirelle")
    P.money = P.money - 530; fire("PLAYER_MONEY")
    assert(cur().xfer == 1500 and cur().exp.mail == 30, "send: " .. tostring(cur().xfer) .. " / " .. tostring(cur().exp.mail))
    fire("MAIL_CLOSED")
end)
step("Ledger: unexplained money is other, numbers add up", function()
    now = now + 10 -- out of the grace windows
    P.money = P.money + 99; fire("PLAYER_MONEY")
    assert(cur().inc.other and cur().inc.other >= 99, "other")
    local s = ST.Session.Stats()
    local earned = 0
    for _, v in pairs(cur().inc) do earned = earned + v end
    assert(s.earned == earned and s.gold == s.earned - s.spent, "net")
    assert(s.xfer == 1500, "xfer in stats")
    assert(#cur().series > 3, "graph points " .. #cur().series)
end)
step("Ledger: pause freezes the clock and the tallies", function()
    local before = ST.Session.Stats()
    ST.Session.Pause()
    now = now + 600
    P.money = P.money + 1000; fire("PLAYER_MONEY")
    local during = ST.Session.Stats()
    assert(during.paused and during.elapsed == before.elapsed, "clock ran while paused")
    assert(during.earned == before.earned, "session counted gold while paused")
    assert(today_().inc.other >= 1000 + 99, "the day still counts it")
    ST.Session.Resume()
    now = now + 30
    assert(ST.Session.Stats().elapsed == before.elapsed + 30, "resume")
end)
step("Ledger: day and lifetime totals, heartbeat", function()
    ST.Ledger.Heartbeat()
    now = now + 15
    ST.Ledger.Heartbeat()
    assert(today_().time >= 15, "time online")
    local d = ST.Ledger.Day(ST.Ledger.DayKey())
    assert(d.inc.vendor >= 500 and d.exp.repair == 420, "day totals")
    local life = ST.Ledger.Lifetime()
    assert(life.firstDay and life.xferIn >= 1000, "lifetime")
    assert(#ST.Ledger.RecentDays(14) == 14 and ST.Ledger.RecentDays(1)[1] == ST.Ledger.DayKey(), "recent days")
    local gold = ST.Ledger.GoldOverTime(30)
    assert(#gold >= 1 and gold[#gold][2] > 0, "gold over time")
end)
step("Ledger: tags", function()
    assert(ST.Session.Tag(cur()) ~= nil, "no tag")
    ST.Session.SetTag("Dungeon")
    assert(ST.Session.Stats().tag == "Dungeon", "manual tag")
    ST.Session.SetTag(nil)
    assert(ST.Session.Stats().tag == "Leveling" or ST.Session.Stats().tag == "Farming", "auto tag")
end)
step("Ledger: window opens, every tab and range builds", function()
    local before = #ST.errors
    SlashCmdList.ALLEMANOLEDGER("")
    local f = _G.AllemanoLedgerWindow
    assert(f and f._shown, "Ledger window not shown")
    local tabs = clickAll(function(btn) return rawget(btn, "underline") end)
    assert(tabs == 7, "tabs " .. tabs)
    -- History: every range button.
    clickAll(function(btn) return rawget(btn, "text") and btn.text._text and (btn.text._text:find("days") or btn.text._text == "All") end)
    SlashCmdList.ALLEMANOLEDGER("history")
    SlashCmdList.ALLEMANOLEDGER("lifetime")
    assert(#ST.errors == before, "errors while drawing: " .. tostring(ST.errors[#ST.errors] and ST.errors[#ST.errors].msg))
    SlashCmdList.ALLEMANOLEDGER("")
    assert(not f._shown, "toggle did not close")
end)
step("Ledger: the HUD shows Paused", function()
    ST.Session.Pause()
    ST.Window.Refresh()
    assert(rowText(1) == "Paused", "HUD time row: " .. tostring(rowText(1)))
    ST.Session.Resume()
end)
step("Ledger: an instance run ends with a summary that can be saved", function()
    ST.Ledger.Heartbeat()
    P.zone = "Deadmines"
    W_.instance, W_.itype = true, "party"
    fire("ZONE_CHANGED_NEW_AREA")
    assert(c().run and c().run.tag == "Dungeon", "run not started")
    fire("MERCHANT_SHOW")
    P.money = P.money + 4000; fire("PLAYER_MONEY")
    fire("MERCHANT_CLOSED")
    now = now + 4000
    ST.Ledger.Heartbeat()
    W_.instance, W_.itype = false, "none"
    P.zone = "Stormwind"
    fire("ZONE_CHANGED_NEW_AREA")
    assert(not c().run and c().pendingRun and c().pendingRun.inc.vendor == 4000, "run not finished")
    local pop = _G.AllemanoLedgerRunSummary
    assert(pop and pop._shown, "summary not shown")
    local saved = clickAll(function(btn) return rawget(btn, "primary") and btn.text._text == "Save to history" end) == 1
    assert(saved and not pop._shown and not c().pendingRun, "not saved")
    assert(c().history[1].kind == "run" and c().history[1].zone == "Deadmines" and c().history[1].net == 4000, "run in history")
end)
step("Ledger: a short visit leaves no summary", function()
    W_.instance, W_.itype = true, "party"
    P.zone = "Wailing Caverns"
    fire("ZONE_CHANGED_NEW_AREA")
    now = now + 30
    W_.instance, W_.itype = false, "none"
    fire("ZONE_CHANGED_NEW_AREA")
    assert(not c().pendingRun, "summary for a 30 s visit")
end)
step("Ledger: kills, deaths, items by quality, rare drops", function()
    local k0 = cur().kills
    fire("CHAT_MSG_COMBAT_XP_GAIN", "Defias Thug dies, you gain 55 experience.")
    fire("CHAT_MSG_COMBAT_XP_GAIN", "Wolf dies, you gain 60 experience. (+12 exp Rested bonus)")
    fire("CHAT_MSG_COMBAT_XP_GAIN", "You gain 300 experience.") -- a quest, not a kill
    assert(cur().kills == k0 + 2, "kills " .. tostring(cur().kills))
    fire("PLAYER_DEAD")
    assert(cur().deaths == 1 and today_().deaths == 1, "deaths")
    lootSlots = { { link = "[Epic Sword]", qty = 1, rarity = 4 }, { link = "[Linen Cloth]", qty = 2, rarity = 1 } }
    fire("LOOT_OPENED")
    fire("LOOT_SLOT_CLEARED", 1)
    fire("LOOT_SLOT_CLEARED", 2)
    fire("LOOT_CLOSED")
    lootSlots = {}
    assert(cur().qItems[4] == 1 and cur().qItems[1] >= 6, "items by quality")
    assert(today_().items[4] == 1, "day items")
    assert(#ST.Ledger.Notable() == 1 and ST.Ledger.Notable()[1].link == "[Epic Sword]", "rare drop list")
end)
step("Ledger: reputation from the chat line", function()
    fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "Reputation with Stormwind increased by 75.")
    fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "Reputation with Stormwind increased by 25.")
    fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "Reputation with Darnassus decreased by 10.")
    fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "something unrelated")
    assert(cur().rep.Stormwind == 100 and cur().rep.Darnassus == -10, "rep " .. tostring(cur().rep.Stormwind))
    assert(today_().rep.Stormwind == 100, "day rep")
end)
step("Ledger: quest XP, whichever comes first", function()
    local q0 = cur().xpQuest
    P.xp = P.xp + 300
    fire("PLAYER_XP_UPDATE", "player")
    fire("QUEST_TURNED_IN", 7, 300, 0) -- the XP bar moved first
    assert(cur().xpQuest == q0 + 300, "quest xp after " .. tostring(cur().xpQuest))
    fire("QUEST_TURNED_IN", 8, 200, 0) -- the quest event first
    P.xp = P.xp + 250
    fire("PLAYER_XP_UPDATE", "player")
    assert(cur().xpQuest == q0 + 500, "quest xp before " .. tostring(cur().xpQuest))
    assert(today_().xpQuest == cur().xpQuest and today_().xp >= 550, "day xp")
end)
step("Ledger: periods", function()
    local s, d, w, a = ST.Ledger.Period("session"), ST.Ledger.Period("today"), ST.Ledger.Period("week"), ST.Ledger.Period("all")
    assert(s.kills == 2 and s.itemCount >= 7 and s.xpQuest == cur().xpQuest, "session period")
    assert(d.kills == 2 and d.items[4] == 1 and d.rep.Stormwind == 100 and d.inc.vendor >= 500, "today period")
    assert(w.kills == 2 and a.kills == 2 and a.xp >= d.xp, "week / all")
end)
step("Ledger: Progress and Loot tabs draw", function()
    local before = #ST.errors
    SlashCmdList.ALLEMANOLEDGER("")
    clickAll(function(btn) return rawget(btn, "underline") and (btn.text._text == "Progress" or btn.text._text == "Loot") end)
    for _, period in ipairs({ "Session", "Today", "7 days", "All time" }) do
        assert(clickAll(function(btn) return rawget(btn, "text") and btn.text._text == period and not rawget(btn, "underline") end) >= 2, "period " .. period)
    end
    assert(#ST.errors == before, "errors: " .. tostring(ST.errors[#ST.errors] and ST.errors[#ST.errors].msg))
    SlashCmdList.ALLEMANOLEDGER("")
end)
step("Ledger: first start after the rename takes over the old data", function()
    AllemanoLedgerDB = nil
    SessionTrackerDB = { chars = { ["Player-9-Z"] = { name = "Old", history = {} } }, settings = {} }
    fire("ADDON_LOADED", "AllemanoLedger")
    assert(AllemanoLedgerDB.chars["Player-9-Z"] and AllemanoLedgerDB.migratedFrom == "SessionTrackerDB", "not migrated")
    assert(SessionTrackerDB.chars["Player-9-Z"], "old data must stay")
    assert(AllemanoLedgerDB.chars ~= SessionTrackerDB.chars, "must be a copy")
end)

print(#errors == 0 and "ALL OK" or (#errors .. " error(s)"))
os.exit(#errors == 0 and 0 or 1)
