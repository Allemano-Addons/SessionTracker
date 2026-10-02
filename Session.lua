-- Session: what the current play session has brought. Saved per character so a /reload
-- keeps it. A new login starts a new session (the old one goes to the history), unless
-- the setting newSession is "manual": then a session runs over several logins and only
-- the time spent logged in counts.
--
-- AllemanoLedgerDB.chars[guid] = {
--     name, class,
--     current = { start, lastSeen, active, stintStart, startMoney, money, xp, xpMax, level,
--                 startLevel, xpGained,
--                 inc, exp,      -- copper by source (see Ledger.lua); transfers between own characters are not in here
--                 xfer, lootValue, items, series = { { seconds, net }, ... },
--                 paused, tag, autoTag, zone },   -- active = online seconds of earlier logins
--     history = { { start, stop, duration, money, net, xpGained, levels, inc, exp, tag, zone, kind }, ... }
--                 (newest first, max 50; kind = "run" for saved instance runs)
-- }
local _, ST = ...

local Session = {}
ST.Session = Session

local HISTORY_MAX = 50
local MIN_SESSION = 60      -- shorter sessions are not kept in the history
local STALE_AFTER = 10 * 60 -- without login/reload info: this long offline = new session

Session.TAGS = { "Farming", "Dungeon", "Raid", "Leveling", "Questing", "Professions", "PvP", "Other" }

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

local function sum(t)
    local n = 0
    for _, v in pairs(t or {}) do n = n + v end
    return n
end
Session.Sum = sum

local function copyNumbers(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = v end
    return out
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
    c.history = c.history or {}
    c.days = c.days or {}
    return c
end

-- Seconds logged in during this session, up to `at` (frozen while the session is paused).
local function onlineTime(s, at)
    if s.paused then return s.active or 0 end
    return (s.active or 0) + math.max(0, at - (s.stintStart or s.start))
end

function Session.Elapsed(s, at) return onlineTime(s, at or time()) end

-- Sessions from before the Ledger have no source tallies: what they made counts as "other".
local function ensure(s)
    if s and not s.inc then
        s.inc, s.exp, s.xfer, s.lootValue, s.items = {}, {}, 0, 0, 0
        local delta = (s.money or s.startMoney or 0) - (s.startMoney or 0)
        if delta > 0 then s.inc.other = delta elseif delta < 0 then s.exp.other = -delta end
        s.series = { { 0, 0 }, { onlineTime(s, time()), delta } }
    end
    if s and not s.qItems then
        s.kills, s.deaths, s.xpQuest, s.qItems, s.rep = 0, 0, 0, {}, {}
    end
    return s
end

function Session.AutoTag()
    local inInstance, kind
    if IsInInstance then inInstance, kind = IsInInstance() end
    if inInstance then
        if kind == "raid" then return "Raid" end
        if kind == "party" then return "Dungeon" end
        if kind == "pvp" or kind == "arena" then return "PvP" end
    end
    local maxLevel = safe(GetMaxPlayerLevel)
    if maxLevel and (UnitLevel("player") or 0) < maxLevel then return "Leveling" end
    return "Farming"
end

-- What the session is called: the player's own choice, else what it looked like.
function Session.Tag(s) return s.tag or s.autoTag or Session.AutoTag() end

-- Close the current session into the history (if it lasted long enough).
local function archive(c)
    local s = ensure(c.current)
    if not s then return end
    local stop = s.lastSeen or s.start
    local duration = onlineTime(s, stop)
    if duration >= MIN_SESSION then
        tinsert(c.history, 1, {
            start = s.start, stop = stop, duration = duration,
            money = (s.money or s.startMoney or 0) - (s.startMoney or 0),
            net = sum(s.inc) - sum(s.exp),
            inc = copyNumbers(s.inc), exp = copyNumbers(s.exp),
            lootValue = s.lootValue, tag = Session.Tag(s), zone = s.zone,
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
        start = now, lastSeen = now, active = 0, stintStart = now,
        startMoney = GetMoney(), money = GetMoney(),
        xp = UnitXP("player"), xpMax = UnitXPMax("player"),
        level = UnitLevel("player"), startLevel = UnitLevel("player"),
        xpGained = 0,
        inc = {}, exp = {}, xfer = 0, lootValue = 0, items = 0, series = { { 0, 0 } },
        kills = 0, deaths = 0, xpQuest = 0, qItems = {}, rep = {},
        zone = safe(GetRealZoneText),
    }
end

function Session.Current()
    local c = ST.db and UnitGUID("player") and ST.db.chars[UnitGUID("player")]
    return c and ensure(c.current), c
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

function Session.Pause()
    local s = Session.Current()
    if not s or s.paused then return end
    local now = time()
    s.active = onlineTime(s, now)
    s.paused = true
    s.lastSeen = now
    Session.Changed()
end

function Session.Resume()
    local s = Session.Current()
    if not s or not s.paused then return end
    local now = time()
    s.paused = nil
    s.stintStart = now
    s.lastSeen = now
    Session.Changed()
end

function Session.SetTag(tag)
    local s = Session.Current()
    if not s then return end
    s.tag = tag
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
    local now = time()
    if not s then
        newSession(c)
    elseif isNew and ST.db.settings.newSession ~= "manual" then
        archive(c)
        newSession(c)
    elseif isNew then
        -- Manual sessions go on over logins: bank the online time of the last login.
        s.active = onlineTime(s, s.lastSeen or now)
        s.stintStart = now
        s.money = GetMoney()
        s.lastSeen = now
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
    local s, c = Session.Current()
    if not s then return end
    local xp, xpMax, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    local gain = 0
    if level > (s.level or level) then
        gain = math.max(0, (s.xpMax or 0) - (s.xp or 0)) + xp
    elseif xp > (s.xp or 0) then
        gain = xp - s.xp
    end
    if gain > 0 then
        if not s.paused then s.xpGained = s.xpGained + gain end
        if ST.Ledger then ST.Ledger.AddXP(gain, c) end
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
    local elapsed = math.max(1, onlineTime(s, now))
    local hours = elapsed / 3600
    local earned, spent = sum(s.inc), sum(s.exp)
    local gold = earned - spent
    local out = {
        elapsed = elapsed,
        paused = s.paused and true or false,
        earned = earned, spent = spent,
        gold = gold,
        goldPerHour = elapsed >= 60 and gold / hours or nil,
        xpGained = s.xpGained or 0,
        xpPerHour = elapsed >= 60 and (s.xpGained or 0) / hours or nil,
        levels = (s.level or 0) - (s.startLevel or 0),
        inc = s.inc, exp = s.exp, xfer = s.xfer or 0,
        lootValue = s.lootValue or 0,
        series = s.series, tag = Session.Tag(s), zone = s.zone,
        kills = s.kills or 0, deaths = s.deaths or 0, xpQuest = s.xpQuest or 0,
        items = s.qItems, rep = s.rep, itemCount = s.items or 0,
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
