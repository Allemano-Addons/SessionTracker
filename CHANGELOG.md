# Changelog

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
