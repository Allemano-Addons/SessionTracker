-- Window: a small movable panel with the session numbers and a level progress bar.
-- It is a HUD, so ESC does not close it. A 1 s ticker runs only while it is shown.
local _, ST = ...

local Theme, W, Session = ST.Theme, ST.Widgets, ST.Session

local Window = {}
ST.Window = Window

local WIDTH, TITLE_H, ROW_H, PAD, BAR_H = 250, 38, 22, 12, 6

local frame, ticker

-- ---------------------------------------------------------------------------
-- Formatting
-- ---------------------------------------------------------------------------

local function colorCode(key)
    local r, g, b = Theme:Color(key)
    return ("|cff%02x%02x%02x"):format(floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

local function num(n) return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n) end

-- Copper as "12g 34s 5c" (copper only below 1 gold), no sign.
local function money(copper)
    copper = floor(math.abs(copper) + 0.5)
    local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = num(g) .. colorCode("gold") .. "g|r" end
    if s > 0 or g > 0 then parts[#parts + 1] = s .. colorCode("silver") .. "s|r" end
    if g == 0 then parts[#parts + 1] = c .. colorCode("copper") .. "c|r" end
    return table.concat(parts, " ")
end

local function signedMoney(copper)
    if copper == 0 then return "0" end
    return (copper > 0 and colorCode("good") .. "+|r" or colorCode("warn") .. "-|r") .. money(copper)
end

local function duration(sec)
    sec = floor(sec)
    local h, m = floor(sec / 3600), floor(sec / 60) % 60
    if h > 0 then return ("%dh %02dm"):format(h, m) end
    if m > 0 then return ("%dm %02ds"):format(m, sec % 60) end
    return sec .. "s"
end

-- ---------------------------------------------------------------------------
-- Rows: label + value(stats) -> text [, colorKey]. id = key in settings.rows.
-- ---------------------------------------------------------------------------

local ROWS = {
    { "Time", function(s) return duration(s.elapsed) end, id = "time" },
    { "Gold", function(s) return signedMoney(s.gold) end, id = "gold" },
    { "Gold / hour", function(s)
        if not s.goldPerHour then return "...", "textFaint" end
        return signedMoney(s.goldPerHour)
    end, id = "goldHour" },
    { "XP", function(s)
        if s.maxLevel and s.xpGained == 0 then return "max level", "textFaint" end
        local text = num(s.xpGained)
        if s.levels > 0 then text = text .. colorCode("good") .. ("  +%d level%s"):format(s.levels, s.levels > 1 and "s" or "") .. "|r" end
        return text
    end, id = "xp" },
    { "XP / hour", function(s)
        if s.maxLevel then return "-", "textFaint" end
        if not s.xpPerHour then return "...", "textFaint" end
        return num(floor(s.xpPerHour + 0.5))
    end, id = "xpHour" },
    { "Next level", function(s)
        if s.maxLevel then return "max level", "textFaint" end
        if not s.timeToLevel then return "...", "textFaint" end
        return duration(s.timeToLevel)
    end, id = "nextLevel" },
    -- /played on the current level; click opens all level times.
    { "This level", function(s)
        if s.maxLevel then return "max level", "textFaint" end
        local t = ST.Levels.CurrentLevelTime()
        if not t then return "...", "textFaint" end
        return duration(t)
    end, id = "thisLevel", click = true },
}
Window.ROWS = ROWS -- the settings list them

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------

local function savePosition()
    local db = ST.db.window
    db.left, db.top = Theme:Snap(frame:GetLeft(), frame), Theme:Snap(frame:GetTop(), frame)
end

local function restorePosition()
    local db = ST.db.window
    frame:ClearAllPoints()
    if db.left and db.top then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.left, db.top)
    else
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -240, 60)
    end
end

local function applyLook()
    frame:SetScale(ST.db.settings.scale or 1)
    frame.bg:SetAlpha(ST.db.settings.bgAlpha or 0.9)
end

local function openMenu(anchor)
    local db = ST.db.window
    W.OpenMenu({
        { text = "Session", title = true },
        { text = "Reset session", onClick = function() Session.Reset() end },
        { text = "Settings", onClick = function() ST.Settings.Toggle() end },
        { text = "Lock position", checked = db.locked == true, onClick = function() db.locked = not db.locked or nil end },
        { text = "Hide (/session shows it)", onClick = function() Window.SetShown(false) end },
    }, anchor)
end

local function build()
    frame = CreateFrame("Frame", "SessionTrackerFrame", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetWidth(WIDTH)
    frame.bg = W.Fill(frame, "window", 1)
    frame.bg:SetAllPoints()
    W.Panel(frame, frame.bg, W.Border(frame, "line"))

    -- Title: drag to move, right-click for the menu (reset, settings, lock, hide).
    local title = CreateFrame("Frame", nil, frame)
    title:SetPoint("TOPLEFT")
    title:SetPoint("TOPRIGHT")
    title:SetHeight(TITLE_H)
    local sep = W.Line(title, "bottom", "line")
    sep:ClearAllPoints()
    sep:SetPoint("BOTTOMLEFT", 1, 0)
    sep:SetPoint("BOTTOMRIGHT", -1, 0)
    title:EnableMouse(true)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function()
        if not ST.db.window.locked then frame:StartMoving() end
    end)
    title:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        savePosition()
        restorePosition()
    end)
    title:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then ST:Call("menu", openMenu, self) end
    end)
    title:SetScript("OnEnter", function(self)
        W.ShowTooltip(self, { "Session", colorCode("textFaint") .. "Drag to move. Right-click: reset, settings, lock, hide.|r" })
    end)
    title:SetScript("OnLeave", W.HideTooltip)

    -- The SessionTracker mark (own colors), then the name.
    local name = W.Text(title, 2, "text")
    local logo = title:CreateTexture(nil, "ARTWORK")
    logo:SetSize(18, 18)
    logo:SetPoint("LEFT", PAD, 0)
    if logo:SetTexture(ST.LOGO) == false then
        logo:Hide()
        name:SetPoint("LEFT", PAD, 0)
    else
        name:SetPoint("LEFT", logo, "RIGHT", 6, 0)
    end
    name:SetText("Session")

    -- "Levels": an outlined button that opens/closes level times (accent while open).
    local levels = CreateFrame("Button", nil, title)
    levels:SetHeight(22)
    levels.bg = W.Fill(levels, "field", 1)
    levels.bg:SetAllPoints()
    W.Round(levels.bg, Theme.radius.control)
    levels.border = W.RoundBorder(W.Border(levels, "line"), Theme.radius.control)
    levels.text = W.Text(levels, -1, "textDim")
    levels.text:SetPoint("CENTER", 0, 0)
    levels.text:SetText("Levels")
    levels:SetWidth(levels.text:GetStringWidth() + 20)
    levels:SetPoint("RIGHT", -PAD + 2, 0)
    levels:SetScript("OnEnter", function(self)
        self.hover = true
        Window.UpdateLevelsButton()
        W.ShowTooltip(self, { "Level times", colorCode("textFaint") .. "How long every level took|r" })
    end)
    levels:SetScript("OnLeave", function(self)
        self.hover = nil
        Window.UpdateLevelsButton()
        W.HideTooltip()
    end)
    levels:SetScript("OnClick", function() ST:Call("levels button", ST.LevelsUI.Toggle) end)
    frame.levelsButton = levels
    W.OnAccent(function() Window.UpdateLevelsButton() end)

    -- Rows (placed by layoutRows, only the ones switched on in the settings).
    frame.rows = {}
    for i, def in ipairs(ROWS) do
        local label = W.Text(frame, -1, "textDim")
        label:SetText(def[1])
        local value = W.Text(frame, 0, "text")
        value:SetJustifyH("RIGHT")
        frame.rows[i] = { label = label, value = value, def = def }
        if def.click then
            local hit = CreateFrame("Button", nil, frame)
            hit:SetHeight(ROW_H)
            hit.hl = W.Fill(hit, "selected", 1, "BACKGROUND")
            hit.hl:SetAllPoints()
            hit.hl:Hide()
            W.Round(hit.hl, Theme.radius.small)
            hit:SetScript("OnEnter", function(self)
                self.hl:Show()
                W.ShowTooltip(self, { "Time played on this level", colorCode("textFaint") .. "Click: how long every level took|r" })
            end)
            hit:SetScript("OnLeave", function(self)
                self.hl:Hide()
                W.HideTooltip()
            end)
            hit:SetScript("OnClick", function() ST:Call("level times", ST.LevelsUI.Toggle) end)
            frame.rows[i].hit = hit
            frame.levelTimesButton = hit
        end
    end

    -- Level progress: a rounded bar with "Level N" and the percent above it.
    frame.levelLabel = W.Text(frame, -2, "textFaint")
    frame.levelPct = W.Text(frame, -2, "textFaint")
    frame.levelPct:SetJustifyH("RIGHT")
    frame.track = frame:CreateTexture(nil, "BORDER")
    frame.track:SetColorTexture(Theme:Color("line"))
    W.Round(frame.track, BAR_H / 2)
    frame.track:SetHeight(BAR_H)
    frame.fill = frame:CreateTexture(nil, "ARTWORK")
    frame.fill:SetColorTexture(Theme:Accent())
    W.Round(frame.fill, BAR_H / 2)
    frame.fill:SetHeight(BAR_H) -- placed by Window.Layout (a rounded texture can't be an anchor)
    W.OnAccent(function(r, g, b) frame.fill:SetColorTexture(r, g, b, 1) end)
    Window.Layout()
    Window.UpdateLevelsButton()

    frame:SetScript("OnShow", function()
        Window.Refresh()
        if C_Timer and C_Timer.NewTicker then
            ticker = C_Timer.NewTicker(1, function() ST:Call("tick", Window.Refresh) end)
        end
    end)
    frame:SetScript("OnHide", function()
        if ticker then ticker:Cancel() end
        ticker = nil
        W.HideTooltip()
    end)
    frame:Hide()
    applyLook()
    restorePosition()
end

-- Place the rows switched on in the settings, then the level bar; sets the two heights.
function Window.Layout()
    if not frame then return end
    local on = ST.db.settings.rows
    local y = TITLE_H + 9
    for _, row in ipairs(frame.rows) do
        local shown = on[row.def.id] ~= false
        row.label:SetShown(shown)
        row.value:SetShown(shown)
        if row.hit then row.hit:SetShown(shown) end
        if shown then
            row.label:ClearAllPoints()
            row.label:SetPoint("TOPLEFT", PAD, -y)
            row.value:ClearAllPoints()
            row.value:SetPoint("TOPRIGHT", -PAD, -y + 1)
            if row.hit then
                row.hit:ClearAllPoints()
                row.hit:SetPoint("TOPLEFT", 4, -(y - 4))
                row.hit:SetPoint("TOPRIGHT", -4, -(y - 4))
            end
            y = y + ROW_H
        end
    end
    frame.rowsH = y + PAD - 8 -- without the level bar
    y = y + 6
    frame.levelLabel:ClearAllPoints()
    frame.levelLabel:SetPoint("TOPLEFT", PAD, -y)
    frame.levelPct:ClearAllPoints()
    frame.levelPct:SetPoint("TOPRIGHT", -PAD, -y)
    y = y + 16
    frame.track:ClearAllPoints()
    frame.track:SetPoint("TOPLEFT", PAD, -y)
    frame.track:SetPoint("TOPRIGHT", -PAD, -y)
    frame.fill:ClearAllPoints()
    frame.fill:SetPoint("TOPLEFT", PAD, -y)
    frame.fullH = y + BAR_H + PAD
end

function Window.Refresh()
    if not frame or not frame:IsShown() then return end
    local s = Session.Stats()
    for _, row in ipairs(frame.rows) do
        local text, colorKey = "-", "textFaint"
        if s then
            local ok, t, k = pcall(row.def[2], s)
            if ok then text, colorKey = t or "-", k or "text" else text, colorKey = "error", "warn" end
        end
        row.value:SetText(text)
        row.value:SetTextColor(Theme:Color(colorKey))
    end
    -- The level bar: off in the settings or at max level.
    local showBar = ST.db.settings.levelBar and s and not s.maxLevel and s.levelPct
    frame.levelLabel:SetShown(showBar and true or false)
    frame.levelPct:SetShown(showBar and true or false)
    frame.track:SetShown(showBar and true or false)
    frame.fill:SetShown(showBar and s.levelPct > 0 or false)
    if showBar then
        frame.levelLabel:SetText("Level " .. (UnitLevel("player") or "?"))
        frame.levelPct:SetText(("%d%%"):format(floor(s.levelPct * 100)))
        frame.fill:SetWidth(math.max(0.01, (WIDTH - 2 * PAD) * s.levelPct))
        frame:SetHeight(frame.fullH)
    else
        frame:SetHeight(frame.rowsH)
    end
end

function Window.SetShown(shown)
    if not ST.db then return end
    if not frame then build() end
    ST.db.window.shown = shown and true or false
    frame:SetShown(shown)
    if not shown then ST:Print("Hidden. Type /session to show it again.") end
end

ST.Toggle = function()
    if not frame then build() end
    Window.SetShown(not frame:IsShown())
end

Session.Changed = function() Window.Refresh() end

-- Shown by default; remembers if the player hid it.
ST:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    if not frame then build() end
    if ST.db.window.shown ~= false and not frame:IsShown() then frame:Show() end
end)

ST:OnSettingChanged(function(key)
    if not frame then return end
    if key == "scale" or key == "bgAlpha" then applyLook() end
    if key == "rows" then Window.Layout() end
    if key == "hideInCombat" and not ST.db.settings.hideInCombat and ST.db.window.shown ~= false then frame:Show() end
    Window.Refresh()
end)

function Window.UpdateLevelsButton()
    local b = frame and frame.levelsButton
    if not b then return end
    -- Open: accent outline and text. Closed: neutral outline, dim text (brighter on hover).
    if ST.LevelsUI.IsOpen() then
        local r, g, bl = Theme:Accent()
        b.text:SetTextColor(r, g, bl)
        b.border:SetColor(r, g, bl, 1)
    else
        b.text:SetTextColor(Theme:Color(b.hover and "text" or "textDim"))
        local r, g, bl = Theme:Color(b.hover and "textFaint" or "line")
        b.border:SetColor(r, g, bl, 1)
    end
end

function Window.ResetPosition()
    ST.db.window.left, ST.db.window.top = nil, nil
    if frame then restorePosition() end
end

-- Hide in combat (optional): out of the way while fighting, back after. The player's own
-- show/hide choice (window.shown) is left alone.
ST:RegisterEvent("PLAYER_REGEN_DISABLED", function()
    if frame and ST.db.settings.hideInCombat and frame:IsShown() then frame:Hide() end
end)
ST:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if frame and ST.db.settings.hideInCombat and ST.db.window.shown ~= false then frame:Show() end
end)

ST:AddSlashCommand("reset", function() Session.Reset() ST:Print("New session started.") end, "start a new session")
