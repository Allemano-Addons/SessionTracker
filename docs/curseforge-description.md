# Session Tracker

**How did your play session go?** Session Tracker is a small, always-on window for **WoW Forever** that shows what the current session has brought you: time played, gold earned or spent, XP, and how long until the next level. It also keeps a record of how long each of your levels took.

> **Alpha.** Session Tracker is new. It is a small HUD-style window; nothing is sent to anyone.

## What it does

### Your session at a glance
A compact window with:
- **Session time**
- **Gold +/-** for the session (what you earned or spent) and **gold per hour**
- **XP gained** (counted across level-ups) and **XP per hour**
- **Time to the next level** at your current pace
- A slim **level progress bar**

*Example:* You farm for an hour. The window shows +12g, 12g per hour, some thousands of XP, and that the next level is 22 minutes away, so you know whether one more run is worth it.

### Level times
Press the **Levels** button next to the title (or type `/session levels`) to see **how long every level took**, newest first, in the game's /played time. Hover a level for the real time, the date and the zone where you dinged. The level you are in is exact from your very first login with the addon.

### Sessions that fit how you play
- A **/reload keeps the session going**.
- By default a **new session starts at every login**. Or choose "only when I press Reset": then one session can run over several logins and counts only the time you were logged in.
- Right-click the title for **Reset**, **Settings**, **Lock** and **Hide**.

### Stays out of the way
Drag it anywhere, lock it in place, hide it in combat, and choose which rows to show. It does not close when you press ESC, like a HUD should, and it remembers whether it was shown or hidden.

## Settings
`/session settings` or right-click the title: font, text size, accent color (Session amber, follow Hush, your class color or a custom one), background, window scale, which rows to show, the level bar on or off, hide in combat, lock position, and the new-session mode.

## Good to know
- Standalone. No other addon is needed; if Hush is installed, the window can follow its accent color.
- The "Total time played" chat line is hidden only for Session Tracker's own /played requests, never for yours.
- WoW Forever hides Lua errors, so Session Tracker records them: `/session errors` lists the most recent ones.

## Commands
`/session` (or `/sesh`) shows or hides the window · `/session reset` starts a new session · `/session levels` level times · `/session settings` · `/session errors`

## Installing manually (WoW Forever)
Session Tracker is made for WoW Forever (interface 16001). If the CurseForge app does not install it into the right folder, download the file from the **Files** tab and unzip it so that the folder is `World of Warcraft\_classic_beta_\Interface\AddOns\SessionTracker`, then restart the game.

Part of **Allemano Addons**. Source code and issues: https://github.com/Allemano-Addons/SessionTracker
