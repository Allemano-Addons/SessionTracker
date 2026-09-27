std = "lua51"
max_line_length = false
self = false
exclude_files = { "Tests/**" }

-- The only globals SessionTracker may write.
globals = {
    "SessionTrackerDB", "SessionTrackerFrame", "SessionTrackerLevelsFrame", "SessionTrackerSettingsFrame",
    "SLASH_SESSIONTRACKER1", "SLASH_SESSIONTRACKER2", "SlashCmdList",
}

-- WoW API used (read-only). Extend as new APIs are used.
read_globals = {
    "_G", "strjoin", "strsplit", "strtrim", "strlower", "strupper", "tostringall", "tinsert", "tremove",
    "wipe", "sort", "floor", "ceil", "min", "max", "format", "date", "time", "CopyTable", "geterrorhandler",
    "CreateFrame", "UIParent", "DEFAULT_CHAT_FRAME", "UISpecialFrames", "GetCursorPosition", "IsShiftKeyDown",
    "GetAddOnMetadata", "C_AddOns", "C_Timer", "LibStub", "HushDB", "BreakUpLargeNumbers",
    "CUSTOM_CLASS_COLORS", "RAID_CLASS_COLORS", "GetPhysicalScreenSize",
    "UnitGUID", "UnitName", "UnitClass", "UnitLevel", "UnitXP", "UnitXPMax", "GetMoney", "GetMaxPlayerLevel",
    "RequestTimePlayed", "ChatFrameUtil", "GetRealZoneText",
}
