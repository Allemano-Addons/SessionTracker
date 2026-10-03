# Changelog

## 0.7.0
- **Alts tab:** every character the addon has seen side by side: level, gold, net earned over the last 7 days, gold per hour, time played and each character's share of the income. Three cards on top show the gold on all characters, the 7-day net and who earns the most per hour. A line under the table tells how much gold you moved between your own characters (left out of the numbers); "Show transfers" lists it per character in chat.
- **Gold goal** on the Lifetime tab: set a target (a mount, say) with Set a goal / Edit goal. A bar shows the gold you hold on all characters against the target, and a line tells how long it takes at your pace of the last 14 days. Clear goal removes it.
- Each character's level and gold are now remembered so the Alts tab can show characters you are not playing right now. A character shows up after you have logged in on it once with this version.

## 0.6.0
- **Session Tracker is now Allemano Ledger.** New window (`/ledger`) with Now, History, Lifetime and Progress/Loot tabs, gold tracked by source, run summaries when you leave an instance, and your old data moves over by itself. The small session window is still `/session`. Details under 0.5.0 below.
- Two new tabs in the Ledger window, each with a period switch (Session / Today / 7 days / All time):
  - **Progress**: XP gained (and how much came from quests), XP per hour, kills, deaths, level progress
    with time on this level, time to next level and rested XP, and reputation gained per faction.
  - **Loot**: items looted by quality, vendor value of the loot (per hour), loot coins, kills per hour, and a list
    of the latest rare and better drops (hover for the item tooltip).
- Daily totals now also keep kills, deaths, quest XP, items by quality and reputation.
- Reputation is read from the game's own chat line, so it works in any language.
- Kills are counted from the XP chat line ("X dies, you gain N experience"), so only kills that give XP count (not grey mobs, not at max level). The combat log cannot be used: addons may not register it on this client.

## 0.5.0 - Allemano Ledger
- Session Tracker is now **Allemano Ledger**. The folder, the saved data and the window title changed
  name; your old data is copied over on the first start (the old variable is left untouched as a backup).
  `/ledger` opens the new window; `/session` and `/sesh` still show/hide the small session window.
- New **Ledger window** with tabs:
  - **Now**: earned, spent, net and gold per hour (with XP per hour), income by source, expenses,
    a graph of net gold over the session, vendor value of loot, Pause / Resume, a manual activity tag
    (automatic by default: Leveling, Farming, Dungeon, Raid, PvP) and End session.
  - **History**: gold earned per day (14 days / 30 days / all) split by source, and a table of finished
    sessions and instance runs with net gold and gold per hour (mouse wheel scrolls).
  - **Lifetime**: totals since the install, gold held over time across all characters and where the gold came from.
  - **Alts** is marked "Soon"; **Settings** opens the settings window.
- Gold is now tracked **by source**: loot coins, vendor sales, quest rewards, auction house, mail, trades and
  other income; repairs, vendor purchases, training, flights, mail and other expenses. Gold you move between
  your own characters (mail or trade) is counted as a transfer, not as income or expense.
- **Run summary**: when you leave a dungeon, raid or battleground a popup shows what the run made
  (Save to history / Discard).
- Daily totals per character (gold by source, XP, time online, gold held) are kept for the charts.
- The small session window: title is "Ledger", a "Details" button opens the Ledger window, the time row shows
  "Paused" when the session is paused, "Gold" is now net income minus expenses without transfers.

## 0.4.0
- Allemano look, like AltBoard and Allemano Raid Tools: rounded panels, the neutral palette,
  the SessionTracker mark and "Session" in the title, an outlined "Levels" button (amber while
  level times are open) and a rounded level bar.
- SessionTracker amber (E8A93B) is the default accent (new accent choice "Session"; "Follow
  Hush", "Class" and "Custom" are still there). Old "Follow Hush" settings move to amber once.
- Level times: finished levels only, newest first, level and time (hover for real time, date
  and zone). The X shows while the mouse is over the window; the Levels button closes it too.
- Reset, Settings, Lock and Hide moved from the title bar to the title's right-click menu.

## 0.3.3
- New SessionTracker logo (Allemano Addons family): Media/wow/icon.tga in the addon list,
  Media/wow/mark.tga left of the "Session" title. Media/png and Media/svg are the sources.
  The old Media/logo.tga and logo.png are gone.

## 0.3.2
- SessionTracker logo: in the game's addon list (IconTexture) and left of the "Session" title.
  Media/logo.tga (64x64) is made from Media/logo.png.

## 0.3.1
- "Levels" button next to the Session title opens/closes Level times (accent while open);
  removed from the right-click menu.
- Level times stays open until its X (or the button): ESC no longer closes it, and it comes back
  after /reload and login. Its position is remembered; it follows "Hide in combat" and the lock.
  "Reset window positions" resets both windows.

## 0.3.0
- Settings window (gear button in the title, title menu, `/session settings`): font, text size,
  accent (follow Hush / class / custom), background, scale; which rows show; level bar on/off;
  hide in combat; lock position; reset window position.
- New session "every login" (default) or "only on Reset": a manual session runs over several
  logins and only counts time logged in. History entries now store that online duration.

## 0.2.0
- Level times: how long each level took in /played time (plus real time, date and zone at the
  ding). The level in progress is exact from the first login (the game reports time played on
  the current level). New row "This level" (click it), "Level times" in the title menu and
  `/session levels`.
- The "Total time played" chat line is hidden for SessionTracker's own /played requests only.

## 0.1.0
- Step 1: small movable window (Hush look) with session time, gold +/-, gold per hour, XP gained
  (across level-ups), XP per hour, time to next level and a level progress bar.
- A /reload keeps the session; a new login starts a new one (the old one is kept as history
  for later). Reset button, right-click the title for Reset / Lock / Hide. `/session` shows or
  hides it, `/session reset`, `/session errors`.
