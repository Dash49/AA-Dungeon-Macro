#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
; =====================================================================
;  AAWatch.ahk - helper processes started by AADungeon.ahk (do not run
;  it alone). Each one only READS the screen, next to the macro, and
;  sends what it sees to the macro window. They never click or press
;  keys (one mouse: only the macro clicks). They quit with the macro.
;    AAWatch.ahk <macro hwnd> yen    the yen under the hotbar, every 0.15 s
;    AAWatch.ahk <macro hwnd> left   the unit panel on the left (name,
;                                    Upgrade [n], MAX, price), every 0.25 s
;    AAWatch.ahk <macro hwnd> right  Unit Overview cards (names, Upg button)
;                                    every 0.7 s + match over? every 1 s
;  Every message carries the A_TickCount when the picture was taken, so
;  the macro only uses what was seen AFTER its own last click.
; =====================================================================
Persistent
DetectHiddenWindows true
CoordMode "Pixel", "Screen"
#Include %A_ScriptDir%\Lib\OCR.ahk

global MAIN := (A_Args.Length >= 1) ? Integer(A_Args[1]) : 0
global MODE := (A_Args.Length >= 2) ? A_Args[2] : "yen"
global WIN := {id: 0, x: 0, y: 0, w: 1920, h: 1080, u: 1.0}
global SNP := {x: 0, y: 0, w: 0, h: 0, buf: ""}
global FS := Chr(31), RS_ := Chr(30)               ; field / record separators

if !MAIN
    ExitApp()
SetTimer(WatchMain, 2000)
switch MODE {
    case "left":  SetTimer(WatchLeft, 250)
    case "right": SetTimer(WatchRight, 350)
    default:      SetTimer(WatchYen, 150)
}
return

; the macro was closed / reloaded: stop too
WatchMain() {
    if !WinExist("ahk_id " MAIN)
        ExitApp()
}

; ---- yen ---------------------------------------------------------------
WatchYen() {
    static busy := false
    if busy
        return
    busy := true
    try {
        if FindRoblox() {
            v := ReadYenOnce()
            if (v >= 0)
                PostMessage(0x5A01, v, 0, , "ahk_id " MAIN)
        }
    }
    busy := false
}

; ---- left: the unit panel ----------------------------------------------
WatchLeft() {
    static busy := false
    if busy
        return
    busy := true
    try {
        if FindRoblox() {
            t0 := A_TickCount
            Snap()
            if UnitPanelVisible() {
                p := PanelRead()
                if IsObject(p)
                    SendText(2, t0 FS p.name FS p.lvl FS p.max FS p.cost FS Round(p.bx) FS Round(p.by))
            } else
                SendText(2, t0 FS "-")              ; no panel open
        }
    }
    busy := false
}
; "Upgrade [n]" as OCR reads it: O=0, I/l=1, A=4, S=5 (-1 = not a number) - same as the macro
LvlNum(s) {
    s := StrReplace(StrReplace(StrReplace(StrReplace(s, "O", "0", false), "S", "5", false), "A", "4", false), "I", "1", false)
    s := StrReplace(s, "l", "1", false)
    return IsDigit(s) ? Integer(s) : -1
}
PanelRead() {
    r := OcrRef(0, 300, 600, 790, 2, "l", "c")             ; (taller panel with DMG rows: button lower)
    if !(IsObject(r) && (InStr(r.t, "pgrade") || RegExMatch(r.t, "i)\bMax\b")))
        return ""
    t := RegExReplace(r.t, "\s+", " ")
    p := {name: "", lvl: -1, max: 0, cost: -1, bx: 0, by: 0}
    tr := OcrRef(20, 315, 300, 415, 2, "l", "c")             ; the big title
    p.name := IsObject(tr) ? Trim(RegExReplace(tr.t, "\s+", " ")) : ""
    p.name := StrReplace(StrReplace(p.name, FS), RS_)
    if RegExMatch(t, "i)Upgrade\s*[\[(\{|l]\s*([0-9OIlSA]{1,2})\s*[\])\}|l1]", &m)
        p.lvl := LvlNum(m[1])
    p.max := RegExMatch(t, "i)\(\s*MAX\s*\)") ? 1 : 0
    if RegExMatch(t, "i)Upgrade\s*:\s*[\]|)}]?\s*([\d][\d,. ]*)", &m)   ; same as the macro
        p.cost := Integer(RegExReplace(m[1], "\D"))
    best := ""
    for w in Words(r)                              ; the big button = the lowest "Upgrade" word
        if (RegExMatch(w.t, "i)^upgrade") && (!IsObject(best) || w.y > best.y))
            best := w
    if (IsObject(best) && best.y > PY(520))
        p.bx := best.x, p.by := best.y
    else if (!p.max && RegExMatch(t, "i)\bMax\b"))
        p.max := 1                                 ; button says Max
    return p
}

; ---- right: Unit Overview cards + is the match over? -------------------
WatchRight() {
    static busy := false, lastMatch := 0
    if busy
        return
    busy := true
    try {
        if FindRoblox() {
            if (A_TickCount - lastMatch >= 1000) {  ; match over? (whole window, once a second)
                lastMatch := A_TickCount
                t0 := A_TickCount
                r := OcrRect(WIN.x, WIN.y, WIN.x + WIN.w, WIN.y + WIN.h, 1)
                tx := IsObject(r) ? r.t : ""
                st := RegExMatch(tx, "VICTORY|DEFEAT|Victory|Defeat|Waves\s*Completed|Total\s*Time\s*:|Click anywhere|anywhere to cont|\(x\d+\)\s*(Common|Uncommon|Rare|Epic|Legendary|Mythic|Secret)|Depth Reached|Disconnected|Open Dungeon")
                    ? "end" : RegExMatch(tx, "Wave\s*\d") ? "play" : "?"
                SendText(4, t0 FS st)
            } else {
                t0 := A_TickCount
                Snap()
                if OverviewReturnVisible() {
                    cards := ScanCards()
                    names := CardNames(cards)
                    s := t0
                    for i, c in cards
                        s .= RS_ Round(c.x) FS Round(c.y) FS (c.buy ? 1 : 0) FS StrReplace(StrReplace(names[i], FS), RS_)
                    SendText(3, s)
                } else
                    SendText(3, t0 RS_ "-")         ; overview closed
            }
        }
    }
    busy := false
}
CardNames(cards) {
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
    return names
}

; ---- send a text to the macro (WM_COPYDATA, code = what it is) ---------
SendText(code, s) {
    buf := Buffer(StrPut(s, "UTF-16") * 2, 0)
    StrPut(s, buf, "UTF-16")
    cds := Buffer(3 * A_PtrSize, 0)
    NumPut("Ptr", code, cds, 0)
    NumPut("UInt", buf.Size, cds, A_PtrSize)
    NumPut("Ptr", buf.Ptr, cds, 2 * A_PtrSize)
    try SendMessage(0x4A, 0, cds.Ptr, , "ahk_id " MAIN, , , , 1000)
}

; ---- the same screen helpers as in AADungeon.ahk (keep them in step) ---
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
Color(sx, sy) {
    x := Round(sx - SNP.x), y := Round(sy - SNP.y)
    if (!IsObject(SNP.buf) || x < 0 || y < 0 || x >= SNP.w || y >= SNP.h)
        return 0
    return NumGet(SNP.buf, (y * SNP.w + x) * 4, "uint") & 0xFFFFFF
}
RGB(c) => {r: (c >> 16) & 0xFF, g: (c >> 8) & 0xFF, b: c & 0xFF}
IsCyan(col) {
    r := (col >> 16) & 0xFF, g := (col >> 8) & 0xFF, b := col & 0xFF
    return (b > 200 && g > 150 && r < 90)
}
OverviewReturnVisible() {
    n := 0
    for pt in [[1471, 973], [1576, 968], [1685, 973], [1490, 1005], [1690, 1005]] {
        c := RGB(Color(PX(pt[1], "r"), PY(pt[2])))
        n += (c.r > 175 && c.g < 50 && c.b < 50)
    }
    return n >= 4
}
UnitPanelVisible() {
    n := 0
    yy := 300
    while (yy <= 410) {
        xx := 490
        while (xx <= 620) {
            c := RGB(Color(PX(xx, "l"), PY(yy)))
            if (c.r > 190 && c.g < 50 && c.b < 50)
                n++
            xx += 4
        }
        yy += 4
    }
    if (n < 25)
        return false
    cy := 0
    yy := 630
    while (yy <= 690) {
        xx := 30
        while (xx <= 160) {
            cy += IsCyan(Color(PX(xx, "l"), PY(yy)))
            xx += 6
        }
        yy += 6
    }
    return cy >= 10
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
                if (runLen >= 26 * u && runLen <= 50 * u && top > PY(152)
                    && IsCyan(Color(PX(bx + 45, "r"), fy))) {
                    uy := fy - 45 * u
                    g := RGB(Color(sx, uy - 13 * u))
                    cards.Push({x: PX(bx, "r"), y: uy, buy: (g.g > 170 && g.r < 130 && g.b < 100)})
                }
                runLen := 0
            }
            y += 1
        }
    }
    res_ := []
    for c in cards {
        i := res_.Length + 1
        while (i > 1 && (res_[i - 1].y - c.y > 40 * u || (Abs(res_[i - 1].y - c.y) <= 40 * u && res_[i - 1].x > c.x)))
            i--
        res_.InsertAt(i, c)
    }
    return res_
}
OcrRef(x1, y1, x2, y2, scale := 1, ax := "c", ay := "c") => OcrRect(PX(x1, ax), PY(y1, ay), PX(x2, ax), PY(y2, ay), scale)
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
ReadYenOnce() {
    r := OcrRef(850, 920, 1070, 971, 3, "c", "b")   ; just the yen line, not the hotbar
    if !IsObject(r)
        return -1
    best := ""
    for ln in Lines(r) {
        t := RegExReplace(ln.t, "[+-]\s*\d[\d,.']*", " ")  ; "+202" / "-550" popups (also on the yen line)
        if RegExMatch(t, "(\d{1,3}(?:[ ,.']?\d{3})*)\s*[¥Yy±]", &m) {   ; the number right before the yen sign
            v := RegExReplace(m[1], "\D")
            if (v != "" && StrLen(v) <= 8)
                return Integer(v)
        }
        t := RegExReplace(t, "(?<=\d)[ ,.'](?=\d)", "")
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
