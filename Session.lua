-- Session: what the current play session has brought. Saved per character so a /reload
-- keeps it; a new login starts a new session (the old one goes to the history).
--
-- SessionTrackerDB.chars[guid] = {
--     name, class,
--     current = { start, lastSeen, startMoney, money, xp, xpMax, level, startLevel, xpGained },
--     history = { { start, stop, money, xpGained, levels }, ... }  (newest first, max 50)
-- }
local _, ST = ...

local Session = {}
ST.Session = Session

local HISTORY_MAX = 50
local MIN_SESSION = 60      -- shorter sessions are not kept in the history
local STALE_AFTER = 10 * 60 -- without login/reload info: this long offline = new session

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

local function playerName()
    local name, surname = UnitName("player")
    if type(surname) == "string" and surname ~= "" then return (name or "?") .. " " .. surname end
    return name or "?"
end

local function char()
    local guid = UnitGUID("player")
    if not guid or not ST.db then return nil end
    local c = ST.db.chars[guid]
    if not c then
        c = { history = {} }
        ST.db.chars[guid] = c
    end
    c.name = playerName()
    c.class = select(2, UnitClass("player"))
    return c
end

-- Close the current session into the history (if it lasted long enough).
local function archive(c)
    local s = c.current
    if not s then return end
    local stop = s.lastSeen or s.start
    if stop - s.start >= MIN_SESSION then
        tinsert(c.history, 1, {
            start = s.start, stop = stop,
            money = (s.money or s.startMoney or 0) - (s.startMoney or 0),
            xpGained = s.xpGained or 0,
            levels = (s.level or 0) - (s.startLevel or 0),
        })
        while #c.history > HISTORY_MAX do tremove(c.history) end
    end
    c.current = nil
end

local function newSession(c)
    local now = time()
    c.current = {
        start = now, lastSeen = now,
        startMoney = GetMoney(), money = GetMoney(),
        xp = UnitXP("player"), xpMax = UnitXPMax("player"),
        level = UnitLevel("player"), startLevel = UnitLevel("player"),
        xpGained = 0,
    }
end

function Session.Current()
    local c = ST.db and UnitGUID("player") and ST.db.chars[UnitGUID("player")]
    return c and c.current, c
end

-- Manual reset: the running session goes to the history, a new one starts now.
function Session.Reset()
    local c = char()
    if not c then return end
    if c.current then c.current.lastSeen = time() end
    archive(c)
    newSession(c)
    Session.Changed()
end

-- The window replaces this to redraw.
function Session.Changed() end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

-- isInitialLogin / isReloadingUi tell a new login from a /reload. Older clients may not
-- pass them: then a session that was quiet for STALE_AFTER counts as over.
ST:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isInitialLogin, isReloadingUi)
    local c = char()
    if not c then return end
    local s = c.current
    local isNew
    if isInitialLogin ~= nil or isReloadingUi ~= nil then
        isNew = isInitialLogin and not isReloadingUi
    else
        isNew = not s or (time() - (s.lastSeen or 0)) > STALE_AFTER
    end
    if isNew or not s then
        archive(c)
        newSession(c)
    else
        -- Same session: catch up on anything that happened while the UI was reloading.
        s.money = GetMoney()
        s.lastSeen = time()
    end
    Session.Changed()
end)

ST:RegisterEvent("PLAYER_MONEY", function()
    local s = Session.Current()
    if not s then return end
    s.money = GetMoney()
    s.lastSeen = time()
    Session.Changed()
end)

-- XP gained, across level-ups: the rest of the old level plus what is into the new one.
local function updateXP()
    local s = Session.Current()
    if not s then return end
    local xp, xpMax, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    if level > (s.level or level) then
        s.xpGained = s.xpGained + math.max(0, (s.xpMax or 0) - (s.xp or 0)) + xp
    elseif xp > (s.xp or 0) then
        s.xpGained = s.xpGained + (xp - s.xp)
    end
    s.xp, s.xpMax, s.level = xp, xpMax, level
    s.lastSeen = time()
    Session.Changed()
end
ST:RegisterEvent("PLAYER_XP_UPDATE", updateXP)
ST:RegisterEvent("PLAYER_LEVEL_UP", function()
    -- UnitLevel may still say the old level here; read once the new values are in.
    if C_Timer and C_Timer.After then C_Timer.After(0.5, updateXP) else updateXP() end
end)

-- Money is NOT read here: GetMoney() returns 0 during logout on WoW Forever.
ST:RegisterEvent("PLAYER_LOGOUT", function()
    local s = Session.Current()
    if s then s.lastSeen = time() end
end)

-- ---------------------------------------------------------------------------
-- Numbers for the window
-- ---------------------------------------------------------------------------

function Session.Stats()
    local s = Session.Current()
    if not s then return nil end
    local now = time()
    s.lastSeen = now
    local elapsed = math.max(1, now - s.start)
    local hours = elapsed / 3600
    local gold = (s.money or 0) - (s.startMoney or 0)
    local out = {
        elapsed = elapsed,
        gold = gold,
        goldPerHour = elapsed >= 60 and gold / hours or nil,
        xpGained = s.xpGained or 0,
        xpPerHour = elapsed >= 60 and (s.xpGained or 0) / hours or nil,
        levels = (s.level or 0) - (s.startLevel or 0),
    }
    local maxLevel = safe(GetMaxPlayerLevel)
    out.maxLevel = (maxLevel and s.level and s.level >= maxLevel) or (s.xpMax or 0) == 0
    if not out.maxLevel and out.xpPerHour and out.xpPerHour > 0 then
        out.timeToLevel = ((s.xpMax or 0) - (s.xp or 0)) / out.xpPerHour * 3600
        out.levelPct = s.xpMax > 0 and (s.xp or 0) / s.xpMax or 0
    elseif not out.maxLevel then
        out.levelPct = (s.xpMax or 0) > 0 and (s.xp or 0) / s.xpMax or 0
    end
    return out
end
