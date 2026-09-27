-- Level times window: one row per level with its /played time and a bar to compare.
-- Hover a row for real time, date and zone. The level in progress is shown last.
local _, ST = ...

local Theme, W, Levels = ST.Theme, ST.Widgets, ST.Levels

local LevelsUI = {}
ST.LevelsUI = LevelsUI

local WIDTH, TITLE_H, ROW_H, PAD, MAX_ROWS = 300, 30, 20, 10, 20
local LABEL_W, TIME_W = 78, 64

local frame, ticker
local list, offset = {}, 0

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

local function createRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row.hl = W.Fill(row, "selected", 1)
    row.hl:SetAllPoints()
    row.hl:Hide()
    row.label = W.Text(row, -1, "textDim")
    row.label:SetPoint("LEFT", PAD, 0)
    row.time = W.Text(row, -1, "text")
    row.time:SetPoint("RIGHT", -PAD, 0)
    row.time:SetJustifyH("RIGHT")
    row.track = row:CreateTexture(nil, "BORDER")
    row.track:SetPoint("LEFT", PAD + LABEL_W, 0)
    row.track:SetPoint("RIGHT", -(PAD + TIME_W), 0)
    W.PixelSize(row.track, row, "h", 4)
    row.track:SetColorTexture(Theme:Color("line"))
    row.fill = row:CreateTexture(nil, "ARTWORK")
    row.fill:SetPoint("TOPLEFT", row.track)
    row.fill:SetPoint("BOTTOMLEFT", row.track)
    row:SetScript("OnEnter", function(self)
        self.hl:Show()
        rowTooltip(self)
    end)
    row:SetScript("OnLeave", function(self)
        self.hl:Hide()
        W.HideTooltip()
    end)
    return row
end

function LevelsUI.Refresh()
    if not frame or not frame:IsShown() then return end
    list = Levels.List()
    local longest, total, known = 1, 0, 0
    for _, e in ipairs(list) do
        if e.played then
            longest = math.max(longest, e.played)
            if not e.current then total, known = total + e.played, known + 1 end
        end
    end
    offset = math.max(0, math.min(offset, #list - MAX_ROWS))
    local barW = WIDTH - 2 * PAD - LABEL_W - TIME_W
    local shown = math.min(#list, MAX_ROWS)
    for i = 1, MAX_ROWS do
        local row, e = frame.rows[i], list[offset + i]
        if e then
            row.entry = e
            row.label:SetText(e.current and ("Level %d  now"):format(e.level) or ("Level %d"):format(e.level))
            row.time:SetText(duration(e.played))
            local r, g, b = Theme:Accent()
            if e.current then
                row.label:SetTextColor(r, g, b)
                row.fill:SetColorTexture(r, g, b, 0.5)
            else
                row.label:SetTextColor(Theme:Color("textDim"))
                row.fill:SetColorTexture(r, g, b, 1)
            end
            row.fill:SetWidth(math.max(0.01, barW * (e.played or 0) / longest))
            row.fill:SetShown((e.played or 0) > 0)
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end
    frame.empty:SetShown(#list == 0)
    frame.footer:SetText(known > 0 and ("%d levels logged, %s played"):format(known, duration(total))
        or "Level times are logged from now on.")
    local listH = math.max(shown, 1) * ROW_H
    frame:SetHeight(TITLE_H + 6 + listH + 30)
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
    W.Border(frame, "line")

    local title = CreateFrame("Frame", nil, frame)
    title:SetPoint("TOPLEFT")
    title:SetPoint("TOPRIGHT")
    title:SetHeight(TITLE_H)
    W.Line(title, "bottom", "line")
    title:EnableMouse(true)
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
    local name = W.Text(title, 1, "text")
    name:SetPoint("LEFT", PAD, 0)
    name:SetText("Level times")
    local close = W.CloseButton(title, function() LevelsUI.SetShown(false) end)
    close:SetSize(20, 20)
    close:SetPoint("RIGHT", -5, 0)

    frame.rows = {}
    for i = 1, MAX_ROWS do
        local row = createRow(frame)
        row:SetPoint("TOPLEFT", 0, -(TITLE_H + 6 + (i - 1) * ROW_H))
        row:SetPoint("TOPRIGHT", 0, -(TITLE_H + 6 + (i - 1) * ROW_H))
        frame.rows[i] = row
    end
    frame.empty = W.Text(frame, -1, "textFaint")
    frame.empty:SetPoint("TOPLEFT", PAD, -(TITLE_H + 10))
    frame.empty:SetText("Nothing yet: your next level will show here.")
    frame.footer = W.Text(frame, -2, "textFaint")
    frame.footer:SetPoint("BOTTOMLEFT", PAD, 10)

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta * 3
        LevelsUI.Refresh()
    end)
    frame:SetScript("OnShow", function()
        offset = math.max(0, #Levels.List() - MAX_ROWS) -- newest levels in view
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
