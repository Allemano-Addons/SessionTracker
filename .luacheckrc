std = "lua51"
max_line_length = false
self = false
exclude_files = { "Tests/**" }

-- The only globals AllemanoLedger may write.
globals = {
    "AllemanoLedgerDB", "AllemanoLedgerFrame", "AllemanoLedgerWindow", "AllemanoLedgerRunSummary",
    "AllemanoLedgerLevelsFrame", "AllemanoLedgerSettingsFrame",
    "SLASH_SESSIONTRACKER1", "SLASH_SESSIONTRACKER2", "SLASH_ALLEMANOLEDGER1", "SlashCmdList",
}

-- WoW API used (read-only). Extend as new APIs are used.
read_globals = {
    "_G", "strjoin", "strsplit", "strtrim", "strlower", "strupper", "tostringall", "tinsert", "tremove",
    "wipe", "sort", "floor", "ceil", "min", "max", "abs", "format", "date", "time", "CopyTable", "geterrorhandler",
    "CreateFrame", "UIParent", "DEFAULT_CHAT_FRAME", "UISpecialFrames", "GetCursorPosition", "IsShiftKeyDown",
    "GetAddOnMetadata", "C_AddOns", "C_Timer", "LibStub", "HushDB", "BreakUpLargeNumbers",
    "CUSTOM_CLASS_COLORS", "RAID_CLASS_COLORS", "GetPhysicalScreenSize",
    "UnitGUID", "UnitName", "UnitClass", "UnitLevel", "UnitXP", "UnitXPMax", "GetMoney", "GetMaxPlayerLevel",
    "RequestTimePlayed", "ChatFrameUtil", "GetRealZoneText",
    -- Ledger: where money comes from and goes
    "SessionTrackerDB", "IsInInstance", "CanMerchantRepair", "GetRepairAllCost", "InRepairMode",
    "GetRewardMoney", "GetNumLootItems", "LootSlotHasItem", "GetLootSlotLink", "GetLootSlotInfo", "GetItemInfo", "C_Item", "issecretvalue",
    "GetInboxHeaderInfo", "GetInboxInvoiceInfo", "GetSendMailMoney", "hooksecurefunc",
    "COMBATLOG_XPGAIN_FIRSTPERSON", "FACTION_STANDING_INCREASED", "FACTION_STANDING_DECREASED", "GetXPExhaustion", "GameTooltip",
}
