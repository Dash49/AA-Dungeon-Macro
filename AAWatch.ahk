#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
; =====================================================================
;  AAWatch.ahk - helper started by AADungeon.ahk (do not run it alone).
;  It only READS the screen, in its own process, next to the macro:
;  the yen under the hotbar, every 0.15 s, posted to the macro window.
;  It never clicks or presses keys (one mouse = one script clicks).
;  Quits by itself when the macro is gone.
; =====================================================================
Persistent
DetectHiddenWindows true
CoordMode "Pixel", "Screen"
#Include %A_ScriptDir%\Lib\OCR.ahk

global MAIN := (A_Args.Length >= 1) ? Integer(A_Args[1]) : 0
global WIN := {id: 0, x: 0, y: 0, w: 1920, h: 1080, u: 1.0}
global MSG_YEN := 0x5A01

if !MAIN
    ExitApp()
SetTimer(WatchYen, 150)
SetTimer(WatchMain, 2000)
return

; the macro was closed / reloaded: stop too
WatchMain() {
    if !WinExist("ahk_id " MAIN)
        ExitApp()
}

WatchYen() {
    static busy := false
    if busy
        return
    busy := true
    try {
        if FindRoblox() {
            v := ReadYenOnce()
            if (v >= 0)
                PostMessage(MSG_YEN, v, 0, , "ahk_id " MAIN)
        }
    }
    busy := false
}

; ---- the same screen helpers as in AADungeon.ahk (kept in step) -------
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
OcrRef(x1, y1, x2, y2, scale := 1, ax := "c", ay := "c") => OcrRect(PX(x1, ax), PY(y1, ay), PX(x2, ax), PY(y2, ay), scale)
OcrRect(x1, y1, x2, y2, scale := 1) {
    w := Round(x2 - x1), h := Round(y2 - y1)
    if (w < 8 || h < 8)
        return ""
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
