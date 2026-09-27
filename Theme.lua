-- Theme (same as AltBoard's): colors, sizes and fonts. Hush's original palette; font, text
-- size and accent come from the settings (the accent can follow Hush, read only).
local _, ST = ...

local Theme = {}
ST.Theme = Theme

local function hex(s)
    return tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255
end
Theme.Hex = hex

Theme.colors = {
    window    = { hex("111418") },
    sidebar   = { hex("0D1013") },
    field     = { hex("15191E") },
    selected  = { hex("1A1F26") },
    line      = { hex("22272E") },
    text      = { hex("E6E8EB") },
    textDim   = { hex("9AA3AD") },
    textFaint = { hex("7C858F") },
    good      = { hex("3FC77F") },
    warn      = { hex("E8A33D") },
    gold      = { 1, 0.82, 0 },
    silver    = { hex("C7C7CF") },
    copper    = { hex("C8753C") },
}

Theme.size = {
    titleH = 40,
    rowH = 22,
    barRowH = 30,
    sectionH = 28,
    headerH = 44,
    labelW = 150,
    colW = 128,
    padding = 12,
}

Theme.COLUMN_WIDTHS = { narrow = 108, normal = 128, wide = 152 }
Theme.TEXT_SIZES = { S = 11, M = 12, L = 14 }

-- Accent presets for "custom" (the first is Hush's blue).
Theme.ACCENTS = { "3FC7EB", "7AA2F7", "3FC77F", "E8A33D", "E0564F", "C8332E", "B57EDC", "E6E8EB" }

local function settings() return ST.db and ST.db.settings or {} end

function Theme:Color(key)
    local c = self.colors[key]
    return c[1], c[2], c[3]
end

local function classColor(classFile)
    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local c = classFile and colors and colors[classFile]
    if c then return c.r, c.g, c.b end
end
Theme.ClassColor = classColor

-- Hush's accent if Hush is installed. HushDB is only complete after every addon loaded,
-- so this is only called once the UI is built (never at load).
local function hushAccent()
    local s = type(HushDB) == "table" and type(HushDB.settings) == "table" and HushDB.settings or nil
    if not s then return nil end
    if s.useClassColor then
        local r, g, b = classColor(select(2, UnitClass("player")))
        if r then return r, g, b end
    end
    if type(s.accent) == "string" and #s.accent == 6 then return hex(s.accent) end
end

function Theme.HasHush() return type(HushDB) == "table" end

-- accentMode: "hush" (follow Hush, else default), "class" or "custom".
function Theme:Accent()
    local s = settings()
    if s.accentMode == "class" then
        local r, g, b = classColor(select(2, UnitClass("player")))
        if r then return r, g, b end
    elseif s.accentMode == "custom" then
        return hex(s.accent or "3FC7EB")
    else
        local r, g, b = hushAccent()
        if r then return r, g, b end
    end
    return hex("3FC7EB")
end

function Theme:ColumnWidth()
    return self.COLUMN_WIDTHS[settings().colWidth] or self.COLUMN_WIDTHS.normal
end

-- ---------------------------------------------------------------------------
-- Fonts. Font files in new addon folders are refused on WoW Forever, so the choice is
-- the game's fonts plus any LibSharedMedia fonts other addons registered (EllesmereUI).
-- ---------------------------------------------------------------------------

local FALLBACK = "Fonts\\FRIZQT__.TTF"

local BUILTIN_FONTS = {
    { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { name = "Arial Narrow",  path = "Fonts\\ARIALN.TTF" },
    { name = "Skurri",        path = "Fonts\\skurri.ttf" },
    { name = "Morpheus",      path = "Fonts\\MORPHEUS.ttf" },
}

local function normalizePath(p) return p and strlower((p:gsub("/", "\\"))) or "" end

local probe
local validCache = {}
-- Does this font file load here? (cached per path)
local function valid(path)
    if not path then return false end
    if validCache[path] == nil then
        probe = probe or UIParent:CreateFontString(nil, "BACKGROUND")
        probe:SetFont(FALLBACK, 12, "")
        local ok = probe:SetFont(path, 12, "")
        if ok == nil then ok = normalizePath(probe:GetFont()) == normalizePath(path) end
        validCache[path] = ok and true or false
    end
    return validCache[path]
end

local function lsm() return LibStub and LibStub("LibSharedMedia-3.0", true) end

-- { { name, path }, ... }: game fonts first, then shared fonts by name.
function Theme:AvailableFonts()
    local list, seen = {}, {}
    local function add(name, path)
        local key = normalizePath(path)
        if not seen[key] and valid(path) then
            seen[key] = true
            list[#list + 1] = { name = name, path = path }
        end
    end
    for _, f in ipairs(BUILTIN_FONTS) do add(f.name, f.path) end
    local L = lsm()
    if L then
        local shared = {}
        for name, path in pairs(L:HashTable("font") or {}) do shared[#shared + 1] = { name = name, path = path } end
        sort(shared, function(a, b) return a.name < b.name end)
        for _, f in ipairs(shared) do add(f.name, f.path) end
    end
    return list
end

local function fontPath(name)
    for _, f in ipairs(BUILTIN_FONTS) do if f.name == name then return f.path end end
    local L = lsm()
    return L and L:IsValid("font", name) and L:Fetch("font", name) or nil
end

-- The chosen font's path, or the game font if it is missing/refused (checked per call:
-- shared fonts may register after us).
function Theme:FontPath()
    local p = fontPath(settings().font)
    return p and valid(p) and p or FALLBACK
end

function Theme:TextSize(delta)
    return (self.TEXT_SIZES[settings().textSize] or 12) + (delta or 0)
end

function Theme:SetFont(fs, delta)
    fs:SetFont(self:FontPath(), self:TextSize(delta), "")
    fs:SetShadowOffset(0, 0)
end

-- ---------------------------------------------------------------------------
-- Pixel-perfect sizing
-- ---------------------------------------------------------------------------

function Theme:Pixel(frame)
    local physH = 1080
    if GetPhysicalScreenSize then
        local _, h = GetPhysicalScreenSize()
        if h and h > 0 then physH = h end
    end
    return 768 / physH / (frame or UIParent):GetEffectiveScale()
end

function Theme:Snap(value, frame)
    local px = self:Pixel(frame)
    return floor(value / px + 0.5) * px
end
