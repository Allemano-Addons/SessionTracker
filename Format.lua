-- Format: gold, time and number text shared by the windows.
local _, ST = ...

local Fmt = {}
ST.Fmt = Fmt

function Fmt.num(n) return BreakUpLargeNumbers and BreakUpLargeNumbers(floor(n + 0.5)) or tostring(floor(n + 0.5)) end

-- Copper as plain text: "84g 20s", "45s", "3c". No sign, no colors (the caller colors the line).
function Fmt.money(copper)
    copper = floor(math.abs(copper) + 0.5)
    local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
    if g > 0 then return ("%sg %02ds"):format(Fmt.num(g), s) end
    if s > 0 then return c > 0 and ("%ds %02dc"):format(s, c) or (s .. "s") end
    return c .. "c"
end

function Fmt.signed(copper)
    if copper == 0 then return "0g" end
    return (copper > 0 and "+" or "-") .. Fmt.money(copper)
end

-- Whole gold only, for big numbers on charts and totals: "2 140g".
function Fmt.gold(copper)
    if math.abs(copper) < 1000000 then return Fmt.money(copper) end -- under 100g the silver matters
    return Fmt.num(copper / 10000) .. "g"
end

-- Seconds as "1:42:18" (clock) or "1h 42m" (words).
function Fmt.clock(sec)
    sec = floor(sec)
    local h, m, s = floor(sec / 3600), floor(sec / 60) % 60, sec % 60
    if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
    return ("%d:%02d"):format(m, s)
end

function Fmt.duration(sec)
    sec = floor(sec)
    local d, h, m = floor(sec / 86400), floor(sec / 3600) % 24, floor(sec / 60) % 60
    if d > 0 then return ("%dd %dh"):format(d, h) end
    if h > 0 then return ("%dh %02dm"):format(h, m) end
    if m > 0 then return ("%dm %02ds"):format(m, sec % 60) end
    return sec .. "s"
end

-- "|cffRRGGBB" for a Theme color or a raw r, g, b.
function Fmt.code(r, g, b)
    return ("|cff%02x%02x%02x"):format(floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

function Fmt.color(text, r, g, b) return Fmt.code(r, g, b) .. text .. "|r" end
