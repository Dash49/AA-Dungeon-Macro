#Requires AutoHotkey v2.0
#SingleInstance Force
; =====================================================================
;  AA Dungeon (full screen)  -  Anime Adventures, Roblox, UPD 20.4.1
;  Built only from real 1920x1080 screenshots of the game.
;  Roblox must be maximised or full screen (F11) on the main monitor.
;
;  F2 = start     F3 = stop (reload)     F4 = pause / resume
;  F5 = "what do you see?" (writes the screen text to the log)
;  F8 = settings window (AASettings.ahk)    F9 = send a bug report
;
;  Files next to this script:
;    plan.txt     - what to place / upgrade, in order (see the file)
;    settings.ini - room points, curse rules, shop list (made on 1st run)
;    AADungeon.log
; =====================================================================
Persistent
SetWorkingDir A_ScriptDir
CoordMode "Mouse", "Screen"
CoordMode "Pixel", "Screen"
CoordMode "ToolTip", "Screen"
SendMode "Input"
#Include %A_ScriptDir%\Lib\OCR.ahk

global LOGFILE := A_ScriptDir "\AADungeon.log"
global INI := A_ScriptDir "\settings.ini"
global PLANFILE := A_ScriptDir "\plan.txt"

; window + scale. All coordinates below are 1920x1080 full-screen pixels;
; they are converted with the real client size (UI scale = height / 1080).
global WIN := {id: 0, x: 0, y: 0, w: 1920, h: 1080, u: 1.0}
global STATE := {run: false, pause: false, stop: false, hb: 0}
; one dungeon run / one match
global SNP := {x: 0, y: 0, w: 0, h: 0, buf: ""}
global RS := {depth: 0, maxDepth: 20, bossDone: false, chestsDone: false, lastRoute: 0, camDone: false, died: false, ready: true, endAt: 0, camVote: false, coins: -1, poke: 0, startAt: 0, hillScan: "", toLobby: false, stage: "", stageMove: "", stageWalked: false, voteAt: 0}
global MT := {}
; two units that fuse when the skill of one of them is used: [a, b, result]
; (the one whose skill was used becomes the result, the other one is gone)
global FUSIONS := [["Vego", "Carrot", "Fused Hero"]]
global CFG := Map()

Hotkey "F2", (*) => Start()
Hotkey "F3", (*) => Reload()
Hotkey "F4", (*) => TogglePause()
Hotkey "F5", (*) => DebugSee()
Hotkey "F6", (*) => (FindRoblox(), CameraSetup())          ; test the camera
Hotkey "F7", (*) => (FindRoblox(), CameraSetup(2))
Hotkey "F8", (*) => OpenSettings()                         ; settings window
Hotkey "F9", (*) => OpenSettings("/report")                ; send a bug report

; compare this file with the newest one on GitHub (once, at start)
CheckNewVersion() {
    try {
        tmp := A_Temp "\aad_check.ahk"
        Download("https://raw.githubusercontent.com/Dash49/AA-Dungeon-Macro/main/AADungeon.ahk?t=" A_TickCount, tmp)
        latest := StrReplace(FileRead(tmp, "UTF-8"), "`r`n", "`n")
        cur := StrReplace(FileRead(A_ScriptFullPath, "UTF-8"), "`r`n", "`n")
        if (InStr(SubStr(latest, 1, 60), "#Requires AutoHotkey v2") && latest != cur) {
            Out("A new macro version is on GitHub - F8 > Update")
            if !STATE.run
                Status("AA Dungeon ready - F2 start   (update available: F8 > Update)")
        }
    }
}

OpenSettings(arg := "") {
    f := A_ScriptDir "\AASettings.ahk"
    if FileExist(f)
        Run('"' A_AhkPath '" "' f '"' (arg != "" ? " " arg : ""))
    else
        MsgBox("AASettings.ahk not found next to the macro")
}

LoadConfig()
FileAppend("`n===== AA Dungeon started " FormatTime(, "yyyy-MM-dd HH:mm:ss") " =====`n", LOGFILE, "UTF-8")
Out("Ready. Maximise Roblox, then press F2. (F3 stop, F4 pause, F5 debug)  mode: " CFG["Preset"])
Status("AA Dungeon ready - F2 start")
SetTimer(CheckNewVersion, -1500)                    ; tell the user when an update is out
if (A_Args.Length && A_Args[1] = "/autostart") {   ; restarted by the watchdog
    Out("Restarted after being stuck - starting again in 5 s")
    SetTimer(Start, -5000)
}
return

; ===================================================== configuration
LoadConfig() {
    ; first run: start from the example file (settings.ini is the user's own
    ; and is not in the download, so updates never overwrite it)
    if (!FileExist(INI) && FileExist(A_ScriptDir "\settings.example.ini"))
        FileCopy(A_ScriptDir "\settings.example.ini", INI)
    d := Map(
        "Boss", 100, "Chest", 70, "Hoard", 20, "Shrine", 25, "Open", 5, "Normal", 0,
        "ShopRich", 60, "ShopMid", 20, "ShopPoor", 0, "ShopRichCoins", 1000, "ShopMidCoins", 600, "ShopBuyAll", 2000,
        "Curse", -10, "CurseMidDepth", 10, "CurseMid", -30, "CurseHighDepth", 15, "CurseHigh", -60,
        "Lookahead", 0.5, "ShrineMin", 25, "ShrineChest", 20, "ShrineRare", 35,
        "ShrineMode", "chest", "ShrineAvoid", "", "Preset", "balanced",
        "SaveChests", 1, "AutoVote", 1, "OnFinish", "again",
        "Cost1", 550, "Cost2", 800, "Cost3", 2000, "Cost4", 1300, "Cost5", 2000, "Cost6", 1400,
        "Type1", "ground", "Type2", "ground", "Type3", "ground", "Type4", "ground", "Type5", "ground", "Type6", "ground",
        "Name1", "", "Name2", "", "Name3", "", "Name4", "", "Name5", "", "Name6", "",
        "HillWalk", 2.5, "HillRun", 1, "HillZoomStep", 3, "HillZoomTries", 2, "CamZoom", 24,
        "StageWalk", "Magic Hill=a 3 jump|Snowy Town=d 3 jump, w 1 jump|Haunted Academy=d 3 jump",
        "Speed", 100, "ShotScreens", 0, "ShopMinPts", 1,
        "Items", "Mask of Riches=100|Philosophers Stone=95|Genie Lamp=90|Golden Mushroom=85|Celestial Blade=80"
            . "|Golden Fishhook=75|Archmage's Hat=70|Aures Maul=70|Shimmering Moon Fragment=60"
            . "|Solar Cleaver=55|Reaper Scythe=50|Magic Tome=50|Glacial Axe=50|Fish Hook=45|Speedy Boots=45"
            . "|Golden Branch=40|Elf Bow=40|Ninja Belt=35|Sword=35|Mage Coat=30|Axe=30|Nimble Cloak=25|Bow=25"
            . "|Dagger=20|Other=20 >1000")
    for k, v in d {
        val := IniRead(INI, "Settings", k, "`a")
        if (val = "`a")                            ; new setting - add it to the file
            val := v, IniWrite(v, INI, "Settings", k)
        else if (k = "StageWalk" && (val = "Magic Hill=a 3" || val = "Magic Hill=a 3|Snowy Town=d 3" || val = "Magic Hill=a 3 jump|Snowy Town=d 3 jump"
            || val = "Magic Hill=a 3 jump|Snowy Town=d 3 jump, w 1 jump")) ; old default
            val := v, IniWrite(v, INI, "Settings", k)
        CFG[k] := IsNumber(val) ? val + 0 : val
    }
    if (IniRead(INI, "Settings", "StageWalkVer", 0) + 0 < 2) {   ; once: add the new map to an edited list
        if !InStr(CFG["StageWalk"], "Haunted Academy")
            CFG["StageWalk"] := Trim(CFG["StageWalk"] "|Haunted Academy=d 3 jump", "|")
        IniWrite(CFG["StageWalk"], INI, "Settings", "StageWalk")
        IniWrite(2, INI, "Settings", "StageWalkVer")
    }
}

; ============================================================ basics
Out(msg) {
    STATE.hb := A_TickCount                        ; still alive (Watchdog)
    line := "[" FormatTime(, "HH:mm:ss") "] " msg
    try FileAppend(line "`n", LOGFILE, "UTF-8")
}

; The main loop stopped moving for 5 min (stuck in OCR or a frozen
; call - once nothing was logged for an hour after the chests): restart
; the macro, and it starts again by itself.
Watchdog() {
    if (!STATE.run || STATE.pause || A_TickCount - STATE.hb < 300000)
        return
    Out("No progress for 5 min - restarting the macro")
    try Shot("stuck")
    Run('"' A_AhkPath '" "' A_ScriptFullPath '" /autostart')
    ExitApp()
}

Status(msg) {
    ; small text in the bottom-left corner (no game words, so OCR ignores it)
    ToolTip(msg, 4, A_ScreenHeight - 60, 1)
}

TogglePause() {
    STATE.pause := !STATE.pause
    Out(STATE.pause ? "Paused" : "Resumed")
    Status(STATE.pause ? "PAUSED - F4 to resume" : "running")
}

Hold() {
    static chk := 0
    while STATE.pause
        Sleep 200
    if STATE.stop
        Exit
    ; Windows locked: the game can't be seen or clicked - just wait
    if (STATE.run && A_TickCount - chk > 1000) {
        chk := A_TickCount
        if IsLocked() {
            Out("Windows is locked - waiting until it is unlocked (the macro can't see or click the game)")
            while IsLocked() {
                STATE.hb := A_TickCount
                Sleep 1000
            }
            Out("Windows unlocked - going on")
            chk := A_TickCount
        }
    }
}
; lock screen up = LogonUI runs and the input desktop can't be switched to
IsLocked() {
    if !ProcessExist("LogonUI.exe")
        return false
    h := DllCall("OpenInputDesktop", "uint", 0, "int", 0, "uint", 0x0100, "ptr")
    if !h
        return true
    ok := DllCall("SwitchDesktop", "ptr", h)
    DllCall("CloseDesktop", "ptr", h)
    return !ok
}

; Speed (settings, %): 100 = normal, 150 = every pause 1.5x shorter.
; scaled := false for waits that must stay as written (plan "wait 5")
Wait(ms, scaled := true) {
    STATE.hb := A_TickCount
    if scaled {
        sp := CFG.Get("Speed", 100) + 0
        sp := (sp < 50) ? 50 : (sp > 250) ? 250 : sp
        if (sp != 100)
            ms := Max(40, Round(ms * 100 / sp))
    }
    t := A_TickCount
    while (A_TickCount - t < ms) {
        Hold()
        Sleep Min(100, ms)
    }
}

FindRoblox() {
    id := WinExist("ahk_exe RobloxPlayerBeta.exe")
    if !id
        id := WinExist("Roblox ahk_class WINDOWSCLIENT")
    if !id
        return false
    WinGetClientPos(&x, &y, &w, &h, id)
    WIN.id := id, WIN.x := x, WIN.y := y, WIN.w := w, WIN.h := h, WIN.u := h / 1080
    return true
}

; 1920x1080 position -> screen. ax: l / c / r (left, centre, right),
; ay: t / c / b (top, centre, bottom) - how that UI part is anchored.
PX(x, ax := "c") {
    if (ax = "l")
        return WIN.x + x * WIN.u
    if (ax = "r")
        return WIN.x + WIN.w - (1920 - x) * WIN.u
    return WIN.x + WIN.w / 2 + (x - 960) * WIN.u
}
PY(y, ay := "c") {
    if (ay = "t")
        return WIN.y + y * WIN.u
    if (ay = "b")
        return WIN.y + WIN.h - (1080 - y) * WIN.u
    return WIN.y + WIN.h / 2 + (y - 540) * WIN.u
}

; Roblox ignores clicks without a hover first
ClickAt(x, y) {
    Hold()
    MouseMove(Round(x), Round(y))
    Sleep 40
    MouseMove(1, 0, , "R")
    Sleep 40
    Click
    Sleep 80
}
ClickRef(x, y, ax := "c", ay := "c") => ClickAt(PX(x, ax), PY(y, ay))

Key(k, ms := 50) {
    Hold()
    Send "{" k " down}"
    Sleep ms
    Send "{" k " up}"
}

Focus() {
    if (WIN.id && !WinActive(WIN.id) && !DllCall("IsHungAppWindow", "ptr", WIN.id)) {
        WinActivate(WIN.id)
        Sleep 150
    }
}

; ---------------------------------------------------------------- OCR
; OCR of a screen rectangle -> {t, o, x, y} (t = all text) or "".
OcrRect(x1, y1, x2, y2, scale := 1) {
    w := Round(x2 - x1), h := Round(y2 - y1)
    if (w < 8 || h < 8)
        return ""
    static lim := 0
    if !lim {
        try lim := OCR.MaxImageDimension
        if !(lim > 0)
            lim := 2600
    }
    if (Max(w, h) * scale > lim - 4)
        scale := Floor((lim - 4) / Max(w, h) * 100) / 100
    try {
        o := OCR.FromRect(Round(x1), Round(y1), w, h, "en-US", {scale: scale, grayscale: true})
        return {t: o.Text, o: o, x: Round(x1), y: Round(y1)}
    } catch {
        try {
            o := OCR.FromRect(Round(x1), Round(y1), w, h, , {scale: scale, grayscale: true})
            return {t: o.Text, o: o, x: Round(x1), y: Round(y1)}
        }
    }
    return ""
}
; same, rectangle given in 1920x1080 coords
OcrRef(x1, y1, x2, y2, scale := 1, ax := "c", ay := "c") => OcrRect(PX(x1, ax), PY(y1, ay), PX(x2, ax), PY(y2, ay), scale)
OcrAll() => OcrRect(WIN.x, WIN.y, WIN.x + WIN.w, WIN.y + WIN.h, 1)
AllText() {
    r := OcrAll()
    return IsObject(r) ? r.t : ""
}

; words with screen centres: [{t, x, y, h}]
Words(r) {
    res_ := []
    if !IsObject(r)
        return res_
    try {
        for wd in r.o.Words
            res_.Push({t: wd.Text, x: r.x + wd.x + wd.w / 2, y: r.y + wd.y + wd.h / 2, h: wd.h})
    }
    return res_
}
Lines(r) {
    res_ := []
    if !IsObject(r)
        return res_
    try {
        for ln in r.o.Lines
            res_.Push({t: ln.Text, x: r.x + ln.x, y: r.y + ln.y + ln.h / 2, w: ln.w, h: ln.h})
    }
    return res_
}
; centre of a phrase in the OCR result
Find(r, needle, &x := 0, &y := 0) {
    if (!IsObject(r) || !InStr(r.t, StrSplit(needle, " ")[1]))
        return false
    try {
        f := r.o.FindString(needle, 1, false, (a, b) => InStr(a, b))
        x := r.x + f.x + f.w / 2, y := r.y + f.y + f.h / 2
        return true
    }
    return false
}

; ---------------------------------------------------------- snapshot
; One copy of the Roblox window in memory - reading thousands of pixels
; from it is instant (PixelGetColor one by one was taking seconds).
Snap() {
    w := WIN.w, h := WIN.h
    hdcS := DllCall("GetDC", "ptr", 0, "ptr")
    hdcM := DllCall("CreateCompatibleDC", "ptr", hdcS, "ptr")
    bi := Buffer(40, 0)
    NumPut("uint", 40, bi, 0), NumPut("int", w, bi, 4), NumPut("int", -h, bi, 8)
    NumPut("ushort", 1, bi, 12), NumPut("ushort", 32, bi, 14)
    pBits := 0
    hbm := DllCall("CreateDIBSection", "ptr", hdcM, "ptr", bi, "uint", 0, "ptr*", &pBits, "ptr", 0, "uint", 0, "ptr")
    obm := DllCall("SelectObject", "ptr", hdcM, "ptr", hbm, "ptr")
    DllCall("BitBlt", "ptr", hdcM, "int", 0, "int", 0, "int", w, "int", h, "ptr", hdcS, "int", WIN.x, "int", WIN.y, "uint", 0x00CC0020)
    if (!IsObject(SNP.buf) || SNP.buf.Size != w * h * 4)
        SNP.buf := Buffer(w * h * 4)
    DllCall("RtlMoveMemory", "ptr", SNP.buf, "ptr", pBits, "uptr", w * h * 4)
    DllCall("SelectObject", "ptr", hdcM, "ptr", obm)
    DllCall("DeleteObject", "ptr", hbm)
    DllCall("DeleteDC", "ptr", hdcM)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdcS)
    SNP.x := WIN.x, SNP.y := WIN.y, SNP.w := w, SNP.h := h
}
; colour at a SCREEN position from the last Snap() -> 0xRRGGBB
Color(sx, sy) {
    x := Round(sx - SNP.x), y := Round(sy - SNP.y)
    if (!IsObject(SNP.buf) || x < 0 || y < 0 || x >= SNP.w || y >= SNP.h)
        return 0
    return NumGet(SNP.buf, (y * SNP.w + x) * 4, "uint") & 0xFFFFFF
}
RGB(c) => {r: (c >> 16) & 0xFF, g: (c >> 8) & 0xFF, b: c & 0xFF}

; ============================================================ reading
; the yen counter above the hotbar. Floating "+202" / "-550" texts can
; cover it for a moment, so it is read twice and the bigger value wins.
ReadYen() {
    best := -1
    Loop 2 {
        v := ReadYenOnce()
        best := Max(best, v)
        if (A_Index = 1)
            Sleep 90
    }
    return best
}

ReadYenOnce() {
    r := OcrRef(860, 926, 1060, 964, 3, "c", "b")   ; just the yen line, not the hotbar
    if !IsObject(r)
        return -1
    best := ""
    for ln in Lines(r) {
        t := RegExReplace(ln.t, "(?<=\d)[ ,.'](?=\d)", "")
        if RegExMatch(t, "^\s*[+-]")                   ; "+202" / "-550" popups
            continue
        pos := 1
        while (pos := RegExMatch(t, "\d+", &m, pos)) {
            if (StrLen(m[0]) > StrLen(best))
                best := m[0]
            pos += StrLen(m[0])
        }
    }
    if (best = "" || StrLen(best) > 8)
        return -1
    return Integer(best)
}

ReadWave() {
    r := OcrRef(480, 70, 760, 125, 2, "c", "t")
    if (IsObject(r) && RegExMatch(r.t, "i)Wave\D{0,3}(\d{1,2})", &m))
        return Integer(m[1])
    return -1
}

; the big red X (white cross in the middle) of the Dungeon Run panel
BoardXVisible() {
    Snap()
    for pt in [[1500, 181], [1585, 181], [1542, 140], [1542, 225]] {
        c := RGB(Color(PX(pt[1]), PY(pt[2])))
        if !(c.r > 170 && c.g < 50 && c.b < 50)
            return false
    }
    c := RGB(Color(PX(1542), PY(181)))
    return (c.r > 200 && c.g > 200 && c.b > 200)
}

; which screen is this? one OCR of the whole window
Screen(&r := "") {
    r := OcrAll()
    if !IsObject(r)
        return "unknown"
    t := r.t
    ; Roblox "Disconnected" box first: the game behind it is still on screen
    if (InStr(t, "Disconnected") || (InStr(t, "Reconnect") && RegExMatch(t, "i)Error\s*Code")))
        return "disconnect"
    if InStr(t, "Leave Dungeon")
        return "leave"
    if (InStr(t, "Died") && InStr(t, "Depth Reached"))
        return "died"
    ; the shop first: a shop item can say "Luck", which also shows on the
    ; chest screen - that once made the macro skip a whole shop
    if (InStr(t, "Spend coins") || (RegExMatch(t, "\bSHOP\b") && InStr(t, "Continue") && !InStr(t, "OPEN CHESTS")))
        return "shop"
    if (InStr(t, "OPEN CHESTS") || (InStr(t, "Luck") && InStr(t, "Continue") && !InStr(t, "Spend")))
        return "chests"
    if (InStr(t, "WILL RECEIVE") || InStr(t, "shrine's") || (InStr(t, "ACCEPT") && InStr(t, "DENY")))
        return "shrine"
    if RegExMatch(t, "i)Room selected|Teleporting|Travelling")
        return "loading"
    if RegExMatch(t, "DUNGEON\s*DEPTH")
        return "route"
    if (InStr(t, "Pick your own") && InStr(t, "Continue"))
        return "shop"
    if InStr(t, "Enter Dungeon")
        return "intro"
    if InStr(t, "Click anywhere")
        return "reward"
    if RegExMatch(t, "VICTORY|DEFEAT|Victory|Defeat|Waves\s*Completed|Total\s*Time\s*:")
        return "result"
    if InStr(t, "Open Dungeon")
        return "afterroom"
    if (InStr(t, "Starts in") || InStr(t, "change your units") || (InStr(t, "Yes") && InStr(t, "No") && RegExMatch(t, "\d/\d")))
        return "vote"
    if BoardXVisible()                             ; dungeon panel open, text not read
        return "route"
    if RegExMatch(t, "Wave\s*\d")
        return "ingame"
    n := 0
    for w in ["Units", "Store", "Items", "Play", "Trade", "Summon", "Contracts", "Dungeon", "Quests", "Areas"]
        n += InStr(t, w) ? 1 : 0
    if (n >= 4)
        return "lobby"
    ; just after the vote the "Wave" text can be missing for a while -
    ; the yen under the hotbar means the match is on
    if (RS.voteAt && A_TickCount - RS.voteAt < 90000 && ReadYen() >= 0)
        return "ingame"
    return "unknown"
}

DebugSee() {
    if !FindRoblox()
        return Out("[F5] Roblox not found")
    s := Screen(&r)
    yr := OcrRef(860, 926, 1060, 964, 3, "c", "b")
    Out("[F5] yen text: '" (IsObject(yr) ? yr.t : "?") "'")
    Out("[F5] client " WIN.w "x" WIN.h " at " WIN.x "," WIN.y " scale " Round(WIN.u, 3) "  screen=" s "  yen=" ReadYen() "  wave=" ReadWave())
    Out("[F5] text: " SubStr(RegExReplace(IsObject(r) ? r.t : "", "\s+", " "), 1, 400))
    Status("F5: " s)
}

; ============================================================== start
Start() {
    if STATE.run
        return
    if !FindRoblox() {
        Out("Roblox window not found")
        Status("Roblox not found")
        return
    }
    if (WIN.w < 1200) {
        Out("Roblox is small (" WIN.w "x" WIN.h ") - maximise it or press F11, then F2 again")
        Status("Maximise Roblox first")
        return
    }
    if !LoadPlan()
        return
    STATE.run := true
    STATE.hb := A_TickCount
    ; keep the screen on and the PC awake while the macro runs (a screen
    ; that turns off can lock Windows, and then nothing can be clicked)
    DllCall("SetThreadExecutionState", "uint", 0x80000003)
    SetTimer(Watchdog, 30000)
    RS.ready := false, RS.endAt := A_TickCount, RS.startAt := RS.endAt ; never assume a new match at start
    Focus()
    Out("Started. client " WIN.w "x" WIN.h " scale " Round(WIN.u, 3) ", plan " MT.planSteps.Length " steps")
    Status("running")
    last := "", since := A_TickCount, closes := 0, hung := 0, unkShot := false
    Loop {
        Hold()
        STATE.hb := A_TickCount
        if !FindRoblox() {
            Out("Roblox closed - waiting")
            Wait(5000)
            continue
        }
        if DllCall("IsHungAppWindow", "ptr", WIN.id) {   ; frozen: don't touch it
            if !hung
                hung := A_TickCount, Out("Roblox is not responding - waiting")
            Wait(3000)
            continue
        }
        if hung
            Out("Roblox responds again (" Round((A_TickCount - hung) / 1000) " s)"), hung := 0
        s := Screen(&r)
        if (s != last) {
            Out("Screen: " s)
            last := s, since := A_TickCount, unkShot := false
            if RegExMatch(s, "^(route|shrine|shop|chests|result|afterroom|leave|intro|died|disconnect|vote|reward)$")
                ShotUi(s)                          ; ShotScreens=1: picture of every dungeon screen
        }
        Status(s)
        if (s = "loading" || s = "vote" || s = "intro" || s = "lobby")
            RS.ready := true                       ; a new match is really starting
        if (s = "loading")
            LoadingMap(r)                          ; "Travelling to... <map>"
        if (s = "loading" || s = "unknown" || s = "vote" || s = "intro")
            StageCheck(r.t)                        ; stage name (StageWalk)
        if (s = "result" || s = "reward" || s = "afterroom" || s = "died") {
            RS.ready := false, RS.endAt := A_TickCount ; a match just ended
            RS.stage := "", RS.stageWalked := false, RS.voteAt := 0
        }
        if (s != "ingame" && s != "vote" && closes < 2 && CloseUi()) {
            closes++                               ; closed it - look at the screen again
            continue
        }
        closes := 0
        if (s = "ingame" && !RS.ready) {
            ; the finished match is still behind the end screens ("Wave 15")
            w := ReadWave()
            if (w >= 1 && w <= 2) || (w >= 3 && w <= 12 && RS.endAt = RS.startAt)
                RS.ready := true                   ; really a new match (or started mid-match)
            else {
                ; a reward popup whose text was not read looks like this too -
                ; click empty space now and then to get past it
                if (A_TickCount - RS.poke > 4000) {
                    RS.poke := A_TickCount
                    ClickAnywhere()
                }
                Wait(800)
                continue
            }
        }
        switch s {
            case "lobby":     DoLobby(r)
            case "intro":     DoIntro(r)
            case "route":     DoRoute()
            case "loading":   Wait(800)
            case "vote":      DoVote(r)
            case "ingame":
                PlayMatch()
                RS.ready := false, RS.endAt := A_TickCount
            case "result":    DoResult(r)
            case "reward":    ClickAnywhere()
            case "afterroom": DoAfterRoom(r)
            case "shop":      DoShop()
            case "shrine":    DoShrine()
            case "chests":    DoChests()
            case "leave":     DoLeave(r)
            case "died":
                ; Continue does nothing here - close with the red X, then go
                ; back to the lobby and start a new run from the Dungeon button
                Out("You Died (all lives lost) - closing, back to lobby")
                RS.depth := 0, RS.bossDone := false, RS.chestsDone := false, RS.died := true
                ClickRef(1543, 182)
                Wait(1500)
            case "disconnect": DoDisconnect(r)
            default:
                if (A_TickCount - since > 15000) {
                    Out("Unknown screen 15s, text: " SubStr(RegExReplace(IsObject(r) ? r.t : "", "\s+", " "), 1, 160))
                    if !unkShot                    ; one picture per stuck screen
                        Shot("unknown"), unkShot := true
                    ClickAnywhere()
                    since := A_TickCount
                }
        }
        Wait(400)
    }
}

; ============================================================ screens
DoLobby(r) {
    RS.depth := 0, RS.bossDone := false, RS.chestsDone := false, RS.died := false, RS.toLobby := false
    ; the Dungeon button (bottom of the left button column)
    for wd in Words(r)
        if (wd.t = "Dungeon" && wd.x < WIN.x + WIN.w * 0.25) {
            ClickAt(wd.x, wd.y - 30 * WIN.u)
            Wait(1500)
            return
        }
    ClickRef(163, 695, "l", "c")
    Wait(1500)
}

DoIntro(r) {
    static tries := 0, lastAt := 0, reopened := false
    tries := (A_TickCount - lastAt < 15000) ? tries + 1 : 1
    lastAt := A_TickCount
    if (tries = 1)
        reopened := false
    if RS.toLobby {                                ; still in the dungeon map after a run:
        Out("Run finished - closing this window and going back to the lobby first")
        ClickRef(1542, 181)                        ; red X -> "Return to lobby" shows up
        Wait(2000)
        return
    }
    if (tries = 4 && !reopened) {                  ; the button does nothing: close and reopen
        Shot("intro_stuck")
        Out("Enter Dungeon does nothing - closing the dungeon window and opening it again")
        reopened := true
        ClickRef(1542, 181)                        ; red X of the window
        Wait(2500)
        return
    }
    if (tries > 9) {
        Out("Could not enter the dungeon (tried 9 times, reopened once)"
            . (RegExMatch(r.t, "i)key") ? " - no Dungeon Key left?" : "") " Stopping - see shots\intro_stuck_*.png")
        tries := 0
        Reload()
    }
    Out("Dungeon menu - Enter Dungeon" (tries > 1 ? " (try " tries ")" : ""))
    RS.depth := 0, RS.bossDone := false, RS.chestsDone := false
    if Find(r, "Enter Dungeon", &x, &y)
        ClickAt(x, y)
    else
        ClickRef(960, 705)
    Wait(2000)
}

; Camera: look straight down on the character from high up (the view
; you play with). Right-drag tilts the camera, the wheel zooms out.
CameraSetup(way := 1) {
    Focus()
    Out("Camera: top-down view (way " way ")")
    cx := Round(PX(960)), cy := Round(PY(540))
    MouseMove(cx, cy)
    Sleep 150
    Loop 30 {                                      ; zoom all the way in = same start every time
        Click "WheelUp"
        Sleep 25
    }
    Sleep 150
    Loop CamZoomNow() {                            ; then out to the set distance
        Click "WheelDown"
        Sleep 40
    }
    Sleep 150
    ; tilt: hold the right button and move the mouse down
    if (way = 1) {
        SendInput "{RButton down}"
        Sleep 80
        Loop 40 {
            DllCall("mouse_event", "UInt", 0x0001, "Int", 0, "Int", 25, "UInt", 0, "UPtr", 0)
            Sleep 16
        }
        Sleep 80
        SendInput "{RButton up}"
    } else {
        Click "Right Down"
        Sleep 80
        Loop 25 {
            MouseMove(0, 20, 2, "R")
            Sleep 16
        }
        Sleep 80
        Click "Right Up"
    }
    Sleep 150
    MouseMove(cx, cy)
    Sleep 300
    RS.camDone := true
}

DoVote(r) {
    static tries := 0, lastAt := 0
    if !RS.camVote {                               ; camera first, then start the game
        StageWalk()                                ; e.g. Magic Hill: move first
        CameraSetup()
        RS.camVote := true
        HillScan()                                 ; where the hills are (before the start)
        return
    }
    tries := (A_TickCount - lastAt < 8000) ? tries + 1 : 1
    lastAt := A_TickCount
    RS.voteAt := A_TickCount                       ; the match starts soon (see Screen)
    if !CFG["AutoVote"] {
        if (tries = 1)
            Out("Vote: AutoVote is off in settings - click Yes yourself")
        return Wait(1000)
    }
    ; Yes is the green button left of the red No, under "Vote start"
    for wd in Words(r)
        if (RegExMatch(wd.t, "i)^\W*Y[e3]s\W*$") && wd.y < WIN.y + WIN.h * 0.35) {
            if (tries <= 3 || !Mod(tries, 10))
                Out("Vote: clicking Yes" (tries > 1 ? " (try " tries ")" : ""))
            ClickAt(wd.x, wd.y)
            Wait(800)
            return
        }
    ; not read: click the button by its look (green), else where it normally is
    Snap()
    gx := 0, gy := 0
    for pt in [[830, 184], [930, 184], [860, 184], [900, 178]] {    ; beside the white text
        c := RGB(Color(PX(pt[1]), PY(pt[2], "t")))
        if (c.g > 150 && c.r < 140 && c.b < 100) {
            gx := PX(pt[1]), gy := PY(pt[2], "t")
            break
        }
    }
    if (tries <= 3 || !Mod(tries, 10))
        Out("Vote: Yes not read - clicking " (gx ? "the green button" : "where Yes normally is") " (try " tries ")")
    if gx
        ClickAt(gx, gy)
    else
        ClickRef(880, 184, "c", "t")
    Wait(800)
}

DoResult(r) {
    static tries := 0, lastAt := 0
    tries := (A_TickCount - lastAt < 8000) ? tries + 1 : 1
    lastAt := A_TickCount
    won := RegExMatch(r.t, "VICTORY|Victory") ? true : false
    if (tries = 1)
        Out(won ? "VICTORY" : "DEFEAT")
    if (won && RS.depth >= RS.maxDepth)
        RS.bossDone := true
    if (tries >= 2) {
        ; Next did not work: the camera may be in first person (mouse locked)
        ; or a unit window covers it - zoom out and close windows first
        if (tries = 2)
            Out("  Next did not react - zooming out / closing windows")
        ZoomOutKeys()
        CloseUi()
        MouseMove(PX(960), PY(540))
    }
    if Find(r, "Next", &x, &y)
        ClickAt(x, y)
    else
        ClickRef(768, 745)
    Wait(1200)
}

ClickAnywhere() {
    ; left middle of the screen - no button there on any dungeon panel
    ClickAt(WIN.x + WIN.w * 0.22, WIN.y + WIN.h * 0.62)
    Wait(600)
}

DoAfterRoom(r) {
    ; "Return to lobby" / "Open Dungeon" after a room
    if (RS.died || RS.toLobby) {                   ; a new run starts from the lobby
        Out("Return to lobby")
        if Find(r, "Return to lobby", &x, &y)
            ClickAt(x, y)
        else
            ClickRef(798, 217, "c", "t")
        Wait(4000)
        return
    }
    if Find(r, "Open Dungeon", &x, &y)
        ClickAt(x, y)
    else
        ClickRef(1120, 217, "c", "t")
    Wait(1500)
}

; keep clicking Reconnect until the box is gone ("Reconnect was
; unsuccessful" often needs many tries)
DoDisconnect(r) {
    Out("Disconnected - clicking Reconnect until it works")
    n := 0
    Loop 300 {                                     ; ~15 min, then the main loop looks again
        Focus()
        if Find(r, "Reconnect", &x, &y)
            ClickAt(x, y)
        else
            ClickRef(1054, 627)                    ; Reconnect = right button of the box
        n++
        Wait(3000)
        r := OcrAll()
        if !(IsObject(r) && (InStr(r.t, "Disconnected") || InStr(r.t, "Reconnect")))
            break
        if (Mod(n, 10) = 0)
            Out("  still disconnected - Reconnect clicked " n " times")
    }
    Out("  Reconnect box gone after " n " clicks - waiting for the game to load")
    RS.camVote := false, RS.ready := false, RS.stage := "", RS.stageWalked := false
    Wait(10000)
}

; ======================================================== room choice
; label words on the room tiles -> type
LabelType(word) {
    w := StrUpper(RegExReplace(word, "[^A-Za-z0-9]"))
    w := StrReplace(StrReplace(w, "0", "O"), "1", "I")
    for k, v in Map("HOARD", "Hoard", "CHEST", "Chest", "SHOP", "Shop", "CURSE", "Curse", "SHRINE", "Shrine", "BOSS", "Boss", "OPEN", "Open")
        if (w = k || (StrLen(w) >= 4 && Lev(w, k) <= 1))
            return v
    return ""
}

Lev(a, b) {
    la := StrLen(a), lb := StrLen(b)
    if (Abs(la - lb) > 1)
        return 9
    prev := []
    Loop lb + 1
        prev.Push(A_Index - 1)
    Loop la {
        i := A_Index, cur := [i], ca := SubStr(a, i, 1)
        Loop lb {
            j := A_Index
            cur.Push(Min(prev[j + 1] + 1, cur[j] + 1, prev[j] + ((ca = SubStr(b, j, 1)) ? 0 : 1)))
        }
        prev := cur
    }
    return prev[lb + 1]
}

CursePts(depth) {
    if (depth >= CFG["CurseHighDepth"])
        return CFG["CurseHigh"]
    if (depth >= CFG["CurseMidDepth"])
        return CFG["CurseMid"]
    return CFG["Curse"]
}

LabelPts(t, coins, depth) {
    switch t {
        case "Curse": return CursePts(depth)
        case "Shop":
            if (coins > CFG["ShopRichCoins"])
                return CFG["ShopRich"]
            if (coins > CFG["ShopMidCoins"])
                return CFG["ShopMid"]
            return (coins >= 0) ? CFG["ShopPoor"] : CFG["ShopMid"]
    }
    return CFG.Has(t) ? CFG[t] : 0
}

SetPts(labels, coins, depth) {
    s := 0
    for t in labels
        s += LabelPts(t, coins, depth)
    return s
}

; Is the big tile at ref x one flat colour (a real tile - empty, OPEN
; green or CURSE purple)? The brick wall behind is textured.
FlatTile(xr) {
    n := 0, s := 0, s2 := 0
    y := 566
    while (y <= 600) {
        x := xr - 75
        while (x <= xr + 75) {
            c := RGB(Color(PX(x), PY(y)))
            L := 0.3 * c.r + 0.59 * c.g + 0.11 * c.b
            s += L, s2 += L * L, n++
            x += 6
        }
        y += 4
    }
    m := s / n, sd := Sqrt(Max(0, s2 / n - m * m))
    return (sd < 1.6 || sd > 15)
}

ReadRoute() {
    res := {depth: 0, max: 20, coins: -1, tiles: []}
    ; depth "13/20"
    h := OcrRef(700, 255, 1180, 305, 2)
    if (IsObject(h) && RegExMatch(h.t, "(\d{1,2})\s*[/lI|\\]\s*2[0Oo]", &m))
        res.depth := Integer(m[1]), res.max := 20
    if !res.depth {                                ; 2nd try: only the number, bigger
        h := OcrRef(1000, 258, 1150, 300, 4)
        if (IsObject(h) && RegExMatch(h.t, "(\d{1,2})\s*[/lI|\\]\s*2[0Oo]", &m))
            res.depth := Integer(m[1]), res.max := 20
    }
    ; coins (first number on the counter row)
    c := OcrRef(470, 760, 580, 808, 3)
    if (IsObject(c) && RegExMatch(c.t, "(\d{1,6})", &m))
        res.coins := Integer(m[1])
    ; labels: small row (next rooms) and big row (rooms you can enter)
    sm := OcrRef(440, 372, 1480, 478, 3)
    bg := OcrRef(500, 560, 1420, 740, 2)
    big := [], small := []
    for wd in Words(bg)
        if (t := LabelType(wd.t))
            big.Push({t: t, x: (wd.x - PX(960)) / WIN.u + 960})
    for wd in Words(sm)
        if (t := LabelType(wd.t))
            small.Push({t: t, x: (wd.x - PX(960)) / WIN.u + 960})
    Snap()
    ; which tile layout: 3 tiles (624/959/1295), 2 (792/1127) or 1 (959)
    layouts := [[624, 959, 1295], [792, 1127], [959]]
    best := 1, bestScore := -999999                ; scores can all be negative (tiles not seen)
    for i, lay in layouts {
        sc := 0
        for x in lay {
            hit := FlatTile(x)
            for b in big
                if (Abs(b.x - x) < 90)
                    hit := true
            sc += hit ? 1 : -1
        }
        for b in big {                             ; labels outside the layout = wrong layout
            near := false
            for x in lay
                if (Abs(b.x - x) < 90)
                    near := true
            sc -= near ? 0 : 2
        }
        if (sc > bestScore)
            bestScore := sc, best := i
    }
    if (bestScore < -2)
        Out("  route: tiles hard to see (best layout score " bestScore ")")
    for x in layouts[best] {
        tile := {x: x, labels: [], ahead: []}
        for b in big
            if (Abs(b.x - x) < 90)
                tile.labels.Push(b.t)
        ; next rooms: the small tiles right above this tile (up to 3, 111 px
        ; apart) are where you can go after it. Their labels are tiny, so
        ; read just this group, enlarged, then split the words per tile.
        grp := []
        g := OcrRef(x - 172, 365, x + 172, 485, 4)
        for wd in Words(g)
            if (t := LabelType(wd.t))
                grp.Push({t: t, x: (wd.x - PX(960)) / WIN.u + 960})
        if !grp.Length {                           ; fall back to the whole-row read
            for s in small {
                nearest := 0, dmin := 99999
                for x2 in layouts[best]
                    if (Abs(s.x - x2) < dmin)
                        dmin := Abs(s.x - x2), nearest := x2
                if (nearest = x)
                    grp.Push(s)
            }
        }
        tile.ahead := Cluster(grp, 55)
        res.tiles.Push(tile)
    }
    return res
}

; group labels whose x are closer than gap -> [[types], ...]
Cluster(arr, gap) {
    s := []
    for a in arr {
        i := s.Length + 1
        while (i > 1 && s[i - 1].x > a.x)
            i--
        s.InsertAt(i, a)
    }
    res_ := [], cur := [], lastX := -9999
    for a in s {
        if (cur.Length && a.x - lastX > gap)
            res_.Push(cur), cur := []
        cur.Push(a.t), lastX := a.x
    }
    if cur.Length
        res_.Push(cur)
    return res_
}

Join(arr, sep := "+") {
    s := ""
    for v in arr
        s .= (A_Index > 1 ? sep : "") v
    return s
}

DoRoute() {
    Focus()
    CloseOverview()                                ; it covers the right room tile
    Wait(600)                                      ; let the panel finish drawing
    r := ReadRoute()
    if (r.depth < 1) {
        ; depth text hidden (the marker icon sits on top of it) - the red X
        ; still proves this is the room board, so pick a room anyway
        if !BoardXVisible() {
            Out("  room board not readable - not clicking")
            Wait(1500)
            return
        }
        r.depth := RS.depth + 1
        Out("  depth text not readable - guessing depth " r.depth)
    }
    if (r.coins >= 0)
        RS.coins := r.coins
    if (r.depth)
        RS.depth := r.depth, RS.maxDepth := r.max
    list := []
    txt := ""
    for t in r.tiles {
        now := SetPts(t.labels, r.coins, r.depth)
        nxt := 0
        if t.ahead.Length {
            nxt := -99999
            for a in t.ahead
                nxt := Max(nxt, SetPts(a, r.coins, r.depth + 1))
            nxt := Max(nxt, 0)                     ; empty next tiles are normal rooms
        }
        t.score := now + CFG["Lookahead"] * nxt
        i := list.Length + 1
        while (i > 1 && list[i - 1].score < t.score)
            i--
        list.InsertAt(i, t)
        ah := ""
        for a in t.ahead
            ah .= (A_Index > 1 ? " | " : "") Join(a)
        txt .= (txt != "" ? "  ||  " : "") (t.labels.Length ? Join(t.labels) : "Normal") (ah != "" ? " > [" ah "]" : "") " = " Round(t.score, 1)
    }
    Out("Depth " r.depth "/" r.max "  coins " r.coins "  " txt)
    for t in list {
        if EnterTile(t) {
            Out("Entered " (t.labels.Length ? Join(t.labels) : "Normal") " room")
            RS.camDone := false
            if (r.depth >= r.max)
                Out("This is the boss room")
            return
        }
        Out("Could not enter that tile - trying the next one")
    }
    Wait(1000)
}

; click a tile, then the green Enter button of its card
EnterTile(t) {
    Loop 2 {
        ClickRef(t.x, 643)
        Wait(800)
        if FindEnter(t.x, &ex, &ey) {
            RoomMap()                              ; the card names the map (StageWalk)
            ClickAt(ex, ey)
            Wait(400)
            Loop 10 {
                s := Screen()
                if (s != "route")
                    return true
                Wait(400)
            }
        }
    }
    return false
}

; the room card shows the map name under "Dungeon Room" (e.g. Snowy Town)
RoomMap() {
    r := OcrAll()
    if !IsObject(r)
        return
    name := "", prev := false
    for ln in Lines(r) {
        if prev {
            name := Trim(ln.t)
            break
        }
        prev := RegExMatch(ln.t, "i)Dungeon\s*Room")
    }
    if (name != "")
        Out("  room map: " name)
    ShotUi("room")                                 ; the room card that is about to be entered
    RS.stage := "", RS.stageWalked := false        ; this card decides it
    StageCheck(r.t)
}
; map names compared as letters only, I = l (the card font mixes them up)
MapKey(t) => StrLower(RegExReplace(StrReplace(t, "I", "l", true), "[^A-Za-z]"))
; the loading screen: "Travelling to..." then the map name in big letters
LoadingMap(r) {
    static last := ""
    prev := false
    for ln in Lines(r) {
        if prev {
            name := Trim(RegExReplace(ln.t, "\s+", " "))
            if RegExMatch(name, "i)^(Dungeon|Depth|Easy|Normal|Hard|Insane|Nightmare|Travel)")
                continue                           ; not the map name - the next line
            if (name != last && RegExMatch(name, "^[A-Za-z][A-Za-z' .-]{2,40}$")) {
                last := name
                Out("  map: " name)
                MapSeen(name)
            }
            return
        }
        prev := prev || RegExMatch(ln.t, "i)Travel+ing\s*to")
    }
}
; every map name seen goes to maps_seen.txt (F8 > ด่าน lists them)
MapSeen(name) {
    f := A_ScriptDir "\maps_seen.txt"
    try {
        old := FileExist(f) ? FileRead(f, "UTF-8") : ""
        for ln in StrSplit(old, "`n", "`r")
            if (MapKey(ln) = MapKey(name))
                return
        FileAppend(name "`n", f, "UTF-8")
    }
}
; the card opens beside the tile; its Enter button is a big bright green bar
FindEnter(tx, &ex, &ey) {
    Snap()
    best := 0
    for side in [1, -1] {
        n := 0, sx := 0, sy := 0
        dx := 140
        while (dx <= 470) {
            y := 690
            while (y <= 880) {
                c := RGB(Color(PX(tx + side * dx), PY(y)))
                if (c.g > 190 && c.r < 150 && c.b < 100)
                    n++, sx += PX(tx + side * dx), sy += PY(y)
                y += 8
            }
            dx += 8
        }
        if (n > best && n >= 15)
            best := n, ex := sx / n, ey := sy / n
    }
    return best > 0
}

; ================================================================ shop
ItemTable() {
    res_ := []
    for line in StrSplit(CFG["Items"], "|") {
        if RegExMatch(Trim(line), "^(.+?)\s*=\s*(-?\d+)(?:\s*(>=|<=|>|<)\s*(\d+))?$", &m)
            res_.Push({name: Trim(m[1]), key: StrLower(RegExReplace(m[1], "[^A-Za-z]")), pts: Integer(m[2]), op: m[3], lim: m[4] != "" ? Integer(m[4]) : 0, idx: res_.Length + 1})
    }
    return res_
}

; items_seen.txt: one line per item the shop ever showed - name|effect|price|date
; (the settings window lists them so they can be added to the buy list)
RecordSeen(name, effect, price) {
    static known := ""
    f := A_ScriptDir "\items_seen.txt"
    key := RegExReplace(StrLower(name), "[^a-z]")
    if (StrLen(key) < 3)
        return
    if !IsObject(known) {
        known := Map()
        if FileExist(f)
            for ln in StrSplit(FileRead(f, "UTF-8"), "`n", "`r")
                if (Trim(ln) != "")
                    known[RegExReplace(StrLower(StrSplit(ln, "|")[1]), "[^a-z]")] := 1
    }
    if known.Has(key)
        return
    known[key] := 1
    try FileAppend(Trim(StrReplace(name, "|", " ")) "|" Trim(StrReplace(effect, "|", " ")) "|" price "|"
        . A_YYYY "-" A_MM "-" A_DD "`n", f, "UTF-8")
    Out("  new shop item noted: " name " (" effect ")")
}

MatchItem(text) {
    t := StrLower(RegExReplace(text, "[^A-Za-z]"))
    if (StrLen(t) < 4)
        return ""
    best := "", bl := 0
    for it in ItemTable()
        if (it.key != "other" && InStr(t, it.key) && StrLen(it.key) > bl)
            best := it, bl := StrLen(it.key)
    if IsObject(best)
        return best
    ; OCR typos ("N imb1e Cloak"): the name with one or two letters off
    bestD := 99
    for it in ItemTable() {
        k := it.key, L := StrLen(k)
        if (it.key = "other" || L < 5)
            continue
        allow := Max(1, L // 6)
        Loop Max(1, StrLen(t) - L + 2) {
            d := Min(NameDist(SubStr(t, A_Index, L), k), NameDist(SubStr(t, A_Index, L - 1), k))
            if (d <= allow && d < bestD)
                bestD := d, best := it
        }
    }
    return best
}

; "Mage Coat=35 >500" = buy it when you have more than 500 coins (as the
; settings window and README say). Unknown coins -> allowed.
PriceOk(it, price, coins := -1) {
    if (it.op = "" || coins < 0)
        return true
    switch it.op {
        case ">":  return coins > it.lim
        case ">=": return coins >= it.lim
        case "<":  return coins < it.lim
        case "<=": return coins <= it.lim
    }
    return true
}

; save a PNG of the Roblox window to AAMacro\shots\<name>_<time>.png
; sub != "": quiet JPG in shots\<sub>, named time first (sorts by time)
Shot(name, sub := "") {
    static gdip := 0
    try {
        dir := A_ScriptDir "\shots" (sub != "" ? "\" sub : "")
        DirCreate(dir)
        file := (sub != "") ? dir "\" FormatTime(, "yyyyMMdd_HHmmss") "_" A_MSec "_" name ".jpg"
            : dir "\" name "_" FormatTime(, "yyyyMMdd_HHmmss") ".png"
        w := WIN.w, h := WIN.h
        hdcS := DllCall("GetDC", "ptr", 0, "ptr")
        hdcM := DllCall("CreateCompatibleDC", "ptr", hdcS, "ptr")
        hbm := DllCall("CreateCompatibleBitmap", "ptr", hdcS, "int", w, "int", h, "ptr")
        obm := DllCall("SelectObject", "ptr", hdcM, "ptr", hbm, "ptr")
        DllCall("BitBlt", "ptr", hdcM, "int", 0, "int", 0, "int", w, "int", h, "ptr", hdcS, "int", WIN.x, "int", WIN.y, "uint", 0x00CC0020)
        DllCall("SelectObject", "ptr", hdcM, "ptr", obm)
        DllCall("DeleteDC", "ptr", hdcM)
        DllCall("ReleaseDC", "ptr", 0, "ptr", hdcS)
        if !gdip {
            DllCall("LoadLibrary", "str", "gdiplus", "ptr")
            si := Buffer(24, 0), NumPut("uint", 1, si)
            DllCall("gdiplus\GdiplusStartup", "ptr*", &gdip, "ptr", si, "ptr", 0)
        }
        pBmp := 0
        DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "ptr", hbm, "ptr", 0, "ptr*", &pBmp)
        clsid := Buffer(16)
        enc := (sub != "") ? "{557CF401-1A04-11D3-9A73-0000F81EF32E}" : "{557CF406-1A04-11D3-9A73-0000F81EF32E}"  ; JPG : PNG
        DllCall("ole32\CLSIDFromString", "wstr", enc, "ptr", clsid)
        DllCall("gdiplus\GdipSaveImageToFile", "ptr", pBmp, "wstr", file, "ptr", clsid, "ptr", 0)
        DllCall("gdiplus\GdipDisposeImage", "ptr", pBmp)
        DllCall("DeleteObject", "ptr", hbm)
        if (sub = "")
            Out("  picture saved: shots\" name "_" FormatTime(, "yyyyMMdd_HHmmss") ".png")
    } catch as e {
        Out("  picture failed: " e.Message)
    }
}

; ShotScreens=1 (settings.ini only, not in F8): a JPG of every dungeon
; screen in shots\ui. Only the newest 500 are kept.
ShotUi(name) {
    static n := 0
    if !CFG.Get("ShotScreens", 0)
        return
    Shot(name, "ui")
    if (Mod(++n, 25) = 0) {
        dir := A_ScriptDir "\shots\ui", all := ""
        Loop Files dir "\*.jpg"
            all .= A_LoopFileName "`n"
        arr := StrSplit(Sort(RTrim(all, "`n")), "`n")
        Loop arr.Length - 500
            try FileDelete(dir "\" arr[A_Index])
    }
}

; Shop rules, strongest first:
;   1. more than ShopBuyAll coins (2000) -> buy everything
;   2. the item text says luck or placement cost -> buy
;   3. the item list in settings (points + price limit)
ShopCoins() {
    c := OcrRef(470, 760, 580, 808, 3)
    if (IsObject(c) && RegExMatch(c.t, "(\d{2,6})", &m))
        return Integer(m[1])
    return RS.coins
}

DoShop() {
    Wait(400)                                      ; let the items finish drawing
    Shot("shop")
    coins := ShopCoins()
    rich := coins > CFG["ShopBuyAll"]
    Out("Shop  coins " coins (rich ? "  (over " CFG["ShopBuyAll"] " - buying everything)" : ""))
    bought := Map()
    Loop 8 {
        pass := A_Index
        ; the 3 item rows sit at fixed places; a row is there when its
        ; yellow price button is (bought items lose the button)
        Snap()
        rows := []
        for ry in [357, 476, 595] {
            c := RGB(Color(PX(1268), PY(ry)))
            if !(c.r > 190 && c.g > 140 && c.b < 90)
                continue
            pr := OcrRef(1262, ry - 24, 1345, ry + 24, 3)
            price := -1
            if (IsObject(pr) && RegExMatch(RegExReplace(pr.t, "[\s,.]"), "(\d{2,6})", &m))
                price := Integer(m[1])
            tx := OcrRef(1018, ry - 50, 1256, ry + 50, 2)
            rows.Push({x: PX(1318), y: PY(ry), price: price, txt: IsObject(tx) ? tx.t : ""})
        }
        offers := []
        for rw in rows {
            txt := RegExReplace(rw.txt, "\s+", " "), first := Trim(StrSplit(rw.txt, "`n")[1])
            if (Trim(txt) = "") {
                txt := "?", first := "item " A_Index
            }
            it := MatchItem(txt)
            if !IsObject(it)
                for o in ItemTable()
                    if (o.key = "other")
                        it := {name: first, pts: o.pts, op: o.op, lim: o.lim, idx: o.idx}
            if !IsObject(it)
                it := {name: first, pts: 0, op: "", lim: 0, idx: 999}
            if (pass = 1 && txt != "?") {              ; remember every item ever seen
                nm := first, ef := Trim(RegExReplace(SubStr(rw.txt, StrLen(StrSplit(rw.txt, "`n")[1]) + 1), "\s+", " "))
                if (ef = "" && RegExMatch(first, "^(.*?)\s*([+\-—–]\s*\d.*)$", &mm))   ; one line: "Bow +20% Range"
                    nm := mm[1], ef := mm[2]
                RecordSeen(it.HasOwnProp("key") && it.key != "other" ? it.name : nm, ef, rw.price)
            }
            if bought.Has(it.name)
                continue
            special := RegExMatch(txt, "i)luck|plac\w*\s*cost|cost\w*\s*(of\s*)?plac|deploy\w*\s*cost")
            ok := PriceOk(it, rw.price, coins), pts := it.pts, why := ""
            if special
                ok := true, pts := Max(pts, 500), why := " [luck/place cost]"
            if rich
                ok := true, pts := Max(pts, 1), why .= " [rich]"
            offers.Push({name: it.name, pts: pts, ok: ok, price: rw.price, x: rw.x, y: rw.y, why: why,
                idx: it.HasOwnProp("idx") ? it.idx : 999})
        }
        if (A_Index = 1) {
            sx := ""
            for o in offers
                sx .= o.name "=" o.pts " $" o.price (o.ok ? "" : " (no)") o.why "  "
            Out("  offers: " (sx != "" ? sx : "none read"))
        }
        pick := "", minPts := Max(1, CFG.Get("ShopMinPts", 1) + 0)   ; F8 shop mode
        for o in offers                            ; best points; same points = higher in the list
            if (o.ok && o.pts >= minPts && (coins < 0 || o.price <= coins)
                && (!IsObject(pick) || o.pts > pick.pts || (o.pts = pick.pts && o.idx < pick.idx)))
                pick := o
        if !IsObject(pick)
            break
        bought[pick.name] := true
        ClickAt(pick.x, pick.y)
        Wait(900)
        if (Screen() = "reward")
            ClickAnywhere()
        if (coins >= 0)
            coins -= pick.price
        Out("  bought " pick.name " for " pick.price pick.why)
    }
    ClickContinue()
}

ClickContinue() {
    r := OcrAll()
    if Find(r, "Continue", &x, &y)
        ClickAt(x, y)
    else
        ClickRef(1150, 748)
    Wait(1200)
}

; ============================================================== shrine
DoShrine() {
    depth := RS.depth + 1
    r := OcrRef(780, 300, 1420, 680, 2)
    total := 0, parts := "", chest := false, curses := []
    for ln in Lines(r) {
        t := ln.t
        if RegExMatch(t, "i)Curse\s*of\s*(\w+)", &m) {
            curses.Push(m[1])
            p := CursePts(depth)
            if (RegExMatch(m[1], "i)Flight|Burst") && p < 0)
                p := Round(p / 2)
            total += p, parts .= m[0] " " p ", "
        } else if RegExMatch(t, "i)Rare\s*Chest") {
            total += CFG["ShrineRare"], parts .= "Rare chest, ", chest := true
        } else if (RegExMatch(t, "i)Treasure\s*Chest") && !RegExMatch(t, "i)\+\s*1")) {
            total += CFG["ShrineChest"], parts .= "Chest, ", chest := true
        } else if IsObject(it := MatchItem(t)) {
            total += it.pts, parts .= it.name ", "
        }
    }
    ; ShrineMode: chest = always take a chest whatever the curse, points = by
    ; the points above, always / never. ShrineAvoid: curses never taken.
    mode := StrLower(CFG.Get("ShrineMode", "chest"))
    take := (mode = "always") ? true : (mode = "never") ? false
        : (mode = "chest" && chest) ? true : (total >= CFG["ShrineMin"])
    why := (mode = "always" || mode = "never") ? mode : (mode = "chest" && chest) ? "has a chest" : "points"
    for cw in StrSplit(CFG.Get("ShrineAvoid", ""), [",", "|", " "]) {
        cw := Trim(cw)
        if (cw = "")
            continue
        for c in curses
            if InStr(c, cw) {
                take := false, why := "curse of " c " is on the never list"
            }
    }
    Out("Shrine: " parts "= " total " -> " (take ? "ACCEPT" : "DENY") " (" why ")")
    b := OcrRef(820, 700, 1500, 800, 1)
    if take {
        if Find(b, "ACCEPT", &x, &y)
            ClickAt(x, y)
        else
            ClickRef(998, 750)
    } else {
        if Find(b, "DENY", &x, &y)
            ClickAt(x, y)
        else
            ClickRef(1276, 750)
    }
    Wait(2500)
}

; ============================================================== chests
; chests are saved for the end (after the boss rare chests can give a
; secret unit); at the end every chest is opened before Finish.
DoChests() {
    final := RS.bossDone || RS.depth >= RS.maxDepth
    if (CFG["SaveChests"] && !final) {
        Out("Open chests - saving them for the end")
        ClickContinue()
        return
    }
    if !RS.chestsDone {
        Out("Open chests - opening everything")
        for row in [425, 556] {
            n := 0, miss := 0
            Loop 60 {
                ClickRef(1318, row)
                got := false
                Loop 8 {
                    Wait(350)
                    if InStr(AllText(), "Click anywhere") {
                        got := true
                        break
                    }
                }
                if !got {                          ; the click can be lost while the last reward fades
                    if (++miss >= 3)               ; 3 misses in a row = none left
                        break
                    Wait(700)
                    continue
                }
                n++, miss := 0
                Loop 8 {
                    ClickAnywhere()
                    if !InStr(AllText(), "Click anywhere")
                        break
                }
                Wait(600)                          ; let the reward close before the next OPEN
            }
            Out("  opened " n (row = 425 ? " treasure" : " rare") " chests")
        }
        RS.chestsDone := true
    }
    ClickContinue()
}

DoLeave(r) {
    if (CFG["SaveChests"] && !RS.chestsDone) {
        Out("Leave Dungeon? - chests not opened yet -> Cancel, open them first")
        RS.bossDone := true
        if Find(r, "Cancel", &x, &y)
            ClickAt(x, y)
        else
            ClickRef(1080, 615)
        Wait(1000)
        return
    }
    Out("Run finished -> Finish")
    if Find(r, "Finish", &x, &y)
        ClickAt(x, y)
    else
        ClickRef(798, 615)
    RS.depth := 0, RS.bossDone := false, RS.chestsDone := false
    RS.toLobby := true                             ; the next run can only start from the lobby
    Wait(2500)
    if (CFG["OnFinish"] = "stop") {
        Out("OnFinish=stop")
        Reload()
    }
}

; ================================================================ plan
; place 1 x3 | upgrade 1,2 [to 3|+1|max] [even|one] [until wave 5]
; ability 3 x2 | auto 6 | wait 5 | wave 7
LoadPlan() {
    if !FileExist(PLANFILE) {                      ; first run: copy the example plan
        if FileExist(A_ScriptDir "\plan.example.txt")
            FileCopy(A_ScriptDir "\plan.example.txt", PLANFILE)
        else
            FileAppend("place 1 x3`nplace 2 x1`nupgrade all max`n", PLANFILE, "UTF-8")
    }
    steps := [], bad := []
    for i, raw in StrSplit(FileRead(PLANFILE, "UTF-8"), "`n", "`r") {
        line := Trim(RegExReplace(raw, ";.*$"))
        if (line = "")
            continue
        l := StrLower(line)
        for th, en in Map("วาง", "place", "อัพ", "upgrade", "อัป", "upgrade", "สกิล", "ability", "ออโต้", "auto", "รอ", "wait", "เวฟ", "wave", "ตัน", "max", "เฉลี่ย", "even", "ทีละตัว", "one",
            "สุ่ม", "random", "ชิดทาง", "near", "ไกล", "far", "กลุ่ม", "group", "กระจาย", "spread", "โค้ง", "cover", "กลาง", "center", "จุด", "at")
            l := StrReplace(l, th, en)
        if RegExMatch(l, "^place\s+([1-6])\s*(?:x\s*(\d+))?(?:\s+(random|near|far|group|spread|cover|center|at\s*(\d+)\s*,\s*(\d+)))?$", &m) {
            st := {k: "place", slot: Integer(m[1]), n: m[2] != "" ? Integer(m[2]) : 1, style: "random", text: line}
            if (m[3] != "")
                st.style := (SubStr(m[3], 1, 2) = "at") ? "at" : m[3]
            if (st.style = "at")
                st.ax := Integer(m[4]), st.ay := Integer(m[5])
            steps.Push(st)
        }
        else if RegExMatch(l, "^upgrade\s+(all|[1-6](?:\s*,\s*[1-6])*)(.*)$", &m) {
            st := {k: "upgrade", targets: [], goal: "max", plus: 0, style: "one", until: 0, text: line}
            if (m[1] = "all") {
                Loop 6
                    st.targets.Push(7 - A_Index)
            } else {
                for s in StrSplit(m[1], ",", " ")
                    st.targets.Push(Integer(s))
            }
            rest := m[2]
            if RegExMatch(rest, "to\s*(\d+)", &g)
                st.goal := Integer(g[1])
            if RegExMatch(rest, "\+\s*(\d+)", &g)
                st.goal := "plus", st.plus := Integer(g[1])
            if InStr(rest, "even")
                st.style := "even"
            if RegExMatch(rest, "until\s*wave\s*(\d+)", &g)
                st.until := Integer(g[1]), st.goal := (st.goal = "max" && !InStr(rest, "max")) ? "max" : st.goal
            steps.Push(st)
        } else if RegExMatch(l, "^ability\s+([1-6])\s*(?:x\s*(\d+))?$", &m)
            steps.Push({k: "ability", slot: Integer(m[1]), n: m[2] != "" ? Integer(m[2]) : 1, text: line})
        else if RegExMatch(l, "^auto\s+([1-6])$", &m)
            steps.Push({k: "auto", slot: Integer(m[1]), text: line})
        else if RegExMatch(l, "^wait\s+(\d+)", &m)
            steps.Push({k: "wait", s: Integer(m[1]), text: line})
        else if RegExMatch(l, "^wave\s+(\d+)", &m)
            steps.Push({k: "wave", w: Integer(m[1]), text: line})
        else
            bad.Push("line " i ": " line)
    }
    if bad.Length {
        for b in bad
            Out("Plan error - " b)
        Status("plan.txt has errors - see the log")
        return false
    }
    global MT
    MT := {planSteps: steps}
    return true
}

; ================================================================ match
PlayMatch() {
    global MT
    Out("Match started - running the plan")
    MT := {planSteps: MT.planSteps, units: [], bad: [], good: [], capped: Map(), start: A_TickCount}
    ; the vote panel can still be there for a moment - never place during it
    Loop 20 {
        if !InStr(AllText(), "Starts in")
            break
        Wait(500)
    }
    ; right after the vote the picture can still be black (fade-in): wait a
    ; little for it, so the path shows when the first unit is held
    Loop 16 {
        Snap(), lit := 0
        for pt in [[480, 300], [960, 300], [1440, 300], [480, 700], [960, 700], [1440, 700]] {
            c := RGB(Color(PX(pt[1]), PY(pt[2])))
            lit += (Max(c.r, c.g, c.b) > 40)
        }
        if (lit >= 2)
            break
        if (A_Index = 1)
            Out("  screen still dark - waiting a moment before placing")
        Wait(500)
    }
    ReadHotbarCosts()
    if (RS.stage = "" && !RS.camVote && ReadWave() <= 1) ; no vote screen seen: look for the name here
        StageCheck(OcrAll().t)
    StageWalk()                                     ; not done on the vote screen
    if !RS.camVote                                  ; camera was not set on the vote screen
        CameraSetup()
    RS.camVote := false                             ; next match sets it again
    if !IsObject(RS.hillScan)                       ; hills not checked on the vote screen
        HillScan()
    if IsObject(RS.hillScan)                        ; ground units keep off these hills
        MT.hillCells := RS.hillScan
    RS.hillScan := ""
    Focus()
    for i, st in MT.planSteps {
        Status("step " i "/" MT.planSteps.Length ": " st.text)
        Out("Step " i "/" MT.planSteps.Length ": " st.text)
        r := RunStep(st)
        if (r = "end") {
            Out("Match over")
            CloseUi()
            return
        }
    }
    Out("Plan done - keeping everything upgraded")
    Loop {
        if (MatchOver()) {
            Out("Match over")
            CloseUi()
            return
        }
        FixFirstPerson()
        UpgradeTargets([6, 5, 4, 3, 2, 1], "max", 0, "one", 0, 20000)
        Wait(2000)
    }
}

; the prices under the 6 hotbar slots -> Cost1..Cost6 (the team can change)
ReadHotbarCosts() {
    Loop 2 {
        r := OcrRef(700, 1008, 1220, 1056, 3, "c", "b")
        if !IsObject(r)
            continue
        nums := []
        for wd in Words(r) {
            d := RegExReplace(wd.t, "[^\d]")
            if (StrLen(d) >= 2 && StrLen(d) <= 5 && d + 0 >= 50)
                nums.Push({x: wd.x, v: d + 0})
        }
        if (nums.Length != 6)
            continue
        Loop 5 {                                    ; left to right
            Loop 6 - A_Index {
                i := A_Index
                if (nums[i].x > nums[i + 1].x)
                    t := nums[i], nums[i] := nums[i + 1], nums[i + 1] := t
            }
        }
        txt := ""
        for i, n in nums {
            v := n.v
            if (v > 20000 && StrLen(v) >= 4)        ; "2000 ¥" read as 42000 / 20004
                v := (Mod(v, 1000) = 0) ? SubStr(v, 2) + 0 : SubStr(v, 1, StrLen(v) - 1) + 0
            if (v >= 50 && v <= 20000)
                CFG["Cost" i] := v
            txt .= CFG["Cost" i] " "
        }
        Out("Unit prices from hotbar: " txt)
        return
    }
    Out("Unit prices: hotbar not readable - using settings")
}

; the match is over when any end / dungeon screen shows up
MatchOver() {
    static last := 0
    STATE.hb := A_TickCount
    if (A_TickCount - last < 1500)
        return false
    last := A_TickCount
    s := Screen()
    return (s != "ingame" && s != "unknown" && s != "vote")
}

RunStep(st) {
    FixFirstPerson()
    switch st.k {
        case "place":
            done := 0, t0 := A_TickCount
            while (done < st.n) {
                if MatchOver()
                    return "end"
                if MT.capped.Has(st.slot) {
                    Out("  unit " st.slot ": game limit reached - next step")
                    return ""
                }
                if !WaitYen(CFG["Cost" st.slot], 60000)
                    return MatchOver() ? "end" : ""
                r := PlaceAny(st.slot, st.HasOwnProp("style") ? st.style : "random",
                    (st.HasOwnProp("ax") ? {x: st.ax, y: st.ay} : ""))
                if (r = "ok")
                    done++, t0 := A_TickCount
                else if (A_TickCount - t0 > 60000) {
                    Out("  unit " st.slot ": could not place (" done "/" st.n ") - next step")
                    return ""
                }
            }
        case "upgrade":
            goal := st.goal
            return UpgradeTargets(st.targets, goal, st.plus, st.style, st.until, 240000)
        case "ability":
            u := FirstUnit(st.slot)
            if IsObject(u)
                UseAbility(u, st.n)
        case "auto":
            u := FirstUnit(st.slot)
            if IsObject(u)
                SetAuto(u)
        case "wait":
            Wait(st.s * 1000, false)               ; the plan's own wait: never faster
        case "wave":
            while (ReadWave() < st.w) {
                if MatchOver()
                    return "end"
                Wait(1500)
            }
    }
    return ""
}

FirstUnit(slot) {
    for u in MT.units
        if (u.slot = slot)
            return u
    Out("  no unit " slot " placed")
    return ""
}

WaitYen(cost, timeout) {
    t := A_TickCount
    Loop {
        y := ReadYen()
        if (y < 0 || y >= cost)
            return true
        if (A_TickCount - t > timeout || MatchOver())
            return false
        Status("saving yen " y "/" cost)
        Wait(500)
    }
}

; ------------------------------------------------------------ placing
; While a unit is held the enemy path turns red. Spots are picked at
; random a short way off that path (in range, but not on it), so it works
; on any map. Placed = the red path goes away (the unit left the hand).
; the "Place / Rotate / Cancel" hint shown next to the mouse while a unit is held
HeldHint() {
    MouseGetPos(&mx, &my)
    r := OcrRect(mx - 20, my - 40, mx + 300, my + 160, 2)
    return IsObject(r) && RegExMatch(r.t, "i)Rotate|Cancel")
}

IsRed(col) {
    r := (col >> 16) & 0xFF, g := (col >> 8) & 0xFF, b := col & 0xFF
    return (r > 150 && g < 95 && b < 105 && r - g > 100)    ; red path on most maps
        || (r > 200 && r - g > 80 && g < 150 && r - b > 25)  ; mixed with the ground: pink on ice (Marineford),
                                                             ; salmon on sand/peach ground
        || (r >= 80 && g < 45 && b < 45 && r - Max(g, b) > 55)   ; dark red on a black floor (Shop room)
}
; red points on the map (ref coords) from the last Snap -> Map(key -> [x, y])
RedGrid(step := 12) {
    m := Map()
    y := 170
    while (y <= 900) {
        sy := PY(y), x := 130
        while (x <= 1780) {
            if IsRed(Color(PX(x), sy))
                m[x * 4096 + y] := [x, y]
            x += step
        }
        y += step
    }
    return m
}
NearPath(cells, x, y, r) {
    cx := Floor(x / 14), cy := Floor(y / 14), k := Ceil(r / 14)
    Loop 2 * k + 1 {
        i := cx - k + A_Index - 1
        Loop 2 * k + 1 {
            if cells.Has(i * 4096 + cy - k + A_Index - 1)
                return true
        }
    }
    return false
}
InUi(x, y) {
    return (y < 175 || y > 960 || (y > 900 && x > 600 && x < 1320) || x < 140 || x > 1770
        || (x > 1640 && y < 210) || (MT.HasOwnProp("ovOpen") && MT.ovOpen && x > 1225))
}

AddCand(cands, cells, x, y, gap, maxN) {
    if (cands.Length >= maxN || InUi(x, y) || NearPath(cells, x, y, gap))
        return false
    if (MT.HasOwnProp("hillCells") && MT.hillCells.Has(Floor(x / 14) * 4096 + Floor(y / 14)))
        return false                               ; a hill: ground units can't stand there
    if IsRed(Color(PX(x), PY(y)))
        return false
    if (gap < 20) {                                ; tinted map: whole spot clear
        for o in [[12, 0], [-12, 0], [0, 10], [0, -10]]
            if IsRed(Color(PX(x + o[1]), PY(y + o[2])))
                return false
    }
    for v in MT.units
        if (Abs(v.x - x) < 32 && Abs(v.y - y) < 28)
            return false
    for bd in MT.bad
        if (Abs(bd.x - x) < 16 && Abs(bd.y - y) < 14)
            return false
    for c in cands
        if (Abs(c.x - x) < 20 && Abs(c.y - y) < 18)
            return false
    cands.Push({x: x, y: y})
    return true
}

; ------------------------------------------------------- hill units
; Hill units can only stand on hills. While one is held, the hills show
; as bright green zones (even on the vote screen, before the start).
; Settings: Type1..Type6 = ground / hill, HillWalk = seconds per walk.
IsHill(slot) => (StrLower(CFG.Get("Type" slot, "ground")) = "hill")

IsGreen(col) {
    r := (col >> 16) & 0xFF, g := (col >> 8) & 0xFF, b := col & 0xFF
    ; hill zones: (20,190,60)-ish, on some maps almost no blue (9,186,25),
    ; on Navy Bay mint (18,255,178); water there is (0,160,255) = more blue
    return (r < 70 && g > 160 && g - r > 110 && g - b > 60 && b < 200)
}
GreenGrid(step := 12) {
    m := Map()
    y := 170
    while (y <= 900) {
        sy := PY(y), x := 130
        while (x <= 1780) {
            if IsGreen(Color(PX(x), sy))
                m[x * 4096 + y] := [x, y]
            x += step
        }
        y += step
    }
    return m
}
; ground units keep off the hills seen from the start position
RememberHills(zone) {
    if !MT.HasOwnProp("hillCells")
        MT.hillCells := Map()
    for gp in zone
        Loop 3 {                                   ; the 12 px grid point covers ~3x3 cells
            dx := A_Index - 2
            Loop 3
                MT.hillCells[(Floor(gp[1] / 14) + dx) * 4096 + Floor(gp[2] / 14) + A_Index - 2] := 1
        }
}
; Before the match starts (vote screen): hold the first hill unit to see
; the hills. No hill on screen -> walk W/D/S/A (HillWalk s each) until one
; shows up and STAY there, so every hill unit can be placed from this spot.
; A way with no hill is walked back before trying the next one.
HillScan() {
    slot := 0
    Loop 6
        if IsHill(A_Index) {
            slot := A_Index
            break
        }
    if !slot
        return
    if LookHere(slot, &m) {
        RS.hillScan := m
        Out("Hill check (unit " slot "): hills on screen")
        return
    }
    t := CFG.Get("HillWalk", 2.5) + 0
    dirs := ["w", "d", "s", "a"], back := Map("w", "s", "s", "w", "a", "d", "d", "a")
    if RS.HasOwnProp("hillDir") {                  ; the way that worked last time first
        for i, d in dirs
            if (d = RS.hillDir) {
                dirs.RemoveAt(i), dirs.InsertAt(1, d)
                break
            }
    }
    Out("Hill check (unit " slot "): no hill on screen - walking to find one before the start")
    for d in dirs {
        Walk(d, t)
        if LookHere(slot, &m) {
            RS.hillScan := m, RS.hillDir := d
            Out("  hills found walking " StrUpper(d) " - staying here")
            return
        }
        Walk(back[d], t)
    }
    RS.hillScan := Map()
    Out("  no hill found in any direction - hill units will look again during the match")
}
; hold a hill unit, read the new green points, put it back -> count, &cells
HillLook(slot, &m) {
    Focus()
    MouseMove(PX(960), PY(120))
    Snap()
    before := GreenGrid()
    Key(slot)
    Wait(300)
    Loop 3 {
        Snap()
        m := Map(), n := 0
        for k, gp in GreenGrid()
            if !before.Has(k) {
                n++
                Loop 3 {
                    dx := A_Index - 2
                    Loop 3
                        m[(Floor(gp[1] / 14) + dx) * 4096 + Floor(gp[2] / 14) + A_Index - 2] := 1
                }
            }
        if (n >= 8 || A_Index = 3 || HeldHint())   ; green seen, or the unit is in hand (no hill here)
            break
        Focus()                                    ; not in hand: click it on the hotbar, then the key again
        if (A_Index = 1)
            ClickRef(746 + (slot - 1) * 84, 1003, "c", "b"), MouseMove(PX(960), PY(120))
        else
            Key(slot)
        Wait(350)
        Out("  hill check: unit " slot " was not in hand - " (A_Index = 1 ? "clicked it on the hotbar" : "pressed " slot " again"))
    }
    Key("q")
    Wait(200)
    return n
}
; spots inside the green zones, ordered by the placing style
HillCands(zone, style, pt0, slot, path, cells) {
    zm := Map()
    for gp in zone
        zm[gp[1] * 4096 + gp[2]] := 1
    ps := [], stp := Max(1, path.Length // 300), i := 1
    while (i <= path.Length)
        ps.Push(path[i]), i += stp
    pool := [], tries := 0, need := 3              ; green neighbours wanted (of 4)
    while (pool.Length < 120 && tries < 2000) {
        tries++
        if (tries = 1000 && pool.Length < 5)       ; thin hills: accept edge spots too
            need := 1
        gp := zone[Random(1, zone.Length)]
        x := gp[1], y := gp[2]
        ; inside the zone: most grid points around it are green too
        nb := zm.Has((x + 12) * 4096 + y) + zm.Has((x - 12) * 4096 + y)
            + zm.Has(x * 4096 + y + 12) + zm.Has(x * 4096 + y - 12)
        if (nb < need)
            continue
        if (InUi(x, y) || NearPath(cells, x, y, 8))
            continue
        ok := true
        for v in MT.units
            if (Abs(v.x - x) < 32 && Abs(v.y - y) < 28)
                ok := false
        for bd in MT.bad
            if (Abs(bd.x - x) < 16 && Abs(bd.y - y) < 14)
                ok := false
        for c in pool
            if (Abs(c.x - x) < 18 && Abs(c.y - y) < 16)
                ok := false
        if ok
            pool.Push({x: x + Random(-4, 4), y: y + Random(-4, 4)})
    }
    Out("  unit " slot ": hill zone " zone.Length " points, " pool.Length " spots to try")
    anc := (style = "group") ? GroupAnchor(slot) : ""
    return ScoreCands(pool, style, ps, pt0, anc)
}
Walk(k, sec, run := -1) {
    Focus()
    if (run < 0)
        run := CFG.Get("HillRun", 1) + 0           ; hold Shift = run
    if run
        Send("{LShift down}")
    Send("{" k " down}")
    Sleep(Round(sec * 1000))
    Send("{" k " up}")
    if run
        Send("{LShift up}")
    Sleep(250)
}
; Stage name, read on the loading / vote screens. StageWalk lists stages
; where the start spot is too far from the path: "Magic Hill=a 3 jump|Other=d 2, w 1"
; = on Magic Hill run A for 3 s before the hill check and the start.
StageCheck(t) {
    if (RS.stage != "" || Trim(CFG["StageWalk"]) = "")
        return
    tt := MapKey(t)                                ; OCR may drop spaces or read l as I
    for e in StrSplit(CFG["StageWalk"], "|") {
        p := StrSplit(e, "=", " `t", 2)
        if (p.Length = 2 && MapKey(p[1]) != "" && InStr(tt, MapKey(p[1]))) {
            RS.stage := p[1], RS.stageMove := p[2], RS.stageWalked := false
            Out("Stage: " p[1] " (StageWalk " p[2] ")")
            return
        }
    }
}
StageWalk() {
    if (RS.stage = "" || RS.stageWalked)
        return
    RS.stageWalked := true
    for mv in StrSplit(RS.stageMove, ",") {        ; several moves: "d 3 jump, w 1 jump"
        if !RegExMatch(mv, "i)^\s*([wasd])\s*([\d.]+)\s*(j)?", &mm) {
            Out("  StageWalk for " RS.stage ": cannot read '" Trim(mv) "' (write it like: a 3 jump)")
            continue
        }
        jump := (mm[3] != "")
        Out("  " RS.stage ": running " (jump ? "+ jumping " : "") StrUpper(mm[1]) " for " mm[2] " s before the start")
        if jump
            RunJump(StrLower(mm[1]), mm[2] + 0)
        else
            Walk(StrLower(mm[1]), mm[2] + 0, 1)
    }
    Wait(300)
}
; run (Shift) one way and jump (Space) all the time
RunJump(k, sec) {
    Focus()
    Send("{LShift down}")
    Send("{" k " down}")
    t := A_TickCount
    while (A_TickCount - t < sec * 1000) {
        Send("{Space down}")
        Sleep(80)
        Send("{Space up}")
        Sleep(270)
    }
    Send("{" k " up}")
    Send("{LShift up}")
    Sleep(250)
}
; look for hills here; if none, zoom in a little at a time (HillZoomStep
; notches, HillZoomTries times). Found after zooming -> keep that zoom.
; Not found -> zoom back out to where it was.
LookHere(slot, &m) {
    if (HillLook(slot, &m) >= 8)
        return true
    zs := CFG.Get("HillZoomStep", 3) + 0, zt := CFG.Get("HillZoomTries", 2) + 0
    if (zs <= 0 || zt <= 0)
        return false
    Loop zt {
        ZoomBy(zs)
        if (HillLook(slot, &m) >= 8) {
            LockZoom(zs * A_Index)
            return true
        }
    }
    ZoomBy(-zs * zt)
    return false
}
; the same for placing: try PlaceUnit, zooming in step by step while it
; sees no hill
PlaceZoomed(slot, style, pt0) {
    r := PlaceUnit(slot, style, pt0)
    zs := CFG.Get("HillZoomStep", 3) + 0, zt := CFG.Get("HillZoomTries", 2) + 0
    if (r != "nozone" || zs <= 0 || zt <= 0)
        return r
    Loop zt {
        CloseOverview()
        ZoomBy(zs)
        r := PlaceUnit(slot, style, pt0)
        if (r != "nozone") {
            LockZoom(zs * A_Index)
            return r
        }
    }
    CloseOverview()
    ZoomBy(-zs * zt)
    return "nozone"
}
; place any unit; a hill unit with no hill on screen walks W/D/S/A to look
; for one, and always walks back to where it started
PlaceAny(slot, style := "random", pt0 := "") {
    r := IsHill(slot) ? PlaceZoomed(slot, style, pt0) : PlaceUnit(slot, style, pt0)
    if (r != "nozone")
        return r
    t := CFG.Get("HillWalk", 2.5) + 0
    dirs := ["w", "d", "s", "a"], back := Map("w", "s", "s", "w", "a", "d", "d", "a")
    if MT.HasOwnProp("hillDir") {                  ; the way that worked last time first
        for i, d in dirs
            if (d = MT.hillDir) {
                dirs.RemoveAt(i), dirs.InsertAt(1, d)
                break
            }
    }
    Out("  unit " slot ": no hill on screen - walking to look for one (" t " s each way)")
    for d in dirs {
        if MatchOver()
            return "end"
        CloseOverview()
        Walk(d, t)
        MT.walked := true
        r := PlaceZoomed(slot, style, pt0)
        Key("q")
        CloseOverview()
        Walk(back[d], t)                           ; back to the start position
        MT.walked := false
        if (r = "ok" || r = "fail") {              ; found hills that way
            MT.hillDir := d
            if (r = "ok") {
                u := MT.units[MT.units.Length]     ; its screen spot was from the moved camera
                u.x := -999, u.y := -999
            }
            Out("  unit " slot ": hills found walking " StrUpper(d) (r = "ok" ? " - placed" : " - could not place there"))
            return r
        }
        if (r = "cap")
            return r
    }
    Out("  unit " slot ": no hill found in any direction - skipping this unit this match")
    MT.capped[slot] := true
    return "cap"
}

; Placing styles (plan.txt: place 1 x3 far / place 3 x2 at 900,500 ...)
;   random  a random spot 30-120 px off the path (default)
;   near    as close to the path as the game allows
;   far     as far from the path as possible (farm units)
;   group   next to this unit's first copy / the last "group" unit
;   spread  as far from the other units as possible, still near the path
;   cover   where the path passes most (curves, corners)
;   center  nearest to the middle of the screen
;   at X,Y  at a fixed spot (1920x1080 screen pixels), the nearest free one
PlaceCands(style, pt0, slot, path, cells, gap, tinted) {
    ps := [], stp := Max(1, path.Length // 300), i := 1
    while (i <= path.Length)
        ps.Push(path[i]), i += stp
    pool := [], anc := ""
    if (style = "at" && IsObject(pt0)) {
        for rr in [0, 22, 40, 60, 85, 115, 150, 190] {
            nA := (rr = 0) ? 1 : Round(rr / 6)
            Loop nA {
                a := 6.2832 * A_Index / nA + Random(0.0, 0.3)
                AddCand(pool, cells, pt0.x + Cos(a) * rr, pt0.y + Sin(a) * rr * 0.85, 10, 300)
            }
        }
    } else {
        for gd in MT.good                            ; ground that already worked
            Loop 6 {
                a := Random(0.0, 6.2832), d := Random(34.0, 85.0)
                if AddCand(pool, cells, gd.x + Cos(a) * d, gd.y + Sin(a) * d * 0.85, gap, 300)
                    pool[pool.Length].g := true
            }
        anc := (style = "group") ? GroupAnchor(slot) : ""
        if IsObject(anc)
            Loop 250 {
                a := Random(0.0, 6.2832), d := Random(32.0, 80.0)
                AddCand(pool, cells, anc.x + Cos(a) * d, anc.y + Sin(a) * d * 0.85, gap, 300)
            }
        dMin := (style = "near") ? 22.0 : 30.0, dMax := (style = "near") ? 60.0 : 120.0
        target := (style = "random") ? 45 : 110      ; random needs no ranking
        if (!tinted && style != "far") {
            n := 0
            Loop 600 {
                if (++n > target)
                    break
                p := path[Random(1, path.Length)]
                a := Random(0.0, 6.2832), d := Random(dMin, dMax)
                if !AddCand(pool, cells, p[1] + Cos(a) * d, p[2] + Sin(a) * d * 0.85, gap, 300)
                    n--
            }
        }
        if (style = "far" || pool.Length < 12) {     ; anywhere on the map
            n := 0
            Loop 1500 {
                if (n >= target)
                    break
                if AddCand(pool, cells, Random(150.0, 1760.0), Random(180.0, 890.0), gap, 300)
                    n++
            }
        }
    }
    return ScoreCands(pool, style, ps, pt0, anc)
}

; order candidate spots by the placing style, best first (max 40)
ScoreCands(pool, style, ps, pt0, anc) {
    for c in pool {
        switch style {
            case "near":   c.s := -MinDist(ps, c.x, c.y)
            case "far":                            ; far, but not out in the void
                d := MinDist(ps, c.x, c.y), c.s := (d <= 230) ? d : 230 - (d - 230) * 0.6
            case "cover":  c.s := CountNear(ps, c.x, c.y, 170)
            case "spread": c.s := MinUnitDist(c.x, c.y) + CountNear(ps, c.x, c.y, 150) * 0.3
            case "center": c.s := -Sqrt((c.x - 960) ** 2 + (c.y - 540) ** 2)
            case "at":     c.s := IsObject(pt0) ? -Sqrt((c.x - pt0.x) ** 2 + (c.y - pt0.y) ** 2) : 0
            case "group":
                c.s := IsObject(anc) ? -Sqrt((c.x - anc.x) ** 2 + (c.y - anc.y) ** 2) : CountNear(ps, c.x, c.y, 170)
            default:       c.s := Random(0.0, 1.0) + (c.HasOwnProp("g") ? 1 : 0)
        }
    }
    sorted := []
    for c in pool {
        i := sorted.Length + 1
        while (i > 1 && sorted[i - 1].s < c.s)
            i--
        sorted.InsertAt(i, c)
    }
    if (sorted.Length > 40)
        sorted.RemoveAt(41, sorted.Length - 40)
    return sorted
}
MinDist(ps, x, y) {
    best := 999999
    for p in ps {
        d := (p[1] - x) ** 2 + (p[2] - y) ** 2
        if (d < best)
            best := d
    }
    return Sqrt(best)
}
CountNear(ps, x, y, r) {
    n := 0, r2 := r * r
    for p in ps
        n += ((p[1] - x) ** 2 + (p[2] - y) ** 2 <= r2)
    return n
}
MinUnitDist(x, y) {
    best := 1000
    for v in MT.units
        best := Min(best, Sqrt((v.x - x) ** 2 + (v.y - y) ** 2))
    return best
}
GroupAnchor(slot) {
    for v in MT.units
        if (v.slot = slot && v.x >= 0)
            return {x: v.x, y: v.y}
    return MT.HasOwnProp("lastGroup") ? MT.lastGroup : ""
}

PlaceUnit(slot, style := "random", pt0 := "") {
    Focus()
    ; Unit Overview stays open on the right: its cards prove a placement
    ; at once, and no time is lost opening/closing it. Spots under it are
    ; skipped. The unit panel on the left (with its Sell button!) is closed.
    CloseUnitPanel()
    n0 := -1
    if !MT.HasOwnProp("streak")
        MT.streak := 0
    wide := (MT.streak >= 1 || MT.HasOwnProp("wideMode")   ; panel side failed once,
        || (style = "at" && IsObject(pt0) && pt0.x > 1180)     ; or the spot is under it,
        || IsHill(slot))                                       ; or hills (often under it):
    if wide                                        ; use the whole map, check by yen
        CloseOverview()
    else if (MT.units.Length < 8) {
        ov := OverviewOpen()
        n0 := ov.open ? 1 : -1
    }
    MT.ovOpen := (n0 >= 0)
    ; no card check (whole map, or 8+ units = more than the panel shows):
    ; the yen must drop instead. Without it, a click on a unit already
    ; standing there also cleared the red path and counted as "placed".
    yen0 := (n0 < 0) ? ReadYen() : -1
    MouseMove(PX(960), PY(120))                    ; off the ground first
    Snap()
    base := (n0 >= 0) ? Max(ScanCards().Length, MT.units.Length) : 0
    before := RedGrid()                            ; red things that are part of the map
    beforeG := IsHill(slot) ? GreenGrid() : ""     ; green things that are part of the map
    Key(slot)
    Wait(170)
    Snap()
    path := []
    for k, pt in RedGrid()
        if !before.Has(k)
            path.Push(pt)
    ; Is the unit really in hand? Held = red path + "Place / Rotate / Cancel"
    ; next to the mouse. Not held (key lost, game not focused): press the
    ; unit's picture on the hotbar, then press the key again.
    if (path.Length < 20 && !HeldHint()) {
        Loop 2 {
            Focus()
            if (A_Index = 1)                        ; click the unit on the hotbar (bottom)
                ClickRef(746 + (slot - 1) * 84, 1003, "c", "b"), MouseMove(PX(960), PY(120))
            else
                Key(slot)
            Wait(300)
            Snap()
            path := []
            for k, pt in RedGrid()
                if !before.Has(k)
                    path.Push(pt)
            if (path.Length >= 20 || HeldHint()) {
                Out("  unit " slot " was not in hand - " (A_Index = 1 ? "clicked it on the hotbar" : "pressed " slot " again"))
                break
            }
        }
    }
    if (path.Length < 20 && FixFirstPerson())      ; first person hides the path
        return "fail"
    if (path.Length < 20) {                        ; nothing in hand (a real path is long)
        if !MT.HasOwnProp("noPathLogged") {
            MT.noPathLogged := true
            c := Color(PX(960), PY(540))
            Out("  unit " slot ": no red path seen after pressing " slot " (" path.Length " points, centre colour "
                . Format("{:06X}", c) ")")
            Shot("nopath")                          ; picture of the held unit's path colour, for fixing
        }
        t := OcrRef(300, 520, 1620, 900, 1)
        if (IsObject(t) && RegExMatch(t.t, "i)Cannot\s*place\s*more\s*than\s*(\d+)", &m)) {
            Out("  unit " slot ": the game allows only " m[1])
            MT.capped[slot] := true
            return "cap"
        }
        Key("q")
        Wait(300)
        return "fail"
    }
    cells := Map()
    for pt in path
        cells[Floor(pt[1] / 14) * 4096 + Floor(pt[2] / 14)] := 1
    hill := IsHill(slot)
    if hill {                                      ; hill unit: only the green zones
        zone := []
        for k, gp in GreenGrid()
            if !beforeG.Has(k)
                zone.Push(gp)
        if (zone.Length < 8) {
            Key("q")                               ; no hill on this screen
            Wait(250)
            return "nozone"
        }
        if !MT.HasOwnProp("walked") || !MT.walked
            RememberHills(zone)
    }
    ; Some maps tint everything you can't build on red, not only the path.
    ; Then "near the path" means nothing: look for the non-red pockets.
    tinted := (path.Length > 1800)
    gap := tinted ? 8 : 26
    if (tinted && !MT.HasOwnProp("tintLogged")) {
        MT.tintLogged := true
        Out("  map turns red almost everywhere (" path.Length " red points) - looking for clear pockets")
    }
    if !MT.HasOwnProp("good")
        MT.good := []
    cands := hill ? HillCands(zone, style, pt0, slot, path, cells)
        : PlaceCands(style, pt0, slot, path, cells, gap, tinted)
    if (cands.Length = 0 && MT.bad.Length) {
        MT.bad := []
        Out("  every spot failed once - trying them again")
    }
    ; a few path points to watch: red gone = unit placed
    watch := []
    Loop Min(30, path.Length)
        watch.Push(path[Random(1, path.Length)])
    fails := 0
    for c in cands {
        ClickRef(c.x, c.y)
        Wait(130)
        Snap()
        red := 0
        for pt in watch
            red += IsRed(Color(PX(pt[1]), PY(pt[2])))
        if (red * 4 < watch.Length) {              ; the path is not red any more
            if !MT.HasOwnProp("fake")
                MT.fake := Map()
            if (n0 >= 0 && MT.fake.Get(slot, 0) < 3) { ; did a card really appear?
                ; the game also drops the unit from the hand when the spot is
                ; refused or the unit limit is reached - check what happened
                got := -1
                Loop 10 {                          ; the new card shows within ~1.5 s
                    Wait(150)
                    Snap()
                    got := ScanCards().Length
                    if (got > base)
                        break
                }
                if (got >= 0 && got <= base) {
                capT := OcrRef(300, 520, 1620, 900, 1)
                if (IsObject(capT) && RegExMatch(capT.t, "i)Cannot\s*place\s*more\s*than\s*(\d+)", &m)) {
                    Out("  unit " slot ": the game allows only " m[1])
                    MT.capped[slot] := true
                    return "cap"
                }
                    MT.fake[slot] := MT.fake.Get(slot, 0) + 1
                    Out("  unit " slot ": not really placed at " Round(c.x) "," Round(c.y) " (cards " got ") - trying again")
                    if (MT.fake[slot] = 3)
                        Out("  unit " slot ": card check keeps failing here - trusting the red path from now on")
                    MT.bad.Push(c)
                    return "fail"
                }
            }
            if (n0 < 0 && yen0 > 0) {              ; no card check: the yen must drop
                drop := Min(CFG["Cost" slot] * 0.5, 250) ; the price in settings may be off
                y1 := -1
                Loop 5 {
                    Wait(150)
                    y1 := ReadYen()
                    if (y1 >= 0 && y1 <= yen0 - drop)
                        break
                }
                if (y1 >= 0 && y1 > yen0 - drop) {
                    capT := OcrRef(300, 520, 1620, 900, 1)
                    if (IsObject(capT) && RegExMatch(capT.t, "i)Cannot\s*place\s*more\s*than\s*(\d+)", &m)) {
                        Out("  unit " slot ": the game allows only " m[1])
                        MT.capped[slot] := true
                        return "cap"
                    }
                    Out("  unit " slot ": not really placed at " Round(c.x) "," Round(c.y) " (yen " yen0 " -> " y1 ") - trying again")
                    MT.bad.Push(c)
                    return "fail"
                }
            }
            MT.streak := 0
            if MT.HasOwnProp("fake") && MT.fake.Get(slot, 0) < 3
                MT.fake[slot] := 0
            n := 1
            for v in MT.units
                n += (v.slot = slot) ? 1 : 0
            MT.units.Push({slot: slot, n: n, x: c.x, y: c.y, lvl: 0, maxed: false, style: style, pt: pt0})
            MT.good.Push({x: c.x, y: c.y})
            if (style = "group" && !MT.HasOwnProp("lastGroup"))
                MT.lastGroup := {x: c.x, y: c.y}
            Out("  placed unit " slot " #" n " at " Round(c.x) "," Round(c.y) " (try " fails + 1
                . (style != "random" ? ", " style : "") ")")
            return "ok"
        }
        MT.bad.Push(c)
        if (Mod(++fails, 6) = 0) {
            t := OcrRef(300, 520, 1620, 900, 1)
            if (IsObject(t) && RegExMatch(t.t, "i)Cannot\s*place\s*more\s*than\s*(\d+)", &m)) {
                Out("  unit " slot ": the game allows only " m[1])
                MT.capped[slot] := true
                Key("q")
                return "cap"
            }
        }
    }
    Key("q")                                        ; drop the unit from hand
    MT.streak := wide ? 0 : MT.streak + 1
    if !wide {                                     ; this map: whole map from now on
        MT.wideMode := true
        Out("  unit " slot ": no spot worked beside the panel - using the whole map from now on")
    }
    return "fail"
}

; ----------------------------------------------------------- upgrades
; Unit Overview (F): every placed unit as a card with a green
; "Upg: 2200¥" button or "Max". Cards are listed by hotbar slot, highest
; slot first, then in placing order.
OverviewOpen() {
    r := OverviewRead()
    if r.open
        return r
    Focus()
    MT.ovOk := false                               ; just opened: where the list stands is unknown
    Key("f")
    Wait(700)
    r := OverviewRead()
    if !r.open {
        ClickRef(1868, 540, "r", "c")              ; the yellow F button
        Wait(700)
        r := OverviewRead()
    }
    return r
}

; the red Return button under the Unit Overview list
; (5 spots, 4 must be red: the "Activate Windows" text can lie over its top)
OverviewReturnVisible() {
    n := 0
    for pt in [[1471, 973], [1576, 968], [1685, 973], [1490, 1005], [1690, 1005]] {
        c := RGB(Color(PX(pt[1], "r"), PY(pt[2])))
        n += (c.r > 175 && c.g < 50 && c.b < 50)
    }
    return n >= 4
}

; the unit panel on the left (opened by clicking a unit): red X + cyan First.
; It sits a bit lower on some screens (stats row above it): look for the
; red X circle in an area, not at one spot. &x/&y = the X (screen).
UnitPanelVisible(&x := 0, &y := 0) {
    n := 0, sx := 0, sy := 0
    yy := 300
    while (yy <= 410) {
        xx := 490
        while (xx <= 620) {
            c := RGB(Color(PX(xx, "l"), PY(yy)))
            if (c.r > 190 && c.g < 50 && c.b < 50)
                n++, sx += xx, sy += yy
            xx += 4
        }
        yy += 4
    }
    if (n < 25)
        return false
    cy := 0
    yy := 630
    while (yy <= 690) {                            ; the cyan First button under it
        xx := 30
        while (xx <= 160) {
            cy += IsCyan(Color(PX(xx, "l"), PY(yy)))
            xx += 6
        }
        yy += 6
    }
    if (cy < 10)
        return false
    x := PX(sx / n, "l"), y := PY(sy / n)
    return true
}
CloseUnitPanel() {
    Snap()
    if !UnitPanelVisible(&x, &y)
        return false
    Loop 2 {
        ClickAt(x, y)                              ; its red X
        Wait(350)
        Snap()
        if !UnitPanelVisible(&x, &y)
            return true
    }
    return false
}
; close every unit window that covers the screen. true = something was closed
CloseUi() {
    a := CloseUnitPanel()
    b := CloseOverview()
    return a || b
}

; close Unit Overview if it is open (it covers the room tiles and buttons).
; Only its red Return button counts as "open", and only Return is clicked:
; pressing F here would open it again on screens where it was closed.
; true = it was open and is closed now
CloseOverview() {
    Snap()
    if !OverviewReturnVisible()
        return false
    Loop 2 {
        ClickRef(1576, 985, "r", "c")              ; Return
        Wait(450)
        Snap()
        if !OverviewReturnVisible()
            return true
    }
    return false
}

; Cards are found from their pixels, not OCR (OCR missed the greyed
; "Upg" buttons, which shifted every card after it). Each card has a
; cyan "First" button; the Upg button is 45 above it, the bar under it.
; card = {x, y (Upg button centre), buy (button bright = enough yen), max}
IsCyan(col) {
    r := (col >> 16) & 0xFF, g := (col >> 8) & 0xFF, b := col & 0xFF
    return (b > 200 && g > 150 && r < 90)
}

ScanCards() {
    u := WIN.u, cards := []
    for bx in [1491, 1776] {
        sx := PX(bx - 30, "r")
        y := PY(150), yEnd := PY(1000), runLen := 0, top := 0
        while (y <= yEnd) {
            c := RGB(Color(sx, y))
            cyan := (c.b > 200 && c.g > 150 && c.r < 90)
            if cyan {
                if !runLen
                    top := y
                runLen++
            } else if runLen {
                fy := top + runLen // 2
                ; a real "First" button: button height, and cyan on its right
                ; side too, past the white text (cyan map stuff behind the
                ; see-through panel is not shaped like that)
                if (runLen >= 26 * u && runLen <= 50 * u && top > PY(152)
                    && IsCyan(Color(PX(bx + 45, "r"), fy))) {
                    uy := fy - 45 * u
                    g := RGB(Color(sx, uy - 13 * u))
                    cards.Push({x: PX(bx, "r"), y: uy, buy: (g.g > 170 && g.r < 130 && g.b < 100), max: false, cost: -1})
                }
                runLen := 0
            }
            y += 1
        }
    }
    ; grid order: row by row, left card first
    res_ := []
    for c in cards {
        i := res_.Length + 1
        while (i > 1 && (res_[i - 1].y - c.y > 40 * u || (Abs(res_[i - 1].y - c.y) <= 40 * u && res_[i - 1].x > c.x)))
            i--
        res_.InsertAt(i, c)
    }
    return res_
}

OverviewRead() {
    Snap()
    cards := ScanCards()
    open := cards.Length > 0 || OverviewReturnVisible()
    return {open: open, cards: cards}
}

; The segmented bar under a card = its upgrade level: lit (bright)
; segments = levels bought, dark segments = levels left. -> {lvl, max}
CardLevel(c) {
    Snap()
    u := WIN.u
    best := ""
    for dy in [98, 94, 102, 90, 106] {
        y := c.y + dy * u
        segs := [], cur := ""
        x := c.x - 182 * u
        while (x <= c.x + 68 * u) {
            col := RGB(Color(x, y))
            mx := Max(col.r, col.g, col.b), mn := Min(col.r, col.g, col.b)
            if (mx < 0x1c || mx - mn < 0x20) {             ; gap / border
                if IsObject(cur)
                    segs.Push(cur), cur := ""
            } else {
                if !IsObject(cur)
                    cur := {n: 0, bright: 0}
                cur.n++
                cur.bright += (mx >= 0x90) ? 1 : 0
            }
            x += 1
        }
        if IsObject(cur)
            segs.Push(cur)
        lit := 0, total := 0
        for sg in segs {
            if (sg.n < 8 * u)
                continue
            total++
            lit += (sg.bright * 2 > sg.n) ? 1 : 0
        }
        if (total >= 3 && total <= 15)
            return {lvl: lit, max: total}
    }
    return {lvl: -1, max: -1}
}

; scroll the Unit Overview list - ONLY when it is really open and the
; mouse is over the list. A wheel over the map zooms the camera, and
; WheelUp there goes all the way into first person (mouse gets locked).
OverviewScroll(dir) {
    if IsObject(MT)
        MT.ncAt := 0, MT.pn := Map()               ; card names moved: read them again
    ; The list only eats the wheel while it CAN scroll. At its top a WheelUp
    ; goes to the camera instead (zoom in -> first person). So: tiny steps,
    ; look after each one, stop at the end of the list.
    ; - panel must stand still: same cards in the same place twice
    Snap()
    a := ScanCards()
    if !(OverviewReturnVisible() && a.Length)
        return false
    MouseMove(PX(1580, "r"), PY(540))
    Wait(250)
    Snap()
    b := ScanCards()
    if !(OverviewReturnVisible() && b.Length = a.Length
        && Abs(b[1].x - a[1].x) < 4 && Abs(b[1].y - a[1].y) < 4)
        return false
    MouseGetPos(&mx)
    if (mx < PX(1300, "r"))                        ; mouse must be over the list
        return false
    topY := PY(244)                                ; Upg button of the top row when at the top
    Loop 12 {
        if (dir = "WheelUp" && Abs(b[1].y - topY) < 12 * WIN.u) {
            MT.ovOff := 0, MT.ovOk := true         ; at the top: list position known
            return true                            ; already at the top - no wheel at all
        }
        before := b[b.Length].y, prev := b
        Click dir
        Wait(160)
        Snap()
        b := ScanCards()
        if !b.Length
            return false
        if (Abs(b[b.Length].y - before) < 3) {     ; did not move = end of the list
            if (dir = "WheelUp")                   ; that notch zoomed the camera in - undo it
                ZoomOutKeys(2)
            return true
        }
        d := ListShift(prev, b, dir)               ; how far the list moved (card numbers)
        if (d = "")
            MT.ovOk := false
        else if MT.HasOwnProp("ovOff")
            MT.ovOff += d
    }
    return true
}

; first person: Roblox keeps pulling the mouse back to the middle
IsFirstPerson() {
    MouseMove(PX(400), PY(300))
    Sleep 150
    MouseGetPos(&mx, &my)
    return (Abs(mx - PX(960)) < 25 && Abs(my - PY(540)) < 25)
}
FixFirstPerson() {
    if !IsFirstPerson()
        return false
    Out("  camera was in first person - fixing it")
    CameraSetup()                                  ; zooms in then out to the top view
    if IsFirstPerson()
        ZoomOutKeys(25)
    return true
}

; first person locks the mouse in the middle - zoom back out with O
; camera distance in wheel notches out from fully zoomed in: the setting
; CamZoom, or the closer one locked when hills only showed after zooming in
CamZoomNow() {
    z := RS.HasOwnProp("zoomLock") ? RS.zoomLock : CFG.Get("CamZoom", 24) + 0
    return Max(0, Min(30, Round(z)))
}
; n > 0 zooms in, n < 0 zooms out (mouse over the middle of the map)
ZoomBy(n) {
    Focus()
    MouseMove(Round(PX(960)), Round(PY(540)))
    Sleep 60
    Loop Abs(n) {
        Click(n > 0 ? "WheelUp" : "WheelDown")
        Sleep 40
    }
    Sleep 250
}
LockZoom(stepsIn) {
    RS.zoomLock := Max(0, CamZoomNow() - stepsIn)
    Out("  camera zoom locked at " RS.zoomLock " (hills showed after zooming in)")
}

ZoomOutKeys(n := 15) {
    Focus()
    Loop n {
        Send "{o down}"
        Sleep 30
        Send "{o up}"
        Sleep 30
    }
}

; Card names (bottom of the portrait, e.g. "Idol (Star)") tell which card
; belongs to which hotbar slot when the slot has a name in settings
; (Name1..Name6). One OCR of the panel, kept for 3 s.
CardNames(cards) {
    if (MT.HasOwnProp("ncAt") && A_TickCount - MT.ncAt < 3000 && MT.ncN = cards.Length
        && cards.Length && MT.ncY = cards[1].y)
        return MT.ncNames
    names := []
    u := WIN.u
    ws := cards.Length ? Words(OcrRect(PX(1290, "r"), PY(190), PX(1870, "r"), PY(945), 3)) : []
    for c in cards {
        parts := []
        for w in ws
            if (w.x >= c.x - 175 * u && w.x <= c.x - 50 * u && w.y >= c.y + 44 * u && w.y <= c.y + 78 * u) {
                i := parts.Length + 1
                while (i > 1 && parts[i - 1].x > w.x)
                    i--
                parts.InsertAt(i, w)
            }
        t := ""
        for p in parts
            t .= p.t " "
        names.Push(Trim(t))
    }
    for i, c in cards                              ; nothing read (e.g. "C.E.O."): this card alone, bigger
        if (names[i] = "") {
            t := ""
            for w in Words(OcrRect(c.x - 175 * u, c.y + 44 * u, c.x - 50 * u, c.y + 78 * u, 5))
                t .= w.t " "
            names[i] := Trim(t)
        }
    MT.ncAt := A_TickCount, MT.ncN := cards.Length, MT.ncY := cards.Length ? cards[1].y : 0, MT.ncNames := names
    return names
}
NormName(t) => RegExReplace(StrLower(t), "[^a-z0-9]")
; how well a card text fits a unit name, 0..1 (cut-off names, OCR typos)
NameScore(ocrText, name) {
    a := NormName(ocrText), b := NormName(name)
    if (StrLen(a) < 2 || StrLen(b) < 2)
        return 0
    if (InStr(a, b) || (StrLen(a) >= 3 && InStr(b, a)))
        return 1
    L := CommonRun(a, b)
    best := (L >= 3) ? L / Min(StrLen(a), StrLen(b)) : 0
    fw := NormName(RegExReplace(Trim(name), "\s.*$"))   ; first word of the name ("Vego")
    if (StrLen(fw) >= 3)
        for w in StrSplit(RegExReplace(ocrText, "[^A-Za-z0-9.]", " "), " ") {
            w := NormName(w)
            if (StrLen(w) >= 3)                    ; "Vege" for "Vego" = 0.75
                best := Max(best, 1 - NameDist(w, fw) / Max(StrLen(w), StrLen(fw)))
        }
    return best
}
; the named slot a card belongs to (best score >= 0.6), or 0
CardSlot(text) {
    bestS := 0, bestV := 0.6
    Loop 6 {
        nm := Trim(CFG.Get("Name" A_Index, ""))
        if (nm = "")
            continue
        v := NameScore(text, nm)
        if (v > bestV || (v = bestV && !bestS))
            bestV := v, bestS := A_Index
    }
    return bestS
}
NameMatch(ocrText, name) {
    a := NormName(ocrText), b := NormName(name)
    if (StrLen(a) < 2 || StrLen(b) < 2)
        return false
    if (InStr(a, b) || (StrLen(a) >= 3 && InStr(b, a)))
        return true
    ; long names are cut on the card ("Dark Mage (Fallen" for "Dark Mage (Fallen Star)")
    ; and OCR adds junk: a long enough common piece is a match
    L := CommonRun(a, b)
    if (StrLen(b) > 3 && (L >= Min(StrLen(b), 6) || (L >= 4 && L >= 0.6 * Min(StrLen(a), StrLen(b)))))
        return true
    return NameDist(SubStr(a, 1, StrLen(b)), b) <= Max(1, StrLen(b) // 4)
}
; length of the longest common substring
CommonRun(a, b) {
    best := 0, la := StrLen(a), lb := StrLen(b)
    Loop la {
        i := A_Index
        Loop lb {
            j := A_Index, n := 0
            while (i + n <= la && j + n <= lb && SubStr(a, i + n, 1) = SubStr(b, j + n, 1))
                n++
            best := Max(best, n)
        }
    }
    return best
}
NameDist(a, b) {                                   ; edit distance (Lev() above gives up early)
    la := StrLen(a), lb := StrLen(b)
    if !la
        return lb
    prev := []
    Loop lb + 1
        prev.Push(A_Index - 1)
    Loop la {
        i := A_Index, cur := [i], ca := SubStr(a, i, 1)
        Loop lb {
            j := A_Index
            cost := (ca = SubStr(b, j, 1)) ? 0 : 1
            cur.Push(Min(prev[j + 1] + 1, cur[j] + 1, prev[j] + cost))
        }
        prev := cur
    }
    return prev[lb + 1]
}
; the card of unit u found by its slot's name -> card or ""
; the unit's name as its big panel (left) shows it: click the picture on
; the card, read the title, close the panel. Kept per card spot.
PanelName(c, count) {
    if (!MT.HasOwnProp("pn") || !MT.HasOwnProp("pnN") || MT.pnN != count)
        MT.pn := Map(), MT.pnN := count
    key := Round(c.x) "|" Round(c.y)
    if MT.pn.Has(key)
        return MT.pn[key]
    CloseUnitPanel()
    ClickAt(c.x - 112 * WIN.u, c.y + 22 * WIN.u)
    Wait(500)
    r := OcrRef(20, 325, 295, 400, 2, "l", "c")          ; title only (Upgrade [n] sits right of it)
    t := IsObject(r) ? Trim(RegExReplace(r.t, "\s+", " ")) : ""
    CloseUnitPanel()
    MT.pn[key] := t
    if (t != "")
        Out("  card at " Round(c.x) "," Round(c.y) " is " t " (read from its panel)")
    return t
}

CardByName(u, nm) {
    k := 0, total := 0                             ; u is copy k of total
    for v in MT.units
        if (v.slot = u.slot) {
            total++
            if (v = u)
                k := total
        }
    Loop 3 {                                       ; visible part, scrolled down, back up
        r := (A_Index = 1) ? OverviewOpen() : OverviewRead()
        if !r.open
            return ""
        names := CardNames(r.cards)
        mine := 0
        for i, c in r.cards
            mine += (CardSlot(names[i]) = u.slot)
        if (mine < k) {                            ; small names not enough: ask the big panel
            for i, c in r.cards
                if !CardSlot(names[i]) {
                    t := PanelName(c, r.cards.Length)
                    if (t != "")
                        names[i] := t
                }
        }
        hits := [], blanks := [], seenN := Map()
        for i, c in r.cards {
            sl := CardSlot(names[i])
            if (sl = u.slot)
                hits.Push(c)
            else if (!sl && NormName(names[i]) = "")
                blanks.Push(c)
            if sl
                seenN[sl] := seenN.Get(sl, 0) + 1
        }
        if (hits.Length < k && blanks.Length && A_Index = 1) {
            ; unreadable cards: if this is the only placed named unit still
            ; missing cards, they must be its cards
            missing := 0, others := false
            for v in MT.units
                if (Trim(CFG.Get("Name" v.slot, "")) != "") {
                    cnt := 0
                    for w in MT.units
                        cnt += (w.slot = v.slot)
                    if (seenN.Get(v.slot, 0) < cnt) {
                        if (v.slot = u.slot)
                            missing := 1
                        else
                            others := true
                    }
                }
            if (missing && !others)
                for c in blanks
                    hits.Push(c)
        }
        j := (A_Index = 2) ? k - (total - hits.Length) : k   ; scrolled: first copies hidden above
        if (j >= 1 && j <= hits.Length)
            return hits[j]
        if (A_Index = 1) {
            if (MT.units.Length <= r.cards.Length)
                break
            if !OverviewScroll("WheelDown") {          ; panel still moving? once more
                Wait(400)
                if !OverviewScroll("WheelDown") {
                    Out("  unit list did not scroll down (" r.cards.Length " cards shown, " MT.units.Length " units)")
                    break
                }
            }
            Wait(400)
        } else if (A_Index = 2) {
            if !OverviewScroll("WheelUp")
                break
            Wait(300)
        }
    }
    if !u.HasOwnProp("nameMiss") {
        u.nameMiss := true
        seen := ""
        if MT.HasOwnProp("ncNames")
            for t in MT.ncNames
                seen .= (seen = "" ? "" : ", ") t
        if (IsSet(hits) && hits.Length)            ; the name is right, a copy is missing
            Out("  unit " u.slot " (" nm "): only " hits.Length " card(s) with that name - #" u.n " is not on the map")
        else
            Out("  unit " u.slot " (" nm "): no card with that name in Unit Overview (read: " seen ") - check the name in F8")
    }
    return ""
}

CardOf(u) {
    nm := Trim(CFG.Get("Name" u.slot, ""))
    if (nm != "") {                                ; named slot: find the card by its name
        c := CardByIdx(u)                          ; every card numbered + named once
        return (c = "?") ? CardByName(u, nm) : c   ; "?" = list not readable: old way
    }
    order := []
    for v in MT.units {
        i := order.Length + 1
        while (i > 1 && (order[i - 1].slot < v.slot || (order[i - 1].slot = v.slot && order[i - 1].n < v.n)))
            i--
        order.InsertAt(i, v)
    }
    idx := 0
    for i, v in order
        if (v = u)
            idx := i
    r := OverviewOpen()
    if (!r.open || !idx)
        return ""
    N := order.Length
    if (N > r.cards.Length && idx > r.cards.Length) {
        if !OverviewScroll("WheelDown")
            return ""
        Wait(400)
        r := OverviewRead()
        j := idx - (N - r.cards.Length)
        return (j >= 1 && j <= r.cards.Length) ? r.cards[j] : ""
    }
    if (N > r.cards.Length) {
        if !OverviewScroll("WheelUp")
            return ""
        Wait(300)
        r := OverviewRead()
    }
    return (idx <= r.cards.Length) ? r.cards[idx] : ""
}

; ------------------------------------------------- card census
; Every card in Unit Overview gets a fixed number (1 = top left, 2 = top
; right, ...) from its place in the WHOLE list - also when the list is
; scrolled (the scroll is measured) - and a name, read once: the small
; name under the picture when it fits a unit name exactly, otherwise the
; big title of the unit panel on the left (click the picture, read, close).
; Cards are then known per unit: how many there are, and which is which.

; distance between two card rows
OvRowH(cards) {
    best := 0
    for i, c in cards
        if (i > 1) {
            d := c.y - cards[i - 1].y
            if (d > 120 * WIN.u && (!best || d < best))
                best := d
        }
    return best
}
; px the list moved between two looks (+ = content went up)
ListShift(a, b, dir) {
    R := MT.HasOwnProp("rowH") ? MT.rowH : 189 * WIN.u
    sg := (dir = "WheelDown") ? 1 : -1
    votes := Map()
    for ca in a
        for cb in b
            if (Abs(ca.x - cb.x) < 20) {
                v := sg * (ca.y - cb.y)
                v := Mod(Mod(v, R) + R, R)         ; the same card moved by v (mod one row)
                k := Round(v / 3)
                votes[k] := votes.Get(k, 0) + 1
            }
    bestK := "", bestN := 0
    for k, n in votes
        if (n > bestN)
            bestK := k, bestN := n
    if (bestK = "")
        return ""
    v := bestK * 3
    if (v > R - 4)                                 ; ~0 or ~one whole row: can't tell
        v := 0
    return sg * v
}
CardIdx(c) => Round((c.y + MT.ovOff - PY(244)) / MT.rowH) * 2 + (c.x > PX(1633, "r") ? 2 : 1)
; the list position must be known: else go to the top (= position 0)
OvSync(&r) {
    if (MT.HasOwnProp("ovOk") && MT.ovOk && MT.HasOwnProp("ovOff"))
        return true
    if (MT.HasOwnProp("ovFail") && MT.ovFail >= 2)
        return false                               ; failed twice this match: don't keep scrolling
    if OverviewScroll("WheelUp") {
        Wait(250)
        r := OverviewRead()
        if (r.open && r.cards.Length && Abs(r.cards[1].y - PY(244)) < 12 * WIN.u) {
            MT.ovOff := 0, MT.ovOk := true
            return true
        }
    }
    MT.ovFail := (MT.HasOwnProp("ovFail") ? MT.ovFail : 0) + 1
    if (MT.ovFail = 2)
        Out("  card list: top of the list not found - using the old card search this match")
    return false
}
SlotName(sl) => (MT.HasOwnProp("fusedSlot") && MT.fusedSlot = sl) ? MT.fusedName : Trim(CFG.Get("Name" sl, ""))
CensusGen() => MT.units.Length "|" (MT.HasOwnProp("fuseGen") ? MT.fuseGen : 0)
; the unit of a card text, also the fused unit
CardSlotF(text) {
    if (MT.HasOwnProp("fusedSlot") && NameScore(text, MT.fusedName) >= 0.8)
        return MT.fusedSlot
    return CardSlot(text)
}
; give the visible cards their numbers, read names not known yet
NameCards(r) {
    gen := CensusGen()
    if (!MT.HasOwnProp("cn") || MT.cnGen != gen)
        MT.cn := Map(), MT.cnGen := gen, MT.cenGen := ""
    h := OvRowH(r.cards)
    if h
        MT.rowH := h
    else if !MT.HasOwnProp("rowH")
        MT.rowH := 189 * WIN.u
    small := ""
    for i, c in r.cards {
        c.idx := CardIdx(c)
        if MT.cn.Has(c.idx)
            continue
        if !IsObject(small)
            small := CardNames(r.cards)
        nm := small[i], sl := CardSlotF(nm), how := "card"
        if !(sl && NameScore(nm, SlotName(sl)) >= 1) {   ; not sure: the big panel
            t := PanelTitle(c)
            if (t != "")
                nm := t, sl := CardSlotF(t), how := "panel"
        }
        MT.cn[c.idx] := {name: nm, slot: sl, how: how}
    }
}
; the big title of a card's unit panel (left)
PanelTitle(c) {
    CloseUnitPanel()
    ClickAt(c.x - 112 * WIN.u, c.y + 22 * WIN.u)
    t := ""
    Loop 2 {
        Wait(A_Index = 1 ? 500 : 400)
        r := OcrRef(20, 325, 295, 400, 2, "l", "c")          ; title only
        t := IsObject(r) ? Trim(RegExReplace(r.t, "\s+", " ")) : ""
        if (t != "")
            break
    }
    CloseUnitPanel()
    return t
}
; name every card (top of the list, then its bottom part). true = all known
Census() {
    gen := CensusGen()
    if (MT.HasOwnProp("cenGen") && MT.cenGen = gen)
        return MT.cenOk
    r := OverviewOpen()
    if !(r.open && r.cards.Length) || !OvSync(&r)
        return false
    NameCards(r)
    if (MT.units.Length > r.cards.Length) {        ; more cards below
        if (OverviewScroll("WheelDown") && MT.ovOk) {   ; scroll measured: numbers still right
            Wait(300)
            r2 := OverviewRead()
            if (r2.open && r2.cards.Length)
                NameCards(r2)
        }
    }
    N := 0
    for idx in MT.cn
        N := Max(N, idx)
    ok := (N >= 1)
    Loop N
        if !MT.cn.Has(A_Index)
            ok := false                            ; a gap: some cards were never seen
    line := ""
    for idx, e in MT.cn
        line .= (line = "" ? "" : ", ") idx "=" (e.slot ? "u" e.slot : "?") " " e.name
    Out("  cards (" N "): " line (ok ? "" : "  [not all seen]"))
    MT.cenGen := gen, MT.cenOk := ok, MT.cenN := N
    return ok
}
; card of unit u by number: copy k of its unit = its k-th card in the list
CardByIdx(u) {
    if !Census()
        return "?"
    k := 0, total := 0
    for v in MT.units
        if (v.slot = u.slot) {
            total++
            if (v = u)
                k := total
        }
    if !k
        return ""                                  ; not one of the placed units any more
    list := []
    for idx, e in MT.cn
        if (e.slot = u.slot)
            list.Push(idx)
    if (k > list.Length) {
        if !u.HasOwnProp("nameMiss") {
            u.nameMiss := true
            Out("  unit " u.slot " (" SlotName(u.slot) "): " list.Length " card(s) for " total " placed - #" k " is not on the map")
        }
        return ""
    }
    want := list[k]
    Loop 2 {
        if (A_Index = 2 && !MT.ovOk)               ; the scroll was not measured: old way
            return "?"
        r := OverviewOpen()
        if !r.open
            return ""
        if !OvSync(&r)                             ; list position lost: old way
            return "?"
        lo := 999, hi := 0
        for c in r.cards {
            c.idx := CardIdx(c), lo := Min(lo, c.idx), hi := Max(hi, c.idx)
            if (c.idx = want)
                return c
        }
        if (A_Index = 2 || !r.cards.Length)
            break
        if !OverviewScroll(want < lo ? "WheelUp" : "WheelDown")
            break
        Wait(250)
    }
    return ""
}
; Plan vs. cards: each placed named unit needs a card. Fewer cards than
; placed units (and no unknown cards) = some were never really placed:
; forget them and place them again.
CheckPlaced() {
    if (MT.HasOwnProp("chkGen") && MT.chkGen = CensusGen())
        return
    MT.chkGen := CensusGen()
    if !Census()
        return
    have := Map(), unk := 0
    for idx, e in MT.cn {
        if e.slot
            have[e.slot] := have.Get(e.slot, 0) + 1
        else
            unk++
    }
    if (unk || MT.cenN >= MT.units.Length)
        return                                     ; every unit has a card (or can't tell)
    again := []
    Loop 6 {
        sl := A_Index
        if (SlotName(sl) = "")
            continue
        mine := []
        for v in MT.units
            if (v.slot = sl)
                mine.Push(v)
        miss := mine.Length - have.Get(sl, 0)
        if (miss <= 0)
            continue
        Out("  unit " sl " (" SlotName(sl) "): " have.Get(sl, 0) " card(s) but " mine.Length " placed - "
            . (MT.HasOwnProp("noReplace") && MT.noReplace.Has(sl) ? "fused, not placing it again" : "placing " miss " again"))
        Loop miss {                                ; forget the newest ones
            v := mine.Pop()
            for i, w in MT.units
                if (w = v) {
                    MT.units.RemoveAt(i)
                    break
                }
            if !(MT.HasOwnProp("noReplace") && MT.noReplace.Has(sl))
                again.Push(v)
        }
    }
    for v in again {
        if MatchOver()
            return
        if !WaitYen(CFG["Cost" v.slot], 30000)
            continue
        PlaceAny(v.slot, v.HasOwnProp("style") ? v.style : "random", v.HasOwnProp("pt") ? v.pt : "")
    }
}
; skill used on a unit that fuses (Vego + Carrot -> Fused Hero)?
FuseCheck(u) {
    nm := Trim(CFG.Get("Name" u.slot, ""))
    if (nm = "")
        return
    for f in FUSIONS {
        other := ""
        if (NameScore(nm, f[1]) >= 0.8)
            other := f[2]
        else if (NameScore(nm, f[2]) >= 0.8)
            other := f[1]
        if (other = "")
            continue
        ps := 0
        Loop 6
            if (A_Index != u.slot && NameScore(Trim(CFG.Get("Name" A_Index, "")), other) >= 0.8)
                ps := A_Index
        n := 0
        for v in MT.units
            n += (v.slot = ps)
        if (!ps || !n)
            return                                 ; partner not on the map: no fusion
        if !MT.HasOwnProp("noReplace")
            MT.noReplace := Map()
        MT.noReplace[ps] := true                   ; the partner is used up: never place it again
        Wait(2500)
        MT.fuseGen := (MT.HasOwnProp("fuseGen") ? MT.fuseGen : 0) + 1
        found := false
        if Census()
            for idx, e in MT.cn
                if (NameScore(e.name, f[3]) >= 0.8)
                    found := true
        if !found
            return Out("  no " f[3] " card after the skill - not fused")
        MT.fusedSlot := u.slot, MT.fusedName := f[3]
        pi := 0
        for i, w in MT.units                       ; the partner's unit is gone
            if (w.slot = ps)
                pi := i
        if pi
            MT.units.RemoveAt(pi)
        MT.fuseGen++                                ; read the cards again
        Out("  " f[1] " + " f[2] " fused -> " f[3] " (unit " u.slot "); upgrades of unit " u.slot " now go to " f[3])
        return
    }
}

; one level for unit u: "ok" "max" "poor" "lost"
; The bar under the card decides everything: lit segments = level.
UpgradeOnce(u) {
    c := CardOf(u)
    if !IsObject(c)
        return "lost"
    lv := CardLevel(c)
    if (lv.lvl >= 0) {
        u.lvl := lv.lvl, u.maxLvl := lv.max
        if (lv.lvl >= lv.max) {
            u.maxed := true
            Out("  unit " u.slot " #" u.n " is MAX (" lv.lvl "/" lv.max ")")
            return "max"
        }
    }
    u.poor := (u.HasOwnProp("poor") ? u.poor : 0) + 1
    if (Mod(u.poor, 15) = 0)
        Out("  [check] unit " u.slot " #" u.n ": card at " Round(c.x) "," Round(c.y) "  bar " lv.lvl "/" lv.max "  button " (c.buy ? "green" : "grey"))
    if !c.buy                                       ; greyed button = not enough yen
        return "poor"
    ClickAt(c.x, c.y)
    Wait(350)
    c2 := CardOf(u)
    lv2 := IsObject(c2) ? CardLevel(c2) : {lvl: -1, max: -1}
    if (lv.lvl >= 0 && lv2.lvl > lv.lvl) {
        u.lvl := lv2.lvl, u.bad := 0, u.poor := 0
        if (lv2.lvl >= lv2.max)
            u.maxed := true
        return "ok"
    }
    if (lv.lvl < 0 || lv2.lvl < 0) {                 ; bar not readable
        u.bad := (u.HasOwnProp("bad") ? u.bad : 0) + 1
        if (u.bad >= 6) {
            Out("  unit " u.slot " #" u.n ": its upgrade bar can't be read - skipping it")
            u.maxed := true
        }
    }
    return "poor"
}

; goal: "max", a level number, or "plus" (+plus levels from now)
UpgradeTargets(slots, goal, plus, style, untilWave, timeout) {
    CheckPlaced()                                  ; plan vs. cards: place missing ones again
    us := []
    for s in slots
        for u in MT.units
            if (u.slot = s)
                us.Push(u)
    if (us.Length = 0)
        return ""
    for u in us {                                  ; start from the real levels
        c := CardOf(u)
        if IsObject(c) {
            lv := CardLevel(c)
            if (lv.lvl >= 0)
                u.lvl := lv.lvl, u.maxed := (lv.lvl >= lv.max)
        }
    }
    want := Map()
    for u in us
        want[u] := (goal = "plus") ? u.lvl + plus : (goal = "max") ? 999 : goal
    t0 := A_TickCount, lastWave := 0
    Loop {
        if MatchOver()
            return "end"
        if (untilWave && A_TickCount - lastWave > 4000) {
            lastWave := A_TickCount
            if (ReadWave() >= untilWave) {
                Out("  wave " untilWave " reached")
                return ""
            }
        }
        pending := []
        for u in us
            if (!u.maxed && u.lvl < want[u])
                pending.Push(u)
        if (pending.Length = 0)
            return ""
        if (A_TickCount - t0 > timeout) {
            Out("  upgrade step took too long - next step")
            return ""
        }
        ; even = the lowest level first; one = finish the first unit first
        pick := pending[1]
        if (style = "even")
            for u in pending
                if (u.lvl < pick.lvl)
                    pick := u
        r := UpgradeOnce(pick)
        if (r = "ok")
            Out("  unit " pick.slot " #" pick.n " -> level " pick.lvl)
        else if (r = "lost") {
            if FixFirstPerson()                     ; that was the reason - try again
                continue
            Out("  unit " pick.slot " #" pick.n ": card not found in Unit Overview")
            pick.maxed := true                      ; give up on it
        } else if (r = "poor") {
            Status("saving yen for unit " pick.slot)
            Wait(700)
        }
    }
}

; ------------------------------------------------------ unit panel
; click the unit on the map -> its panel opens on the left. The auto
; switch says "Off"/"On"; the ability button is just below it.
; Open the unit's own panel (left side): close any open panel, then click
; the unit's picture on its card in Unit Overview (found by name). Only
; when that fails, click where the unit stands on the map.
OpenPanel(u) {
    CloseUnitPanel()
    nm := Trim(CFG.Get("Name" u.slot, ""))
    c := CardOf(u)
    if IsObject(c) {
        Loop 2 {
            ClickAt(c.x - 112 * WIN.u, c.y + 22 * WIN.u)   ; the picture on the card
            Wait(550)
            r := OcrRef(0, 180, 900, 600, 2, "l", "c")
            if (IsObject(r) && InStr(r.t, "pgrade") && (nm = "" || NameScore(r.t, nm) >= 0.6))
                return r                           ; the right unit's panel
            CloseUnitPanel()
            c := CardOf(u)
            if !IsObject(c)
                break
        }
    }
    CloseOverview()
    for dy in [-10, -25, 4, -40, -55] {
        ClickRef(u.x, u.y + dy)
        Wait(450)
        r := OcrRef(0, 180, 860, 560, 2, "l", "c")
        if (IsObject(r) && InStr(r.t, "pgrade"))
            return r
    }
    return ""
}

AutoSwitch(r, &x, &y, &on) {
    for wd in Words(r)
        if (wd.x > PX(500, "l") && RegExMatch(wd.t, "i)^(Off|On)$")) {
            x := wd.x, y := wd.y, on := (StrLower(wd.t) = "on")
            return true
        }
    return false
}

; the skill button on the panel ("Gale of the Moon (Activate)")
AbilityButton(r, &x, &y) {
    for wd in Words(r)
        if (wd.x > PX(480, "l") && RegExMatch(wd.t, "i)activ")) {
            x := wd.x, y := wd.y
            return true
        }
    return false
}

UseAbility(u, times) {
    r := OpenPanel(u)
    if !IsObject(r)
        return Out("  unit " u.slot ": panel did not open - ability skipped")
    x := 0, y := 0
    if AbilityButton(r, &x, &y)
        how := "skill button"
    else if AutoSwitch(r, &x, &y, &on)             ; the skill sits under the auto switch
        y += 85 * WIN.u, how := "under auto switch"
    else {
        CloseUnitPanel()
        return Out("  unit " u.slot ": no skill on its panel - skipped")
    }
    Loop times {
        ClickAt(x, y)
        Out("  ability unit " u.slot " (" A_Index "/" times ", " how ")")
        if (A_Index < times)
            Wait(1500)
    }
    Wait(300)
    CloseUnitPanel()
    FuseCheck(u)
}

SetAuto(u) {
    r := OpenPanel(u)
    if !IsObject(r)
        return Out("  unit " u.slot ": panel did not open - auto skipped")
    if !AutoSwitch(r, &x, &y, &on)
        return Out("  unit " u.slot ": no auto switch on its panel")
    if on
        return (CloseUnitPanel(), Out("  unit " u.slot ": auto already on"))
    ClickAt(x, y)
    Out("  auto ON for unit " u.slot)
    Wait(300)
    CloseUnitPanel()
}
