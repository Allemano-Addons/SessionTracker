-- The Ledger window (the Allemano look): tabs Now / History / Lifetime / Alts / Settings.
-- Alts is the characters table; Lifetime has the gold goal. A small summary popup shows when an instance run ends.
local _, ST = ...

local Theme, W, Session, Ledger, Fmt = ST.Theme, ST.Widgets, ST.Session, ST.Ledger, ST.Fmt

local LedgerUI = {}
ST.LedgerUI = LedgerUI

local WIDTH, HEIGHT = 720, 500
local TITLE_H, TABS_H, PAD, GAP = 46, 38, 16, 10
local TOP = TITLE_H + TABS_H + GAP -- where the pages start

local TABS = { "Now", "History", "Lifetime", "Progress", "Loot", "Alts", "Settings" }

local frame, ticker
local pages = {}
local tabButtons = {}
local currentTab = "Now"

-- Colors per source (income bars and the history chart).
local SOURCE_COLOR = {
    loot = "E8A93B", vendor = "4F7FFF", quest = "3FC77F", ah = "B99BFF", mail = "3FD0E0",
    trade = "E86FA8", other = "9098A1",
    repair = "E5484D", training = "B99BFF", travel = "3FD0E0",
}
local TAG_COLOR = {
    Farming = "E8A93B", Dungeon = "6C8CFF", Raid = "B99BFF", Leveling = "3FC77F", Questing = "3FC77F",
    Professions = "3FD0E0", PvP = "E5484D", Other = "9098A1",
}

local function hexRGB(h) return Theme.Hex(h) end

local function dayText(key)
    if not key then return "?" end
    local y, m, d = key:match("^(%d+)-(%d+)-(%d+)$")
    local months = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
    return ("%d %s"):format(tonumber(d) or 0, months[tonumber(m) or 1] or "?") .. (y and "" or "")
end

local function paint(tex, r, g, b, a) tex:SetColorTexture(r, g, b, a or 1) end

-- ---------------------------------------------------------------------------
-- Small builders
-- ---------------------------------------------------------------------------

-- A card: rounded, slightly lighter than the window, 1 px border.
local function card(parent, w, h)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)
    f.bg = W.Fill(f, "field", 1)
    f.bg:SetAllPoints()
    W.Panel(f, f.bg, W.Border(f, "line"), Theme.radius.control + 2)
    return f
end

local function label(parent, delta, colorKey, justify)
    local fs = W.Text(parent, delta, colorKey)
    if justify then fs:SetJustifyH(justify) end
    return fs
end

-- Outlined or filled button. kind = "primary" (accent fill, dark text) / nil (outlined).
local function button(parent, text, onClick, kind)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(28)
    b.bg = W.Fill(b, kind == "primary" and "text" or "field", 1)
    b.bg:SetAllPoints()
    W.Round(b.bg, Theme.radius.control)
    if kind ~= "primary" then
        b.border = W.RoundBorder(W.Border(b, "line"), Theme.radius.control)
    end
    b.text = W.Text(b, 0, kind == "primary" and "window" or "text")
    b.text:SetPoint("CENTER", 0, 0)
    function b:SetLabel(t)
        self.text:SetText(t)
        self:SetWidth(self.text:GetStringWidth() + 28)
    end
    b:SetLabel(text)
    b.primary = kind == "primary"
    local function recolor(self)
        if self.primary then
            local r, g, bl = Theme:Accent()
            paint(self.bg, r, g, bl, self.hover and 0.85 or 1)
        elseif self.border then
            local r, g, bl
            if self.hover then r, g, bl = Theme:Color("textFaint") else r, g, bl = Theme:Color("line") end
            self.border:SetColor(r, g, bl, 1)
        end
    end
    b:SetScript("OnEnter", function(self) self.hover = true; recolor(self) end)
    b:SetScript("OnLeave", function(self) self.hover = nil; recolor(self) end)
    b:SetScript("OnClick", onClick)
    if kind == "primary" then W.OnAccent(function() recolor(b) end) end
    return b
end

-- A flat horizontal bar: track + fill. fill width is set with bar:SetFraction(0..1).
local function bar(parent, height)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(height or 6)
    f.track = f:CreateTexture(nil, "BORDER")
    paint(f.track, Theme:Color("line"))
    f.track:SetAllPoints()
    f.fill = f:CreateTexture(nil, "ARTWORK")
    f.fill:SetPoint("TOPLEFT")
    f.fill:SetPoint("BOTTOMLEFT")
    f.fill:SetWidth(0.01)
    function f:SetFraction(x)
        x = math.max(0, math.min(1, x or 0))
        local w = self:GetWidth()
        if not w or w < 1 then w = 100 end
        self.fill:SetWidth(math.max(0.01, w * x))
        self.fill:SetShown(x > 0)
    end
    function f:SetColor(r, g, b) paint(self.fill, r, g, b, 1) end
    return f
end

-- A stat card: small label on top, big value, faint line under it.
local function statCard(parent, w)
    local f = card(parent, w, 72)
    f.title = label(f, -1, "textDim")
    f.title:SetPoint("TOPLEFT", 14, -12)
    f.value = label(f, 8, "text")
    f.value:SetPoint("TOPLEFT", 14, -28)
    f.sub = label(f, -2, "textFaint")
    f.sub:SetPoint("BOTTOMLEFT", 14, 9)
    function f:Set(title, value, sub, colorKey)
        self.title:SetText(title)
        self.value:SetText(value)
        self.value:SetTextColor(Theme:Color(colorKey or "text"))
        self.sub:SetText(sub or "")
    end
    return f
end

-- A line chart in a card region: points = { { x, y }, ... } already in 0..1 space is not
-- needed, they are scaled here. Uses a pool of lines created on demand.
local function lineChart(parent)
    local c = CreateFrame("Frame", nil, parent)
    c.lines = {}
    c.grid = {}
    for i = 1, 3 do
        local g = c:CreateTexture(nil, "BORDER")
        paint(g, Theme:Color("line"))
        g:SetHeight(1)
        c.grid[i] = g
    end
    c.dot = c:CreateTexture(nil, "OVERLAY")
    c.dot:SetSize(8, 8)
    W.Round(c.dot, 4)
    W.OnAccent(function(r, g, b)
        paint(c.dot, r, g, b, 1)
        for _, l in ipairs(c.lines) do l:SetColorTexture(r, g, b, 1) end
    end)
    function c:SetPoints(points)
        local w, h = self:GetWidth(), self:GetHeight()
        if not w or w < 4 then w, h = 300, 140 end
        for i, g in ipairs(self.grid) do
            g:ClearAllPoints()
            g:SetPoint("LEFT", self, "BOTTOMLEFT", 0, (i - 1) * (h - 2) / 2 + 1)
            g:SetPoint("RIGHT", self, "BOTTOMRIGHT", 0, (i - 1) * (h - 2) / 2 + 1)
        end
        local n = #points
        if n == 1 then points = { points[1], { points[1][1] + 1, points[1][2] } }; n = 2 end -- one day: a flat line
        for _, l in ipairs(self.lines) do l:Hide() end
        self.dot:Hide()
        if n < 2 then return end
        local minX, maxX, minY, maxY = points[1][1], points[1][1], 0, 0
        for _, p in ipairs(points) do
            minX, maxX = math.min(minX, p[1]), math.max(maxX, p[1])
            minY, maxY = math.min(minY, p[2]), math.max(maxY, p[2])
        end
        if maxY <= minY then maxY = minY + 1 end
        if maxX <= minX then maxX = minX + 1 end
        local function px(p) return 4 + (p[1] - minX) / (maxX - minX) * (w - 12), 4 + (p[2] - minY) / (maxY - minY) * (h - 8) end
        local r, g, b = Theme:Accent()
        for i = 1, n - 1 do
            local line = self.lines[i]
            if not line then
                line = self:CreateLine(nil, "ARTWORK")
                line:SetThickness(2)
                self.lines[i] = line
            end
            line:SetColorTexture(r, g, b, 1)
            local x1, y1 = px(points[i])
            local x2, y2 = px(points[i + 1])
            line:SetStartPoint("BOTTOMLEFT", self, x1, y1)
            line:SetEndPoint("BOTTOMLEFT", self, x2, y2)
            line:Show()
        end
        local lx, ly = px(points[n])
        self.dot:ClearAllPoints()
        self.dot:SetPoint("CENTER", self, "BOTTOMLEFT", lx, ly)
        self.dot:Show()
    end
    return c
end

-- ---------------------------------------------------------------------------
-- Page: Now
-- ---------------------------------------------------------------------------

local function buildNow(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetPoint("TOPLEFT", 0, 0)
    p:SetPoint("BOTTOMRIGHT", 0, 0)
    local innerW = WIDTH - 2 * PAD
    local cardW = floor((innerW - 3 * GAP) / 4)

    p.cards = {}
    for i = 1, 4 do
        local c = statCard(p, cardW)
        c:SetPoint("TOPLEFT", PAD + (i - 1) * (cardW + GAP), -TOP)
        p.cards[i] = c
    end

    local rowsTop = TOP + 72 + GAP
    local rowsH = HEIGHT - rowsTop - 64
    local leftW = floor((innerW - GAP) * 0.46)
    local rightW = innerW - GAP - leftW

    -- Income by source (up to 4 bars) and expenses (up to 3 rows).
    local left = card(p, leftW, rowsH)
    left:SetPoint("TOPLEFT", PAD, -rowsTop)
    local head = label(left, -2, "textDim")
    head:SetPoint("TOPLEFT", 14, -12)
    head:SetText("INCOME BY SOURCE")
    p.incRows = {}
    for i = 1, 4 do
        local row = {}
        row.name = label(left, 0, "text")
        row.name:SetPoint("TOPLEFT", 14, -34 - (i - 1) * 32)
        row.value = label(left, 0, "good", "RIGHT")
        row.value:SetPoint("TOPRIGHT", -14, -34 - (i - 1) * 32)
        row.bar = bar(left, 6)
        row.bar:SetPoint("TOPLEFT", 14, -54 - (i - 1) * 32)
        row.bar:SetPoint("TOPRIGHT", -14, -54 - (i - 1) * 32)
        p.incRows[i] = row
    end
    p.incEmpty = label(left, 0, "textFaint")
    p.incEmpty:SetPoint("TOPLEFT", 14, -40)
    p.incEmpty:SetText("Nothing earned yet this session.")
    local ehead = label(left, -2, "textDim")
    ehead:SetPoint("TOPLEFT", 14, -34 - 4 * 32 - 4)
    ehead:SetText("EXPENSES")
    p.expRows = {}
    for i = 1, 2 do
        local row = CreateFrame("Frame", nil, left)
        row:SetHeight(26)
        row:SetPoint("TOPLEFT", 14, -34 - 4 * 32 - 22 - (i - 1) * 31)
        row:SetPoint("TOPRIGHT", -14, -34 - 4 * 32 - 22 - (i - 1) * 31)
        row.bg = W.Fill(row, "window", 1)
        row.bg:SetAllPoints()
        W.Round(row.bg, Theme.radius.small + 1)
        row.border = W.RoundBorder(W.Border(row, "line"), Theme.radius.small + 1)
        row.name = label(row, 0, "text")
        row.name:SetPoint("LEFT", 10, 0)
        row.value = label(row, 0, "warn", "RIGHT")
        row.value:SetPoint("RIGHT", -10, 0)
        p.expRows[i] = row
    end
    p.expEmpty = label(left, 0, "textFaint")
    p.expEmpty:SetPoint("TOPLEFT", 14, -34 - 4 * 32 - 22)
    p.expEmpty:SetText("No expenses yet.")

    -- The graph and the lines under it.
    local right = card(p, rightW, rowsH)
    right:SetPoint("TOPRIGHT", -PAD, -rowsTop)
    local ghead = label(right, -2, "textDim")
    ghead:SetPoint("TOPLEFT", 14, -12)
    ghead:SetText("NET GOLD THIS SESSION")
    local gnote = label(right, -2, "textFaint", "RIGHT")
    gnote:SetPoint("TOPRIGHT", -14, -12)
    gnote:SetText("gold over time")
    p.chart = lineChart(right)
    p.chart:SetPoint("TOPLEFT", 14, -34)
    p.chart:SetPoint("TOPRIGHT", -14, -34)
    p.chart:SetHeight(rowsH - 34 - 106)
    p.startLabel = label(right, -1, "textDim")
    p.startLabel:SetPoint("TOPLEFT", p.chart, "BOTTOMLEFT", 0, -6)
    p.startLabel:SetText("Start")
    p.nowLabel = label(right, -1, "textDim", "RIGHT")
    p.nowLabel:SetPoint("TOPRIGHT", p.chart, "BOTTOMRIGHT", 0, -6)
    p.nowLabel:SetText("Now")

    local y = 82
    local function infoRow(text, key)
        local l = label(right, 0, "textDim")
        l:SetPoint("BOTTOMLEFT", 14, y - 82 + 12)
        l:SetText(text)
        local v = label(right, 0, "text", "RIGHT")
        v:SetPoint("BOTTOMRIGHT", -14, y - 82 + 12)
        p[key] = v
        y = y + 26
    end
    infoRow("Total with loot value", "totalValue")
    infoRow("Vendor value of loot", "lootValue")
    infoRow("Activity", "activity")
    -- Activity is a pill: a tinted rounded box behind the text.
    -- (a texture of the card itself, in a layer under the text; a child frame would cover it)
    p.pillBg = W.Fill(right, "window", 1, "ARTWORK")
    p.pillBg:SetPoint("TOPLEFT", p.activity, "TOPLEFT", -10, 4)
    p.pillBg:SetPoint("BOTTOMRIGHT", p.activity, "BOTTOMRIGHT", 10, -4)
    W.Round(p.pillBg, 11)

    -- Footer.
    local foot = CreateFrame("Frame", nil, p)
    foot:SetPoint("BOTTOMLEFT", 0, 0)
    foot:SetPoint("BOTTOMRIGHT", 0, 0)
    foot:SetHeight(56)
    local sep = W.Line(foot, "top", "line")
    sep:ClearAllPoints()
    sep:SetPoint("TOPLEFT", 1, 0)
    sep:SetPoint("TOPRIGHT", -1, 0)
    p.pause = button(foot, "Pause", function()
        local s = Session.Current()
        if s and s.paused then Session.Resume() else Session.Pause() end
    end)
    p.pause:SetPoint("LEFT", PAD, 0)
    p.tag = button(foot, "Tag: Farming", function(self)
        local items = { { text = "Tag this session", title = true },
            { text = "Automatic", onClick = function() Session.SetTag(nil) end } }
        for _, tag in ipairs(Session.TAGS) do
            items[#items + 1] = { text = tag, onClick = function() Session.SetTag(tag) end }
        end
        W.OpenMenu(items, self)
    end)
    p.tag:SetPoint("LEFT", p.pause, "RIGHT", 8, 0)
    p.end_ = button(foot, "End session", function()
        W.Confirm("End this session and save it to the history?", "End session", function()
            Session.Reset()
            ST:Print("Session saved. A new one has started.")
        end)
    end, "primary")
    p.end_:SetPoint("RIGHT", -PAD, 0)
    p.note = label(foot, -1, "textFaint")
    p.note:SetPoint("LEFT", p.tag, "RIGHT", 14, 0)
    p.note:SetPoint("RIGHT", p.end_, "LEFT", -14, 0)
    p.note:SetWordWrap(true)
    p.note:SetText("Gold moved between your own characters is not counted as income.")
    return p
end

-- Largest sources first; the rest are lumped together so the bars stay four.
local function sortedSources(map, order, maxRows)
    local list = {}
    for _, key in ipairs(order) do
        if (map[key] or 0) > 0 then list[#list + 1] = { key = key, value = map[key] } end
    end
    sort(list, function(a, b) return a.value > b.value end)
    if #list > maxRows then
        local rest = 0
        for i = maxRows, #list do rest = rest + list[i].value end
        for i = #list, maxRows + 1, -1 do list[i] = nil end
        list[maxRows] = { key = "rest", value = rest }
    end
    return list
end

local function refreshNow(p)
    local s = Session.Stats()
    if not s then return end
    local good, warn = "good", "warn"
    p.cards[1]:Set("Earned", Fmt.money(s.earned), "before expenses", good)
    p.cards[2]:Set("Spent", Fmt.money(s.spent), "repairs and vendor", warn)
    p.cards[3]:Set("Net", (s.gold < 0 and "-" or "") .. Fmt.money(s.gold), s.paused and "paused" or "this session", "text")
    local perHour = s.goldPerHour and ((s.goldPerHour < 0 and "-" or "") .. Fmt.money(s.goldPerHour)) or "..."
    local xph = s.maxLevel and "max level" or (s.xpPerHour and ("XP/h " .. Fmt.num(s.xpPerHour)) or "XP/h ...")
    p.cards[4]:Set("Gold / hour", perHour, "net, " .. xph, "warn")
    p.cards[4].value:SetTextColor(Theme:Accent())

    local inc = sortedSources(s.inc, Ledger.IN, 4)
    p.incEmpty:SetShown(#inc == 0)
    local top = inc[1] and inc[1].value or 1
    for i, row in ipairs(p.incRows) do
        local e = inc[i]
        row.name:SetShown(e ~= nil)
        row.value:SetShown(e ~= nil)
        row.bar:SetShown(e ~= nil)
        if e then
            row.name:SetText(e.key == "rest" and "Other sources" or Ledger.LABEL_IN[e.key])
            row.value:SetText(Fmt.money(e.value))
            row.bar:SetFraction(e.value / top)
            local r, g, b = hexRGB(SOURCE_COLOR[e.key] or SOURCE_COLOR.other)
            if e.key == "loot" then r, g, b = Theme:Accent() end
            row.bar:SetColor(r, g, b)
        end
    end
    local exp = sortedSources(s.exp, Ledger.OUT, 2)
    p.expEmpty:SetShown(#exp == 0)
    for i, row in ipairs(p.expRows) do
        local e = exp[i]
        row:SetShown(e ~= nil)
        if e then
            row.name:SetText(e.key == "rest" and "Other expenses" or Ledger.LABEL_OUT[e.key])
            row.value:SetText("-" .. Fmt.money(e.value))
        end
    end

    -- Graph: the net gold over the session.
    local pts = {}
    for _, q in ipairs(s.series or {}) do pts[#pts + 1] = { q[1], q[2] } end
    pts[#pts + 1] = { s.elapsed, s.gold }
    p.chart:SetPoints(pts)

    p.activity:SetText(s.tag)
    local r, g, b = hexRGB(TAG_COLOR[s.tag] or TAG_COLOR.Other)
    p.activity:SetTextColor(r, g, b)
    p.lootValue:SetText(Fmt.money(s.lootValue))
    p.totalValue:SetText((s.gold + s.lootValue < 0 and "-" or "") .. Fmt.money(s.gold + s.lootValue))
    p.totalValue:SetTextColor(Theme:Color(s.gold + s.lootValue >= 0 and "good" or "warn"))
    p.pause:SetLabel(s.paused and "Resume" or "Pause")
    p.tag:SetLabel("Tag: " .. s.tag)
end

-- ---------------------------------------------------------------------------
-- Page: History
-- ---------------------------------------------------------------------------

local RANGES = { { "14 days", 14 }, { "30 days", 30 }, { "All", 90 } }
local GROUPS = { -- legend order, bottom to top
    { "loot", "Loot coins" }, { "vendor", "Vendor sales" }, { "quest", "Quest rewards" }, { "other", "Other (AH, mail)" },
}
local TABLE_ROWS = 5
local ROW_H = 28
local histOffset = 0
local histRange = 14

local function groupOf(inc)
    local out = { loot = inc.loot or 0, vendor = inc.vendor or 0, quest = inc.quest or 0 }
    out.other = (inc.ah or 0) + (inc.mail or 0) + (inc.trade or 0) + (inc.other or 0)
    return out
end

local function buildHistory(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetPoint("TOPLEFT", 0, 0)
    p:SetPoint("BOTTOMRIGHT", 0, 0)
    local innerW = WIDTH - 2 * PAD

    local chartH = 214
    local cc = card(p, innerW, chartH)
    cc:SetPoint("TOPLEFT", PAD, -TOP)
    local title = label(cc, 2, "text")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Gold earned per day")
    p.rangeButtons = {}
    local prev
    for i = #RANGES, 1, -1 do
        local r = RANGES[i]
        local b = button(cc, r[1], function()
            histRange = r[2]
            LedgerUI.Refresh()
        end)
        b:SetHeight(24)
        if prev then b:SetPoint("RIGHT", prev, "LEFT", -6, 0) else b:SetPoint("TOPRIGHT", -12, -10) end
        prev = b
        p.rangeButtons[i] = b
    end
    p.plot = CreateFrame("Frame", nil, cc)
    p.plot:SetPoint("TOPLEFT", 14, -46)
    p.plot:SetPoint("TOPRIGHT", -14, -46)
    p.plot:SetHeight(chartH - 46 - 54)
    p.base = p.plot:CreateTexture(nil, "BORDER")
    paint(p.base, Theme:Color("line"))
    p.base:SetPoint("BOTTOMLEFT")
    p.base:SetPoint("BOTTOMRIGHT")
    p.base:SetHeight(1)
    p.segments = {}
    p.dayLabels = {}
    -- Legend (bottom left) and range text (bottom right).
    local lx = 14
    p.legend = {}
    for i, g in ipairs(GROUPS) do
        local sw = cc:CreateTexture(nil, "ARTWORK")
        sw:SetSize(10, 10)
        sw:SetPoint("BOTTOMLEFT", lx, 12)
        local t = label(cc, -1, "textDim")
        t:SetPoint("LEFT", sw, "RIGHT", 5, 0)
        t:SetText(g[2])
        lx = lx + 10 + 5 + t:GetStringWidth() + 16
        p.legend[i] = sw
    end
    p.rangeText = label(cc, -1, "textFaint", "RIGHT")
    p.rangeText:SetPoint("BOTTOMRIGHT", -14, 10)

    -- The table of saved sessions and runs.
    local tableTop = TOP + chartH + GAP
    local tc = card(p, innerW, 26 + TABLE_ROWS * ROW_H + 2)
    tc:SetPoint("TOPLEFT", PAD, -tableTop)
    local COLS = { -- x, width, justify
        date = { 14, 62 }, char = { 80, 90 }, tag = { 176, 84 }, zone = { 270, 150 },
        time = { 428, 52 }, net = { 488, 100 }, perHour = { 596, 96 },
    }
    p.COLS = COLS
    local heads = { date = "Date", char = "Character", tag = "Activity", zone = "Zone", time = "Time", net = "Net gold", perHour = "Gold / h" }
    for key, col in pairs(COLS) do
        local h = label(tc, -1, "textDim")
        h:SetPoint("TOPLEFT", col[1], -8)
        h:SetText(heads[key])
    end
    local hsep = W.Line(tc, "top", "line")
    hsep:ClearAllPoints()
    hsep:SetPoint("TOPLEFT", 1, -26)
    hsep:SetPoint("TOPRIGHT", -1, -26)
    p.rows = {}
    for i = 1, TABLE_ROWS do
        local row = CreateFrame("Button", nil, tc)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 1, -27 - (i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", -1, -27 - (i - 1) * ROW_H)
        row.hl = W.Fill(row, "selected", 1)
        row.hl:SetAllPoints()
        row.hl:Hide()
        for key, col in pairs(COLS) do
            local t = label(row, 0, key == "date" and "textDim" or "text")
            t:SetPoint("LEFT", col[1] - 1, 0)
            t:SetWidth(col[2] - 6)
            row[key] = t
        end
        row:SetScript("OnEnter", function(self)
            self.hl:Show()
            local e = self.entry
            if not e then return end
            local lines = { (e.zone or "?") .. (e.kind == "run" and " (instance run)" or "") }
            lines[#lines + 1] = "Earned " .. Fmt.money(Session.Sum(e.inc)) .. ", spent " .. Fmt.money(Session.Sum(e.exp))
            if (e.lootValue or 0) > 0 then lines[#lines + 1] = "Vendor value of loot " .. Fmt.money(e.lootValue) end
            if (e.xpGained or 0) > 0 then lines[#lines + 1] = "XP " .. Fmt.num(e.xpGained) end
            W.ShowTooltip(self, lines)
        end)
        row:SetScript("OnLeave", function(self)
            self.hl:Hide()
            W.HideTooltip()
        end)
        p.rows[i] = row
    end
    p.empty = label(tc, 0, "textFaint", "CENTER")
    p.empty:SetPoint("CENTER", 0, -12)
    p.empty:SetText("Finished sessions and instance runs show up here.")
    tc:EnableMouseWheel(true)
    tc:SetScript("OnMouseWheel", function(_, delta)
        histOffset = math.max(0, histOffset - delta)
        LedgerUI.Refresh()
    end)
    p.tableCard = tc
    return p
end

local function refreshHistory(p)
    -- Chart: income per day, split in four groups.
    local keys = Ledger.RecentDays(histRange)
    local days = {}
    local maxTotal, best, bestKey = 1, 0, nil
    local firstWithData
    for i = #keys, 1, -1 do -- oldest first
        local d = Ledger.Day(keys[i])
        local g = groupOf(d.inc)
        local total = g.loot + g.vendor + g.quest + g.other
        days[#days + 1] = { key = keys[i], g = g, total = total }
        if total > maxTotal then maxTotal = total end
        if total > best then best, bestKey = total, keys[i] end
        if total > 0 and not firstWithData then firstWithData = #days end
    end
    -- "All": cut the empty days before the first one with data.
    if histRange >= 90 and firstWithData and firstWithData > 1 then
        local trimmed = {}
        for i = firstWithData, #days do trimmed[#trimmed + 1] = days[i] end
        days = trimmed
    end
    for i, b in ipairs(p.rangeButtons) do
        local lr, lg, lb = Theme:Color("line")
        b.border:SetColor(lr, lg, lb, 1)
        if RANGES[i][2] == histRange then
            local r, g, bl = Theme:Accent()
            b.border:SetColor(r, g, bl, 1)
            b.text:SetTextColor(r, g, bl)
        else
            b.text:SetTextColor(Theme:Color("text"))
        end
    end
    for i, sw in ipairs(p.legend) do
        local key = GROUPS[i][1]
        local r, g, b = hexRGB(SOURCE_COLOR[key])
        if key == "loot" then r, g, b = Theme:Accent() end
        paint(sw, r, g, b, 1)
    end
    local plotW, plotH = p.plot:GetWidth(), p.plot:GetHeight()
    if not plotW or plotW < 10 then plotW, plotH = WIDTH - 2 * PAD - 28, 114 end
    local n = #days
    local slot = plotW / math.max(n, 1)
    local barW = math.max(2, slot - math.min(8, slot * 0.2))
    local used = 0
    for i, day in ipairs(days) do
        local x = (i - 1) * slot + (slot - barW) / 2
        local yOff = 1
        for _, g in ipairs(GROUPS) do
            local value = day.g[g[1]]
            if value > 0 then
                used = used + 1
                local seg = p.segments[used]
                if not seg then
                    seg = p.plot:CreateTexture(nil, "ARTWORK")
                    p.segments[used] = seg
                end
                local h = math.max(1, value / maxTotal * (plotH - 6))
                local r, gg, b = hexRGB(SOURCE_COLOR[g[1]])
                if g[1] == "loot" then r, gg, b = Theme:Accent() end
                paint(seg, r, gg, b, 1)
                seg:ClearAllPoints()
                seg:SetPoint("BOTTOMLEFT", p.plot, "BOTTOMLEFT", x, yOff)
                seg:SetSize(barW, h)
                seg:Show()
                yOff = yOff + h
            end
        end
        -- Day number under the bars (not every one when crowded).
        local lab = p.dayLabels[i]
        if not lab then
            lab = label(p.plot, -2, "textDim", "CENTER")
            p.dayLabels[i] = lab
        end
        local every = n > 40 and 7 or (n > 20 and 2 or 1)
        lab:ClearAllPoints()
        lab:SetPoint("TOP", p.plot, "BOTTOMLEFT", x + barW / 2, -6)
        lab:SetText(tonumber(day.key:sub(9, 10)) or "")
        lab:SetShown((n - i) % every == 0)
    end
    for i = used + 1, #p.segments do p.segments[i]:Hide() end
    for i = n + 1, #p.dayLabels do p.dayLabels[i]:Hide() end
    if best > 0 then
        p.rangeText:SetText(("%s - today  -  best day: %s, %s"):format(dayText(days[1].key), dayText(bestKey), Fmt.gold(best)))
    else
        p.rangeText:SetText("No gold earned in this period yet.")
    end

    -- Table.
    local list = Ledger.AllHistory()
    histOffset = math.max(0, math.min(histOffset, #list - TABLE_ROWS))
    p.empty:SetShown(#list == 0)
    for i, row in ipairs(p.rows) do
        local item = list[histOffset + i]
        row:SetShown(item ~= nil)
        if item then
            local e = item.e
            row.entry = e
            row.date:SetText(date("%d %b", e.start or time()))
            row.char:SetText(item.name or "?")
            local cr, cg, cb = Theme.ClassColor(item.class)
            if cr then row.char:SetTextColor(cr, cg, cb) else row.char:SetTextColor(Theme:Color("text")) end
            row.tag:SetText(e.tag or "-")
            row.tag:SetTextColor(hexRGB(TAG_COLOR[e.tag] or TAG_COLOR.Other))
            row.zone:SetText(e.zone or "-")
            row.time:SetText(Fmt.clock(e.duration or 0))
            local net = e.net or e.money or 0
            row.net:SetText((net >= 0 and "+" or "-") .. Fmt.money(net))
            row.net:SetTextColor(Theme:Color(net >= 0 and "good" or "warn"))
            local dur = e.duration or 0
            if dur >= 60 then
                local gph = net / (dur / 3600)
                row.perHour:SetText((gph < 0 and "-" or "") .. Fmt.money(gph))
                row.perHour:SetTextColor(Theme:Accent())
            else
                row.perHour:SetText("-")
                row.perHour:SetTextColor(Theme:Color("textFaint"))
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Page: Lifetime
-- ---------------------------------------------------------------------------

local function buildLifetime(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetPoint("TOPLEFT", 0, 0)
    p:SetPoint("BOTTOMRIGHT", 0, 0)
    local innerW = WIDTH - 2 * PAD
    local cardW = floor((innerW - 2 * GAP) / 3)
    p.cards = {}
    for i = 1, 3 do
        local c = statCard(p, cardW)
        c:SetPoint("TOPLEFT", PAD + (i - 1) * (cardW + GAP), -TOP)
        p.cards[i] = c
    end
    local rowsTop = TOP + 72 + GAP
    local rowsH = 176
    local leftW = floor((innerW - GAP) * 0.62)
    local rightW = innerW - GAP - leftW
    local left = card(p, leftW, rowsH)
    left:SetPoint("TOPLEFT", PAD, -rowsTop)
    local head = label(left, -2, "textDim")
    head:SetPoint("TOPLEFT", 14, -12)
    head:SetText("GOLD HELD OVER TIME (ALL CHARACTERS)")
    p.chart = lineChart(left)
    p.chart:SetPoint("TOPLEFT", 14, -34)
    p.chart:SetPoint("TOPRIGHT", -14, -34)
    p.chart:SetHeight(rowsH - 34 - 30)
    p.fromLabel = label(left, -1, "textDim")
    p.fromLabel:SetPoint("TOPLEFT", p.chart, "BOTTOMLEFT", 0, -6)
    p.sinceLabel = label(left, -1, "textFaint", "CENTER")
    p.sinceLabel:SetPoint("TOP", p.chart, "BOTTOM", 0, -6)
    p.toLabel = label(left, -1, "textDim", "RIGHT")
    p.toLabel:SetPoint("TOPRIGHT", p.chart, "BOTTOMRIGHT", 0, -6)

    local right = card(p, rightW, rowsH)
    right:SetPoint("TOPRIGHT", -PAD, -rowsTop)
    local rhead = label(right, -2, "textDim")
    rhead:SetPoint("TOPLEFT", 14, -12)
    rhead:SetText("WHERE IT CAME FROM")
    p.srcRows = {}
    for i = 1, 4 do
        local row = {}
        row.name = label(right, 0, "text")
        row.name:SetPoint("TOPLEFT", 14, -36 - (i - 1) * 32)
        row.pct = label(right, 0, "text", "RIGHT")
        row.pct:SetPoint("TOPRIGHT", -14, -36 - (i - 1) * 32)
        row.bar = bar(right, 5)
        row.bar:SetPoint("TOPLEFT", 14, -56 - (i - 1) * 32)
        row.bar:SetPoint("TOPRIGHT", -14, -56 - (i - 1) * 32)
        p.srcRows[i] = row
    end

    -- The gold goal: a target for the gold you hold, and how long it takes at your pace.
    local goalTop = rowsTop + rowsH + GAP
    local goal = card(p, innerW, 88)
    goal:SetPoint("TOPLEFT", PAD, -goalTop)
    goal.title = label(goal, 2, "text")
    goal.title:SetPoint("TOPLEFT", 14, -14)
    goal.edit = button(goal, "Edit goal", function() LedgerUI.EditGoal() end)
    goal.edit:SetHeight(26)
    goal.edit:SetPoint("TOPRIGHT", -12, -10)
    goal.progress = label(goal, 0, "text", "RIGHT")
    goal.progress:SetPoint("RIGHT", goal.edit, "LEFT", -12, 0)
    goal.bar = bar(goal, 8)
    goal.bar:SetPoint("TOPLEFT", 14, -46)
    goal.bar:SetPoint("TOPRIGHT", -14, -46)
    W.OnAccent(function(r, g, b) goal.bar:SetColor(r, g, b) end)
    goal.text = label(goal, 0, "textDim")
    goal.text:SetPoint("TOPLEFT", 14, -62)
    goal.text:SetPoint("TOPRIGHT", -14, -62)
    p.goal = goal

    p.foot = label(p, -1, "textFaint")
    p.foot:SetPoint("BOTTOMLEFT", PAD, 14)
    p.foot:SetPoint("BOTTOMRIGHT", -PAD, 14)
    p.foot:SetWordWrap(true)
    p.foot:SetText("Lifetime figures only cover what the addon has seen since it was installed. Gold moved between your own characters is excluded.")
    return p
end

local function refreshGoal(p)
    local goal, g = p.goal, Ledger.Goal()
    if not g then
        goal.title:SetText("Gold goal")
        goal.edit:SetLabel("Set a goal")
        goal.progress:SetText("")
        goal.bar:SetFraction(0)
        goal.text:SetText("Set a target (a mount, say) and see how long it takes at your pace.")
        return
    end
    local held = Ledger.TotalGold()
    local pace = Ledger.Pace()
    goal.title:SetText("Goal: " .. g.name)
    goal.edit:SetLabel("Edit goal")
    goal.progress:SetText(Fmt.gold(held) .. " of " .. Fmt.gold(g.amount))
    goal.bar:SetFraction(held / g.amount)
    if held >= g.amount then
        goal.text:SetText("Goal reached. You hold " .. Fmt.gold(held - g.amount) .. " more than the target.")
    elseif pace > 0 then
        local days = math.ceil((g.amount - held) / pace)
        goal.text:SetText(("At your current pace of about %s per day you reach it in %d day%s."):format(Fmt.gold(pace), days, days == 1 and "" or "s"))
    else
        goal.text:SetText("No positive pace over the last 14 days yet, so there is no estimate.")
    end
end

local function refreshLifetime(p)
    refreshGoal(p)
    local life = Ledger.Lifetime()
    local earned, spent = Session.Sum(life.inc), Session.Sum(life.exp)
    local since = life.firstDay and ("since " .. dayText(life.firstDay)) or "nothing tracked yet"
    p.cards[1]:Set("Total earned", Fmt.gold(earned), since, "good")
    p.cards[2]:Set("Total spent", Fmt.gold(spent), "repairs, vendor, AH", "warn")
    p.cards[3]:Set("Net gain", (earned - spent < 0 and "-" or "") .. Fmt.gold(math.abs(earned - spent)), "across all characters", "text")

    local series = Ledger.GoldOverTime(120)
    local pts = {}
    for i, e in ipairs(series) do pts[i] = { i, e[2] } end
    p.chart:SetPoints(pts)
    p.fromLabel:SetText(series[1] and dayText(series[1][1]) or "")
    p.toLabel:SetText(series[#series] and dayText(series[#series][1]) or "")
    p.sinceLabel:SetText("Tracked since install")

    local inc = sortedSources(life.inc, Ledger.IN, 4)
    for i, row in ipairs(p.srcRows) do
        local e = inc[i]
        row.name:SetShown(e ~= nil)
        row.pct:SetShown(e ~= nil)
        row.bar:SetShown(e ~= nil)
        if e then
            row.name:SetText(e.key == "rest" and "Other sources" or Ledger.LABEL_IN[e.key])
            row.pct:SetText(("%d%%"):format(floor(e.value / earned * 100 + 0.5)))
            row.bar:SetFraction(e.value / earned)
            local r, g, b = hexRGB(SOURCE_COLOR[e.key] or SOURCE_COLOR.other)
            if e.key == "loot" then r, g, b = Theme:Accent() end
            row.bar:SetColor(r, g, b)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Period bar (Progress and Loot): this session / today / 7 days / all time
-- ---------------------------------------------------------------------------

local PERIODS = { { "Session", "session" }, { "Today", "today" }, { "7 days", "week" }, { "All time", "all" } }
local periodKey = "session"

local function periodBar(parent)
    local list = {}
    local prev
    for i, def in ipairs(PERIODS) do
        local b = button(parent, def[1], function()
            periodKey = def[2]
            LedgerUI.Refresh()
        end)
        b:SetHeight(24)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", PAD, -TOP) end
        prev = b
        list[i] = b
    end
    return list
end

local function updatePeriodBar(list)
    for i, b in ipairs(list) do
        if PERIODS[i][2] == periodKey then
            local r, g, bl = Theme:Accent()
            b.border:SetColor(r, g, bl, 1)
            b.text:SetTextColor(r, g, bl)
        else
            b.border:SetColor(Theme:Color("line"))
            b.text:SetTextColor(Theme:Color("text"))
        end
    end
end

local function perHour(n, seconds)
    if seconds < 60 then return nil end
    return n / (seconds / 3600)
end

-- ---------------------------------------------------------------------------
-- Page: Progress (XP, level, reputation)
-- ---------------------------------------------------------------------------

local function buildProgress(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetPoint("TOPLEFT", 0, 0)
    p:SetPoint("BOTTOMRIGHT", 0, 0)
    p.periods = periodBar(p)
    local innerW = WIDTH - 2 * PAD
    local cardW = floor((innerW - 3 * GAP) / 4)
    local cardsTop = TOP + 34
    p.cards = {}
    for i = 1, 4 do
        local c = statCard(p, cardW)
        c:SetPoint("TOPLEFT", PAD + (i - 1) * (cardW + GAP), -cardsTop)
        p.cards[i] = c
    end
    local rowsTop = cardsTop + 72 + GAP
    local rowsH = HEIGHT - rowsTop - PAD
    local leftW = floor((innerW - GAP) * 0.5)
    local rightW = innerW - GAP - leftW

    local left = card(p, leftW, rowsH)
    left:SetPoint("TOPLEFT", PAD, -rowsTop)
    local head = label(left, -2, "textDim")
    head:SetPoint("TOPLEFT", 14, -12)
    head:SetText("LEVEL PROGRESS (THIS CHARACTER)")
    p.lvlTitle = label(left, 6, "text")
    p.lvlTitle:SetPoint("TOPLEFT", 14, -34)
    p.lvlPct = label(left, 2, "textDim", "RIGHT")
    p.lvlPct:SetPoint("TOPRIGHT", -14, -40)
    p.lvlBar = bar(left, 8)
    p.lvlBar:SetPoint("TOPLEFT", 14, -68)
    p.lvlBar:SetPoint("TOPRIGHT", -14, -68)
    W.OnAccent(function(r, g, b) p.lvlBar:SetColor(r, g, b) end)
    p.lvlRows = {}
    for i, name in ipairs({ "Time on this level", "Time to next level", "Rested XP" }) do
        local l = label(left, 0, "textDim")
        l:SetPoint("TOPLEFT", 14, -94 - (i - 1) * 26)
        l:SetText(name)
        local v = label(left, 0, "text", "RIGHT")
        v:SetPoint("TOPRIGHT", -14, -94 - (i - 1) * 26)
        p.lvlRows[i] = v
    end
    p.lvlNote = label(left, -1, "textFaint")
    p.lvlNote:SetPoint("TOPLEFT", 14, -94 - 3 * 26)
    p.lvlNote:SetPoint("TOPRIGHT", -14, -94 - 3 * 26)
    p.lvlNote:SetWordWrap(true)
    p.lvlNote:SetText("Time to next level uses your pace in this session.")
    local times = button(left, "Level times", function() ST:Call("level times", ST.LevelsUI.Toggle) end)
    times:SetPoint("BOTTOMLEFT", 14, 14)

    local right = card(p, rightW, rowsH)
    right:SetPoint("TOPRIGHT", -PAD, -rowsTop)
    local rhead = label(right, -2, "textDim")
    rhead:SetPoint("TOPLEFT", 14, -12)
    rhead:SetText("REPUTATION GAINED")
    p.repRows = {}
    for i = 1, 6 do
        local row = {}
        row.name = label(right, 0, "text")
        row.name:SetPoint("TOPLEFT", 14, -34 - (i - 1) * 34)
        row.name:SetPoint("TOPRIGHT", -90, -34 - (i - 1) * 34)
        row.value = label(right, 0, "good", "RIGHT")
        row.value:SetPoint("TOPRIGHT", -14, -34 - (i - 1) * 34)
        row.bar = bar(right, 5)
        row.bar:SetPoint("TOPLEFT", 14, -54 - (i - 1) * 34)
        row.bar:SetPoint("TOPRIGHT", -14, -54 - (i - 1) * 34)
        p.repRows[i] = row
    end
    p.repEmpty = label(right, 0, "textFaint")
    p.repEmpty:SetPoint("TOPLEFT", 14, -40)
    p.repEmpty:SetText("No reputation gained in this period.")
    return p
end

local function refreshProgress(p)
    updatePeriodBar(p.periods)
    local d = Ledger.Period(periodKey)
    local xph = perHour(d.xp, d.time)
    p.cards[1]:Set("XP gained", Fmt.num(d.xp), d.xpQuest > 0 and ("from quests: " .. Fmt.num(d.xpQuest)) or "kills and other", "text")
    p.cards[2]:Set("XP / hour", xph and Fmt.num(xph) or "...", "online " .. Fmt.duration(d.time), "text")
    p.cards[2].value:SetTextColor(Theme:Accent())
    local kph = perHour(d.kills, d.time)
    p.cards[3]:Set("Kills", Fmt.num(d.kills), kph and (Fmt.num(kph) .. " / hour") or "that gave XP", "text")
    p.cards[4]:Set("Deaths", Fmt.num(d.deaths), "", d.deaths > 0 and "warn" or "text")

    local s = Session.Stats()
    local level = UnitLevel("player") or 0
    if s and s.maxLevel then
        p.lvlTitle:SetText("Level " .. level .. " (max)")
        p.lvlPct:SetText("")
        p.lvlBar:SetFraction(1)
        p.lvlRows[1]:SetText("-")
        p.lvlRows[2]:SetText("-")
    else
        p.lvlTitle:SetText("Level " .. level)
        local pct = s and s.levelPct or 0
        p.lvlPct:SetText(("%d%%"):format(floor(pct * 100)))
        p.lvlBar:SetFraction(pct)
        local t = ST.Levels.CurrentLevelTime()
        p.lvlRows[1]:SetText(t and Fmt.duration(t) or "...")
        p.lvlRows[2]:SetText(s and s.timeToLevel and Fmt.duration(s.timeToLevel) or "...")
    end
    local rested = GetXPExhaustion and GetXPExhaustion()
    if rested and rested > 0 then
        local max = UnitXPMax("player") or 0
        p.lvlRows[3]:SetText(Fmt.num(rested) .. (max > 0 and (" (" .. floor(rested / max * 100) .. "%)") or ""))
    else
        p.lvlRows[3]:SetText("none")
    end

    local list = {}
    for name, n in pairs(d.rep) do if n ~= 0 then list[#list + 1] = { name = name, n = n } end end
    sort(list, function(a, b) return math.abs(a.n) > math.abs(b.n) end)
    p.repEmpty:SetShown(#list == 0)
    local top = list[1] and math.abs(list[1].n) or 1
    for i, row in ipairs(p.repRows) do
        local e = list[i]
        row.name:SetShown(e ~= nil)
        row.value:SetShown(e ~= nil)
        row.bar:SetShown(e ~= nil)
        if e then
            row.name:SetText(e.name)
            row.value:SetText((e.n > 0 and "+" or "-") .. Fmt.num(math.abs(e.n)))
            row.value:SetTextColor(Theme:Color(e.n > 0 and "good" or "warn"))
            row.bar:SetFraction(math.abs(e.n) / top)
            row.bar:SetColor(Theme:Color(e.n > 0 and "good" or "warn"))
        end
    end
end

-- ---------------------------------------------------------------------------
-- Page: Loot (items by quality, vendor value, rare drops)
-- ---------------------------------------------------------------------------

local QUALITY = {
    { 0, "Poor", "9D9D9D" }, { 1, "Common", "FFFFFF" }, { 2, "Uncommon", "1EFF00" },
    { 3, "Rare", "0070DD" }, { 4, "Epic", "A335EE" }, { 5, "Legendary", "FF8000" },
}

local function buildLoot(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetPoint("TOPLEFT", 0, 0)
    p:SetPoint("BOTTOMRIGHT", 0, 0)
    p.periods = periodBar(p)
    local innerW = WIDTH - 2 * PAD
    local cardW = floor((innerW - 3 * GAP) / 4)
    local cardsTop = TOP + 34
    p.cards = {}
    for i = 1, 4 do
        local c = statCard(p, cardW)
        c:SetPoint("TOPLEFT", PAD + (i - 1) * (cardW + GAP), -cardsTop)
        p.cards[i] = c
    end
    local rowsTop = cardsTop + 72 + GAP
    local rowsH = HEIGHT - rowsTop - PAD
    local leftW = floor((innerW - GAP) * 0.5)
    local rightW = innerW - GAP - leftW

    local left = card(p, leftW, rowsH)
    left:SetPoint("TOPLEFT", PAD, -rowsTop)
    local head = label(left, -2, "textDim")
    head:SetPoint("TOPLEFT", 14, -12)
    head:SetText("ITEMS LOOTED BY QUALITY")
    p.qRows = {}
    for i, q in ipairs(QUALITY) do
        local row = {}
        row.name = label(left, 0, "text")
        row.name:SetPoint("TOPLEFT", 14, -34 - (i - 1) * 34)
        row.name:SetTextColor(hexRGB(q[3]))
        row.value = label(left, 0, "text", "RIGHT")
        row.value:SetPoint("TOPRIGHT", -14, -34 - (i - 1) * 34)
        row.bar = bar(left, 5)
        row.bar:SetPoint("TOPLEFT", 14, -54 - (i - 1) * 34)
        row.bar:SetPoint("TOPRIGHT", -14, -54 - (i - 1) * 34)
        row.bar:SetColor(hexRGB(q[3]))
        row.name:SetText(q[2])
        p.qRows[i] = row
    end

    local right = card(p, rightW, rowsH)
    right:SetPoint("TOPRIGHT", -PAD, -rowsTop)
    local rhead = label(right, -2, "textDim")
    rhead:SetPoint("TOPLEFT", 14, -12)
    rhead:SetText("RARE AND BETTER DROPS (THIS CHARACTER)")
    p.dropRows = {}
    for i = 1, 7 do
        local row = CreateFrame("Button", nil, right)
        row:SetHeight(28)
        row:SetPoint("TOPLEFT", 6, -32 - (i - 1) * 30)
        row:SetPoint("TOPRIGHT", -6, -32 - (i - 1) * 30)
        row.hl = W.Fill(row, "selected", 1)
        row.hl:SetAllPoints()
        row.hl:Hide()
        row.item = label(row, 0, "text")
        row.item:SetPoint("LEFT", 8, 0)
        row.item:SetPoint("RIGHT", -70, 0)
        row.when = label(row, -1, "textFaint", "RIGHT")
        row.when:SetPoint("RIGHT", -8, 0)
        row:SetScript("OnEnter", function(self)
            self.hl:Show()
            if self.link and GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:SetHyperlink(self.link)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            self.hl:Hide()
            if GameTooltip then GameTooltip:Hide() end
        end)
        p.dropRows[i] = row
    end
    p.dropEmpty = label(right, 0, "textFaint")
    p.dropEmpty:SetPoint("TOPLEFT", 14, -40)
    p.dropEmpty:SetText("No rare drops yet.")
    return p
end

local function refreshLoot(p)
    updatePeriodBar(p.periods)
    local d = Ledger.Period(periodKey)
    local iph = perHour(d.itemCount, d.time)
    p.cards[1]:Set("Items looted", Fmt.num(d.itemCount), iph and (Fmt.num(iph) .. " / hour") or "", "text")
    local vph = perHour(d.loot, d.time)
    p.cards[2]:Set("Vendor value", Fmt.money(d.loot), vph and (Fmt.money(vph) .. " / hour") or "of looted items", "text")
    p.cards[2].value:SetTextColor(Theme:Accent())
    local coins = d.inc and d.inc.loot or 0
    p.cards[3]:Set("Loot coins", Fmt.money(coins), "gold from corpses", "good")
    local kph = perHour(d.kills, d.time)
    p.cards[4]:Set("Kills", Fmt.num(d.kills), kph and (Fmt.num(kph) .. " / hour") or "that gave XP", "text")

    local top = 1
    for _, q in ipairs(QUALITY) do top = math.max(top, d.items[q[1]] or 0) end
    for i, q in ipairs(QUALITY) do
        local n = d.items[q[1]] or 0
        p.qRows[i].value:SetText(Fmt.num(n))
        p.qRows[i].bar:SetFraction(n / top)
    end

    local drops = Ledger.Notable()
    p.dropEmpty:SetShown(#drops == 0)
    for i, row in ipairs(p.dropRows) do
        local e = drops[i]
        row:SetShown(e ~= nil)
        if e then
            row.link = e.link
            row.item:SetText(e.link .. (e.qty and e.qty > 1 and (" x" .. e.qty) or ""))
            row.when:SetText(date("%d %b", e.t or time()))
        end
    end
end

-- ---------------------------------------------------------------------------
-- Page: Alts (every character side by side, last 7 days)
-- ---------------------------------------------------------------------------

local ALT_ROWS = 6
local altOffset = 0

local function buildAlts(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetPoint("TOPLEFT", 0, 0)
    p:SetPoint("BOTTOMRIGHT", 0, 0)
    local innerW = WIDTH - 2 * PAD
    local cardW = floor((innerW - 2 * GAP) / 3)
    p.cards = {}
    for i = 1, 3 do
        local c = statCard(p, cardW)
        c:SetPoint("TOPLEFT", PAD + (i - 1) * (cardW + GAP), -TOP)
        p.cards[i] = c
    end

    local tableTop = TOP + 72 + GAP
    local tc = card(p, innerW, 30 + ALT_ROWS * 34 + 4)
    tc:SetPoint("TOPLEFT", PAD, -tableTop)
    local COLS = {
        name = { 14, 128 }, level = { 146, 40 }, gold = { 192, 96 }, earned = { 296, 100 },
        perHour = { 404, 92 }, played = { 500, 64 },
    }
    local heads = { name = "Character", level = "Level", gold = "Gold", earned = "Earned (7 d)", perHour = "Gold / h", played = "Played" }
    for key, col in pairs(COLS) do
        local h = label(tc, -1, "textDim")
        h:SetPoint("TOPLEFT", col[1], -9)
        h:SetText(heads[key])
    end
    local sh = label(tc, -1, "textDim")
    sh:SetPoint("TOPLEFT", 574, -9)
    sh:SetText("Share of income")
    local hsep = W.Line(tc, "top", "line")
    hsep:ClearAllPoints()
    hsep:SetPoint("TOPLEFT", 1, -30)
    hsep:SetPoint("TOPRIGHT", -1, -30)
    p.rows = {}
    for i = 1, ALT_ROWS do
        local row = CreateFrame("Button", nil, tc)
        row:SetHeight(34)
        row:SetPoint("TOPLEFT", 1, -31 - (i - 1) * 34)
        row:SetPoint("TOPRIGHT", -1, -31 - (i - 1) * 34)
        row.hl = W.Fill(row, "selected", 1)
        row.hl:SetAllPoints()
        row.hl:Hide()
        for key, col in pairs(COLS) do
            local t = label(row, 0, key == "gold" and "text" or "text")
            t:SetPoint("LEFT", col[1] - 1, 0)
            t:SetWidth(col[2] - 6)
            row[key] = t
        end
        row.shareBar = bar(row, 5)
        row.shareBar:SetWidth(54)
        row.shareBar:SetPoint("LEFT", 573, 0)
        row.pct = label(row, 0, "text", "RIGHT")
        row.pct:SetPoint("RIGHT", -10, 0)
        row:SetScript("OnEnter", function(self)
            self.hl:Show()
            local e = self.entry
            if not e then return end
            W.ShowTooltip(self, {
                e.name .. (e.isMe and " (you)" or ""),
                "Earned " .. Fmt.money(e.inc) .. ", spent " .. Fmt.money(e.exp) .. " in 7 days",
                "Online " .. Fmt.duration(e.time) .. " in 7 days",
            })
        end)
        row:SetScript("OnLeave", function(self)
            self.hl:Hide()
            W.HideTooltip()
        end)
        p.rows[i] = row
    end
    p.empty = label(tc, 0, "textFaint", "CENTER")
    p.empty:SetPoint("CENTER", 0, -12)
    p.empty:SetText("Log in on your characters to see them here.")
    tc:EnableMouseWheel(true)
    tc:SetScript("OnMouseWheel", function(_, delta)
        altOffset = math.max(0, altOffset - delta)
        LedgerUI.Refresh()
    end)

    -- Transfers between your own characters, left out of the numbers above.
    local noteTop = tableTop + 30 + ALT_ROWS * 34 + 4 + GAP
    local note = card(p, innerW, HEIGHT - noteTop - PAD)
    note:SetPoint("TOPLEFT", PAD, -noteTop)
    p.noteText = label(note, 0, "textDim")
    p.noteText:SetPoint("LEFT", 14, 0)
    p.noteText:SetPoint("RIGHT", -150, 0)
    p.noteText:SetWordWrap(true)
    p.transfers = button(note, "Show transfers", function()
        local any
        for _, e in ipairs(Ledger.Characters()) do
            if e.xferIn > 0 or e.xferOut > 0 then
                any = true
                ST:Print(("%s: received %s, sent %s (7 days)"):format(e.name, Fmt.money(e.xferIn), Fmt.money(e.xferOut)))
            end
        end
        if not any then ST:Print("No transfers between your characters in the last 7 days.") end
    end)
    p.transfers:SetPoint("RIGHT", -12, 0)
    return p
end

local function refreshAlts(p)
    local list = Ledger.Characters()
    local total, net, incSum, best = 0, 0, 0, nil
    local xin, xout = 0, 0
    for _, e in ipairs(list) do
        total, net, incSum = total + e.gold, net + e.net, incSum + e.inc
        xin, xout = xin + e.xferIn, xout + e.xferOut
        local gph = perHour(e.net, e.time)
        e.gph = gph
        if gph and (not best or gph > best.gph) then best = e end
    end
    p.cards[1]:Set("Gold on all characters", Fmt.money(total), #list .. " character" .. (#list == 1 and "" or "s"), "text")
    p.cards[1].value:SetTextColor(Theme:Accent())
    p.cards[2]:Set("Earned last 7 days", (net < 0 and "-" or "+") .. Fmt.money(net), "net, transfers left out", net >= 0 and "good" or "warn")
    p.cards[3]:Set("Best gold / hour", best and best.name or "-", best and (Fmt.money(best.gph) .. " / hour") or "play a bit to see this", "text")
    if best then
        local r, g, b = Theme.ClassColor(best.class)
        if r then p.cards[3].value:SetTextColor(r, g, b) end
    end

    altOffset = math.max(0, math.min(altOffset, #list - ALT_ROWS))
    p.empty:SetShown(#list == 0)
    for i, row in ipairs(p.rows) do
        local e = list[altOffset + i]
        row:SetShown(e ~= nil)
        if e then
            row.entry = e
            row.name:SetText(e.name)
            local r, g, b = Theme.ClassColor(e.class)
            if r then row.name:SetTextColor(r, g, b) else row.name:SetTextColor(Theme:Color("text")) end
            row.level:SetText(e.level and tostring(e.level) or "-")
            row.gold:SetText(Fmt.money(e.gold))
            row.earned:SetText((e.net < 0 and "-" or "+") .. Fmt.money(e.net))
            row.earned:SetTextColor(Theme:Color(e.net >= 0 and "good" or "warn"))
            row.perHour:SetText(e.gph and ((e.gph < 0 and "-" or "") .. Fmt.money(e.gph)) or "-")
            row.played:SetText(e.played and Fmt.duration(e.played) or "-")
            local share = incSum > 0 and e.inc / incSum or 0
            row.pct:SetText(("%d%%"):format(floor(share * 100 + 0.5)))
            row.shareBar:SetFraction(share)
            if not r then r, g, b = Theme:Accent() end
            row.shareBar:SetColor(r, g, b)
        end
    end
    local moved = math.max(xin, xout)
    if moved > 0 then
        p.noteText:SetText("Transfers excluded: " .. Fmt.money(moved) .. " moved between your own characters this week is not counted as income or expense.")
    else
        p.noteText:SetText("Gold you mail or trade between your own characters is not counted as income or expense. Nothing moved this week.")
    end
end

-- ---------------------------------------------------------------------------
-- The goal editor
-- ---------------------------------------------------------------------------

local goalDialog

local function buildGoalDialog()
    local d = CreateFrame("Frame", "AllemanoLedgerGoal", UIParent)
    d:SetFrameStrata("DIALOG")
    d:SetSize(340, 218)
    d:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    d:EnableMouse(true)
    d.bg = W.Fill(d, "window", 1)
    d.bg:SetAllPoints()
    W.Panel(d, d.bg, W.Border(d, "line"))
    tinsert(UISpecialFrames, "AllemanoLedgerGoal")
    local title = label(d, 2, "text")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Gold goal")
    local nl = label(d, -1, "textDim")
    nl:SetPoint("TOPLEFT", 16, -48)
    nl:SetText("What is it for?")
    d.name = W.EditBox(d, "Mount fund", 28)
    d.name:SetPoint("TOPLEFT", 16, -64)
    d.name:SetPoint("TOPRIGHT", -16, -64)
    d.name:SetMaxLetters(40)
    local al = label(d, -1, "textDim")
    al:SetPoint("TOPLEFT", 16, -102)
    al:SetText("How much gold?")
    d.amount = W.EditBox(d, "1000", 28)
    d.amount:SetPoint("TOPLEFT", 16, -118)
    d.amount:SetPoint("TOPRIGHT", -16, -118)
    d.amount:SetMaxLetters(9)
    d.hint = label(d, -1, "warn")
    d.hint:SetPoint("TOPLEFT", 16, -152)
    d.hint:SetText("")
    local save = button(d, "Save", function() LedgerUI.SaveGoal() end, "primary")
    save:SetPoint("BOTTOMRIGHT", -16, 14)
    local cancel = button(d, "Cancel", function() d:Hide() end)
    cancel:SetPoint("RIGHT", save, "LEFT", -8, 0)
    d.clear = button(d, "Clear goal", function()
        Ledger.ClearGoal()
        d:Hide()
        LedgerUI.Refresh()
    end)
    d.clear:SetPoint("BOTTOMLEFT", 16, 14)
    d.amount:SetScript("OnEnterPressed", function() LedgerUI.SaveGoal() end)
    d.name:SetScript("OnEnterPressed", function() d.amount:SetFocus() end)
    d:Hide()
    return d
end

function LedgerUI.EditGoal()
    if not ST.db then return end
    goalDialog = goalDialog or buildGoalDialog()
    local g = Ledger.Goal()
    goalDialog.name:SetText(g and g.name or "")
    goalDialog.amount:SetText(g and tostring(floor(g.amount / 10000)) or "")
    goalDialog.hint:SetText("")
    goalDialog.clear:SetShown(g ~= nil)
    goalDialog:SetScale(ST.db.settings.scale or 1)
    goalDialog:Show()
    goalDialog.amount:SetFocus()
end

function LedgerUI.SaveGoal()
    local d = goalDialog
    if not d then return end
    local text = (d.amount:GetText() or ""):gsub("[%s,]", "")
    local gold = tonumber(text)
    if not gold or gold < 1 or gold ~= floor(gold) then
        d.hint:SetText("Enter a whole number of gold, like 1000.")
        return
    end
    Ledger.SetGoal(d.name:GetText(), gold * 10000)
    d:Hide()
    LedgerUI.Refresh()
end

-- ---------------------------------------------------------------------------
-- Page: Settings (the real settings window opens from here)
-- ---------------------------------------------------------------------------

local function buildSettings(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetPoint("TOPLEFT", PAD, -TOP)
    p:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    local c = card(p, 10, 10)
    c:SetAllPoints()
    local t = label(c, 2, "text")
    t:SetPoint("TOPLEFT", 16, -16)
    t:SetText("Settings")
    local d = label(c, 0, "textDim")
    d:SetPoint("TOPLEFT", 16, -42)
    d:SetPoint("TOPRIGHT", -16, -42)
    d:SetWordWrap(true)
    d:SetText("Look, accent color, which rows the small session window shows, and how sessions start.")
    local open = button(c, "Open settings", function() ST.Settings.Toggle() end)
    open:SetPoint("TOPLEFT", 16, -82)
    local hud = button(c, "Show/hide the small session window", function() ST.Toggle() end)
    hud:SetPoint("LEFT", open, "RIGHT", 8, 0)
    return p
end

-- ---------------------------------------------------------------------------
-- Frame, tabs
-- ---------------------------------------------------------------------------

local BUILDERS = {
    Now = { buildNow, refreshNow },
    History = { buildHistory, refreshHistory },
    Lifetime = { buildLifetime, refreshLifetime },
    Progress = { buildProgress, refreshProgress },
    Loot = { buildLoot, refreshLoot },
    Alts = { buildAlts, refreshAlts },
    Settings = { buildSettings },
}

local function updateTabs()
    for name, t in pairs(tabButtons) do
        local on = name == currentTab
        t.text:SetTextColor(Theme:Color(on and "text" or (t.hover and "text" or "textDim")))
        t.underline:SetShown(on)
        local r, g, b = Theme:Accent()
        paint(t.underline, r, g, b, 1)
    end
end

local function showTab(name)
    currentTab = name
    ST.db.ledgerWindow.tab = name
    for tabName, def in pairs(BUILDERS) do
        if tabName == name and not pages[tabName] then
            local ok, page = pcall(def[1], frame.content)
            if ok then
                pages[tabName] = page
            else
                ST:RecordError("build " .. tabName, page)
            end
        end
        if pages[tabName] then pages[tabName]:SetShown(tabName == name) end
    end
    updateTabs()
    LedgerUI.Refresh()
end

function LedgerUI.Refresh()
    if not frame or not frame:IsShown() then return end
    local def = BUILDERS[currentTab]
    local page = pages[currentTab]
    if def and def[2] and page then
        local ok, err = pcall(def[2], page)
        if not ok then ST:RecordError("refresh " .. currentTab, err) end
    end
    -- The session pill in the title bar.
    local s = Session.Stats()
    if s and frame.pill then
        frame.pillText:SetText(("Session   %s"):format(s.paused and "Paused" or Fmt.clock(s.elapsed)))
        frame.pillDot:SetColorTexture(Theme:Color(s.paused and "warn" or "good"))
    end
end

local function savePosition()
    local db = ST.db.ledgerWindow
    db.left, db.top = Theme:Snap(frame:GetLeft(), frame), Theme:Snap(frame:GetTop(), frame)
end

local function restorePosition()
    local db = ST.db.ledgerWindow
    frame:ClearAllPoints()
    if db.left and db.top then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.left, db.top)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    end
end

local function build()
    frame = CreateFrame("Frame", "AllemanoLedgerWindow", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetSize(WIDTH, HEIGHT)
    frame.bg = W.Fill(frame, "window", 1)
    frame.bg:SetAllPoints()
    W.Panel(frame, frame.bg, W.Border(frame, "line"))
    tinsert(UISpecialFrames, "AllemanoLedgerWindow") -- ESC closes it

    -- Title bar: drag to move.
    local title = CreateFrame("Frame", nil, frame)
    title:SetPoint("TOPLEFT")
    title:SetPoint("TOPRIGHT")
    title:SetHeight(TITLE_H)
    title:EnableMouse(true)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() frame:StartMoving() end)
    title:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        savePosition()
        restorePosition()
    end)
    local name = W.Text(title, 3, "text")
    local logo = title:CreateTexture(nil, "ARTWORK")
    logo:SetSize(22, 22)
    logo:SetPoint("LEFT", PAD, 0)
    if logo:SetTexture(ST.LOGO) == false then
        logo:Hide()
        name:SetPoint("LEFT", PAD, 0)
    else
        name:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    end
    name:SetText("Ledger")

    local close = W.CloseButton(title, function() frame:Hide() end)
    close:SetPoint("RIGHT", -PAD + 4, 0)

    -- The running session, top right (Now tab only).
    frame.pill = CreateFrame("Frame", nil, title)
    frame.pill:SetHeight(28)
    frame.pill.bg = W.Fill(frame.pill, "field", 1)
    frame.pill.bg:SetAllPoints()
    W.Round(frame.pill.bg, Theme.radius.control)
    W.RoundBorder(W.Border(frame.pill, "line"), Theme.radius.control)
    frame.pill:SetWidth(150)
    frame.pill:SetPoint("RIGHT", close, "LEFT", -10, 0)
    frame.pillDot = frame.pill:CreateTexture(nil, "OVERLAY")
    frame.pillDot:SetSize(8, 8)
    frame.pillDot:SetPoint("LEFT", 12, 0)
    W.Round(frame.pillDot, 4)
    frame.pillText = W.Text(frame.pill, 0, "text")
    frame.pillText:SetPoint("LEFT", frame.pillDot, "RIGHT", 8, 0)
    frame.pillText:SetText("Session")

    local tsep = W.Line(title, "bottom", "line")
    tsep:ClearAllPoints()
    tsep:SetPoint("BOTTOMLEFT", 1, 0)
    tsep:SetPoint("BOTTOMRIGHT", -1, 0)

    -- Tabs.
    local x = PAD
    for _, tabName in ipairs(TABS) do
        local t = CreateFrame("Button", nil, frame)
        t:SetHeight(TABS_H)
        t.text = W.Text(t, 1, "textDim")
        t.text:SetPoint("CENTER", 0, 2)
        t.text:SetText(tabName)
        t:SetWidth(t.text:GetStringWidth() + 24)
        t:SetPoint("TOPLEFT", x - 12, -TITLE_H)
        x = x + t:GetWidth()
        t.underline = t:CreateTexture(nil, "OVERLAY")
        t.underline:SetHeight(2)
        t.underline:SetPoint("BOTTOMLEFT", 12, 0)
        t.underline:SetPoint("BOTTOMRIGHT", -12, 0)
        t:SetScript("OnEnter", function(self) self.hover = true; updateTabs() end)
        t:SetScript("OnLeave", function(self) self.hover = nil; updateTabs() end)
        t:SetScript("OnClick", function() showTab(tabName) end)
        tabButtons[tabName] = t
    end
    local line = W.Line(frame, "top", "line")
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", 1, -(TITLE_H + TABS_H))
    line:SetPoint("TOPRIGHT", -1, -(TITLE_H + TABS_H))

    frame.content = CreateFrame("Frame", nil, frame)
    frame.content:SetAllPoints()

    frame:SetScript("OnShow", function()
        LedgerUI.Refresh()
        if C_Timer and C_Timer.NewTicker then
            ticker = C_Timer.NewTicker(1, function() ST:Call("ledger tick", LedgerUI.Refresh) end)
        end
        ST.db.ledgerWindow.shown = true
    end)
    frame:SetScript("OnHide", function()
        if ticker then ticker:Cancel() end
        ticker = nil
        W.HideTooltip()
        W.CloseMenus()
        if ST.db then ST.db.ledgerWindow.shown = false end
    end)
    frame:SetScale(ST.db.settings.scale or 1)
    frame.bg:SetAlpha(1)
    frame:Hide()
    restorePosition()
    W.OnAccent(function() updateTabs() end)
    local tab = ST.db.ledgerWindow.tab
    showTab(BUILDERS[tab] and tab or "Now")
end

function LedgerUI.Show(tab)
    if not ST.db then return end
    if not frame then build() end
    if tab and BUILDERS[tab] then showTab(tab) end
    frame:Show()
end

function LedgerUI.Toggle()
    if not ST.db then return end
    if not frame then build() end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

function LedgerUI.IsOpen() return frame ~= nil and frame:IsShown() end

ST.ToggleLedger = LedgerUI.Toggle

ST:AddSlashCommand("hud", function() ST.Toggle() end, "show/hide the small session window")
ST:AddSlashCommand("history", function() LedgerUI.Show("History") end, "open the History tab")
ST:AddSlashCommand("lifetime", function() LedgerUI.Show("Lifetime") end, "open the Lifetime tab")

ST:OnSettingChanged(function(key)
    if not frame then return end
    if key == "scale" then frame:SetScale(ST.db.settings.scale or 1) end
    updateTabs()
    LedgerUI.Refresh()
end)

ST:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    -- Comes back after a /reload if it was open.
    if ST.db.ledgerWindow.shown then
        if not frame then build() end
        if not frame:IsShown() then frame:Show() end
    end
end)

function LedgerUI.ResetPosition()
    ST.db.ledgerWindow.left, ST.db.ledgerWindow.top = nil, nil
    if frame then restorePosition() end
end

-- ---------------------------------------------------------------------------
-- Run summary: shown when an instance run ends
-- ---------------------------------------------------------------------------

local popup

local function buildPopup()
    popup = CreateFrame("Frame", "AllemanoLedgerRunSummary", UIParent)
    popup:SetFrameStrata("DIALOG")
    popup:SetClampedToScreen(true)
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:SetSize(380, 372)
    popup.bg = W.Fill(popup, "window", 1)
    popup.bg:SetAllPoints()
    W.Panel(popup, popup.bg, W.Border(popup, "line"))
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", function() popup:StartMoving() end)
    popup:SetScript("OnDragStop", function() popup:StopMovingOrSizing() end)

    local logo = popup:CreateTexture(nil, "ARTWORK")
    logo:SetSize(20, 20)
    logo:SetPoint("TOPLEFT", PAD, -14)
    logo:SetTexture(ST.LOGO)
    local head = W.Text(popup, 2, "text")
    head:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    head:SetText("Run summary")
    popup.tag = W.Text(popup, -1, "text")
    popup.tag:SetPoint("LEFT", head, "RIGHT", 10, 0)
    popup.zone = W.Text(popup, 6, "text")
    popup.zone:SetPoint("TOPLEFT", PAD, -52)
    popup.sub = W.Text(popup, -1, "textDim")
    popup.sub:SetPoint("TOPLEFT", PAD, -78)

    local list = card(popup, 380 - 2 * PAD, 5 * 30 + 6)
    list:SetPoint("TOPLEFT", PAD, -100)
    popup.rows = {}
    for i = 1, 5 do
        local name = label(list, 0, "text")
        name:SetPoint("TOPLEFT", 14, -10 - (i - 1) * 30)
        local value = label(list, 0, "text", "RIGHT")
        value:SetPoint("TOPRIGHT", -14, -10 - (i - 1) * 30)
        popup.rows[i] = { name, value }
        if i < 5 then
            local sep = W.Line(list, "top", "line")
            sep:ClearAllPoints()
            sep:SetPoint("TOPLEFT", 1, -9 - i * 30 + 6)
            sep:SetPoint("TOPRIGHT", -1, -9 - i * 30 + 6)
        end
    end
    popup.perHour = statCard(popup, 170)
    popup.perHour:SetPoint("TOPLEFT", PAD, -100 - 5 * 30 - 6 - GAP)
    popup.withLoot = statCard(popup, 170)
    popup.withLoot:SetPoint("TOPRIGHT", -PAD, -100 - 5 * 30 - 6 - GAP)
    local discard = button(popup, "Discard", function()
        Ledger.DiscardRun()
        popup:Hide()
    end)
    discard:SetPoint("BOTTOMLEFT", PAD, PAD)
    local save = button(popup, "Save to history", function()
        Ledger.SaveRun()
        popup:Hide()
        LedgerUI.Refresh()
    end, "primary")
    save:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    popup:SetScale(ST.db.settings.scale or 1)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    popup:Hide()
end

local function showRun(run, c)
    if not popup then buildPopup() end
    local net = Session.Sum(run.inc) - Session.Sum(run.exp)
    popup.tag:SetText(run.tag:upper())
    popup.tag:SetTextColor(hexRGB(TAG_COLOR[run.tag] or TAG_COLOR.Other))
    popup.zone:SetText(run.zone or "?")
    popup.sub:SetText(("%s - %s - %s"):format(c and c.name or "?", Fmt.clock(run.duration or 0), "left the instance"))
    local rows = {
        { "Loot coins", "+" .. Fmt.money(run.inc.loot or 0), "good" },
        { "Vendor sales", "+" .. Fmt.money(run.inc.vendor or 0), "good" },
        { "Quest rewards", "+" .. Fmt.money(run.inc.quest or 0), "good" },
        { "Repairs", "-" .. Fmt.money(run.exp.repair or 0), "warn" },
        { "Purchases", "-" .. Fmt.money((run.exp.vendor or 0) + (run.exp.other or 0)), "warn" },
    }
    for i, r in ipairs(rows) do
        popup.rows[i][1]:SetText(r[1])
        popup.rows[i][2]:SetText(r[2])
        popup.rows[i][2]:SetTextColor(Theme:Color(r[3]))
    end
    local hours = math.max(60, run.duration or 0) / 3600
    popup.perHour:Set("Gold / hour", (net < 0 and "-" or "") .. Fmt.money(net / hours), "net", "text")
    popup.perHour.value:SetTextColor(Theme:Accent())
    local withLoot = net + (run.loot or 0)
    popup.withLoot:Set("Incl. unsold loot", (withLoot < 0 and "-" or "+") .. Fmt.money(withLoot),
        ("loot worth %s"):format(Fmt.money(run.loot or 0)), withLoot >= 0 and "good" or "warn")
    popup:SetScale(ST.db.settings.scale or 1)
    popup:Show()
end

Ledger.RunFinished = function(run, c) ST:Call("run summary", showRun, run, c) end
function LedgerUI.PopupShown() return popup ~= nil and popup:IsShown() end
