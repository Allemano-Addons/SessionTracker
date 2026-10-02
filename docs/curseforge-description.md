# Allemano Ledger

**Where did your gold come from, and where did it go?** Allemano Ledger keeps the books for **WoW Forever**: gold by source, XP, kills, reputation and loot, for the session you are playing, for today and for all time. It is the new name and the next big version of Session Tracker.

> **Beta.** Ledger is new and still growing. Everything is saved on your own computer; nothing is sent to anyone.

## What it does

### Now: this session
Open it with `/ledger`.
- **Earned, spent, net and gold per hour** (with XP per hour) for the session.
- **Income by source:** loot coins, vendor sales, quest rewards, auction house, mail and trades.
- **Expenses:** repairs, vendor purchases, training, flights and mail.
- A **graph of your net gold** over the session, the **vendor value of the loot** you picked up, and the total with it.
- **Pause** the session (the clock and the tallies stop), tag it (**Farming, Dungeon, Raid, Leveling, Questing, Professions, PvP** or automatic) and **End session** to save it.

*Example:* You farm for an hour. Ledger shows that vendor sales brought most of it, what the repair bill was, and that your net gold per hour is lower than you thought.

### History
- **Gold earned per day** for 14 days, 30 days or all time, split by source.
- A table of your finished **sessions and instance runs**: date, character, activity, zone, time, net gold and gold per hour.
- When you **leave a dungeon, raid or battleground** a small **run summary** pops up: what the run made, repairs, gold per hour and the value of the loot you did not sell. Save it to the history or discard it.

### Lifetime
Total earned, total spent and net gain across all your characters since you installed the addon, **gold held over time** and **where it all came from**.

### Progress
**XP gained** (and how much came from quests), **XP per hour**, kills, deaths, your **level progress** with the time on this level, time to the next level and rested XP, and **reputation gained** per faction. Switch between this **session, today, 7 days and all time**.

### Loot
**Items looted by quality** (poor to legendary), the vendor value of your loot, loot coins, and a list of your latest **rare and better drops** (hover one for its tooltip). Same period switch as Progress.

### Level times
Press the **Levels** button on the small window (or type `/ledger levels`) to see how long every level took, in the game's /played time.

### The small session window
`/session` (or `/sesh`) still shows or hides the small always-on window with time, gold, gold per hour, XP and a level bar. It has a **Details** button that opens the Ledger window.

## Gold between your own characters
Gold you mail or trade to **a character the addon has seen** is counted as a transfer, not as income or expense. Log in once on each character so the addon knows them.

## Coming
An **Alts** tab with every character side by side, and a **gold goal** ("how long until I can afford the mount?"). Both are marked "Soon" in the window.

## Good to know
- **Standalone.** No other addon is needed. If Hush is installed, Ledger can follow its accent color.
- **Where the gold came from is worked out from what you were doing** (a vendor open, the mail box, a trade, a quest turn-in, a loot window). Anything that fits none of them is shown as "Other".
- **Kills are counted from the XP message**, so only kills that give XP count: not grey mobs and not at max level.
- Your **Session Tracker data moves over by itself** the first time you log in. The old file is left untouched as a backup.
- WoW Forever hides Lua errors, so Ledger records them: `/ledger errors` lists the most recent ones.

## Settings
`/ledger settings`: font, text size, accent color (Ledger amber, follow Hush, your class color or a custom one), background, window scale, which rows the small window shows, the level bar, hide in combat, lock position, and whether a new session starts at every login or only when you press Reset.

## Commands
`/ledger` opens the Ledger window · `/ledger hud` or `/session` shows/hides the small window · `/ledger history` · `/ledger lifetime` · `/ledger levels` · `/ledger reset` starts a new session · `/ledger settings` · `/ledger errors`

## Installing manually (WoW Forever)
Ledger is made for WoW Forever (interface 16001). If the CurseForge app does not install it into the right folder, download the file from the **Files** tab and unzip it so that the folder is `World of Warcraft\_classic_beta_\Interface\AddOns\AllemanoLedger` (the folder must be called AllemanoLedger), then restart the game. If you still have the old `SessionTracker` folder, delete it so the two do not clash.

## How it is made
Allemano Addons are designed, tested and decided by a person who plays the game, and written with the help of Claude (an AI assistant). It is tested in the game by the author and a few guildmates, so some things only show up once more people use it. Found a bug or have an idea? Tell us.

Part of **Allemano Addons**. Source code and issues: https://github.com/Allemano-Addons/SessionTracker
