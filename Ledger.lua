-- Ledger: where the gold came from and where it went, per session, per day and per
-- instance run. The game only says "your money changed" (PLAYER_MONEY), so the source is
-- worked out from what was going on: a vendor, the mail box, a trade, a quest turn-in, a
-- loot window... Whatever fits none of them is "other".
--
-- Gold moved between the player's own characters (mail or trade to a character this
-- addon has seen) is a transfer: it is counted separately and is neither income nor expense.
--
-- AllemanoLedgerDB.chars[guid].days["YYYY-MM-DD"] = {
--     inc = { source = copper }, exp = { source = copper },
--     xferIn, xferOut, xp, time (seconds online), loot (vendor value of looted items),
--     gold (copper held at the last note that day)
-- }
-- chars[guid].run = the instance run in progress; chars[guid].pendingRun = a finished run
-- waiting for "Save to history" / "Discard".
local _, ST = ...

local Session = ST.Session

local Ledger = {}
ST.Ledger = Ledger

local sum = Session.Sum

-- Sources in display order.
Ledger.IN = { "loot", "vendor", "quest", "ah", "mail", "trade", "other" }
Ledger.OUT = { "repair", "vendor", "training", "travel", "ah", "mail", "trade", "other" }
Ledger.LABEL_IN = {
    loot = "Loot coins", vendor = "Vendor sales", quest = "Quest rewards", ah = "Auction house",
    mail = "Mail", trade = "Trades", other = "Other",
}
Ledger.LABEL_OUT = {
    repair = "Repairs", vendor = "Vendor purchases", training = "Training", travel = "Flights",
    ah = "Auction house", mail = "Mail and postage", trade = "Trades", other = "Other",
}

local DAYS_KEPT = 800
local RUN_MIN = 120 -- shorter instance visits are not worth a summary
local RUN_TAG = { party = "Dungeon", raid = "Raid", pvp = "PvP", arena = "PvP" }

local function char()
    local guid = UnitGUID("player")
    local c = guid and ST.db and ST.db.chars[guid]
    if c then c.days = c.days or {} end
    return c
end

function Ledger.DayKey(t) return date("%Y-%m-%d", t or time()) end

local function today(c)
    local key = Ledger.DayKey()
    local d = c.days[key]
    if not d then
        d = { inc = {}, exp = {}, xp = 0, time = 0, xferIn = 0, xferOut = 0, loot = 0 }
        c.days[key] = d
        -- Forget very old days (a handful of numbers each; this keeps the file bounded).
        local n = 0
        for _ in pairs(c.days) do n = n + 1 end
        if n > DAYS_KEPT then
            local keys = {}
            for k in pairs(c.days) do keys[#keys + 1] = k end
            sort(keys)
            for i = 1, n - DAYS_KEPT do c.days[keys[i]] = nil end
        end
    end
    return d
end

-- ---------------------------------------------------------------------------
-- State of the game around the player (not saved)
-- ---------------------------------------------------------------------------

local ctx = {
    open = {},        -- merchant, mail, trade, ah, trainer, taxi: window is up
    grace = {},       -- for mail/trade/taxi/ah the money can move just after the window closed
    mailTakes = {},   -- { money, alt, invoice, t } from TakeInboxMoney
    slots = {},       -- loot window slots: { link, qty }
}

local function active(name)
    return ctx.open[name] or (ctx.grace[name] or 0) >= time()
end

local function setOpen(name, value, grace)
    ctx.open[name] = value or nil
    if not value and grace then ctx.grace[name] = time() + grace end
end

-- Is this the name of one of the player's own characters (seen by this addon)?
function Ledger.IsOwnCharacter(name)
    if type(name) ~= "string" or name == "" or not ST.db then return false end
    name = name:match("^[^-]+") or name
    for _, c in pairs(ST.db.chars) do
        if c.name and (c.name == name or (c.name:match("^%S+") == name)) then return true end
    end
    return false
end

-- Thin a series that has grown long (keeps the first and last point).
local function thin(series, max)
    if #series <= max then return end
    local out = {}
    for i = 1, #series do
        if i == 1 or i == #series or i % 2 == 1 then out[#out + 1] = series[i] end
    end
    for i = 1, #series do series[i] = out[i] end
end

local function addPoint(s)
    local ser = s.series
    ser[#ser + 1] = { Session.Elapsed(s), sum(s.inc) - sum(s.exp) }
    if #ser > 240 then thin(ser, 240) end
end

local function bump(t, key, n) t[key] = (t[key] or 0) + n end

-- ---------------------------------------------------------------------------
-- Recording
-- ---------------------------------------------------------------------------

-- kind: "in" / "out" (source = a key of IN / OUT) or "xfer" (source = "in" / "out").
function Ledger.Record(kind, source, amount)
    if not amount or amount <= 0 then return end
    local c = char()
    if not c then return end
    local d = today(c)
    local s = Session.Current()
    local live = s and not s.paused
    if kind == "xfer" then
        bump(d, source == "in" and "xferIn" or "xferOut", amount)
        if live then s.xfer = (s.xfer or 0) + amount end
        return
    end
    bump(kind == "in" and d.inc or d.exp, source, amount)
    if not ctx.loggingOut then
        local money = GetMoney()
        if money then d.gold = money end
    end
    if live then
        bump(kind == "in" and s.inc or s.exp, source, amount)
        if kind == "in" then
            s.zone = (GetRealZoneText and GetRealZoneText()) or s.zone
            s.autoTag = Session.AutoTag()
        end
        addPoint(s)
        s.lastSeen = time()
    end
    local run = c.run
    if run then
        bump(kind == "in" and run.inc or run.exp, source, amount)
        run.last = time()
    end
end

-- Experience: how much of it was a quest turn-in. QUEST_TURNED_IN names the quest XP, and it may
-- come just before or just after the XP bar moves, so both orders are handled.
local function addQuestXP(n, c)
    local d = today(c)
    d.xpQuest = (d.xpQuest or 0) + n
    local s = Session.Current()
    if s and not s.paused then s.xpQuest = (s.xpQuest or 0) + n end
end

function Ledger.AddXP(gain, c)
    c = c or char()
    if not c or not gain or gain <= 0 then return end
    c.days = c.days or {}
    local d = today(c)
    d.xp = (d.xp or 0) + gain
    if c.run then c.run.xp = (c.run.xp or 0) + gain end
    local now = time()
    if ctx.questXP and ctx.questXPUntil >= now then
        local part = math.min(gain, ctx.questXP)
        ctx.questXP = nil
        addQuestXP(part, c)
        gain = gain - part
    end
    ctx.lastXP = gain > 0 and { gain = gain, t = now } or nil
end

ST:RegisterEvent("QUEST_TURNED_IN", function(_, _, xp)
    xp = tonumber(xp)
    if not xp or xp <= 0 then return end
    local c, now = char(), time()
    local last = ctx.lastXP
    if c and last and now - last.t <= 3 then
        local part = math.min(last.gain, xp)
        ctx.lastXP = nil
        addQuestXP(part, c)
    else
        ctx.questXP, ctx.questXPUntil = xp, now + 3
    end
end)

-- Items looted from the loot window: counted by quality, valued at the vendor price.
local function addItem(link, qty, quality, value)
    local c = char()
    if not c then return end
    quality = tonumber(quality) or 1
    local d = today(c)
    d.items = d.items or {}
    bump(d.items, quality, qty)
    d.loot = (d.loot or 0) + value
    local s = Session.Current()
    if s and not s.paused then
        s.lootValue = (s.lootValue or 0) + value
        s.items = (s.items or 0) + qty
        bump(s.qItems, quality, qty)
    end
    if c.run then c.run.loot = (c.run.loot or 0) + value end
    if quality >= 3 then
        c.notable = c.notable or {}
        tinsert(c.notable, 1, { link = link, t = time(), q = quality, qty = qty })
        while #c.notable > 30 do tremove(c.notable) end
    end
end

-- Deaths. (Kills: see below, they come from the XP chat line; the combat log cannot be used,
-- registering COMBAT_LOG_EVENT_UNFILTERED is forbidden for addons on this client.)
ST:RegisterEvent("PLAYER_DEAD", function()
    local c = char()
    if not c then return end
    local d = today(c)
    d.deaths = (d.deaths or 0) + 1
    local s = Session.Current()
    if s and not s.paused then s.deaths = (s.deaths or 0) + 1 end
end)

-- Reputation: the chat line "Your reputation with X has increased by N." (taken from the
-- game's own text, so it works in any language).
local function patternOf(format)
    if type(format) ~= "string" then return nil end
    local p = format:gsub("[%-%.%+%[%]%(%)%^%*%?]", "%%%0")
    p = p:gsub("%%%d%$s", "(.+)"):gsub("%%s", "(.+)"):gsub("%%%d%$d", "(%%d+)"):gsub("%%d", "(%%d+)")
    return "^" .. p .. "$"
end

-- Kills: "X dies, you gain N experience." only appears for kills that give XP (not grey mobs,
-- not at max level), so that is what is counted.
local killPattern
ST:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    if killPattern == nil then
        local p = patternOf(type(COMBATLOG_XPGAIN_FIRSTPERSON) == "string" and COMBATLOG_XPGAIN_FIRSTPERSON:gsub("%.$", "") or nil)
        killPattern = p and p:gsub("%$$", "") or false
    end
end)
ST:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN", function(_, msg)
    if not killPattern or type(msg) ~= "string" or not msg:match(killPattern) then return end
    local c = char()
    if not c then return end
    local d = today(c)
    d.kills = (d.kills or 0) + 1
    local s = Session.Current()
    if s and not s.paused then s.kills = (s.kills or 0) + 1 end
end)

local repUp, repDown
ST:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    if repUp == nil then
        repUp = patternOf(FACTION_STANDING_INCREASED) or false
        repDown = patternOf(FACTION_STANDING_DECREASED) or false
    end
end)

local function addRep(faction, n)
    local c = char()
    if not c or not faction or n == 0 then return end
    local d = today(c)
    d.rep = d.rep or {}
    bump(d.rep, faction, n)
    local s = Session.Current()
    if s and not s.paused then bump(s.rep, faction, n) end
end

ST:RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE", function(_, msg)
    if type(msg) ~= "string" then return end
    local faction, n
    if repUp then faction, n = msg:match(repUp) end
    if faction and tonumber(n) then return addRep(faction, tonumber(n)) end
    if repDown then faction, n = msg:match(repDown) end
    if faction and tonumber(n) then addRep(faction, -tonumber(n)) end
end)

-- ---------------------------------------------------------------------------
-- Working out the source of a change in money
-- ---------------------------------------------------------------------------

local function classifyIn(amount)
    local now = time()
    -- Money taken from the mail box (the hook noted what the letter held).
    for i = #ctx.mailTakes, 1, -1 do
        local m = ctx.mailTakes[i]
        if now - m.t > 10 then
            tremove(ctx.mailTakes, i)
        elseif m.money == amount then
            tremove(ctx.mailTakes, i)
            if m.alt then return Ledger.Record("xfer", "in", amount) end
            return Ledger.Record("in", m.invoice and "ah" or "mail", amount)
        end
    end
    if ctx.questMoney and ctx.questUntil >= now and amount == ctx.questMoney then
        ctx.questMoney = nil
        return Ledger.Record("in", "quest", amount)
    end
    if active("merchant") then return Ledger.Record("in", "vendor", amount) end
    if active("trade") then
        if Ledger.IsOwnCharacter(ctx.tradePartner) then return Ledger.Record("xfer", "in", amount) end
        return Ledger.Record("in", "trade", amount)
    end
    if active("ah") then return Ledger.Record("in", "ah", amount) end
    if active("mail") then return Ledger.Record("in", "mail", amount) end
    if ctx.open.loot or (ctx.lootUntil or 0) >= now then return Ledger.Record("in", "loot", amount) end
    return Ledger.Record("in", "other", amount)
end

local function classifyOut(amount)
    local now = time()
    if active("merchant") then
        local repairing = (ctx.repairUntil or 0) >= now
            or (InRepairMode and InRepairMode())
            or (ctx.repairAll and ctx.repairAll > 0 and amount == ctx.repairAll)
        if repairing then
            ctx.repairAll = nil
            return Ledger.Record("out", "repair", amount)
        end
        return Ledger.Record("out", "vendor", amount)
    end
    if active("trade") then
        if Ledger.IsOwnCharacter(ctx.tradePartner) then return Ledger.Record("xfer", "out", amount) end
        return Ledger.Record("out", "trade", amount)
    end
    if active("mail") then
        local send = ctx.send
        if send and now - send.t <= 10 then
            ctx.send = nil
            local moved = Ledger.IsOwnCharacter(send.to) and math.min(send.money or 0, amount) or 0
            if moved > 0 then Ledger.Record("xfer", "out", moved) end
            return Ledger.Record("out", "mail", amount - moved)
        end
        return Ledger.Record("out", "mail", amount)
    end
    if active("ah") then return Ledger.Record("out", "ah", amount) end
    if active("trainer") then return Ledger.Record("out", "training", amount) end
    if active("taxi") then return Ledger.Record("out", "travel", amount) end
    return Ledger.Record("out", "other", amount)
end

ST:RegisterEvent("PLAYER_MONEY", function()
    if ctx.loggingOut then return end
    local new = GetMoney()
    if not new then return end
    local last = ctx.lastMoney
    ctx.lastMoney = new
    if last == nil then return end
    if new > last then classifyIn(new - last) elseif new < last then classifyOut(last - new) end
end)

ST:RegisterEvent("PLAYER_LOGOUT", function() ctx.loggingOut = true end)

-- Windows that tell where money moves.
local WINDOWS = {
    { "MERCHANT_SHOW", "MERCHANT_CLOSED", "merchant" },
    { "MAIL_SHOW", "MAIL_CLOSED", "mail", 3 },
    { "TRADE_SHOW", "TRADE_CLOSED", "trade", 3 },
    { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "ah", 3 },
    { "TRAINER_SHOW", "TRAINER_CLOSED", "trainer" },
    { "TAXIMAP_OPENED", "TAXIMAP_CLOSED", "taxi", 3 },
}
for _, w in ipairs(WINDOWS) do
    local name, grace = w[3], w[4]
    ST:RegisterEvent(w[1], function()
        setOpen(name, true)
        if name == "trade" then ctx.tradePartner = UnitName and UnitName("NPC") or nil end
        if name == "merchant" then
            ctx.repairAll = (CanMerchantRepair and CanMerchantRepair() and GetRepairAllCost and GetRepairAllCost()) or 0
        end
    end)
    ST:RegisterEvent(w[2], function() setOpen(name, false, grace) end)
end

-- The cost of "Repair all" is read while the vendor is open; a later reading of 0 (after
-- repairing) must not wipe it before the money event has been understood.
local function readRepairCost()
    if not ctx.open.merchant or not (CanMerchantRepair and CanMerchantRepair() and GetRepairAllCost) then return end
    local cost = GetRepairAllCost()
    if cost and cost > 0 then ctx.repairAll = cost end
end
ST:RegisterEvent("MERCHANT_UPDATE", readRepairCost)
ST:RegisterEvent("UPDATE_INVENTORY_DURABILITY", readRepairCost)

-- Quest rewards.
ST:RegisterEvent("QUEST_COMPLETE", function()
    local reward = GetRewardMoney and GetRewardMoney() or 0
    if reward > 0 then ctx.questMoney, ctx.questUntil = reward, time() + 120 end
end)
ST:RegisterEvent("QUEST_TURNED_IN", function(_, _, _, money)
    if tonumber(money) and money > 0 then ctx.questMoney, ctx.questUntil = money, time() + 10 end
end)

-- Loot: coins show up as money while the loot window is up (or just after, auto loot).
ST:RegisterEvent("LOOT_OPENED", function()
    ctx.open.loot = true
    wipe(ctx.slots)
    for i = 1, (GetNumLootItems and GetNumLootItems() or 0) do
        if LootSlotHasItem and LootSlotHasItem(i) then
            local link = GetLootSlotLink and GetLootSlotLink(i)
            local _, _, qty, rarity = GetLootSlotInfo(i)
            if link then ctx.slots[i] = { link = link, qty = tonumber(qty) or 1, rarity = tonumber(rarity) } end
        end
    end
end)
ST:RegisterEvent("LOOT_CLOSED", function()
    ctx.open.loot = nil
    ctx.lootUntil = time() + 2
    wipe(ctx.slots)
end)
ST:RegisterEvent("CHAT_MSG_MONEY", function() ctx.lootUntil = time() + 2 end)
ST:RegisterEvent("LOOT_SLOT_CLEARED", function(_, slot)
    local e = ctx.slots[slot]
    if not e then return end
    ctx.slots[slot] = nil
    local _, _, quality, _, _, _, _, _, _, _, price = GetItemInfo(e.link)
    quality = tonumber(quality) or (e.rarity and e.rarity >= 0 and e.rarity <= 6 and e.rarity) or 1
    addItem(e.link, e.qty, quality, (tonumber(price) or 0) * e.qty)
end)

-- Mail: note what a letter holds before the money is taken (the money event comes later).
local function noteMail(index)
    if not GetInboxHeaderInfo then return end
    local _, _, sender, _, money = GetInboxHeaderInfo(index)
    if not tonumber(money) or money <= 0 then return end
    local invoice = GetInboxInvoiceInfo and GetInboxInvoiceInfo(index)
    local list = ctx.mailTakes
    list[#list + 1] = {
        money = money, t = time(), invoice = invoice == "seller",
        alt = Ledger.IsOwnCharacter(sender),
    }
end

local function install()
    if not hooksecurefunc then return end
    local function hook(name, fn)
        if type(_G[name]) == "function" then
            local ok, err = pcall(hooksecurefunc, name, function(...)
                local fine, e = pcall(fn, ...)
                if not fine then ST:RecordError("hook " .. name, e) end
            end)
            if not ok then ST:RecordError("hook " .. name, err) end
        end
    end
    hook("TakeInboxMoney", noteMail)
    hook("AutoLootMailItem", noteMail)
    hook("RepairAllItems", function() ctx.repairUntil = time() + 5 end)
    hook("SendMail", function(to)
        ctx.send = { to = to, money = ctx.sendMoney or (GetSendMailMoney and GetSendMailMoney()) or 0, t = time() }
    end)
end
ST:RegisterEvent("ADDON_LOADED", function(_, name)
    if name == ST.name then install() end
end)
-- The amount typed into the money boxes of the send-mail tab (it is cleared when sending).
ST:RegisterEvent("MAIL_SEND_INFO_UPDATE", function()
    ctx.sendMoney = GetSendMailMoney and GetSendMailMoney() or 0
end)
ST:RegisterEvent("MAIL_SEND_SUCCESS", function() ctx.sendMoney = nil end)

-- ---------------------------------------------------------------------------
-- Time online per day, and the gold held at the end of each day
-- ---------------------------------------------------------------------------

function Ledger.Heartbeat()
    local c = char()
    if not c then return end
    local now = time()
    local dt = ctx.lastBeat and (now - ctx.lastBeat) or 0
    ctx.lastBeat = now
    local d = today(c)
    if dt > 0 and dt <= 60 then d.time = (d.time or 0) + dt end
    if not ctx.loggingOut then
        local money = GetMoney()
        if money and money > 0 then d.gold = money end
    end
    if c.run then c.run.last = now end
end

-- ---------------------------------------------------------------------------
-- Instance runs
-- ---------------------------------------------------------------------------

-- Fires when a run has ended and is waiting for the player (the window shows the summary).
function Ledger.RunFinished() end

function Ledger.FinishRun(c)
    local run = c.run
    c.run = nil
    if not run then return end
    run.stop = run.last or time()
    run.duration = run.stop - run.start
    if run.duration < RUN_MIN then return end
    c.pendingRun = run
    Ledger.RunFinished(run, c)
end

function Ledger.CheckRun()
    local c = char()
    if not c or not IsInInstance then return end
    local inInstance, kind = IsInInstance()
    local zone = GetRealZoneText and GetRealZoneText() or ""
    if inInstance and RUN_TAG[kind] then
        if zone == "" then return end -- loading screen
        if c.run and c.run.zone ~= zone then Ledger.FinishRun(c) end
        if not c.run then
            c.run = { zone = zone, tag = RUN_TAG[kind], start = time(), last = time(), inc = {}, exp = {}, loot = 0, xp = 0 }
        end
    elseif c.run then
        Ledger.FinishRun(c)
    end
end

-- "Save to history": the run becomes an entry next to the sessions.
function Ledger.SaveRun(c)
    c = c or char()
    local run = c and c.pendingRun
    if not run then return end
    c.pendingRun = nil
    c.history = c.history or {}
    tinsert(c.history, 1, {
        kind = "run", start = run.start, stop = run.stop, duration = run.duration,
        inc = run.inc, exp = run.exp, net = sum(run.inc) - sum(run.exp),
        money = sum(run.inc) - sum(run.exp),
        lootValue = run.loot, xpGained = run.xp, levels = 0, tag = run.tag, zone = run.zone,
    })
    sort(c.history, function(a, b) return (a.start or 0) > (b.start or 0) end)
    while #c.history > 50 do tremove(c.history) end
end

function Ledger.DiscardRun(c)
    c = c or char()
    if c then c.pendingRun = nil end
end

function Ledger.PendingRun()
    local c = char()
    return c and c.pendingRun, c
end

ST:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    ctx.loggingOut = nil
    ctx.lastMoney = GetMoney()
    ctx.lastBeat = time()
    -- Windows do not survive a loading screen.
    wipe(ctx.open)
    Ledger.CheckRun()
    Ledger.Heartbeat()
    if not ctx.ticker and C_Timer and C_Timer.NewTicker then
        ctx.ticker = C_Timer.NewTicker(15, function() ST:Call("heartbeat", Ledger.Heartbeat) end)
    end
    local _, c = Ledger.PendingRun()
    if c and c.pendingRun then Ledger.RunFinished(c.pendingRun, c) end
end)
ST:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() Ledger.CheckRun() end)

-- ---------------------------------------------------------------------------
-- Reading (for the windows)
-- ---------------------------------------------------------------------------

-- Day keys from today backwards: { "2026-10-02", "2026-10-01", ... }. Noon-anchored so a
-- daylight-saving change never repeats or skips a day.
function Ledger.RecentDays(count)
    local now = time()
    local t = date("*t", now)
    local noon = now - (t.hour * 3600 + t.min * 60 + t.sec) + 43200
    local out = {}
    for i = 0, count - 1 do out[#out + 1] = Ledger.DayKey(noon - i * 86400) end
    return out
end

-- The sum over all characters of one day: { inc = {}, exp = {}, xp, time, loot }.
local function newTotals()
    return { inc = {}, exp = {}, xp = 0, xpQuest = 0, time = 0, loot = 0, xferIn = 0, xferOut = 0,
        kills = 0, deaths = 0, items = {}, rep = {} }
end

local function addDay(out, d)
    for k, v in pairs(d.inc or {}) do bump(out.inc, k, v) end
    for k, v in pairs(d.exp or {}) do bump(out.exp, k, v) end
    for k, v in pairs(d.items or {}) do bump(out.items, k, v) end
    for k, v in pairs(d.rep or {}) do bump(out.rep, k, v) end
    for _, field in ipairs({ "xp", "xpQuest", "time", "loot", "xferIn", "xferOut", "kills", "deaths" }) do
        out[field] = out[field] + (d[field] or 0)
    end
end

function Ledger.Day(key)
    local out = newTotals()
    if not ST.db then return out end
    for _, c in pairs(ST.db.chars) do
        local d = c.days and c.days[key]
        if d then addDay(out, d) end
    end
    return out
end

-- XP, kills, loot and reputation over a period, in one shape: "session", "today", "week" or "all".
-- { xp, xpQuest, kills, deaths, items = { [quality] = n }, itemCount, loot (vendor value), rep = { faction = n }, time }
function Ledger.Period(period)
    local out
    if period == "session" then
        local s = Session.Stats()
        out = newTotals()
        if s then
            out.xp, out.xpQuest, out.kills, out.deaths = s.xpGained, s.xpQuest, s.kills, s.deaths
            out.items, out.rep, out.loot, out.time = s.items, s.rep, s.lootValue, s.elapsed
            out.inc = s.inc
        end
    elseif period == "all" then
        out = Ledger.Lifetime()
    else
        out = newTotals()
        for _, key in ipairs(Ledger.RecentDays(period == "week" and 7 or 1)) do
            local day = Ledger.Day(key)
            for k, v in pairs(day.items) do bump(out.items, k, v) end
            for k, v in pairs(day.rep) do bump(out.rep, k, v) end
            for k, v in pairs(day.inc) do bump(out.inc, k, v) end
            for _, field in ipairs({ "xp", "xpQuest", "time", "loot", "kills", "deaths" }) do out[field] = out[field] + day[field] end
        end
    end
    out.itemCount = 0
    for _, n in pairs(out.items) do out.itemCount = out.itemCount + n end
    return out
end

-- Rare and better drops of this character, newest first.
function Ledger.Notable()
    local c = char()
    return c and c.notable or {}
end

-- Everything since the beginning: { inc = {}, exp = {}, firstDay, xferIn, xferOut }.
function Ledger.Lifetime()
    local out = newTotals()
    if not ST.db then return out end
    for _, c in pairs(ST.db.chars) do
        for key, d in pairs(c.days or {}) do
            if not out.firstDay or key < out.firstDay then out.firstDay = key end
            addDay(out, d)
        end
    end
    return out
end

-- Gold held by all characters together at the end of each day, oldest first:
-- { { key, copper }, ... }. A day without a note carries the earlier value forward.
function Ledger.GoldOverTime(maxDays)
    local keys, perChar = {}, {}
    local seen = {}
    for guid, c in pairs(ST.db and ST.db.chars or {}) do
        for key, d in pairs(c.days or {}) do
            if d.gold then
                perChar[guid] = perChar[guid] or {}
                perChar[guid][key] = d.gold
                if not seen[key] then seen[key] = true; keys[#keys + 1] = key end
            end
        end
    end
    sort(keys)
    if maxDays and #keys > maxDays then
        local cut = {}
        for i = #keys - maxDays + 1, #keys do cut[#cut + 1] = keys[i] end
        keys = cut
    end
    local last, out = {}, {}
    -- Start from what each character held before the first listed day.
    for guid, days in pairs(perChar) do
        local best
        for key, gold in pairs(days) do
            if key < (keys[1] or "") and (not best or key > best) then best = key; last[guid] = gold end
        end
    end
    for _, key in ipairs(keys) do
        local total = 0
        for guid, days in pairs(perChar) do
            if days[key] then last[guid] = days[key] end
            total = total + (last[guid] or 0)
        end
        out[#out + 1] = { key, total }
    end
    return out
end

-- Every saved session and run of every character, newest first:
-- { entry..., name, class }.
function Ledger.AllHistory()
    local out = {}
    for _, c in pairs(ST.db and ST.db.chars or {}) do
        for _, h in ipairs(c.history or {}) do
            out[#out + 1] = { e = h, name = c.name, class = c.class }
        end
    end
    sort(out, function(a, b) return (a.e.start or 0) > (b.e.start or 0) end)
    return out
end
