-- Level times window (Allemano look): one row per finished level with its /played time,
-- newest first. Hover a row for real time, date and zone. The level in progress is on
-- the session window's bar, not here.
local _, ST = ...

local Theme, W, Levels = ST.Theme, ST.Widgets, ST.Levels

local LevelsUI = {}
ST.LevelsUI = LevelsUI

local WIDTH, TITLE_H, ROW_H, PAD, MAX_ROWS = 210, 38, 24, 14, 15

local frame, ticker
local list, offset = {}, 0

-- Finished levels, newest first.
local function finishedLevels()
    local out = {}
    for _, e in ipairs(Levels.List()) do
        if not e.current then tinsert(out, 1, e) end
    end
    return out
end

local function duration(sec)
    if not sec then return "?" end
    sec = floor(sec)
    local d, h, m = floor(sec / 86400), floor(sec / 3600) % 24, floor(sec / 60) % 60
    if d > 0 then return ("%dd %dh"):format(d, h) end
    if h > 0 then return ("%dh %02dm"):format(h, m) end
    if m > 0 then return ("%dm %02ds"):format(m, sec % 60) end
    return sec .. "s"
end

local function faint(text)
    local r, g, b = Theme:Color("textFaint")
    return ("|cff%02x%02x%02x%s|r"):format(floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5), text)
end

local function rowTooltip(row)
    local e = row.entry
    if not e then return end
    local lines = { e.current and ("Level %d (in progress)"):format(e.level) or ("Level %d to %d"):format(e.level, e.level + 1) }
    lines[#lines + 1] = "Played: " .. duration(e.played)
    if e.wall then lines[#lines + 1] = "Real time: " .. duration(e.wall) end
    if e.reached then
        lines[#lines + 1] = faint(("Reached %d: %s%s"):format(e.level + 1, date("%d/%m %H:%M", e.reached),
            e.zone and (" in " .. e.zone) or ""))
    end
    W.ShowTooltip(row, lines)
end

-- The X only shows while the mouse is over the window (the look has no close button;
-- the Levels button on the session window also closes it).
local function updateClose()
    if frame and frame.close then frame.close:SetShown(frame:IsMouseOver()) end
end

local function createRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row.hl = W.Fill(row, "selected", 1)
    row.hl:SetAllPoints()
    row.hl:Hide()
    W.Round(row.hl, Theme.radius.small)
    row.label = W.Text(row, -1, "textDim")
    row.label:SetPoint("LEFT", PAD, 0)
    row.time = W.Text(row, 0, "text")
    row.time:SetPoint("RIGHT", -PAD, 0)
    row.time:SetJustifyH("RIGHT")
    row:SetScript("OnEnter", function(self)
        self.hl:Show()
        rowTooltip(self)
        updateClose()
    end)
    row:SetScript("OnLeave", function(self)
        self.hl:Hide()
        W.HideTooltip()
        updateClose()
    end)
    return row
end

function LevelsUI.Refresh()
    if not frame or not frame:IsShown() then return end
    list = finishedLevels()
    offset = math.max(0, math.min(offset, #list - MAX_ROWS))
    local shown = math.min(#list, MAX_ROWS)
    for i = 1, MAX_ROWS do
        local row, e = frame.rows[i], list[offset + i]
        if e then
            row.entry = e
            row.label:SetText(("Level %d"):format(e.level))
            row.time:SetText(duration(e.played))
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end
    frame.empty:SetShown(#list == 0)
    local listH = (#list == 0 and 1 or shown) * ROW_H
    frame:SetHeight(TITLE_H + 6 + listH + 8)
    updateClose()
end

-- Open state and position are remembered (SessionTrackerDB.levelsWindow). Like the
-- session window it stays up: only its X (or the Levels button) closes it, not ESC.
local function db() return ST.db.levelsWindow end

local function savePosition()
    db().left, db().top = Theme:Snap(frame:GetLeft(), frame), Theme:Snap(frame:GetTop(), frame)
end

local function build()
    frame = CreateFrame("Frame", "SessionTrackerLevelsFrame", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetWidth(WIDTH)
    frame.bg = W.Fill(frame, "window", 0.96)
    frame.bg:SetAllPoints()
    W.Panel(frame, frame.bg, W.Border(frame, "line"))

    local title = CreateFrame("Frame", nil, frame)
    title:SetPoint("TOPLEFT")
    title:SetPoint("TOPRIGHT")
    title:SetHeight(TITLE_H)
    local sep = W.Line(title, "bottom", "line")
    sep:ClearAllPoints()
    sep:SetPoint("BOTTOMLEFT", 1, 0)
    sep:SetPoint("BOTTOMRIGHT", -1, 0)
    title:EnableMouse(true)
    title:SetScript("OnEnter", updateClose)
    title:SetScript("OnLeave", updateClose)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function()
        if not ST.db.window.locked then frame:StartMoving() end
    end)
    title:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        savePosition()
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db().left, db().top)
    end)
    local name = W.Text(title, 2, "text")
    name:SetPoint("LEFT", PAD, 0)
    name:SetText("Level times")
    local close = W.CloseButton(title, function() LevelsUI.SetShown(false) end)
    close:SetSize(20, 20)
    close:SetPoint("RIGHT", -8, 0)
    close:HookScript("OnLeave", updateClose)
    frame.close = close

    frame.rows = {}
    for i = 1, MAX_ROWS do
        local row = createRow(frame)
        row:SetPoint("TOPLEFT", 4, -(TITLE_H + 6 + (i - 1) * ROW_H))
        row:SetPoint("TOPRIGHT", -4, -(TITLE_H + 6 + (i - 1) * ROW_H))
        frame.rows[i] = row
    end
    frame.empty = W.Text(frame, -1, "textFaint")
    frame.empty:SetPoint("TOPLEFT", PAD, -(TITLE_H + 11))
    frame.empty:SetText("Your next level will show here.")

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta * 3
        LevelsUI.Refresh()
    end)
    frame:SetScript("OnEnter", updateClose)
    frame:SetScript("OnLeave", updateClose)
    frame:SetScript("OnShow", function()
        offset = 0 -- newest levels in view
        LevelsUI.Refresh()
        if C_Timer and C_Timer.NewTicker then
            ticker = C_Timer.NewTicker(1, function() ST:Call("levels tick", LevelsUI.Refresh) end)
        end
    end)
    frame:SetScript("OnHide", function()
        if ticker then ticker:Cancel() end
        ticker = nil
        W.HideTooltip()
    end)
    frame:SetScale(ST.db.settings.scale or 1)
    frame.bg:SetAlpha(ST.db.settings.bgAlpha or 0.96)
    frame:Hide()
end

-- Where the player left it; the first time next to the session window.
local function place()
    frame:ClearAllPoints()
    if db().left and db().top then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db().left, db().top)
        return
    end
    local main = _G.SessionTrackerFrame
    if main and main:IsShown() and (main:GetLeft() or 0) > WIDTH + 20 then
        frame:SetPoint("TOPRIGHT", main, "TOPLEFT", -8, 0)
    elseif main and main:IsShown() then
        frame:SetPoint("TOPLEFT", main, "TOPRIGHT", 8, 0)
    else
        frame:SetPoint("CENTER")
    end
end

function LevelsUI.IsOpen() return ST.db ~= nil and db().shown == true end

function LevelsUI.SetShown(shown)
    if not ST.db then return end
    if not frame then build() end
    db().shown = shown and true or nil
    if shown then
        if not frame:IsShown() then
            place()
            frame:Show()
        end
    else
        frame:Hide()
    end
    if ST.Window.UpdateLevelsButton then ST.Window.UpdateLevelsButton() end
end

function LevelsUI.Toggle() LevelsUI.SetShown(not LevelsUI.IsOpen()) end

function LevelsUI.ResetPosition()
    db().left, db().top = nil, nil
    if frame and frame:IsShown() then place() end
end

-- Open again after a /reload or login if it was open.
ST:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    if LevelsUI.IsOpen() then
        if not frame then build() end
        if not frame:IsShown() then
            place()
            frame:Show()
        end
    end
end)

-- Follows the session window's "hide in combat".
ST:RegisterEvent("PLAYER_REGEN_DISABLED", function()
    if frame and ST.db.settings.hideInCombat and frame:IsShown() then frame:Hide() end
end)
ST:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if frame and LevelsUI.IsOpen() and not frame:IsShown() then frame:Show() end
end)

ST:OnSettingChanged(function(key)
    if not frame then return end
    if key == "scale" then frame:SetScale(ST.db.settings.scale or 1) end
    if key == "bgAlpha" then frame.bg:SetAlpha(ST.db.settings.bgAlpha or 0.96) end
    LevelsUI.Refresh()
end)

ST:AddSlashCommand("levels", function() LevelsUI.Toggle() end, "show how long each level took")
