#Requires AutoHotkey v2.0
#SingleInstance Force
; =====================================================================
;  AA Dungeon - หน้าต่างตั้งค่า
;  แก้ plan.txt (ลำดับวาง/อัปยูนิต) และ settings.ini (ห้อง ร้านค้า ราคา)
;  โดยไม่ต้องเปิดไฟล์เอง  เปิดได้จากไฟล์นี้ หรือกด F8 ตอนมาโครเปิดอยู่
; =====================================================================
SetWorkingDir A_ScriptDir

global PLANFILE := A_ScriptDir "\plan.txt"
global INI := A_ScriptDir "\settings.ini"
global MACRO := A_ScriptDir "\AADungeon.ahk"

; ค่าเริ่มต้น (เหมือนในมาโคร)
global DEF := Map(
    "Boss", 100, "Chest", 70, "Hoard", 20, "Shrine", 25, "Open", 5, "Normal", 0,
    "ShopRich", 60, "ShopMid", 20, "ShopPoor", 0, "ShopRichCoins", 1000, "ShopMidCoins", 600, "ShopBuyAll", 2000,
    "Curse", -10, "CurseMidDepth", 10, "CurseMid", -30, "CurseHighDepth", 15, "CurseHigh", -60,
    "Lookahead", 0.5, "ShrineMin", 25, "ShrineChest", 20, "ShrineRare", 35,
    "SaveChests", 1, "AutoVote", 1, "OnFinish", "again",
    "Cost1", 550, "Cost2", 800, "Cost3", 2000, "Cost4", 1300, "Cost5", 2000, "Cost6", 1400,
    "Items", "Mask of Riches=100|Philosophers Stone=95|Genie Lamp=90|Golden Mushroom=80|Golden Fishhook=75"
        . "|Archmage's Hat=65 >500|Aures Maul=65 >500|Solar Cleaver=60 >500|Magic Tome=50 >500|Mage Coat=35 >500|Elf Bow=35 >500"
        . "|Speedy Boots=30|Glacial Axe=30|Golden Branch=30|Dagger=20|Nimble Cloak=20"
        . "|Reaper Scythe=0|Ninja Belt=0|Celestial Blade=0|Other=20 >1000")

global EXAMPLE_PLAN := "
(
place 1 x3
place 2 x1
place 3 x1
place 4 x1
place 5 x1
upgrade 1,2 max even until wave 5
place 5 x1
upgrade 1,2 max even
upgrade 3 to 3
ability 3 x2
upgrade 4 max
place 6 x1
upgrade 6 +1
auto 6
upgrade 3 max
ability 3 x2
upgrade 5 max one
place 6 x3
upgrade 6 max one
upgrade all max
)"

global KINDS := ["place", "upgrade", "ability", "auto", "wait", "wave"]
global KIND_TH := ["วางยูนิต", "อัปเกรด", "กดสกิล", "เปิดสกิล Auto", "รอ (วินาที)", "รอจนถึงเวฟ"]

global Steps := []          ; ขั้นตอนของแผน
global Items := []          ; ของในร้าน {name, score, min}
global E := Map()           ; ช่องกรอกของ settings.ini
global C := {}              ; ปุ่ม/ช่องอื่นๆ
global G := ""
global Dirty := false
global Filling := false

BuildGui()
LoadPlanFile()
LoadSettings()
if Steps.Length
    FillBuilder(Steps[1])
Dirty := false
G.Show("w800 h610")
return

; ============================================================== GUI
BuildGui() {
    global G
    G := Gui("+MinSize800x610", "AA Dungeon - ตั้งค่ามาโคร")
    G.SetFont("s10", "Leelawadee UI")
    G.OnEvent("Close", OnClose)
    tab := G.AddTab3("x10 y10 w780 h545", ["แผนวางยูนิต", "เลือกห้อง", "ร้านค้า", "ราคายูนิต / ทั่วไป"])

    ; ---------------------------------------------------- แท็บ 1: แผน
    tab.UseTab(1)
    G.AddText("x25 y45 w750 cGray", "มาโครจะทำทีละขั้นจากบนลงล่างในทุกห้อง  (ช่อง 1-6 = ช่อง hotbar ของยูนิต)")
    C.lv := G.AddListView("x25 y70 w750 h215 -Multi Grid", ["#", "ขั้นตอน", "คำสั่งใน plan.txt", "หมายเหตุ"])
    C.lv.ModifyCol(1, 35), C.lv.ModifyCol(2, 330), C.lv.ModifyCol(3, 210), C.lv.ModifyCol(4, 170)
    C.lv.OnEvent("ItemSelect", (ctl, row, sel) => (sel && row <= Steps.Length) ? FillBuilder(Steps[row]) : 0)

    G.AddButton("x25 y292 w70", "▲ ขึ้น").OnEvent("Click", (*) => MoveStep(-1))
    G.AddButton("x100 y292 w70", "▼ ลง").OnEvent("Click", (*) => MoveStep(1))
    G.AddButton("x175 y292 w80", "ลบแถว").OnEvent("Click", (*) => DeleteStep())
    G.AddButton("x515 y292 w120", "ใช้แผนตัวอย่าง").OnEvent("Click", (*) => LoadExample())
    G.AddButton("x640 y292 w135", "ล้างแผนทั้งหมด").OnEvent("Click", (*) => ClearPlan())

    G.AddGroupBox("x25 y325 w750 h220", "สร้าง / แก้ขั้นตอน  (คลิกแถวด้านบนเพื่อแก้แถวนั้น)")
    G.AddText("x40 y352 w60", "คำสั่ง")
    C.act := G.AddDropDownList("x105 y348 w170 Choose1", KIND_TH)
    C.act.OnEvent("Change", (*) => UpdateBuilder())

    G.AddText("x295 y352 w45", "ช่อง")
    C.slot := []
    Loop 6 {
        cb := G.AddCheckbox("x" (335 + (A_Index - 1) * 45) " y352 w40", A_Index)
        cb.OnEvent("Click", (*) => UpdateBuilder())
        C.slot.Push(cb)
    }
    C.all := G.AddCheckbox("x610 y352 w80", "ทุกตัว")
    C.all.OnEvent("Click", (*) => UpdateBuilder())

    C.nLabel := G.AddText("x40 y388 w60", "จำนวน")
    C.n := G.AddEdit("x105 y384 w60 Number", 1)
    G.AddUpDown("Range1-999", 1)
    C.n.OnEvent("Change", (*) => UpdateBuilder())

    C.goalLabel := G.AddText("x295 y388 w45", "อัปถึง")
    C.goal := G.AddDropDownList("x335 y384 w110 Choose1", ["ตัน (max)", "ถึงเลเวล", "เพิ่มอีก (ขั้น)"])
    C.goal.OnEvent("Change", (*) => UpdateBuilder())
    C.gv := G.AddEdit("x450 y384 w55 Number", 3)
    G.AddUpDown("Range1-99", 3)
    C.gv.OnEvent("Change", (*) => UpdateBuilder())
    C.style := G.AddDropDownList("x515 y384 w175 Choose1", ["ทีละตัวจนเสร็จ", "สลับกันให้เท่าๆ กัน"])
    C.style.OnEvent("Change", (*) => UpdateBuilder())

    C.untilCb := G.AddCheckbox("x40 y424 w150", "หยุดเมื่อถึงเวฟ")
    C.untilCb.OnEvent("Click", (*) => UpdateBuilder())
    C.untilW := G.AddEdit("x195 y420 w55 Number", 5)
    G.AddUpDown("Range1-99", 5)
    C.untilW.OnEvent("Change", (*) => UpdateBuilder())

    G.AddText("x295 y424 w65", "หมายเหตุ")
    C.note := G.AddEdit("x365 y420 w325")
    C.note.OnEvent("Change", (*) => UpdateBuilder())

    G.AddText("x40 y458 w60", "จะได้")
    C.preview := G.AddText("x105 y458 w590 cBlue", "")

    G.AddButton("x40 y490 w150 h35 Default", "+ เพิ่มต่อท้าย").OnEvent("Click", (*) => AddStep("end"))
    G.AddButton("x200 y490 w175 h35", "+ แทรกก่อนแถวที่เลือก").OnEvent("Click", (*) => AddStep("before"))
    G.AddButton("x385 y490 w175 h35", "✎ แก้แถวที่เลือก").OnEvent("Click", (*) => AddStep("replace"))

    ; ---------------------------------------------- แท็บ 2: เลือกห้อง
    tab.UseTab(2)
    G.AddText("x25 y45 w750 cGray", "คะแนนห้อง: มาโครจะเลือกเส้นทางที่คะแนนรวมสูงสุด  ตัวเลขติดลบ = พยายามเลี่ยง")
    y := 80
    AddNum("Boss", "ห้องบอส", 30, y), AddNum("Chest", "ห้องหีบ (Chest)", 400, y)
    y += 34
    AddNum("Hoard", "ห้อง Hoard", 30, y), AddNum("Shrine", "ห้อง Shrine", 400, y)
    y += 34
    AddNum("Open", "ห้องเปิด (Open)", 30, y), AddNum("Normal", "ห้องธรรมดา", 400, y)
    y += 34
    AddNum("Lookahead", "น้ำหนักห้องถัดไป", 30, y, "0 = ไม่ดู, 0.5 = ครึ่งหนึ่ง")
    y += 50
    G.AddGroupBox("x25 y" y " w750 h120", "ห้อง Curse")
    y += 28
    AddNum("Curse", "Curse (ช่วงแรก)", 40, y)
    y += 34
    AddNum("CurseMid", "Curse ช่วงกลาง", 40, y), AddNum("CurseMidDepth", "ช่วงกลางเริ่มที่ Depth", 400, y)
    y += 34
    AddNum("CurseHigh", "Curse ช่วงลึก", 40, y), AddNum("CurseHighDepth", "ช่วงลึกเริ่มที่ Depth", 400, y)
    y += 50
    G.AddGroupBox("x25 y" y " w750 h88", "Shrine (ห้องแลกพร)")
    y += 28
    AddNum("ShrineMin", "รับพรเมื่อคะแนนถึง", 40, y), AddNum("ShrineChest", "คะแนนพรที่ให้หีบ", 400, y)
    y += 34
    AddNum("ShrineRare", "คะแนนพรที่ให้หีบหายาก", 40, y)

    ; ------------------------------------------------ แท็บ 3: ร้านค้า
    tab.UseTab(3)
    G.AddText("x25 y45 w750 cGray", "ของที่เขียนว่าเพิ่ม luck / ลด placement cost จะซื้อก่อนเสมอ  ถ้าเหรียญเกิน 'ซื้อทุกอย่าง' จะซื้อหมด")
    AddNum("ShopBuyAll", "ซื้อทุกอย่างเมื่อเหรียญเกิน", 30, 75)
    AddNum("ShopRich", "คะแนนห้องร้าน เหรียญเยอะ", 30, 109), AddNum("ShopRichCoins", "เหรียญเยอะ = เกิน", 400, 109)
    AddNum("ShopMid", "คะแนนห้องร้าน เหรียญกลาง", 30, 143), AddNum("ShopMidCoins", "เหรียญกลาง = เกิน", 400, 143)
    AddNum("ShopPoor", "คะแนนห้องร้าน เหรียญน้อย", 30, 177)
    C.ilv := G.AddListView("x25 y215 w530 h290 -Multi Grid", ["ชื่อไอเทม", "คะแนน", "ซื้อเมื่อเหรียญเกิน"])
    C.ilv.ModifyCol(1, 270), C.ilv.ModifyCol(2, 80), C.ilv.ModifyCol(3, 150)
    C.ilv.OnEvent("ItemSelect", (ctl, row, sel) => (sel && row <= Items.Length) ? FillItem(Items[row]) : 0)
    G.AddText("x570 y215 w200", "ชื่อไอเทม (ตรงกับในเกม)")
    C.iname := G.AddEdit("x570 y237 w205")
    G.AddText("x570 y272 w95", "คะแนน")
    C.iscore := G.AddEdit("x670 y268 w105", 30)
    G.AddText("x570 y306 w95", "เหรียญเกิน")
    C.imin := G.AddEdit("x670 y302 w105 Number", 0)
    G.AddText("x570 y332 w205 cGray", "(0 = ซื้อได้ตลอด)`n'Other' = ของที่ไม่อยู่ในรายการ")
    G.AddButton("x570 y380 w100", "+ เพิ่ม").OnEvent("Click", (*) => ItemAdd(false))
    G.AddButton("x675 y380 w100", "✎ แก้").OnEvent("Click", (*) => ItemAdd(true))
    G.AddButton("x570 y415 w100", "ลบ").OnEvent("Click", (*) => ItemDelete())
    G.AddButton("x675 y415 w48", "▲").OnEvent("Click", (*) => ItemMove(-1))
    G.AddButton("x727 y415 w48", "▼").OnEvent("Click", (*) => ItemMove(1))

    ; ------------------------------------------- แท็บ 4: ราคา / ทั่วไป
    tab.UseTab(4)
    G.AddText("x25 y45 w750 cGray", "ราคาวางยูนิตแต่ละช่อง (ใช้เมื่ออ่านราคาจาก hotbar ไม่ได้)  มาโครจะรอจนเงินพอก่อนวาง")
    Loop 6
        AddNum("Cost" A_Index, "ราคาวาง ช่อง " A_Index, 30, 75 + (A_Index - 1) * 34, "¥")
    G.AddGroupBox("x25 y300 w750 h150", "ทั่วไป")
    C.save := G.AddCheckbox("x40 y330 w700", "เก็บหีบไว้เปิดตอนห้องสุดท้าย (SaveChests)")
    C.vote := G.AddCheckbox("x40 y362 w700", "กดโหวต Yes ให้อัตโนมัติ (AutoVote)")
    G.AddText("x40 y400 w170", "จบดันเจี้ยนแล้ว")
    C.finish := G.AddDropDownList("x215 y396 w250", ["เริ่มดันเจี้ยนใหม่ (again)", "หยุดมาโคร (stop)"])
    for ctl in [C.save, C.vote, C.finish]
        ctl.OnEvent(ctl.Type = "DDL" ? "Change" : "Click", (*) => MarkDirty())

    ; ---------------------------------------------------- ปุ่มล่าง
    tab.UseTab()
    G.AddButton("x10 y565 w120 h35", "บันทึก").OnEvent("Click", (*) => SaveAll(false))
    G.AddButton("x140 y565 w220 h35", "บันทึก + เปิดมาโครใหม่").OnEvent("Click", (*) => SaveAll(true))
    C.status := G.AddText("x375 y574 w415 cGreen", "")
    UpdateBuilder()
}

AddNum(key, label, x, y, tip := "") {
    G.AddText("x" x " y" (y + 4) " w190", label)
    E[key] := G.AddEdit("x" (x + 195) " y" y " w80")
    E[key].OnEvent("Change", (*) => MarkDirty())
    if (tip != "")
        G.AddText("x" (x + 282) " y" (y + 4) " w170 cGray", tip)
}

MarkDirty() {
    global Dirty
    if !Filling
        Dirty := true
}

; ============================================================ plan
NewStep(k) {
    return {k: k, slots: [], all: false, n: 1, goal: "max", gv: 1, style: "one", until: 0, note: ""}
}

ParseStep(line) {
    l := StrLower(Trim(line))
    for th, en in Map("วาง", "place", "อัพ", "upgrade", "อัป", "upgrade", "สกิล", "ability", "ออโต้", "auto",
        "รอ", "wait", "เวฟ", "wave", "ตัน", "max", "เฉลี่ย", "even", "ทีละตัว", "one")
        l := StrReplace(l, th, en)
    if RegExMatch(l, "^place\s+([1-6])\s*(?:x\s*(\d+))?$", &m) {
        s := NewStep("place"), s.slots := [Integer(m[1])], s.n := m[2] != "" ? Integer(m[2]) : 1
        return s
    }
    if RegExMatch(l, "^upgrade\s+(all|[1-6](?:\s*,\s*[1-6])*)(.*)$", &m) {
        s := NewStep("upgrade")
        if (m[1] = "all")
            s.all := true
        else
            for v in StrSplit(m[1], ",", " ")
                s.slots.Push(Integer(v))
        rest := m[2]
        if RegExMatch(rest, "to\s*(\d+)", &g)
            s.goal := "to", s.gv := Integer(g[1])
        if RegExMatch(rest, "\+\s*(\d+)", &g)
            s.goal := "plus", s.gv := Integer(g[1])
        if InStr(rest, "even")
            s.style := "even"
        if RegExMatch(rest, "until\s*wave\s*(\d+)", &g)
            s.until := Integer(g[1])
        return s
    }
    if RegExMatch(l, "^ability\s+([1-6])\s*(?:x\s*(\d+))?$", &m) {
        s := NewStep("ability"), s.slots := [Integer(m[1])], s.n := m[2] != "" ? Integer(m[2]) : 1
        return s
    }
    if RegExMatch(l, "^auto\s+([1-6])$", &m) {
        s := NewStep("auto"), s.slots := [Integer(m[1])]
        return s
    }
    if RegExMatch(l, "^wait\s+(\d+)$", &m) {
        s := NewStep("wait"), s.n := Integer(m[1])
        return s
    }
    if RegExMatch(l, "^wave\s+(\d+)$", &m) {
        s := NewStep("wave"), s.n := Integer(m[1])
        return s
    }
    return ""
}

JoinSlots(arr) {
    t := ""
    for v in arr
        t .= (t = "" ? "" : ",") v
    return t
}

StepCmd(s) {
    switch s.k {
        case "place":   return "place " s.slots[1] " x" s.n
        case "ability": return "ability " s.slots[1] " x" s.n
        case "auto":    return "auto " s.slots[1]
        case "wait":    return "wait " s.n
        case "wave":    return "wave " s.n
        case "upgrade":
            t := "upgrade " (s.all ? "all" : JoinSlots(s.slots))
            t .= (s.goal = "max") ? " max" : (s.goal = "to") ? " to " s.gv : " +" s.gv
            t .= (s.style = "even") ? " even" : " one"
            if s.until
                t .= " until wave " s.until
            return t
    }
    return ""
}

StepDesc(s) {
    switch s.k {
        case "place":   return "วางยูนิตช่อง " s.slots[1] " จำนวน " s.n " ตัว"
        case "ability": return "กดสกิลยูนิตช่อง " s.slots[1] " จำนวน " s.n " ครั้ง"
        case "auto":    return "เปิดสกิล Auto ยูนิตช่อง " s.slots[1]
        case "wait":    return "รอ " s.n " วินาที"
        case "wave":    return "รอจนถึงเวฟ " s.n
        case "upgrade":
            t := "อัปเกรด" (s.all ? "ทุกตัว" : "ช่อง " JoinSlots(s.slots))
            t .= (s.goal = "max") ? " ให้ตัน" : (s.goal = "to") ? " ถึงเลเวล " s.gv : " เพิ่มอีก " s.gv " ขั้น"
            if (s.style = "even" && (s.all || s.slots.Length > 1))
                t .= " (สลับกันให้เท่าๆ กัน)"
            else if (s.all || s.slots.Length > 1)
                t .= " (ทีละตัว)"
            if s.until
                t .= " หยุดเมื่อถึงเวฟ " s.until
            return t
    }
    return ""
}

LoadPlanFile() {
    global Steps
    Steps := []
    text := FileExist(PLANFILE) ? FileRead(PLANFILE, "UTF-8") : EXAMPLE_PLAN
    LoadPlanText(text)
}

LoadPlanText(text) {
    global Steps
    Steps := []
    bad := "", note := ""
    for i, raw in StrSplit(text, "`n", "`r") {
        line := Trim(raw)
        if (line = "") {
            note := ""
            continue
        }
        if (SubStr(line, 1, 1) = ";") {             ; comment line = note of the next step
            c := Trim(SubStr(line, 2))
            note := InStr(c, "=====") ? "" : c
            continue
        }
        cmd := line, inl := ""
        if (p := InStr(line, ";"))
            cmd := Trim(SubStr(line, 1, p - 1)), inl := Trim(SubStr(line, p + 1))
        s := ParseStep(cmd)
        if !IsObject(s) {
            bad .= "บรรทัด " i ": " line "`n"
            continue
        }
        s.note := inl != "" ? inl : note
        note := ""
        Steps.Push(s)
    }
    RefreshPlan(Steps.Length ? 1 : 0)
    if (bad != "")
        MsgBox("บรรทัดเหล่านี้ใน plan.txt อ่านไม่ได้ จะถูกตัดทิ้งตอนบันทึก:`n`n" bad, "AA Dungeon", "Icon!")
}

RefreshPlan(sel := 0) {
    C.lv.Opt("-Redraw")
    C.lv.Delete()
    for i, s in Steps
        C.lv.Add(, i, StepDesc(s), StepCmd(s), s.note)
    C.lv.Opt("+Redraw")
    if (sel >= 1 && sel <= Steps.Length)
        C.lv.Modify(sel, "Select Focus Vis")
}

; read the builder -> step (or "" + reason)
BuilderStep(&why := "") {
    k := KINDS[C.act.Value]
    s := NewStep(k)
    slots := []
    for i, cb in C.slot
        if cb.Value
            slots.Push(i)
    n := Trim(C.n.Value)
    if (k = "place" || k = "ability" || k = "auto") {
        if (slots.Length != 1) {
            why := "เลือกช่องยูนิต 1 ช่อง"
            return ""
        }
        s.slots := slots
    }
    if (k = "upgrade") {
        if C.all.Value
            s.all := true
        else if !slots.Length {
            why := "เลือกช่องยูนิตอย่างน้อย 1 ช่อง หรือ 'ทุกตัว'"
            return ""
        }
        s.slots := slots
        goals := ["max", "to", "plus"]
        s.goal := goals[C.goal.Value]
        if (s.goal != "max") {
            if !(IsInteger(C.gv.Value) && C.gv.Value >= 1) {
                why := "ใส่ตัวเลขเลเวล/ขั้น"
                return ""
            }
            s.gv := Integer(C.gv.Value)
        }
        s.style := C.style.Value = 2 ? "even" : "one"
        if C.untilCb.Value {
            if !(IsInteger(C.untilW.Value) && C.untilW.Value >= 1) {
                why := "ใส่เลขเวฟ"
                return ""
            }
            s.until := Integer(C.untilW.Value)
        }
    }
    if (k = "place" || k = "ability" || k = "wait" || k = "wave") {
        if !(IsInteger(n) && n >= 1) {
            why := "ใส่ตัวเลข 1 ขึ้นไป"
            return ""
        }
        s.n := Integer(n)
    }
    s.note := Trim(StrReplace(StrReplace(C.note.Value, "`n", " "), ";", ","))
    return s
}

UpdateBuilder() {
    k := KINDS[C.act.Value]
    slotOn := (k != "wait" && k != "wave")
    isUp := (k = "upgrade")
    for cb in C.slot
        cb.Enabled := slotOn && !(isUp && C.all.Value)
    C.all.Enabled := isUp
    nOn := (k = "place" || k = "ability" || k = "wait" || k = "wave")
    C.n.Enabled := nOn
    C.nLabel.Text := (k = "place") ? "จำนวนตัว" : (k = "ability") ? "กี่ครั้ง" : (k = "wait") ? "วินาที" : (k = "wave") ? "เวฟ" : "จำนวน"
    C.goal.Enabled := isUp, C.style.Enabled := isUp, C.untilCb.Enabled := isUp
    C.gv.Enabled := isUp && C.goal.Value != 1
    C.untilW.Enabled := isUp && C.untilCb.Value
    s := BuilderStep(&why)
    C.preview.Text := IsObject(s) ? StepDesc(s) "     →  " StepCmd(s) : "(ยังไม่ครบ: " why ")"
}

FillBuilder(s) {
    global Filling
    Filling := true
    C.act.Value := ArrIndex(KINDS, s.k)
    for i, cb in C.slot {
        on := false
        for v in s.slots
            on := on || (v = i)
        cb.Value := on
    }
    C.all.Value := s.all
    C.n.Value := s.n
    C.goal.Value := (s.goal = "to") ? 2 : (s.goal = "plus") ? 3 : 1
    C.gv.Value := s.gv
    C.style.Value := (s.style = "even") ? 2 : 1
    C.untilCb.Value := s.until ? 1 : 0
    if s.until
        C.untilW.Value := s.until
    C.note.Value := s.note
    Filling := false
    UpdateBuilder()
}

ArrIndex(arr, v) {
    for i, x in arr
        if (x = v)
            return i
    return 1
}

AddStep(where) {
    global Dirty
    s := BuilderStep(&why)
    if !IsObject(s) {
        MsgBox("ยังสร้างขั้นตอนไม่ได้: " why, "AA Dungeon", "Icon!")
        return
    }
    row := C.lv.GetNext()
    if (where = "replace") {
        if !row {
            MsgBox("คลิกเลือกแถวที่จะแก้ก่อน", "AA Dungeon", "Icon!")
            return
        }
        Steps[row] := s
    } else if (where = "before" && row) {
        Steps.InsertAt(row, s)
    } else {
        Steps.Push(s), row := Steps.Length
    }
    Dirty := true
    RefreshPlan(row)
}

DeleteStep() {
    global Dirty
    if !(row := C.lv.GetNext())
        return
    Steps.RemoveAt(row)
    Dirty := true
    RefreshPlan(Min(row, Steps.Length))
}

MoveStep(d) {
    global Dirty
    row := C.lv.GetNext(), to := row + d
    if (!row || to < 1 || to > Steps.Length)
        return
    t := Steps[row], Steps[row] := Steps[to], Steps[to] := t
    Dirty := true
    RefreshPlan(to)
}

ClearPlan() {
    global Steps, Dirty
    if (MsgBox("ลบทุกขั้นตอนในแผน?", "AA Dungeon", "YesNo Icon?") != "Yes")
        return
    Steps := [], Dirty := true
    RefreshPlan()
}

LoadExample() {
    global Dirty
    if (Steps.Length && MsgBox("แทนที่แผนตอนนี้ด้วยแผนตัวอย่าง?", "AA Dungeon", "YesNo Icon?") != "Yes")
        return
    LoadPlanText(EXAMPLE_PLAN)
    Dirty := true
}

SavePlan() {
    t := "; ===== แผนวางยูนิต (แก้ด้วย AASettings.ahk ได้) =====`r`n"
    t .= "; มาโครทำทีละบรรทัดจากบนลงล่าง  ช่อง 1-6 = ช่อง hotbar`r`n"
    for s in Steps {
        if (s.note != "")
            t .= "; " s.note "`r`n"
        t .= StepCmd(s) "`r`n"
    }
    f := FileOpen(PLANFILE, "w", "UTF-8")
    f.Write(t)
    f.Close()
}

; ============================================================ shop items
ParseItems(str) {
    arr := []
    for part in StrSplit(str, "|") {
        part := Trim(part)
        if (part = "" || !(p := InStr(part, "=", , -1)))
            continue
        name := Trim(SubStr(part, 1, p - 1)), rest := SubStr(part, p + 1)
        sc := 0, mn := 0
        if RegExMatch(rest, "(-?\d+(?:\.\d+)?)", &m)
            sc := m[1] + 0
        if RegExMatch(rest, ">\s*(\d+)", &m)
            mn := Integer(m[1])
        arr.Push({name: name, score: sc, min: mn})
    }
    return arr
}

ItemsString() {
    t := ""
    for it in Items
        t .= (t = "" ? "" : "|") it.name "=" it.score (it.min > 0 ? " >" it.min : "")
    return t
}

RefreshItems(sel := 0) {
    C.ilv.Delete()
    for it in Items
        C.ilv.Add(, it.name, it.score, it.min > 0 ? it.min : "-")
    if (sel >= 1 && sel <= Items.Length)
        C.ilv.Modify(sel, "Select Focus Vis")
}

FillItem(it) {
    C.iname.Value := it.name, C.iscore.Value := it.score, C.imin.Value := it.min
}

ItemAdd(replace) {
    global Dirty
    name := Trim(StrReplace(StrReplace(C.iname.Value, "|", ""), "=", ""))
    if (name = "" || !IsNumber(Trim(C.iscore.Value))) {
        MsgBox("ใส่ชื่อไอเทมและคะแนน (ตัวเลข)", "AA Dungeon", "Icon!")
        return
    }
    it := {name: name, score: Trim(C.iscore.Value) + 0, min: IsInteger(C.imin.Value) ? Integer(C.imin.Value) : 0}
    row := C.ilv.GetNext()
    if replace {
        if !row {
            MsgBox("คลิกเลือกไอเทมที่จะแก้ก่อน", "AA Dungeon", "Icon!")
            return
        }
        Items[row] := it
    } else
        Items.Push(it), row := Items.Length
    Dirty := true
    RefreshItems(row)
}

ItemDelete() {
    global Dirty
    if !(row := C.ilv.GetNext())
        return
    Items.RemoveAt(row), Dirty := true
    RefreshItems(Min(row, Items.Length))
}

ItemMove(d) {
    global Dirty
    row := C.ilv.GetNext(), to := row + d
    if (!row || to < 1 || to > Items.Length)
        return
    t := Items[row], Items[row] := Items[to], Items[to] := t
    Dirty := true
    RefreshItems(to)
}

; ============================================================ settings
LoadSettings() {
    global Items, Filling
    Filling := true
    for k, v in DEF {
        val := IniRead(INI, "Settings", k, v)
        if E.Has(k)
            E[k].Value := val
        else if (k = "Items")
            Items := ParseItems(val)
        else if (k = "SaveChests")
            C.save.Value := (val + 0) ? 1 : 0
        else if (k = "AutoVote")
            C.vote.Value := (val + 0) ? 1 : 0
        else if (k = "OnFinish")
            C.finish.Value := (StrLower(val) = "stop") ? 2 : 1
    }
    Filling := false
    RefreshItems()
}

SaveAll(restart) {
    global Dirty
    ; check numbers first, write nothing if one is wrong
    for k, ctl in E {
        if !IsNumber(Trim(ctl.Value)) {
            MsgBox("ช่อง '" k "' ต้องเป็นตัวเลข", "AA Dungeon", "Icon!")
            return
        }
    }
    try {
        for k, ctl in E
            IniWrite(Trim(ctl.Value), INI, "Settings", k)
        IniWrite(ItemsString(), INI, "Settings", "Items")
        IniWrite(C.save.Value ? 1 : 0, INI, "Settings", "SaveChests")
        IniWrite(C.vote.Value ? 1 : 0, INI, "Settings", "AutoVote")
        IniWrite(C.finish.Value = 2 ? "stop" : "again", INI, "Settings", "OnFinish")
        SavePlan()
    } catch as err {
        MsgBox("บันทึกไม่สำเร็จ: " err.Message, "AA Dungeon", "Icon!")
        return
    }
    Dirty := false
    C.status.Text := "บันทึกแล้ว " FormatTime(, "HH:mm:ss")
    if restart {
        if FileExist(MACRO) {
            Run('"' A_AhkPath '" "' MACRO '"')
            C.status.Text .= "  -  เปิดมาโครใหม่แล้ว กด F2 ในเกมเพื่อเริ่ม"
        } else
            MsgBox("ไม่พบ AADungeon.ahk ในโฟลเดอร์เดียวกัน", "AA Dungeon", "Icon!")
    } else
        C.status.Text .= "  -  ถ้ามาโครเปิดอยู่ ให้กด F3 เพื่อโหลดค่าใหม่"
}

OnClose(*) {
    if Dirty {
        r := MsgBox("ยังไม่ได้บันทึก จะบันทึกก่อนปิดไหม?", "AA Dungeon", "YesNoCancel Icon?")
        if (r = "Cancel")
            return true                            ; keep the window open
        if (r = "Yes") {
            SaveAll(false)
            if Dirty
                return true
        }
    }
    ExitApp
}
