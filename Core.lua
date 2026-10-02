-- Allemano Ledger: core namespace, event dispatcher, errors, SavedVariables and slash command.
-- Standalone: never requires Hush or AltBoard.
local addonName, ST = ...

ST.name = addonName
-- The Allemano Ledger mark (Media/wow/mark.tga, 64x64, own colors); Media/wow/icon.tga is the
-- addon list icon (TOC). Media/png and Media/svg hold the source pictures.
ST.LOGO = "Interface\\AddOns\\" .. addonName .. "\\Media\\wow\\mark"

function ST:Print(...)
    local msg = strjoin(" ", tostringall(...))
    DEFAULT_CHAT_FRAME:AddMessage("|cffe8a93bLedger|r " .. msg)
end

-- ---------------------------------------------------------------------------
-- Errors: WoW Forever does not show Lua errors, so they are kept (last 10, also in
-- AllemanoLedgerDB.errors), announced once per session and listed by /ledger errors.
-- ---------------------------------------------------------------------------

ST.errors = {}
local announced = false

function ST:RecordError(where, err)
    local list = self.errors
    list[#list + 1] = { t = time(), where = tostring(where), msg = tostring(err):sub(1, 400), v = self.version }
    while #list > 10 do tremove(list, 1) end
    if not announced then
        announced = true
        self:Print("|cffe8a33dhit an error|r (" .. tostring(where) .. "). /ledger errors shows it.")
    end
    geterrorhandler()(err)
end

function ST:Call(where, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then self:RecordError(where, err) end
    return ok
end

-- ---------------------------------------------------------------------------
-- Game events: several handlers per event, one shared frame, each run protected.
-- ---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

function ST:RegisterEvent(event, handler)
    local list = eventHandlers[event]
    if not list then
        if not pcall(eventFrame.RegisterEvent, eventFrame, event) then return false end
        list = {}
        eventHandlers[event] = list
    end
    list[#list + 1] = handler
    return true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], event, ...)
        if not ok then ST:RecordError(event, err) end
    end
end)

-- ---------------------------------------------------------------------------
-- SavedVariables: read at ADDON_LOADED, never at file load (WoW Forever quirk).
-- ---------------------------------------------------------------------------

local DEFAULT_SETTINGS = {
    font = "Friz Quadrata",
    textSize = "M",
    accentMode = "own",   -- own (Ledger amber) / hush (follow Hush if installed) / class / custom
    accent = "E8A93B",  -- used by "custom"
    bgAlpha = 0.9,
    scale = 1,
    rows = { time = true, gold = true, goldHour = true, xp = true, xpHour = true, nextLevel = true, thisLevel = true },
    levelBar = true,
    hideInCombat = false,
    newSession = "login", -- "login": every login starts one / "manual": only Reset does
}

local function fillDefaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = type(v) == "table" and CopyTable(v) or v
        elseif type(v) == "table" and type(dst[k]) == "table" then
            fillDefaults(dst[k], v)
        end
    end
end

local settingListeners = {}
function ST:OnSettingChanged(fn) settingListeners[#settingListeners + 1] = fn end

function ST:SetSetting(key, value)
    self.db.settings[key] = value
    for _, fn in ipairs(settingListeners) do
        local ok, err = pcall(fn, key, value)
        if not ok then self:RecordError("setting " .. tostring(key), err) end
    end
end

local function initDB()
    if type(AllemanoLedgerDB) ~= "table" then
        -- First start after the rename (Session Tracker -> Allemano Ledger): take over the old
        -- data. The old variable is left alone as a backup.
        local old = rawget(_G, "SessionTrackerDB")
        if type(old) == "table" and next(old) then
            AllemanoLedgerDB = CopyTable(old)
            AllemanoLedgerDB.migratedFrom = "SessionTrackerDB"
        else
            AllemanoLedgerDB = {}
        end
    end
    local db = AllemanoLedgerDB
    db.firstSeen = db.firstSeen or time()
    db.settings = db.settings or {}
    fillDefaults(db.settings, DEFAULT_SETTINGS)
    db.window = db.window or {}
    db.levelsWindow = db.levelsWindow or {}
    db.ledgerWindow = db.ledgerWindow or {}
    db.chars = db.chars or {} -- keyed by player GUID
    db.errors = db.errors or {}
    for _, e in ipairs(ST.errors) do tinsert(db.errors, e) end
    while #db.errors > 10 do tremove(db.errors, 1) end
    ST.errors = db.errors
    ST.db = db
end

ST:RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= addonName then return end
    initDB()
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    ST.version = getMeta and getMeta(addonName, "Version") or "?"
end)

-- ---------------------------------------------------------------------------
-- Slash command: /session (other files add subcommands).
-- ---------------------------------------------------------------------------

local slashCommands, slashOrder = {}, {}

function ST:AddSlashCommand(name, fn, help)
    if not slashCommands[name] then slashOrder[#slashOrder + 1] = name end
    slashCommands[name] = { fn = fn, help = help }
end

function ST:Toggle() end -- replaced by the HUD window
function ST.ToggleLedger() end -- replaced by the Ledger window

ST:AddSlashCommand("errors", function(arg)
    if strlower(arg or "") == "clear" then
        wipe(ST.errors)
        ST:Print("Error list cleared.")
        return
    end
    if #ST.errors == 0 then ST:Print("No errors recorded.") return end
    for _, e in ipairs(ST.errors) do
        ST:Print(("[%s] %s (v%s): %s"):format(date("%d/%m %H:%M", e.t), e.where, tostring(e.v), e.msg))
    end
end, "show recent errors (/ledger errors clear empties the list)")

local function runSlash(msg, emptyFn, label)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = strlower(cmd or "")
    local c = slashCommands[cmd]
    if cmd == "" then
        ST:Call(label, emptyFn, ST)
    elseif c then
        ST:Call(label .. " " .. cmd, c.fn, rest)
    else
        ST:Print("/ledger - show/hide the Ledger window")
        for _, name in ipairs(slashOrder) do
            ST:Print(("/ledger %s - %s"):format(name, slashCommands[name].help or ""))
        end
    end
end

-- /ledger opens the big window; /session (and /sesh, the old Session Tracker commands) still
-- show/hide the small session window. Both take the same subcommands.
SLASH_ALLEMANOLEDGER1 = "/ledger"
SlashCmdList.ALLEMANOLEDGER = function(msg) runSlash(msg, function() ST.ToggleLedger() end, "/ledger") end

SLASH_SESSIONTRACKER1 = "/session"
SLASH_SESSIONTRACKER2 = "/sesh"
SlashCmdList.SESSIONTRACKER = function(msg) runSlash(msg, function() ST.Toggle() end, "/session") end
