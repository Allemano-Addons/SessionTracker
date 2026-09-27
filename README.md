# SessionTracker

A small window for WoW Forever that shows what your current play session has brought:
time, gold (+/-), gold per hour, XP, XP per hour and time to the next level.

- `/session` shows or hides the window. `/session reset` starts a new session.
- Drag the title to move it; right-click the title for Reset / Lock / Hide.
- A /reload keeps the session; logging in again starts a new one.
- `/session levels` or a click on "This level": how long every level took (/played time).
- Gear button or `/session settings`: look, rows, hide in combat, and whether a new session
  starts on every login or only when you press Reset.
- Something not working? `/session errors` lists recent errors (WoW Forever hides Lua errors).
