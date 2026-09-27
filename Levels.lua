-- Levels: how long each level took, in /played time (plus wall-clock time and zone).
--
-- The game reports total /played and time played at the current level (TIME_PLAYED_MSG),
-- so the start of the current level is known exactly: total - levelPlayed. On each ding
-- the level that just ended is logged.
--
-- SessionTrackerDB.chars[guid]:
--   levelLog   = { [level] = { played, wall, reached, zone } }  -- level -> level+1
--   levelStart = { level, playedTotal, wallStart }             -- the level in progress
--   played     = { total, at }                                  -- last known /played
local _, ST = ...

local Levels = {}
ST.Levels = Levels

local pendingDings = {} -- level-ups waiting for the next TIME_PLAYED_MSG

local function char()
    local guid = UnitGUID("player")
    local c = guid and ST.db and ST.db.chars[guid]
    if c then c.levelLog = c.levelLog or {} end
    return c
end

-- ---------------------------------------------------------------------------
-- Asking for /played without the chat line. Only our own requests are hidden: the
-- chat frames print through ChatFrame_DisplayTimePlayed (ChatFrameUtil on newer clients).
-- ---------------------------------------------------------------------------

local hideChat = false

local function wrap(tbl, key)
    local original = tbl and tbl[key]
    if type(original) ~= "function" then return end
    tbl[key] = function(...)
        if hideChat then return end
        return original(...)
    end
end
wrap(_G, "ChatFrame_DisplayTimePlayed")
wrap(ChatFrameUtil, "DisplayTimePlayed")

function Levels.RequestPlayed()
    if not RequestTimePlayed then return end
    hideChat = true
    RequestTimePlayed()
    -- Never keep hiding if the answer does not come.
    if C_Timer and C_Timer.After then C_Timer.After(10, function() hideChat = false end) end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

ST:RegisterEvent("TIME_PLAYED_MSG", function(_, total, levelPlayed)
    -- Every chat frame prints during this same event; stop hiding right after it.
    if C_Timer and C_Timer.After then C_Timer.After(0, function() hideChat = false end) else hideChat = false end
    local c = char()
    if not c or not total then return end
    local now = time()
    c.played = { total = total, at = now }
    local level = UnitLevel("player")
    local startTotal = total - (levelPlayed or 0)

    -- Dings since the last answer: log each level that ended. The /played moment of the
    -- last ding is exact (the start of the current level); with several dings at once (a
    -- quest worth two levels) the ones in between get no played time.
    for i, ding in ipairs(pendingDings) do
        local s = c.levelStart
        local dingTotal = (i == #pendingDings and ding.from + 1 == level) and startTotal or nil
        if s and s.level == ding.from then
            c.levelLog[ding.from] = {
                played = (dingTotal and s.playedTotal) and math.max(0, dingTotal - s.playedTotal) or nil,
                wall = s.wallStart and (ding.wall - s.wallStart) or nil,
                reached = ding.wall, zone = ding.zone,
            }
        end
        c.levelStart = { level = ding.from + 1, playedTotal = dingTotal, wallStart = ding.wall }
    end
    wipe(pendingDings)

    -- Keep (or learn) where the current level started.
    local s = c.levelStart
    if not s or s.level ~= level or not s.playedTotal then
        c.levelStart = { level = level, playedTotal = startTotal, wallStart = s and s.level == level and s.wallStart or nil }
    end
    if ST.Session then ST.Session.Changed() end
end)

ST:RegisterEvent("PLAYER_LEVEL_UP", function(_, newLevel)
    newLevel = tonumber(newLevel) or (UnitLevel("player") + 1)
    pendingDings[#pendingDings + 1] = {
        from = newLevel - 1, wall = time(),
        zone = GetRealZoneText and GetRealZoneText() or nil,
    }
    -- The server needs a moment to count the new level.
    if C_Timer and C_Timer.After then C_Timer.After(1, Levels.RequestPlayed) else Levels.RequestPlayed() end
end)

ST:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isInitialLogin, isReloadingUi)
    local c = char()
    -- Once per login (and on a /reload if we do not know the level start yet).
    if isInitialLogin or not isReloadingUi or not (c and c.levelStart and c.played) then
        if C_Timer and C_Timer.After then C_Timer.After(3, Levels.RequestPlayed) else Levels.RequestPlayed() end
    end
end)

-- ---------------------------------------------------------------------------
-- Reading
-- ---------------------------------------------------------------------------

-- Seconds played on the current level right now, or nil if not known yet.
function Levels.CurrentLevelTime()
    local c = char()
    if not (c and c.played and c.levelStart and c.levelStart.playedTotal) then return nil end
    if c.levelStart.level ~= UnitLevel("player") then return nil end
    local nowTotal = c.played.total + (time() - c.played.at)
    return math.max(0, nowTotal - c.levelStart.playedTotal)
end

-- { { level, played, wall, reached, zone, current } } sorted by level, for a character.
function Levels.List(guid)
    local c = ST.db.chars[guid or UnitGUID("player")]
    local out = {}
    if not c then return out end
    for level, e in pairs(c.levelLog or {}) do
        out[#out + 1] = { level = level, played = e.played, wall = e.wall, reached = e.reached, zone = e.zone }
    end
    sort(out, function(a, b) return a.level < b.level end)
    if (guid == nil or guid == UnitGUID("player")) and Levels.CurrentLevelTime() then
        out[#out + 1] = { level = UnitLevel("player"), played = Levels.CurrentLevelTime(), current = true }
    end
    return out
end
