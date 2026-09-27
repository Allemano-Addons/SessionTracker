-- Settings window (same look as AltBoard's): label left, control right, in sections.
-- Every change applies at once (ST:SetSetting); nothing needs a /reload.
local _, ST = ...

local Theme, W = ST.Theme, ST.Widgets

local Settings = {}
ST.Settings = Settings

local WIDTH, ROW, LABEL_X, CONTROL_X, TITLE_H = 460, 30, 16, 170, 40
local frame
local controls = {} -- each has :refresh(), called when the window opens

local function set(key, value) ST:SetSetting(key, value) end

-- Layout helpers: y grows downward while building.
local y
local function heading(parent, text)
    y = y + 8
    local fs = W.Text(parent, -1, "text")
    fs:SetPoint("TOPLEFT", LABEL_X, -y)
    fs:SetText(strupper(text))
    W.OnAccent(function(r, g, b) fs:SetTextColor(r, g, b) end)
    y = y + 22
end

local function row(parent, label, control, offsetY)
    local fs = W.Text(parent, 0, "textDim")
    fs:SetPoint("TOPLEFT", LABEL_X, -(y + 6))
    fs:SetText(label)
    control:SetPoint("TOPLEFT", CONTROL_X, -(y + (offsetY or 2)))
    y = y + ROW
    return fs
end

local function addControl(control, refresh)
    control.refresh = refresh
    controls[#controls + 1] = control
    return control
end

local function toggleRow(parent, label, get, onChange)
    local t = W.Toggle(parent, onChange)
    row(parent, label, t, 6)
    return addControl(t, function() t:Set(get()) end)
end

local function textButton(parent, label, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(24)
    b.bg = W.Fill(b, "field", 1)
    b.bg:SetAllPoints()
    W.Border(b, "line")
    b.text = W.Text(b, -1, "text")
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b:SetWidth(b.text:GetStringWidth() + 24)
    b:SetScript("OnEnter", function(self) self.bg:SetColorTexture(Theme:Color("selected")) end)
    b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(Theme:Color("field")) end)
    b:SetScript("OnClick", onClick)
    return b
end

local function build()
    local s = ST.db.settings
    frame = CreateFrame("Frame", "SessionTrackerSettingsFrame", UIParent)
    tinsert(UISpecialFrames, "SessionTrackerSettingsFrame") -- ESC closes it
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetWidth(WIDTH)
    frame.bg = W.Fill(frame, "window", 0.98)
    frame.bg:SetAllPoints()
    W.Border(frame, "line")

    local title = CreateFrame("Frame", nil, frame)
    title:SetPoint("TOPLEFT")
    title:SetPoint("TOPRIGHT")
    title:SetHeight(TITLE_H)
    W.Line(title, "bottom", "line")
    title:EnableMouse(true)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() frame:StartMoving() end)
    title:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    local name = W.Text(title, 3, "text")
    name:SetPoint("LEFT", 12, 0)
    name:SetText("Session Settings")
    local close = W.CloseButton(title, function() frame:Hide() end)
    close:SetPoint("RIGHT", -8, 0)

    y = TITLE_H + 2

    -- Appearance ---------------------------------------------------------------
    heading(frame, "Appearance")

    local font = W.Dropdown(frame, 220, function()
        local opts = {}
        for _, f in ipairs(Theme:AvailableFonts()) do opts[#opts + 1] = { value = f.name, label = f.name, font = f.path } end
        return opts
    end, function(v) set("font", v) end)
    row(frame, "Font", font)
    addControl(font, function() font:Set(s.font) end)

    local size = W.Segment(frame, {
        { value = "S", label = "Small" }, { value = "M", label = "Medium" }, { value = "L", label = "Large" },
    }, function(v) set("textSize", v) end)
    row(frame, "Text size", size, 3)
    addControl(size, function() size:Set(s.textSize) end)

    local swatches = CreateFrame("Frame", nil, frame)
    local accent = W.Segment(frame, {
        { value = "hush", label = Theme.HasHush() and "Follow Hush" or "Default" },
        { value = "class", label = "Class" },
        { value = "custom", label = "Custom" },
    }, function(v)
        set("accentMode", v)
        swatches.refresh()
    end)
    row(frame, "Accent color", accent, 3)
    addControl(accent, function() accent:Set(s.accentMode) end)

    swatches:SetSize(8 * 26, 22)
    swatches:SetPoint("TOPLEFT", CONTROL_X, -(y - 2))
    swatches.list = {}
    for i, hex in ipairs(Theme.ACCENTS) do
        local sw = W.Swatch(swatches, hex, function()
            s.accentMode = "custom"
            accent:Set("custom")
            set("accent", hex)
            swatches.refresh()
        end)
        sw:SetPoint("LEFT", (i - 1) * 26, 0)
        sw.hex = hex
        swatches.list[i] = sw
    end
    addControl(swatches, function()
        for _, sw in ipairs(swatches.list) do
            sw:SetSelected(s.accentMode == "custom" and s.accent == sw.hex)
            sw:SetAlpha(s.accentMode == "custom" and 1 or 0.4)
        end
    end)
    y = y + ROW - 4

    local alpha = W.Slider(frame, 30, 100, 5, 170, function(v) return v .. "%" end,
        function(v) set("bgAlpha", v / 100) end)
    row(frame, "Background", alpha, 7)
    addControl(alpha, function() alpha:Set(floor((s.bgAlpha or 0.9) * 100 + 0.5)) end)

    local scale = W.Slider(frame, 70, 150, 5, 170, function(v) return v .. "%" end,
        function(v) set("scale", v / 100) end)
    row(frame, "Window scale", scale, 7)
    addControl(scale, function() scale:Set(floor((s.scale or 1) * 100 + 0.5)) end)

    -- Window -----------------------------------------------------------------
    heading(frame, "Window")
    -- The rows, two per line: name + toggle.
    local rows = ST.Window.ROWS
    local colW = (WIDTH - 2 * LABEL_X) / 2
    for i, def in ipairs(rows) do
        local col, line = (i - 1) % 2, floor((i - 1) / 2)
        local ly = y + line * 26
        local fs = W.Text(frame, 0, "textDim")
        fs:SetPoint("TOPLEFT", LABEL_X + col * colW, -(ly + 5))
        fs:SetText(def[1])
        local t = W.Toggle(frame, function(on)
            s.rows[def.id] = on
            set("rows", s.rows)
        end)
        t:SetPoint("TOPLEFT", LABEL_X + col * colW + colW - 56, -(ly + 5))
        addControl(t, function() t:Set(s.rows[def.id] ~= false) end)
    end
    y = y + ceil(#rows / 2) * 26 + 6

    toggleRow(frame, "Level progress bar", function() return s.levelBar end, function(on) set("levelBar", on) end)
    toggleRow(frame, "Hide in combat", function() return s.hideInCombat end, function(on) set("hideInCombat", on) end)
    toggleRow(frame, "Lock position", function() return ST.db.window.locked == true end,
        function(on) ST.db.window.locked = on or nil end)

    -- Session ----------------------------------------------------------------
    heading(frame, "Session")
    local mode = W.Segment(frame, {
        { value = "login", label = "Every login" },
        { value = "manual", label = "Only on Reset" },
    }, function(v) set("newSession", v) end)
    row(frame, "New session", mode, 3)
    addControl(mode, function() mode:Set(s.newSession) end)
    local hint = W.Text(frame, -2, "textFaint")
    hint:SetPoint("TOPLEFT", CONTROL_X, -(y - 4))
    hint:SetText("\"Only on Reset\" keeps one session over several logins\n(only time logged in counts).")
    hint:SetWordWrap(true)
    hint:SetWidth(WIDTH - CONTROL_X - 12)
    y = y + 30

    local reset = textButton(frame, "Reset window position", function()
        ST.Window.ResetPosition()
        ST:Print("Window position reset.")
    end)
    reset:SetPoint("TOPLEFT", LABEL_X, -(y + 8))
    y = y + 44

    frame:SetHeight(y)
    frame:SetScript("OnHide", function()
        W.HideTooltip()
        W.CloseMenus()
    end)
    frame:Hide()
end

-- Next to the session window if there is room, else in the middle.
local function place()
    frame:ClearAllPoints()
    local main = _G.SessionTrackerFrame
    if main and main:IsShown() and (main:GetLeft() or 0) * main:GetEffectiveScale() > WIDTH * frame:GetEffectiveScale() + 20 then
        frame:SetPoint("TOPRIGHT", main, "TOPLEFT", -8, 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    end
end

function Settings.Toggle()
    if not ST.db then return end
    if not frame then
        -- A failed build must not leave a half-made (invisible) window behind.
        local ok, err = pcall(build)
        if not ok then
            if frame then frame:Hide() end
            frame = nil
            wipe(controls)
            ST:RecordError("settings build", err)
            return
        end
    end
    if frame:IsShown() then frame:Hide() return end
    for _, c in ipairs(controls) do c.refresh() end
    place()
    frame:Show()
end

ST:AddSlashCommand("settings", function() Settings.Toggle() end, "open the settings")
