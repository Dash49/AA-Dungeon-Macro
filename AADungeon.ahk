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
global STATE := {run: false, pause: false, stop: false}
; one dungeon run / one match
global SNP := {x: 0, y: 0, w: 0, h: 0, buf: ""}
global RS := {depth: 0, maxDepth: 20, bossDone: false, chestsDone: false, lastRoute: 0, camDone: false, died: false, ready: true, endAt: 0, camVote: false, coins: -1, poke: 0, startAt: 0}
global MT := {}
global CFG := Map()

Hotkey "F2", (*) => Start()
Hotkey "F3", (*) => Reload()
Hotkey "F4", (*) => TogglePause()
Hotkey "F5", (*) => DebugSee()
Hotkey "F6", (*) => (FindRoblox(), CameraSetup())          ; test the camera
Hotkey "F7", (*) => (FindRoblox(), CameraSetup(2))
Hotkey "F8", (*) => OpenSettings()                         ; settings window
Hotkey "F9", (*) => OpenSettings("/report")                ; send a bug report

OpenSettings(arg := "") {
    f := A_ScriptDir "\AASettings.ahk"
    if FileExist(f)
        Run('"' A_AhkPath '" "' f '"' (arg != "" ? " " arg : ""))
    else
        MsgBox("AASettings.ahk not found next to the macro")
}

LoadConfig()
FileAppend("`n===== AA Dungeon started " FormatTime(, "yyyy-MM-dd HH:mm:ss") " =====`n", LOGFILE, "UTF-8")
Out("Ready. Maximise Roblox, then press F2. (F3 stop, F4 pause, F5 debug)")
Status("AA Dungeon ready - F2 start")
return

; ===================================================== configuration
LoadConfig() {
    d := Map(
        "Boss", 100, "Chest", 40, "Hoard", 20, "Shrine", 25, "Open", 5, "Normal", 0,
        "ShopRich", 60, "ShopMid", 20, "ShopPoor", 0, "ShopRichCoins", 1000, "ShopMidCoins", 600, "ShopBuyAll", 2000,
        "Curse", -10, "CurseMidDepth", 10, "CurseMid", -40, "CurseHighDepth", 15, "CurseHigh", -150,
        "Lookahead", 0.5, "ShrineMin", 25, "ShrineChest", 20, "ShrineRare", 35,
        "SaveChests", 1, "AutoVote", 1, "OnFinish", "again",
        "Cost1", 550, "Cost2", 800, "Cost3", 2000, "Cost4", 1300, "Cost5", 2000, "Cost6", 1400,
        "Items", "Mask of Riches=100|Philosophers Stone=95|Genie Lamp=90|Golden Mushroom=80|Golden Fishhook=75"
            . "|Archmage's Hat=65 >500|Aures Maul=65 >500|Solar Cleaver=60 >500|Magic Tome=50 >500|Mage Coat=35 >500|Elf Bow=35 >500"
            . "|Speedy Boots=30|Glacial Axe=30|Golden Branch=30|Dagger=20|Nimble Cloak=20"
            . "|Reaper Scythe=0|Ninja Belt=0|Celestial Blade=0|Other=20 >1000")
    for k, v in d {
        val := IniRead(INI, "Settings", k, "`a")
        if (val = "`a")                            ; new setting - add it to the file
            val := v, IniWrite(v, INI, "Settings", k)
        CFG[k] := IsNumber(val) ? val + 0 : val
    }
}

; ============================================================ basics
Out(msg) {
    line := "[" FormatTime(, "HH:mm:ss") "] " msg
    try FileAppend(line "`n", LOGFILE, "UTF-8")
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
    while STATE.pause
        Sleep 200
    if STATE.stop
        Exit
}

Wait(ms) {
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
    if (WIN.id && !WinActive(WIN.id)) {
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
    if InStr(t, "Leave Dungeon")
        return "leave"
    if (InStr(t, "Died") && InStr(t, "Depth Reached"))
        return "died"
    if (InStr(t, "OPEN CHESTS") || (InStr(t, "Luck") && InStr(t, "Continue")))
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
    if InStr(t, "Disconnected")
        return "disconnect"
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
    RS.ready := false, RS.endAt := A_TickCount, RS.startAt := RS.endAt ; never assume a new match at start
    Focus()
    Out("Started. client " WIN.w "x" WIN.h " scale " Round(WIN.u, 3) ", plan " MT.planSteps.Length " steps")
    Status("running")
    last := "", since := A_TickCount, closes := 0
    Loop {
        Hold()
        if !FindRoblox() {
            Out("Roblox closed - waiting")
            Wait(5000)
            continue
        }
        s := Screen(&r)
        if (s != last) {
            Out("Screen: " s)
            last := s, since := A_TickCount
        }
        Status(s)
        if (s = "loading" || s = "vote" || s = "intro" || s = "lobby")
            RS.ready := true                       ; a new match is really starting
        if (s = "result" || s = "reward" || s = "afterroom" || s = "died")
            RS.ready := false, RS.endAt := A_TickCount ; a match just ended
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
                if (A_TickCount - since > 25000) {
                    Out("Unknown screen 25s, text: " SubStr(RegExReplace(IsObject(r) ? r.t : "", "\s+", " "), 1, 160))
                    ClickAnywhere()
                    since := A_TickCount
                }
        }
        Wait(400)
    }
}

; ============================================================ screens
DoLobby(r) {
    RS.depth := 0, RS.bossDone := false, RS.chestsDone := false, RS.died := false
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
    Out("Dungeon menu - Enter Dungeon")
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
    Loop 24 {                                      ; then out to a fixed distance
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
    if !RS.camVote {                               ; camera first, then start the game
        CameraSetup()
        RS.camVote := true
        return
    }
    if !CFG["AutoVote"]
        return Wait(1000)
    for wd in Words(r)
        if (wd.t = "Yes" && wd.y < WIN.y + WIN.h * 0.35) {
            ClickAt(wd.x, wd.y)
            Wait(800)
            return
        }
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
    if RS.died {
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

DoDisconnect(r) {
    Out("Disconnected - clicking Reconnect")
    if Find(r, "Reconnect", &x, &y)
        ClickAt(x, y)
    Wait(15000)
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
    best := 0, bestScore := -1
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
    for x in layouts[best] {
        tile := {x: x, labels: [], ahead: []}
        for b in big
            if (Abs(b.x - x) < 90)
                tile.labels.Push(b.t)
        ; next rooms: small labels nearest to this tile, grouped per small tile
        grp := []
        for s in small {
            nearest := 0, dmin := 99999
            for x2 in layouts[best]
                if (Abs(s.x - x2) < dmin)
                    dmin := Abs(s.x - x2), nearest := x2
            if (nearest = x)
                grp.Push(s)
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
            res_.Push({name: Trim(m[1]), key: StrLower(RegExReplace(m[1], "[^A-Za-z]")), pts: Integer(m[2]), op: m[3], lim: m[4] != "" ? Integer(m[4]) : 0})
    }
    return res_
}

MatchItem(text) {
    t := StrLower(RegExReplace(text, "[^A-Za-z]"))
    if (StrLen(t) < 4)
        return ""
    best := "", bl := 0
    for it in ItemTable()
        if (it.key != "other" && InStr(t, it.key) && StrLen(it.key) > bl)
            best := it, bl := StrLen(it.key)
    return best
}

PriceOk(it, price) {
    if (it.op = "")
        return true
    if (price < 0)
        return false
    switch it.op {
        case ">":  return price > it.lim
        case ">=": return price >= it.lim
        case "<":  return price < it.lim
        case "<=": return price <= it.lim
    }
    return true
}

; save a PNG of the Roblox window to AAMacro\shots\<name>_<time>.png
Shot(name) {
    static gdip := 0
    try {
        dir := A_ScriptDir "\shots"
        DirCreate(dir)
        file := dir "\" name "_" FormatTime(, "yyyyMMdd_HHmmss") ".png"
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
        DllCall("ole32\CLSIDFromString", "wstr", "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "ptr", clsid)
        DllCall("gdiplus\GdipSaveImageToFile", "ptr", pBmp, "wstr", file, "ptr", clsid, "ptr", 0)
        DllCall("gdiplus\GdipDisposeImage", "ptr", pBmp)
        DllCall("DeleteObject", "ptr", hbm)
        Out("  picture saved: shots\" name "_" FormatTime(, "yyyyMMdd_HHmmss") ".png")
    } catch as e {
        Out("  picture failed: " e.Message)
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
                        it := {name: first, pts: o.pts, op: o.op, lim: o.lim}
            if !IsObject(it)
                it := {name: first, pts: 0, op: "", lim: 0}
            if bought.Has(it.name)
                continue
            special := RegExMatch(txt, "i)luck|plac\w*\s*cost|cost\w*\s*(of\s*)?plac|deploy\w*\s*cost")
            ok := PriceOk(it, rw.price), pts := it.pts, why := ""
            if special
                ok := true, pts := Max(pts, 500), why := " [luck/place cost]"
            if rich
                ok := true, pts := Max(pts, 1), why .= " [rich]"
            offers.Push({name: it.name, pts: pts, ok: ok, price: rw.price, x: rw.x, y: rw.y, why: why})
        }
        if (A_Index = 1) {
            sx := ""
            for o in offers
                sx .= o.name "=" o.pts " $" o.price (o.ok ? "" : " (no)") o.why "  "
            Out("  offers: " (sx != "" ? sx : "none read"))
        }
        pick := ""
        for o in offers
            if (o.ok && o.pts > 0 && (coins < 0 || o.price <= coins) && (!IsObject(pick) || o.pts > pick.pts))
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
    total := 0, parts := ""
    for ln in Lines(r) {
        t := ln.t
        if RegExMatch(t, "i)Curse\s*of\s*(\w+)", &m) {
            p := CursePts(depth)
            if (RegExMatch(m[1], "i)Flight|Burst") && p < 0)
                p := Round(p / 2)
            total += p, parts .= m[0] " " p ", "
        } else if RegExMatch(t, "i)Rare\s*Chest") {
            total += CFG["ShrineRare"], parts .= "Rare chest, "
        } else if (RegExMatch(t, "i)Treasure\s*Chest") && !RegExMatch(t, "i)\+\s*1")) {
            total += CFG["ShrineChest"], parts .= "Chest, "
        } else if IsObject(it := MatchItem(t)) {
            total += it.pts, parts .= it.name ", "
        }
    }
    take := total >= CFG["ShrineMin"]
    Out("Shrine: " parts "= " total " -> " (take ? "ACCEPT" : "DENY"))
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
            n := 0
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
                if !got
                    break
                n++
                Loop 8 {
                    ClickAnywhere()
                    if !InStr(AllText(), "Click anywhere")
                        break
                }
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
    if !FileExist(PLANFILE) {
        FileAppend("place 1 x3`nplace 2 x1`nupgrade all max`n", PLANFILE, "UTF-8")
    }
    steps := [], bad := []
    for i, raw in StrSplit(FileRead(PLANFILE, "UTF-8"), "`n", "`r") {
        line := Trim(RegExReplace(raw, ";.*$"))
        if (line = "")
            continue
        l := StrLower(line)
        for th, en in Map("วาง", "place", "อัพ", "upgrade", "อัป", "upgrade", "สกิล", "ability", "ออโต้", "auto", "รอ", "wait", "เวฟ", "wave", "ตัน", "max", "เฉลี่ย", "even", "ทีละตัว", "one")
            l := StrReplace(l, th, en)
        if RegExMatch(l, "^place\s+([1-6])\s*(?:x\s*(\d+))?$", &m)
            steps.Push({k: "place", slot: Integer(m[1]), n: m[2] != "" ? Integer(m[2]) : 1, text: line})
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
    ReadHotbarCosts()
    if !RS.camVote                                  ; camera was not set on the vote screen
        CameraSetup()
    RS.camVote := false                             ; next match sets it again
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
                r := PlaceUnit(st.slot)
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
            Wait(st.s * 1000)
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
IsRed(col) {
    r := (col >> 16) & 0xFF, g := (col >> 8) & 0xFF, b := col & 0xFF
    return (r > 150 && g < 95 && b < 105 && r - g > 100)
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

PlaceUnit(slot) {
    Focus()
    ; Unit Overview stays open on the right: its cards prove a placement
    ; at once, and no time is lost opening/closing it. Spots under it are
    ; skipped. The unit panel on the left (with its Sell button!) is closed.
    CloseUnitPanel()
    n0 := -1
    if !MT.HasOwnProp("streak")
        MT.streak := 0
    wide := (MT.streak >= 1 || MT.HasOwnProp("wideMode"))  ; panel side failed once:
    if wide                                        ; use the whole map, check by yen
        CloseOverview()
    else if (MT.units.Length < 8) {
        ov := OverviewOpen()
        n0 := ov.open ? 1 : -1
    }
    MT.ovOpen := (n0 >= 0)
    yen0 := wide ? ReadYen() : -1
    MouseMove(PX(960), PY(120))                    ; off the ground first
    Snap()
    base := (n0 >= 0) ? Max(ScanCards().Length, MT.units.Length) : 0
    before := RedGrid()                            ; red things that are part of the map
    Key(slot)
    Wait(170)
    Snap()
    path := []
    for k, pt in RedGrid()
        if !before.Has(k)
            path.Push(pt)
    if (path.Length < 20 && FixFirstPerson())      ; first person hides the path
        return "fail"
    if (path.Length < 20) {                        ; nothing in hand (a real path is long)
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
    cands := []
    ; 1) next to spots that already worked in this match (same ground)
    for gd in MT.good {
        Loop 8 {
            a := Random(0.0, 6.2832), d := Random(34.0, 85.0)
            AddCand(cands, cells, gd.x + Cos(a) * d, gd.y + Sin(a) * d * 0.85, gap, 14)
        }
    }
    ; 2) random spots 30..120 px off a random path point
    if !tinted {
        Loop 400 {
            if (cands.Length >= 40)
                break
            pt := path[Random(1, path.Length)]
            a := Random(0.0, 6.2832), d := Random(30.0, 120.0)
            AddCand(cands, cells, pt[1] + Cos(a) * d, pt[2] + Sin(a) * d * 0.85, gap, 40)
        }
    }
    ; 3) anywhere on the map that is not red (tinted maps, or the path
    ;    spots all failed already)
    if (cands.Length < 12) {
        Loop 1500 {
            if (cands.Length >= 40)
                break
            AddCand(cands, cells, Random(150.0, 1760.0), Random(180.0, 890.0), gap, 40)
        }
    }
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
            if (wide && yen0 > 0) {                ; no cards on screen: the yen must drop
                cost := CFG["Cost" slot]
                y1 := -1
                Loop 4 {
                    Wait(150)
                    y1 := ReadYen()
                    if (y1 >= 0 && y1 <= yen0 - cost * 0.5)
                        break
                }
                if (y1 >= 0 && y1 > yen0 - cost * 0.5) {
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
            MT.units.Push({slot: slot, n: n, x: c.x, y: c.y, lvl: 0, maxed: false})
            MT.good.Push({x: c.x, y: c.y})
            Out("  placed unit " slot " #" n " at " Round(c.x) "," Round(c.y) " (try " fails + 1 ")")
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
OverviewReturnVisible() {
    for pt in [[1471, 973], [1576, 968], [1685, 973]] {
        c := RGB(Color(PX(pt[1], "r"), PY(pt[2])))
        if !(c.r > 200 && c.g < 50 && c.b < 50)
            return false
    }
    return true
}

; the unit panel on the left (opened by clicking a unit): red X + cyan First
UnitPanelVisible() {
    for pt in [[544, 346], [580, 346]] {
        c := RGB(Color(PX(pt[1], "l"), PY(pt[2])))
        if !(c.r > 190 && c.g < 50 && c.b < 50)
            return false
    }
    for pt in [[61, 658], [123, 658]] {
        c := RGB(Color(PX(pt[1], "l"), PY(pt[2])))
        if !(c.b > 190 && c.g > 150 && c.r < 90)
            return false
    }
    return true
}
CloseUnitPanel() {
    Snap()
    if !UnitPanelVisible()
        return false
    Loop 2 {
        ClickRef(562, 346, "l", "c")               ; its red X
        Wait(350)
        Snap()
        if !UnitPanelVisible()
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
        if (dir = "WheelUp" && Abs(b[1].y - topY) < 12 * WIN.u)
            return true                            ; already at the top - no wheel at all
        before := b[b.Length].y
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
ZoomOutKeys(n := 15) {
    Focus()
    Loop n {
        Send "{o down}"
        Sleep 30
        Send "{o up}"
        Sleep 30
    }
}

CardOf(u) {
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
OpenPanel(u) {
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

UseAbility(u, times) {
    found := false, x := 0, y := 0, lv := "?"
    Loop 4 {
        r := OpenPanel(u)
        if !IsObject(r)
            return Out("  unit " u.slot ": panel did not open - ability skipped")
        if AutoSwitch(r, &x, &y, &on) {
            found := true
            break
        }
        lv := RegExMatch(r.t, "i)pgrade\s*\W?\s*(\d+)", &m) ? m[1] : "?"
        if (A_Index = 4 || u.maxed)
            break                                  ; already tried / can't level further
        ; no ability button yet = it unlocks at a higher level: one more level
        Out("  unit " u.slot ": no ability yet (level " lv ") - upgrading once more")
        res := "poor"
        Loop 20 {
            res := UpgradeOnce(u)
            if (res != "poor" || MatchOver())
                break
            Wait(1000)
        }
        if (res = "max" || res = "lost")
            u.maxed := true
    }
    if !found {
        CloseUnitPanel()
        return Out("  unit " u.slot ": no ability on its panel (level " lv ") - skipped")
    }
    Loop times {
        ClickAt(x, y + 80 * WIN.u)
        Out("  ability unit " u.slot " (" A_Index "/" times ")")
        if (A_Index < times)
            Wait(1500)
    }
    Wait(300)
    CloseUnitPanel()
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
