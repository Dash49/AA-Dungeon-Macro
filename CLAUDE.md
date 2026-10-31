# AA Dungeon Macro – notes for Claude

AutoHotkey **v2** macro for the Dungeon mode of *Anime Adventures* (Roblox, UPD 20.4.1).
Users are Thai; talk to them in Thai (issue comments, PR text). Code comments stay English.

## Files
| File | What |
|---|---|
| `AADungeon.ahk` | the macro (one file, ~2300 lines) |
| `AASettings.ahk` | Thai settings window (F8) for plan.txt / settings.ini, bug report (F9) |
| `AAWatch.ahk` | 3 reader processes started by the macro (`StartWatchers`), they never click: `yen` (0.15 s, PostMessage 0x5A01), `left` unit panel (0.25 s, WM_COPYDATA code 2), `right` Unit Overview cards (code 3) + match state play/end (code 4, 1 s). Each message carries the capture tick; the macro uses it only if newer than its last click (`MT.panelClick`, `MT.ovMoveAt`) – `WatchedPanel/WatchedCards/WatchedMatch`, else its own OCR. Screen helpers there are copies – keep them in step |
| `Lib/OCR.ahk` | Descolada's Windows OCR wrapper – third party, do not edit |
| `plan.example.txt` | example plan; copied to the user's `plan.txt` on first run |
| `settings.example.ini` | example settings, **UTF-16 LE**; copied to `settings.ini` on first run |

Users' own `settings.ini` / `plan.txt` are not in the repo, so updates (F8 > Update, or a new ZIP) never overwrite them.
The updater replaces only `AADungeon.ahk`, `AASettings.ahk`, `AAWatch.ahk`, `Lib/OCR.ahk`, taken from the newest commit SHA (`LatestRaw`) –
raw `.../main/` is CDN-cached and once overwrote a newer local file with an older one.

`.ahk` files are UTF-8 **with BOM**. Keep the BOM and CRLF-agnostic style; never reformat whole files.
There is no AutoHotkey on your runner: you cannot run the code (the separate "AHK syntax check" workflow
loads both scripts in real AutoHotkey on Windows for every push/PR – a red check there means a load error). Re-read your edit carefully for v2
syntax (see pitfalls) – a syntax error stops the macro for every user.

## How the macro works
- `Start()` (F2) loops: `Screen()` OCRs the whole window and names the screen
  (`leave, died, chests, shrine, loading, route, shop, intro, reward, result, afterroom, disconnect, vote, ingame, lobby, unknown`),
  then calls the handler (`DoRoute`, `DoShop`, `DoVote`, `DoResult`, `PlayMatch`, ...).
- `RS` = state of one dungeon run (depth, ready flag, coins...). `MT` = state of one match
  (placed `units`, `bad`/`good` spots, `capped` slots, flags). `CFG` = settings.ini values.
- `RS.ready` guards against starting a "match" on a stale screen: it turns true only on
  loading/vote/intro/lobby and false after result/reward/afterroom/died.
- Rooms: `ReadRoute()` + scoring (Boss/Chest/Hoard/Shrine/Open/Normal/Curse… from settings, `Lookahead`).
  Curse icons: `CurseIcon()` samples the icon above each CURSE word (10x10 points, `CurseBin` colour groups per quarter)
  and compares with `CURSE_ICONS` (made offline from 101 icons in route shots) -> label `Curse(Wind)`. `CurseAvoid`
  (settings) curses get -1000; `EnterTile(t, true)` also reads "Curse of X" on the room card and closes it (`CloseRoomCard`)
  if avoided; only avoided rooms left -> entered anyway. Icons for the F8 picker: `Images/curses/*.png` (the picker downloads missing ones).
- Before the start (`StartMoves`, vote screen or first look at a match): maps with a route in `WALKS` (Capy's recorded
  key timings, `MapRoutes`=1) go `MapRouteGo`: `CapyCamera` (his Zoomtech moves; `RS.capyCam` -> CamZoomNow 20,
  CameraSetup redoes it) -> `SpawnReset` (gear, 10 notches at Capy's spot - measured live at 1080p, Capy's 800x600 uses 6; `SpawnRow` OCR check, never a blind click:
  Return to Lobby is the next row; red X) -> `PlayRoute`. Map = newest of `RS.roomMap` (card) / `RS.mapName` (loading), 5 min.
  Other maps: `StageWalk` then `CameraSetup` (old way).
- Match: `PlayMatch()` runs the steps of plan.txt via `RunStep()`.
  Plan syntax: `place 1 x3 [random|near|far|group|spread|cover|center|at X,Y]`,
  `upgrade 1,2 [max|to N|+N] [even|one] [until wave N]`, `ability 3 x2`, `auto 6`, `wait 5`, `wave 7`.
- Placing: `PlaceAny()` → `PlaceUnit()`. Press the hotbar key; the enemy path turns **red**
  (`RedGrid` before/after diff = path). Candidates come from `PlaceCands()` (ground) or
  `HillCands()` (hill units: only inside the **green** zones shown while a hill unit is held,
  `GreenGrid` diff). `ScoreCands()` orders them by style. Click a candidate; "placed" =
  red path gone **and** a new card in Unit Overview (`ScanCards`, cyan "First" buttons) –
  or, in "wide" mode with the overview closed, the yen dropped. After 3 failed card checks
  for a slot it trusts the red path (`MT.fake`).
  A placed unit opens its panel on the left with its name: `OpenPanelName()` right after the red path goes =
  the slot's name -> placed (`byPanel`, no card/yen check); another name = the click hit a standing unit -> not placed.
  Named slots count ONLY with their name on the panel (user wish): no panel -> the spot is clicked once; still none -> not placed.
  After every missed click `CapSeen()` OCRs the middle for "Cannot place more than N of this unit!": `CapHit()` marks the slot
  `MT.capped` (no more placing it, `CheckPlaced`/`CatchPlace` skip it) and adds back units the card count missed (up to N).
  Hill units with no green on screen walk W/D/S/A (`HillWalk` s) and always walk back.
- Card census (named slots, `CardOf()` → `CardByIdx()`): every card gets a number in the WHOLE list
  (`CardIdx`, scroll offset `MT.ovOff` measured in `OverviewScroll` via `ListShift`, reset to 0 at the top)
  and a name read once per "generation" (`CensusGen`: unit count + fusions): the small card name if it fits
  a unit name exactly, else the big panel title (`PanelTitle`). `CheckPlaced()` (start of every upgrade step)
  re-places units that have no card. `FuseCheck()` after a skill: Vego + Carrot -> "Fused Hero" (`FUSIONS`),
  the clicked unit's slot then means the Fused Hero card, the partner is removed and never re-placed.
  If the list position is lost, `CardByIdx` returns "?" and the old way below is used.
- Old card ↔ slot way: if `Name<slot>` is set, `CardByName()` OCRs the names under the portraits
  (`CardNames`, cached 3 s) and matches them (`NameMatch`, fuzzy). Without a name it guesses from card order
  (slot high→low), which is often wrong – the game does not always sort that way.
- `UpgradeMode` (settings, default `spot`): `UpgradeOnce` -> `UpgradeBySpot` clicks the unit where it was placed
  (`u.x/u.y`, reference coords; `SpotPanel` checks the name; 3 misses -> `u.spotBad`, Unit Overview for that unit).
  Spot mode skips `CheckPlaced`/card census (placing is checked by the panel). `PanelBuy` = the shared "panel open -> buy" part.
  3 spot misses -> `ReplaceUnit`: click 20/40 px higher; still nothing -> the unit is forgotten and placed again ("gone": `UpgradeSteps` rebuilds its list).
  Spots need a fixed camera: a stray wheel notch on the map (list ignored the wheel) is undone with `RestoreZoom()` (in 30, out CamZoom),
  and `ReplaceUnit` restores the zoom once (per 60 s) before deciding a unit is gone. Spot mode never scrolls the list for `auto`.
- Upgrades of named units go through the unit panel (`UpgradeByPanel`): click the card picture, read the
  big name (must match), `Upgrade [n]`, `(MAX)`, the price on the big button (`PanelInfo`), click it only when
  the yen is enough, check the level went up. Unnamed units use the card button (`UpgradeByCard`).
- Saving phase: while an upgrade waits for yen, `CatchUp(need)` (every 3 s) looks back at plan steps 1..current-1
  and stops as soon as the yen covers the current task. `CatchPlace`: real card count (census) vs. all place steps of
  that unit so far – phantom units are forgotten and placed again. `CatchUpgrade`: each target's panel is opened once
  (`u.chk`) for its real level/MAX, then one level for the furthest behind. A step found complete is marked `st.done` and never checked again this match (the user
  first wanted no marks, then asked for them back - endless rechecking cost too much time); log only on change via `CatchSay`;
  panel levels re-read at most every 30 s per unit (`u.chkAt`).
  `CatchAuto`: auto switch must be On (turned on if not). Skill presses (`ability`) can't be counted later - not rechecked.
  Census: if the wheel does not move the list, a card picture is clicked first (wakes the list) and it scrolls again. Census bottom part: `BottomCards()` lines the
  bottom cards up with the top ones by unit (not by pixels); `CheckPlaced()` counts twice before re-placing.
- Multitasking (cooperative – AHK has one thread; timers must stay short and must not click): while the current
  task waits for yen (`MT.need`, set in the upgrade loop and in `WaitYen`), `CatchUp()` runs back to back. All checking
  work asks `Preempt()` (yen via `YenNow()`, re-read every 0.25 s) between cards/units and stops when the yen covers
  `MT.need`; the census keeps the names read so far and resumes later. `MT.paying` = the current task runs (no pre-emption).
- Upgrades: Unit Overview (key F). Card level = lit segments of the bar under the card (`CardLevel`).
  `OverviewScroll` scrolls one notch at a time – an extra wheel notch at the list end zooms the
  camera into first person (a classic bug). `FixFirstPerson()` repairs that.
- Coordinates: everything is written in a 1920x1080 reference. `PX(x, anchor)` / `PY(y, anchor)`
  convert to the real client (anchors l/c/r and t/c/b; scale `WIN.u` = client height / 1080).
  `Snap()` copies the client into a buffer; `Color(x, y)` reads it (screen coords).
- Discord (`Webhook`, `WebhookShots`): `Hook(msg)`/`HookSend(json, img)` write the JSON to `%TEMP%\aad_hook` and run curl.exe hidden.
  Item Tracking (user wish, like Capy's macro): ONE embed card per dungeon run - `TRACK` items (Gems, Stat Cube, Perfect Stat Cube,
  Star Remnant, Cursed Token, Snow Reaper, April Coins) + depth reached + rooms won/lost (`Trk()` = `STATE.trk`).
  `RewardSeen(r)` reads reward popups ("Name (xN)" or the line above a rarity word, deduped 8 s) from the main loop, `MatchOver`, `DoChests`.
  Finish / died -> `SummaryDue()`; the main loop sends `RunSummary()` 25 s later or on the next lobby/route screen (rewards after Finish count).
- `StopAtLives` (default 1): `ReadLives()` on the room board ("3/5" under red hearts, `DoRoute`); lives <= it -> card + `Reload()`.
- `StuckRejoin` (min, default 10) + `PrivateServer` (link): `Progress(what)` marks real progress (known screen change, plan step,
  unit placed, level bought; Windows locked counts too). `Watchdog` (30 s timer): no progress that long -> `Rejoin()`: Discord note,
  close RobloxPlayerBeta.exe, `Run(link)` (browser), wait for the window, restart with `/autostart` (`AutoStart` waits for a big window).
- `StopAfterLosses` (default 4): `STATE.lossRow` counts DEFEATs in a row (VICTORY resets); at the limit -> Discord message + `Reload()` (= F3).
- `ShotScreens=1` (settings.ini only, deliberately not in F8/README – only the owner uses it): JPG of every dungeon
  screen and room card in `shots\ui` (`ShotUi`), newest 500 kept; every room board in `shots\route`
  (`ShotRoute`, newest 2000) with what was read and the chosen route in `shots\route\routes.txt`.
- OCR helpers: `OcrRef(x1,y1,x2,y2,scale)` on reference coords, `OcrAll()`, `Find(r, "text", &x, &y)`.

## Reading a bug report
`report/system.txt`: screen size, Windows scale, Roblox client size, OCR languages, macro file date.
Common non-bugs: Windows scale not 100%, Roblox not maximised / on a second monitor, no `en-US` OCR,
old macro version (compare the file date with the latest commit), costs/plan not matching the user's units.
`AADungeon.log`: one line per action, `[HH:MM:SS]`. Look at the last match: `Screen: ...`,
`Step n/m`, `placed unit ...`, `not really placed ...`, `[check] ...`, `VICTORY/DEFEAT`.
A loop of the same line usually shows where it is stuck.

## AHK v2 pitfalls (all of these broke the macro before)
- Two functions with the same name (any case) = the script will not load (`Lev` broke it once).
- Names are case-insensitive: `T` and `t` (or `B`/`b`) are ONE variable – `t := PanelTitle()` once wiped the
  array `T` (BottomCards crash). Use distinct names. Script errors are logged as `ERROR: ... | line n` (`ErrLog`).
- Names are case-insensitive: a local variable must not share a function's name
  (e.g. a variable `lines` hides the function `Lines()` – that crashed the shop).
- Assigning a global inside a function needs `global X`; property/item writes (`MT.x := 1`) do not.
- `static` declarations go at the top of the function.
- Code after the auto-execute `return` near the top never runs – global inits belong before it.
- `Color()` wants numbers; keep coordinates numeric (it rounds).
- Don't send keys/wheel blindly at list ends (first-person camera).

## Making a fix
- Smallest change that fixes the cause; keep the existing style and log messages (`Out("...")`).
- Add a log line where it helps the next report.
- If the change touches `settings.ini` keys, also update the defaults in `LoadConfig()` (macro),
  `DEF` (AASettings.ahk) and the README table.
- README is Thai – update it when behaviour visible to users changes.
