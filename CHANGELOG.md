# Changelog

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
