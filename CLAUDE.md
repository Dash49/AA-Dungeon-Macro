# AA Dungeon Macro – notes for Claude

AutoHotkey **v2** macro for the Dungeon mode of *Anime Adventures* (Roblox, UPD 20.4.1).
Users are Thai; talk to them in Thai (issue comments, PR text). Code comments stay English.

## Files
| File | What |
|---|---|
| `AADungeon.ahk` | the macro (one file, ~2300 lines) |
| `AASettings.ahk` | Thai settings window (F8) for plan.txt / settings.ini, bug report (F9) |
| `Lib/OCR.ahk` | Descolada's Windows OCR wrapper – third party, do not edit |
| `plan.txt` | example plan (users have their own) |
| `settings.ini` | example settings, **UTF-16 LE** (IniRead/IniWrite) – keep that encoding |

`.ahk` files are UTF-8 **with BOM**. Keep the BOM and CRLF-agnostic style; never reformat whole files.
There is no AutoHotkey on the CI runner: you cannot run the code. Re-read your edit carefully for v2
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
  Hill units with no green on screen walk W/D/S/A (`HillWalk` s) and always walk back.
- Upgrades: Unit Overview (key F). Card level = lit segments of the bar under the card (`CardLevel`).
  `OverviewScroll` scrolls one notch at a time – an extra wheel notch at the list end zooms the
  camera into first person (a classic bug). `FixFirstPerson()` repairs that.
- Coordinates: everything is written in a 1920x1080 reference. `PX(x, anchor)` / `PY(y, anchor)`
  convert to the real client (anchors l/c/r and t/c/b; scale `WIN.u` = client height / 1080).
  `Snap()` copies the client into a buffer; `Color(x, y)` reads it (screen coords).
- OCR helpers: `OcrRef(x1,y1,x2,y2,scale)` on reference coords, `OcrAll()`, `Find(r, "text", &x, &y)`.

## Reading a bug report
`report/system.txt`: screen size, Windows scale, Roblox client size, OCR languages, macro file date.
Common non-bugs: Windows scale not 100%, Roblox not maximised / on a second monitor, no `en-US` OCR,
old macro version (compare the file date with the latest commit), costs/plan not matching the user's units.
`AADungeon.log`: one line per action, `[HH:MM:SS]`. Look at the last match: `Screen: ...`,
`Step n/m`, `placed unit ...`, `not really placed ...`, `[check] ...`, `VICTORY/DEFEAT`.
A loop of the same line usually shows where it is stuck.

## AHK v2 pitfalls (all of these broke the macro before)
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
