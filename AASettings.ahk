#Requires AutoHotkey v2.0
#SingleInstance Force
; =====================================================================
;  AA Dungeon - หน้าต่างตั้งค่า
;  แก้ plan.txt (ลำดับวาง/อัปยูนิต) และ settings.ini (ห้อง ร้านค้า ราคา)
;  โดยไม่ต้องเปิดไฟล์เอง  เปิดได้จากไฟล์นี้ หรือกด F8 ตอนมาโครเปิดอยู่
; =====================================================================
SetWorkingDir A_ScriptDir
CoordMode "Mouse", "Screen"
CoordMode "ToolTip", "Screen"
#Include %A_ScriptDir%\Lib\OCR.ahk          ; only to check OCR languages in bug reports

global PLANFILE := A_ScriptDir "\plan.txt"
global INI := A_ScriptDir "\settings.ini"
global MACRO := A_ScriptDir "\AADungeon.ahk"

; ---- รายงานบั๊ก ----
; หน้าแจ้งบั๊กบน GitHub (ผู้ใช้ลากไฟล์ zip ใส่เอง)
global ISSUE_URL := "https://github.com/Dash49/AA-Dungeon-Macro/issues/new?template=bug_report.yml"
; ถ้าใส่ Discord webhook ตรงนี้ ปุ่มรายงานบั๊กจะส่งไฟล์เข้าห้อง Discord ให้เลย
; (เว้นว่าง = ใช้ GitHub อย่างเดียว)
global REPORT_WEBHOOK := ""

; ค่าเริ่มต้น (เหมือนในมาโคร)
global DEF := Map(
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
    "StageWalk", "Magic Hill=a 3 jump|Snowy Town=d 3 jump, w 1 jump",
    "Items", "Mask of Riches=100|Philosophers Stone=95|Genie Lamp=90|Golden Mushroom=85|Celestial Blade=80"
        . "|Golden Fishhook=75|Archmage's Hat=70|Aures Maul=70|Shimmering Moon Fragment=60"
        . "|Solar Cleaver=55|Reaper Scythe=50|Magic Tome=50|Glacial Axe=50|Fish Hook=45|Speedy Boots=45"
        . "|Golden Branch=40|Elf Bow=40|Ninja Belt=35|Sword=35|Mage Coat=30|Axe=30|Nimble Cloak=25|Bow=25"
        . "|Dagger=20|Other=20 >1000")

global EXAMPLE_PLAN := "
(
place 1 x3 far
place 2 x1 far
place 3 x1 cover
place 4 x1 near
place 5 x1 group
upgrade 1,2 max even until wave 5
place 5 x1 group
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
place 6 x3 spread
upgrade 6 max one
upgrade all max
)"

global KINDS := ["place", "upgrade", "ability", "auto", "wait", "wave"]
global PLACE_KEYS := ["random", "near", "far", "group", "spread", "cover", "center", "at"]
global PLACE_TH := ["สุ่มใกล้ทาง (ค่าเริ่มต้น)", "ชิดทางเดิน", "ไกลทางเดิน (ตัวฟาร์ม)", "รวมกลุ่มติดกัน",
    "กระจายห่างกัน", "จุดที่ทางผ่านเยอะ (โค้ง)", "กลางจอ", "กำหนดจุดเอง"]
global PLACE_DESC := Map("near", "ชิดทางเดิน", "far", "ไกลทางเดิน", "group", "รวมกลุ่ม", "spread", "กระจายห่างกัน",
    "cover", "ตรงโค้ง/จุดที่ทางผ่านเยอะ", "center", "กลางจอ")
global PickResult := ""
global Seen := []                ; items the shop has shown (items_seen.txt)
; known dungeon shop items (from the game wiki + shop pictures): name, effect, suggested points
global ITEMDB := [
    {name: "Mask of Riches", eff: "-50% ค่าวาง/อัปเกรด", pts: 100},
    {name: "Philosophers Stone", eff: "เปลี่ยนหีบทั้งหมดเป็นหีบหายาก", pts: 95},
    {name: "Genie Lamp", eff: "+100% โชคหีบ (luck)", pts: 90},
    {name: "Golden Mushroom", eff: "-30% ค่าวาง/อัปเกรด", pts: 85},
    {name: "Celestial Blade", eff: "+777% true damage, +75% attack", pts: 80},
    {name: "Golden Fishhook", eff: "+40% โชคหีบ (luck)", pts: 75},
    {name: "Archmage's Hat", eff: "+250% magic damage", pts: 70},
    {name: "Aures Maul", eff: "+200% physical damage", pts: 70},
    {name: "Shimmering Moon Fragment", eff: "+1 Star Remnant ทุกหีบที่เปิด", pts: 60},
    {name: "Solar Cleaver", eff: "+100% physical crit chance", pts: 55},
    {name: "Reaper Scythe", eff: "+75% damage ใส่บอส", pts: 50},
    {name: "Magic Tome", eff: "+100% magic damage", pts: 50},
    {name: "Glacial Axe", eff: "ศัตรูเดินช้าลง 30%", pts: 50},
    {name: "Fish Hook", eff: "+20% โชคหีบ (luck)", pts: 45},
    {name: "Speedy Boots", eff: "-20% attack cooldown", pts: 45},
    {name: "Golden Branch", eff: "-15% ค่าวาง/อัปเกรด", pts: 40},
    {name: "Elf Bow", eff: "+50% range", pts: 40},
    {name: "Ninja Belt", eff: "-12% attack cooldown", pts: 35},
    {name: "Sword", eff: "+30% attack", pts: 35},
    {name: "Mage Coat", eff: "+50% magic damage", pts: 30},
    {name: "Axe", eff: "+50% physical crit chance", pts: 30},
    {name: "Nimble Cloak", eff: "-7% attack cooldown", pts: 25},
    {name: "Bow", eff: "+20% range", pts: 25},
    {name: "Dagger", eff: "+15% attack", pts: 20}
]
; ready-made settings for room choice, curses, shrines and the shop
global PRESETS := [
    {key: "beginner", th: "🟢 มือใหม่ (ปลอดภัยไว้ก่อน)",
     desc: "เลี่ยงห้อง Curse ให้มากที่สุด ไม่รับ Shrine เน้นผ่านด่านให้ได้ก่อน เหมาะกับทีมที่ยังไม่แข็ง",
     vals: Map("Boss", 100, "Chest", 40, "Hoard", 30, "Shrine", 0, "Open", 10, "Normal", 5, "Curse", -60, "CurseMid", -120,
        "CurseHigh", -200, "CurseMidDepth", 8, "CurseHighDepth", 14, "Lookahead", 0.5, "ShopRich", 50, "ShopMid", 25,
        "ShopPoor", 0, "ShopRichCoins", 1000, "ShopMidCoins", 600, "ShopBuyAll", 2500, "ShrineMode", "never",
        "ShrineMin", 50, "ShrineChest", 20, "ShrineRare", 35)},
    {key: "balanced", th: "🔵 สมดุล (ค่าเริ่มต้น)",
     desc: "ชอบห้องหีบ เลี่ยง Curse พอประมาณ (หนักขึ้นเมื่อลึก) Shrine ที่ให้หีบรับเสมอ",
     vals: Map("Boss", 100, "Chest", 70, "Hoard", 20, "Shrine", 25, "Open", 5, "Normal", 0, "Curse", -10, "CurseMid", -30,
        "CurseHigh", -60, "CurseMidDepth", 10, "CurseHighDepth", 15, "Lookahead", 0.5, "ShopRich", 60, "ShopMid", 20,
        "ShopPoor", 0, "ShopRichCoins", 1000, "ShopMidCoins", 600, "ShopBuyAll", 2000, "ShrineMode", "chest",
        "ShrineMin", 25, "ShrineChest", 20, "ShrineRare", 35)},
    {key: "chest", th: "🟡 ล่าหีบ (หีบมาก่อนเสมอ)",
     desc: "หีบสำคัญที่สุด ยอมเข้า Curse ถ้าได้หีบ มองห้องถัดไปมากขึ้น Shrine ที่ให้หีบรับเสมอ",
     vals: Map("Boss", 100, "Chest", 130, "Hoard", 20, "Shrine", 45, "Open", 5, "Normal", 0, "Curse", -5, "CurseMid", -15,
        "CurseHigh", -35, "CurseMidDepth", 10, "CurseHighDepth", 16, "Lookahead", 0.8, "ShopRich", 45, "ShopMid", 15,
        "ShopPoor", 0, "ShopRichCoins", 1200, "ShopMidCoins", 700, "ShopBuyAll", 2500, "ShrineMode", "chest",
        "ShrineMin", 20, "ShrineChest", 40, "ShrineRare", 60)},
    {key: "advanced", th: "🔴 ขั้นสูง (ของเยอะสุด เสี่ยงสุด)",
     desc: "สำหรับทีมแข็ง: เข้า Curse ได้แทบไม่สน รับ Shrine ทุกครั้ง หีบ+Hoard สูง มองห้องถัดไปเต็มที่",
     vals: Map("Boss", 100, "Chest", 150, "Hoard", 50, "Shrine", 60, "Open", 5, "Normal", 0, "Curse", 0, "CurseMid", -10,
        "CurseHigh", -20, "CurseMidDepth", 12, "CurseHighDepth", 18, "Lookahead", 1.0, "ShopRich", 60, "ShopMid", 30,
        "ShopPoor", 5, "ShopRichCoins", 1000, "ShopMidCoins", 500, "ShopBuyAll", 1500, "ShrineMode", "always",
        "ShrineMin", 0, "ShrineChest", 40, "ShrineRare", 60)},
    {key: "coins", th: "💰 ฟาร์มเหรียญ + ร้านค้า",
     desc: "เน้น Hoard (เหรียญ) และร้านค้าเพื่อซื้อของเพิ่มพลัง ซื้อทุกอย่างเมื่อเหรียญเกิน 1500",
     vals: Map("Boss", 100, "Chest", 50, "Hoard", 90, "Shrine", 20, "Open", 5, "Normal", 0, "Curse", -15, "CurseMid", -35,
        "CurseHigh", -70, "CurseMidDepth", 10, "CurseHighDepth", 15, "Lookahead", 0.6, "ShopRich", 100, "ShopMid", 50,
        "ShopPoor", 0, "ShopRichCoins", 900, "ShopMidCoins", 500, "ShopBuyAll", 1500, "ShrineMode", "chest",
        "ShrineMin", 25, "ShrineChest", 20, "ShrineRare", 35)},
    {key: "deep", th: "🛡 ลงลึกให้รอด (เน้นถึงบอส)",
     desc: "ช่วงต้นเก็บของได้ แต่ยิ่งลึกยิ่งหนี Curse หนัก เก็บเงินซื้อของในร้านไว้สู้ช่วงท้าย Shrine คิดจากคะแนน",
     vals: Map("Boss", 100, "Chest", 60, "Hoard", 30, "Shrine", 15, "Open", 10, "Normal", 5, "Curse", -10, "CurseMid", -80,
        "CurseHigh", -200, "CurseMidDepth", 8, "CurseHighDepth", 13, "Lookahead", 0.7, "ShopRich", 80, "ShopMid", 40,
        "ShopPoor", 10, "ShopRichCoins", 900, "ShopMidCoins", 500, "ShopBuyAll", 2000, "ShrineMode", "points",
        "ShrineMin", 30, "ShrineChest", 25, "ShrineRare", 40)},
    {key: "nocurse", th: "🚫 ไม่เอาคำสาปเลย",
     desc: "ไม่เข้าห้อง Curse และไม่รับ Shrine เด็ดขาด (ถ้ามีทางเลือกอื่น) ช้ากว่าแต่ปลอดภัยที่สุด",
     vals: Map("Boss", 100, "Chest", 60, "Hoard", 30, "Shrine", 0, "Open", 10, "Normal", 5, "Curse", -1000, "CurseMid", -1000,
        "CurseHigh", -1000, "CurseMidDepth", 10, "CurseHighDepth", 15, "Lookahead", 0.5, "ShopRich", 60, "ShopMid", 25,
        "ShopPoor", 0, "ShopRichCoins", 1000, "ShopMidCoins", 600, "ShopBuyAll", 2000, "ShrineMode", "never",
        "ShrineMin", 999, "ShrineChest", 20, "ShrineRare", 35)}
]
global SHRINE_KEYS := ["chest", "points", "always", "never"]
global SHRINE_TH := ["ได้หีบ = รับเสมอ ไม่สนคำสาป (แนะนำ)", "คิดจากคะแนน (หีบ + คำสาป)", "รับทุกครั้ง", "ไม่รับเลย"]
global SlotNames := ["", "", "", "", "", ""]     ; unit names per hotbar slot (Name1..Name6)
; ---- update: only the program files are replaced, never settings.ini / plan.txt
global REPO_RAW := "https://raw.githubusercontent.com/Dash49/AA-Dungeon-Macro/main/"
global UPDATE_FILES := ["AADungeon.ahk", "AASettings.ahk", "Lib/OCR.ahk"]
global KIND_TH := ["วางยูนิต", "อัปเกรด", "กดสกิล", "เปิดสกิล Auto", "รอ (วินาที)", "รอจนถึงเวฟ"]

global Steps := []          ; ขั้นตอนของแผน
global Items := []          ; ของในร้าน {name, score, min}
global E := Map()           ; ช่องกรอกของ settings.ini
global C := {}              ; ปุ่ม/ช่องอื่นๆ
global G := ""
global Dirty := false
global Filling := false

if (A_Args.Length && A_Args[1] = "/report") {       ; F9 in the macro
    ReportBug()
    ExitApp
}
BuildGui()
LoadPlanFile()
LoadSettings()
if Steps.Length
    FillBuilder(Steps[1])
Dirty := false
G.Show("w800 h720")
return

; ============================================================== GUI
BuildGui() {
    global G
    G := Gui("+MinSize800x720", "AA Dungeon - ตั้งค่ามาโคร")
    G.SetFont("s10", "Leelawadee UI")
    G.OnEvent("Close", OnClose)
    tab := G.AddTab3("x10 y10 w780 h625", ["แผนวางยูนิต", "เลือกห้อง", "ร้านค้า", "ยูนิต / ทั่วไป"])

    ; ---------------------------------------------------- แท็บ 1: แผน
    tab.UseTab(1)
    C.legend := G.AddText("x25 y45 w750 cGray", "มาโครจะทำทีละขั้นจากบนลงล่างในทุกห้อง  (ช่อง 1-6 = ช่อง hotbar ของยูนิต)")
    C.lv := G.AddListView("x25 y70 w750 h215 -Multi Grid", ["#", "ขั้นตอน", "คำสั่งใน plan.txt", "หมายเหตุ"])
    C.lv.ModifyCol(1, 35), C.lv.ModifyCol(2, 330), C.lv.ModifyCol(3, 210), C.lv.ModifyCol(4, 170)
    C.lv.OnEvent("ItemSelect", (ctl, row, sel) => (sel && row <= Steps.Length) ? FillBuilder(Steps[row]) : 0)

    G.AddButton("x25 y292 w70", "▲ ขึ้น").OnEvent("Click", (*) => MoveStep(-1))
    G.AddButton("x100 y292 w70", "▼ ลง").OnEvent("Click", (*) => MoveStep(1))
    G.AddButton("x175 y292 w80", "ลบแถว").OnEvent("Click", (*) => DeleteStep())
    G.AddButton("x515 y292 w120", "ใช้แผนตัวอย่าง").OnEvent("Click", (*) => LoadExample())
    G.AddButton("x640 y292 w135", "ล้างแผนทั้งหมด").OnEvent("Click", (*) => ClearPlan())

    G.AddGroupBox("x25 y325 w750 h260", "สร้าง / แก้ขั้นตอน  (คลิกแถวด้านบนเพื่อแก้แถวนั้น)")
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

    G.AddText("x40 y460 w60", "ท่าวาง")
    C.pstyle := G.AddDropDownList("x105 y456 w230 Choose1", PLACE_TH)
    C.pstyle.OnEvent("Change", (*) => UpdateBuilder())
    C.atLabel := G.AddText("x350 y460 w50", "จุด X,Y")
    C.atX := G.AddEdit("x405 y456 w55 Number", 960)
    C.atX.OnEvent("Change", (*) => UpdateBuilder())
    C.atY := G.AddEdit("x465 y456 w55 Number", 540)
    C.atY.OnEvent("Change", (*) => UpdateBuilder())
    C.pick := G.AddButton("x530 y454 w160", "🎯 เลือกจุดบนจอเกม")
    C.pick.OnEvent("Click", (*) => PickSpot())

    G.AddText("x40 y496 w60", "จะได้")
    C.preview := G.AddText("x105 y496 w665 cBlue", "")

    G.AddButton("x40 y530 w150 h35 Default", "+ เพิ่มต่อท้าย").OnEvent("Click", (*) => AddStep("end"))
    G.AddButton("x200 y530 w175 h35", "+ แทรกก่อนแถวที่เลือก").OnEvent("Click", (*) => AddStep("before"))
    G.AddButton("x385 y530 w175 h35", "✎ แก้แถวที่เลือก").OnEvent("Click", (*) => AddStep("replace"))

    ; ---------------------------------------------- แท็บ 2: เลือกห้อง
    tab.UseTab(2)
    G.AddText("x25 y45 w750 cGray", "เลือกโหมดสำเร็จรูปแล้วกด 'ใช้โหมดนี้' จะตั้งค่าด้านล่างให้ทั้งหมด (ปรับเองต่อได้) แล้วกดบันทึก")
    G.AddText("x30 y78 w60", "โหมด")
    pnames := []
    for pr in PRESETS
        pnames.Push(pr.th)
    C.preset := G.AddDropDownList("x95 y74 w330 Choose2", pnames)
    C.preset.OnEvent("Change", (*) => (C.pdesc.Text := PRESETS[C.preset.Value].desc))
    G.AddButton("x435 y72 w140 h28", "✔ ใช้โหมดนี้").OnEvent("Click", (*) => ApplyPreset())
    C.pdesc := G.AddText("x30 y106 w740 h36 cBlue", PRESETS[2].desc)
    G.AddText("x25 y146 w750 cGray", "คะแนนห้อง: มาโครจะเลือกเส้นทางที่คะแนนรวมสูงสุด  ตัวเลขติดลบ = พยายามเลี่ยง")
    y := 170
    AddNum("Boss", "ห้องบอส", 30, y), AddNum("Chest", "ห้องหีบ (Chest)", 400, y)
    y += 34
    AddNum("Hoard", "ห้อง Hoard", 30, y), AddNum("Shrine", "ห้อง Shrine", 400, y)
    y += 34
    AddNum("Open", "ห้องเปิด (Open)", 30, y), AddNum("Normal", "ห้องธรรมดา", 400, y)
    y += 34
    AddNum("Lookahead", "น้ำหนักห้องถัดไป", 30, y, "0 = ไม่ดู, 0.5 = ครึ่งหนึ่ง", 300)
    y += 42
    G.AddGroupBox("x25 y" y " w750 h120", "ห้อง Curse")
    y += 28
    AddNum("Curse", "Curse (ช่วงแรก)", 40, y)
    y += 34
    AddNum("CurseMid", "Curse ช่วงกลาง", 40, y), AddNum("CurseMidDepth", "ช่วงกลางเริ่มที่ Depth", 400, y)
    y += 34
    AddNum("CurseHigh", "Curse ช่วงลึก", 40, y), AddNum("CurseHighDepth", "ช่วงลึกเริ่มที่ Depth", 400, y)
    y += 40
    G.AddGroupBox("x25 y" y " w750 h178", "Shrine (ห้องแลกพร: ได้ของ แต่โดนคำสาป)")
    y += 28
    G.AddText("x40 y" (y + 4) " w190", "เมื่อเจอ Shrine")
    C.shrine := G.AddDropDownList("x235 y" y " w380 Choose1", SHRINE_TH)
    C.shrine.OnEvent("Change", (*) => MarkDirty())
    y += 34
    G.AddText("x40 y" (y + 4) " w190", "คำสาปที่ไม่รับเด็ดขาด")
    C.avoid := G.AddEdit("x235 y" y " w380")
    C.avoid.OnEvent("Change", (*) => MarkDirty())
    G.AddText("x622 y" (y + 4) " w150 cGray", "เช่น Health, Shield")
    y += 34
    AddNum("ShrineMin", "แบบคะแนน: รับเมื่อถึง", 40, y), AddNum("ShrineChest", "คะแนนพรที่ให้หีบ", 400, y)
    y += 34
    AddNum("ShrineRare", "คะแนนพรที่ให้หีบหายาก", 40, y)

    ; ------------------------------------------------ แท็บ 3: ร้านค้า
    tab.UseTab(3)
    G.AddText("x25 y45 w750 cGray", "ของที่เขียนว่าเพิ่ม luck / ลด placement cost จะซื้อก่อนเสมอ  ถ้าเหรียญเกิน 'ซื้อทุกอย่าง' จะซื้อหมด")
    AddNum("ShopBuyAll", "ซื้อทุกอย่างเมื่อเหรียญเกิน", 30, 75)
    AddNum("ShopRich", "คะแนนห้องร้าน เหรียญเยอะ", 30, 109), AddNum("ShopRichCoins", "เหรียญเยอะ = เกิน", 400, 109)
    AddNum("ShopMid", "คะแนนห้องร้าน เหรียญกลาง", 30, 143), AddNum("ShopMidCoins", "เหรียญกลาง = เกิน", 400, 143)
    AddNum("ShopPoor", "คะแนนห้องร้าน เหรียญน้อย", 30, 177)
    C.ilv := G.AddListView("x25 y212 w530 h215 -Multi Grid", ["ชื่อไอเทม", "คะแนน", "เหรียญเกิน", "ผลของไอเทม"])
    C.ilv.ModifyCol(1, 150), C.ilv.ModifyCol(2, 55), C.ilv.ModifyCol(3, 75), C.ilv.ModifyCol(4, 225)
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
    G.AddButton("x570 y450 w205", "⭐ ใช้รายการแนะนำ").OnEvent("Click", (*) => ItemsRecommended())
    ; items the shop has shown (items_seen.txt, written by the macro)
    G.AddText("x25 y437 w530", "ของที่มาโครเคยเห็นในร้าน  (คลิกแล้วกด '← ใช้ชื่อนี้' เพื่อเพิ่มเข้ารายการซื้อ)")
    C.slv := G.AddListView("x25 y458 w530 h165 -Multi Grid", ["ชื่อ", "ผล", "ราคา", "ในรายการ"])
    C.slv.ModifyCol(1, 140), C.slv.ModifyCol(2, 230), C.slv.ModifyCol(3, 55), C.slv.ModifyCol(4, 70)
    G.AddButton("x570 y490 w205", "← ใช้ชื่อนี้").OnEvent("Click", (*) => SeenToItem())
    G.AddButton("x570 y525 w205", "รีเฟรชรายการที่เห็น").OnEvent("Click", (*) => LoadSeen())

    ; ------------------------------------------- แท็บ 4: ราคา / ทั่วไป
    tab.UseTab(4)
    G.AddText("x25 y45 w750 cGray", "ชื่อยูนิต: พิมพ์ให้ตรงกับชื่อใต้รูปใน Unit Overview (เช่น C.E.O., Idol) มาโครจะหาการ์ดอัปเกรดจากชื่อนี้")
    C.type := [], C.name := []
    Loop 6 {
        yy := 75 + (A_Index - 1) * 34
        G.AddText("x30 y" (yy + 4) " w55", "ช่อง " A_Index)
        ne := G.AddEdit("x90 y" yy " w200")
        ne.OnEvent("Change", (*) => (MarkDirty(), RefreshNames()))
        C.name.Push(ne)
        G.AddText("x305 y" (yy + 4) " w40", "ราคา")
        E["Cost" A_Index] := G.AddEdit("x345 y" yy " w75")
        E["Cost" A_Index].OnEvent("Change", (*) => MarkDirty())
        G.AddText("x425 y" (yy + 4) " w15 cGray", "¥")
        G.AddText("x450 y" (yy + 4) " w55", "ประเภท")
        dd := G.AddDropDownList("x510 y" yy " w180 Choose1", ["พื้นดิน (ground)", "เนิน (hill)"])
        dd.OnEvent("Change", (*) => MarkDirty())
        C.type.Push(dd)
    }
    G.AddGroupBox("x25 y300 w750 h325", "ทั่วไป / กล้อง / หาเนิน")
    AddNum("CamZoom", "ระยะกล้อง (ซูมออกกี่ขีด)", 40, 432, "มาก = ไกล  (0-30, ค่าเริ่มต้น 24)", 420)
    AddNum("HillWalk", "หาเนินไม่เจอ: เดินทางละ", 40, 466, "วินาที (W/D/S/A แล้วเดินกลับที่เดิม)", 420)
    AddNum("HillZoomStep", "ไม่เจอ: ซูมเข้าทีละ", 40, 500, "ขีด", 60)
    AddNum("HillZoomTries", "ซูมเข้าสูงสุด", 400, 500, "ครั้ง", 60)
    C.run := G.AddCheckbox("x40 y538 w700", "กด Shift วิ่งตอนเดินหาเนิน  (เจอเนินหลังซูมเข้า = ใช้ระยะกล้องนั้นต่อไป)")
    C.run.OnEvent("Click", (*) => MarkDirty())
    G.AddText("x40 y572 w170", "ด่านที่ต้องเดินก่อนเริ่ม")
    C.stage := G.AddEdit("x215 y568 w400")
    C.stage.OnEvent("Change", (*) => MarkDirty())
    G.AddText("x40 y598 w720 cGray", "ชื่อด่าน=ปุ่ม วินาที  คั่นหลายด่านด้วย |   เช่น  Magic Hill=a 3 jump|Snowy Town=d 3 jump, w 1  (jump = กระโดดด้วย, คั่นหลายท่าด้วย ,)")
    C.save := G.AddCheckbox("x40 y330 w700", "เก็บหีบไว้เปิดตอนห้องสุดท้าย (SaveChests)")
    C.vote := G.AddCheckbox("x40 y362 w700", "กดโหวต Yes ให้อัตโนมัติ (AutoVote)")
    G.AddText("x40 y400 w170", "จบดันเจี้ยนแล้ว")
    C.finish := G.AddDropDownList("x215 y396 w250", ["เริ่มดันเจี้ยนใหม่ (again)", "หยุดมาโคร (stop)"])
    for ctl in [C.save, C.vote, C.finish]
        ctl.OnEvent(ctl.Type = "DDL" ? "Change" : "Click", (*) => MarkDirty())

    ; ---------------------------------------------------- ปุ่มล่าง
    tab.UseTab()
    G.AddButton("x10 y645 w120 h35", "บันทึก").OnEvent("Click", (*) => SaveAll(false))
    G.AddButton("x140 y645 w220 h35", "บันทึก + เปิดมาโครใหม่").OnEvent("Click", (*) => SaveAll(true))
    G.AddButton("x370 y645 w150 h35", "🐞 รายงานบั๊ก").OnEvent("Click", (*) => ReportBug())
    G.AddButton("x530 y645 w160 h35", "🔄 อัปเดตมาโคร").OnEvent("Click", (*) => UpdateMacro())
    C.status := G.AddText("x12 y690 w776 cGreen", "")
    UpdateBuilder()
}

AddNum(key, label, x, y, tip := "", tipW := 100) {
    G.AddText("x" x " y" (y + 4) " w190", label)
    E[key] := G.AddEdit("x" (x + 195) " y" y " w80")
    E[key].OnEvent("Change", (*) => MarkDirty())
    if (tip != "")
        G.AddText("x" (x + 282) " y" (y + 4) " w" tipW " cGray", tip)
}

MarkDirty() {
    global Dirty
    if !Filling
        Dirty := true
}

; ============================================================ plan
NewStep(k) {
    return {k: k, slots: [], all: false, n: 1, goal: "max", gv: 1, style: "one", until: 0, note: "",
        place: "random", ax: 960, ay: 540}
}

ParseStep(line) {
    l := StrLower(Trim(line))
    for th, en in Map("วาง", "place", "อัพ", "upgrade", "อัป", "upgrade", "สกิล", "ability", "ออโต้", "auto",
        "รอ", "wait", "เวฟ", "wave", "ตัน", "max", "เฉลี่ย", "even", "ทีละตัว", "one",
        "สุ่ม", "random", "ชิดทาง", "near", "ไกล", "far", "กลุ่ม", "group", "กระจาย", "spread", "โค้ง", "cover",
        "กลาง", "center", "จุด", "at")
        l := StrReplace(l, th, en)
    if RegExMatch(l, "^place\s+([1-6])\s*(?:x\s*(\d+))?(?:\s+(random|near|far|group|spread|cover|center|at\s*(\d+)\s*,\s*(\d+)))?$", &m) {
        s := NewStep("place"), s.slots := [Integer(m[1])], s.n := m[2] != "" ? Integer(m[2]) : 1
        if (m[3] != "")
            s.place := (SubStr(m[3], 1, 2) = "at") ? "at" : m[3]
        if (s.place = "at")
            s.ax := Integer(m[4]), s.ay := Integer(m[5])
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
        case "place":
            t := "place " s.slots[1] " x" s.n
            if (s.place = "at")
                t .= " at " s.ax "," s.ay
            else if (s.place != "random")
                t .= " " s.place
            return t
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

SlotLabel(i) => (SlotNames[i] != "") ? SlotNames[i] " (ช่อง " i ")" : "ยูนิตช่อง " i
SlotList(arr) {
    t := ""
    for v in arr
        t .= (t = "" ? "" : ", ") SlotLabel(v)
    return t
}
; names typed in the unit tab -> legend, step texts, slot check boxes
RefreshNames() {
    leg := ""
    for i, ne in C.name {
        SlotNames[i] := Trim(ne.Value)
        if (SlotNames[i] != "")
            leg .= "   " i "=" SlotNames[i]
    }
    C.legend.Text := (leg = "") ? "มาโครจะทำทีละขั้นจากบนลงล่างในทุกห้อง  (ช่อง 1-6 = ช่อง hotbar ของยูนิต  ตั้งชื่อยูนิตได้ในแท็บ ยูนิต / ทั่วไป)"
        : "ช่อง hotbar:" leg
    row := C.lv.GetNext()
    RefreshPlan(row)
    UpdateBuilder()
}

StepDesc(s) {
    switch s.k {
        case "place":
            t := "วาง " SlotLabel(s.slots[1]) " จำนวน " s.n " ตัว"
            if (s.place = "at")
                t .= " ที่จุด (" s.ax ", " s.ay ")"
            else if PLACE_DESC.Has(s.place)
                t .= " แบบ" PLACE_DESC[s.place]
            return t
        case "ability": return "กดสกิล " SlotLabel(s.slots[1]) " จำนวน " s.n " ครั้ง"
        case "auto":    return "เปิดสกิล Auto " SlotLabel(s.slots[1])
        case "wait":    return "รอ " s.n " วินาที"
        case "wave":    return "รอจนถึงเวฟ " s.n
        case "upgrade":
            t := "อัปเกรด " (s.all ? "ทุกตัว" : SlotList(s.slots))
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
    if (k = "place") {
        s.place := PLACE_KEYS[C.pstyle.Value]
        if (s.place = "at") {
            if !(IsInteger(C.atX.Value) && IsInteger(C.atY.Value) && C.atX.Value <= 1920 && C.atY.Value <= 1080) {
                why := "ใส่จุด X (0-1920) และ Y (0-1080) หรือกด 'เลือกจุดบนจอเกม'"
                return ""
            }
            s.ax := Integer(C.atX.Value), s.ay := Integer(C.atY.Value)
        }
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
    isPl := (k = "place"), isAt := isPl && PLACE_KEYS[C.pstyle.Value] = "at"
    C.pstyle.Enabled := isPl
    C.atX.Enabled := isAt, C.atY.Enabled := isAt, C.pick.Enabled := isAt
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
    C.pstyle.Value := ArrIndex(PLACE_KEYS, s.place)
    C.atX.Value := s.ax, C.atY.Value := s.ay
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

; fill the room / shop / shrine boxes from the chosen preset (saved on Save)
ApplyPreset() {
    pr := PRESETS[C.preset.Value]
    for k, v in pr.vals {
        if E.Has(k)
            E[k].Value := v
        else if (k = "ShrineMode")
            C.shrine.Value := ArrIndex(SHRINE_KEYS, v)
    }
    MarkDirty()
    C.status.Text := "ตั้งค่าตามโหมด " pr.th " แล้ว - กดบันทึก"
}

; ---- pick a spot on the game screen (for "กำหนดจุดเอง")
; The click is caught here and does not reach the game.
PickSpot() {
    global PickResult
    rb := "ahk_exe RobloxPlayerBeta.exe"
    if !WinExist(rb) {
        MsgBox("เปิด Roblox ก่อน (แนะนำให้อยู่ในด่าน จะเห็นตำแหน่งจริง)", "AA Dungeon", "Icon!")
        return
    }
    G.Hide()
    WinActivate(rb)
    PickResult := ""
    Hotkey("*LButton", PickClick, "On")
    Hotkey("*Esc", PickCancel, "On")
    while (!IsObject(PickResult) && PickResult = "") {
        MouseGetPos(&mx, &my)
        ToolTip("คลิกตรงจุดที่จะให้วางยูนิต  (Esc = ยกเลิก)", mx + 18, my + 18)
        Sleep 30
    }
    Hotkey("*LButton", "Off"), Hotkey("*Esc", "Off")
    ToolTip()
    G.Show()
    if !IsObject(PickResult)
        return
    ; screen pixel -> the macro's 1920x1080 coordinates (Roblox window centre based)
    WinGetClientPos(&cx, &cy, &cw, &ch, rb)
    u := ch / 1080
    rx := Round((PickResult.x - (cx + cw / 2)) / u + 960)
    ry := Round((PickResult.y - (cy + ch / 2)) / u + 540)
    if (rx < 0 || ry < 0 || rx > 1920 || ry > 1080) {
        MsgBox("จุดที่คลิกอยู่นอกหน้าต่าง Roblox", "AA Dungeon", "Icon!")
        return
    }
    C.atX.Value := rx, C.atY.Value := ry
    UpdateBuilder()
}
PickClick(*) {
    global PickResult
    MouseGetPos(&x, &y)
    PickResult := {x: x, y: y}
}
PickCancel(*) {
    global PickResult
    PickResult := "cancel"
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

ItemEffect(name) {
    k := RegExReplace(StrLower(name), "[^a-z]")
    for d in ITEMDB
        if (RegExReplace(StrLower(d.name), "[^a-z]") = k)
            return d.eff
    for sv in Seen
        if (RegExReplace(StrLower(sv.name), "[^a-z]") = k)
            return sv.eff
    return (k = "other") ? "ของที่ไม่อยู่ในรายการ" : ""
}

RefreshItems(sel := 0) {
    C.ilv.Delete()
    for it in Items
        C.ilv.Add(, it.name, it.score, it.min > 0 ? it.min : "-", ItemEffect(it.name))
    if (sel >= 1 && sel <= Items.Length)
        C.ilv.Modify(sel, "Select Focus Vis")
}

; replace the buy list with the recommended one (all known items)
ItemsRecommended() {
    global Items, Dirty
    if (MsgBox("แทนที่รายการซื้อด้วยรายการแนะนำ (" ITEMDB.Length " ชิ้น)?", "AA Dungeon", "YesNo Icon?") != "Yes")
        return
    Items := []
    for d in ITEMDB
        Items.Push({name: d.name, score: d.pts, min: 0})
    Items.Push({name: "Other", score: 20, min: 1000})
    Dirty := true
    RefreshItems(1)
    RefreshSeen()
}

LoadSeen() {
    global Seen
    Seen := []
    f := A_ScriptDir "\items_seen.txt"
    if FileExist(f)
        for ln in StrSplit(FileRead(f, "UTF-8"), "`n", "`r") {
            p := StrSplit(ln, "|")
            if (p.Length >= 1 && Trim(p[1]) != "")
                Seen.Push({name: Trim(p[1]), eff: p.Length >= 2 ? Trim(p[2]) : "", price: p.Length >= 3 ? p[3] : ""})
        }
    RefreshSeen()
}
RefreshSeen() {
    C.slv.Delete()
    for sv in Seen {
        inList := "-"
        k := RegExReplace(StrLower(sv.name), "[^a-z]")
        for it in Items
            if (RegExReplace(StrLower(it.name), "[^a-z]") = k)
                inList := "✔ " it.score
        C.slv.Add(, sv.name, sv.eff, sv.price, inList)
    }
}
SeenToItem() {
    if !(row := C.slv.GetNext()) {
        MsgBox("คลิกเลือกของในรายการที่เห็นก่อน", "AA Dungeon", "Icon!")
        return
    }
    sv := Seen[row]
    C.iname.Value := sv.name
    pts := 30
    for d in ITEMDB
        if (RegExReplace(StrLower(d.name), "[^a-z]") = RegExReplace(StrLower(sv.name), "[^a-z]"))
            pts := d.pts
    C.iscore.Value := pts, C.imin.Value := 0
    C.status.Text := "ใส่ชื่อ " sv.name " แล้ว - ปรับคะแนนแล้วกด '+ เพิ่ม'"
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
        else if (k = "ShrineMode")
            C.shrine.Value := ArrIndex(SHRINE_KEYS, StrLower(val))
        else if (k = "Preset") {
            for i, pr in PRESETS
                if (pr.key = StrLower(val))
                    C.preset.Value := i, C.pdesc.Text := pr.desc
        }
        else if (k = "ShrineAvoid")
            C.avoid.Value := val
        else if (k = "HillRun")
            C.run.Value := (val + 0) ? 1 : 0
        else if (k = "StageWalk")
            C.stage.Value := val
        else if (k = "OnFinish")
            C.finish.Value := (StrLower(val) = "stop") ? 2 : 1
        else if (SubStr(k, 1, 4) = "Name")
            C.name[Integer(SubStr(k, 5))].Value := val
        else if (SubStr(k, 1, 4) = "Type")
            C.type[Integer(SubStr(k, 5))].Value := (StrLower(val) = "hill") ? 2 : 1
    }
    Filling := false
    RefreshItems()
    LoadSeen()
    RefreshNames()
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
        IniWrite(C.run.Value ? 1 : 0, INI, "Settings", "HillRun")
        IniWrite(Trim(C.stage.Value), INI, "Settings", "StageWalk")
        IniWrite(SHRINE_KEYS[C.shrine.Value], INI, "Settings", "ShrineMode")
        IniWrite(PRESETS[C.preset.Value].key, INI, "Settings", "Preset")
        IniWrite(Trim(StrReplace(C.avoid.Value, "|", ",")), INI, "Settings", "ShrineAvoid")
        IniWrite(C.finish.Value = 2 ? "stop" : "again", INI, "Settings", "OnFinish")
        for i, dd in C.type
            IniWrite(dd.Value = 2 ? "hill" : "ground", INI, "Settings", "Type" i)
        for i, ne in C.name
            IniWrite(Trim(StrReplace(ne.Value, "|", "")), INI, "Settings", "Name" i)
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
            C.status.Text .= " - เปิดมาโครใหม่แล้ว กด F2"
        } else
            MsgBox("ไม่พบ AADungeon.ahk ในโฟลเดอร์เดียวกัน", "AA Dungeon", "Icon!")
    } else
        C.status.Text .= " - กด F3 ในมาโครเพื่อโหลดค่าใหม่"
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

; ============================================================ update
; Downloads the newest program files from GitHub and replaces only those.
; settings.ini, plan.txt, logs and reports are never touched.
UpdateMacro() {
    C.status.Text := "กำลังเช็คเวอร์ชันใหม่..."
    dir := A_Temp "\aad_update"
    changed := []
    try {
        DirCreate(dir)
        for f in UPDATE_FILES {
            tmp := dir "\" StrReplace(f, "/", "_")
            Download(REPO_RAW f "?t=" A_TickCount, tmp)
            latest := FileRead(tmp, "UTF-8")
            if !InStr(SubStr(latest, 1, 60), "#Requires AutoHotkey v2")
                throw Error("ไฟล์ที่โหลดมาไม่ถูกต้อง: " f)
            loc := A_ScriptDir "\" StrReplace(f, "/", "\")
            cur := FileExist(loc) ? FileRead(loc, "UTF-8") : ""
            if (StrReplace(latest, "`r`n", "`n") != StrReplace(cur, "`r`n", "`n"))
                changed.Push({f: f, tmp: tmp, loc: loc})
        }
    } catch as err {
        C.status.Text := ""
        MsgBox("เช็คเวอร์ชันใหม่ไม่ได้ (ต่อเน็ตอยู่ไหม?)`n`n" err.Message, "AA Dungeon", "Icon!")
        return
    }
    if !changed.Length {
        C.status.Text := "เป็นเวอร์ชันล่าสุดแล้ว"
        return
    }
    list := ""
    for c in changed
        list .= "  • " c.f "`n"
    if (MsgBox("มีเวอร์ชันใหม่:`n" list "`nอัปเดตเลยไหม? (การตั้งค่าและแผนของคุณจะไม่ถูกเปลี่ยน)`n"
        . "มาโครจะเปิดใหม่ ถ้ากำลังเล่นอยู่จะหยุด", "AA Dungeon", "YesNo Iconi") != "Yes") {
        C.status.Text := ""
        return
    }
    if Dirty
        SaveAll(false)
    bak := A_ScriptDir "\backup\" SubStr(A_Now, 1, 8) "_" SubStr(A_Now, 9, 6)
    try {
        for c in changed {
            if FileExist(c.loc) {
                SplitPath(c.loc, &nm)
                DirCreate(bak)
                FileCopy(c.loc, bak "\" nm, 1)
            }
            SplitPath(c.loc, , &d)
            DirCreate(d)
            FileCopy(c.tmp, c.loc, 1)
        }
    } catch as err {
        MsgBox("อัปเดตไม่สำเร็จ: " err.Message "`nไฟล์เดิมสำรองไว้ที่ " bak, "AA Dungeon", "Icon!")
        return
    }
    if FileExist(MACRO)
        Run('"' A_AhkPath '" "' MACRO '"')         ; restart the macro with the new code
    MsgBox("อัปเดตแล้ว กด F2 ในเกมเพื่อเริ่ม`n(ไฟล์เก่าสำรองไว้ที่ " bak ")", "AA Dungeon", "Iconi")
    Run('"' A_AhkPath '" "' A_ScriptFullPath '"')  ; reopen this window (new version)
    ExitApp
}

; ============================================================ bug report
; Packs the log (last part), settings, plan, newest shop shots and system
; info into one zip, then sends it to Discord (if a webhook is set) or opens
; the GitHub bug page with the zip ready to drag in.
ReportBug() {
    what := InputBox("เกิดอะไรขึ้น? (เช่น ห้อง Depth 4 วางยูนิตช่อง 2 ซ้ำไม่หยุด)`n`n"
        . "ไฟล์ที่จะแนบ: log ของมาโคร, settings.ini, plan.txt, ภาพร้านค้าล่าสุด, ข้อมูลจอ/Windows`n"
        . "(ใน log อาจมีชื่อผู้เล่นในเกมของคุณ)", "AA Dungeon - รายงานบั๊ก", "w460 h220")
    if (what.Result != "OK")
        return
    desc := Trim(what.Value)
    dir := A_ScriptDir "\bug_reports"
    stamp := SubStr(A_Now, 1, 8) "_" SubStr(A_Now, 9, 6)   ; A_Now is always the western year
    tmp := dir "\report_" stamp
    zip := dir "\bug_report_" stamp ".zip"
    try {
        DirCreate(tmp)
        ; log: only the last 4000 lines (the newest runs)
        lf := A_ScriptDir "\AADungeon.log"
        if FileExist(lf) {
            lines := StrSplit(FileRead(lf, "UTF-8"), "`n", "`r")
            first := Max(1, lines.Length - 4000), out := ""
            Loop lines.Length - first + 1
                out .= lines[first + A_Index - 1] "`n"
            FileAppend(out, tmp "\AADungeon.log", "UTF-8")
        }
        for f in ["settings.ini", "plan.txt"]
            if FileExist(A_ScriptDir "\" f)
                FileCopy(A_ScriptDir "\" f, tmp "\" f, 1)
        ; the newest shop screenshot (keeps the zip small enough to upload)
        shots := []
        Loop Files A_ScriptDir "\shots\*.png"
            shots.Push({p: A_LoopFileFullPath, n: A_LoopFileName, t: A_LoopFileTimeModified})
        Loop 1 {
            best := 0
            for i, sh in shots
                if (!best || sh.t > shots[best].t)
                    best := i
            if !best
                break
            FileCopy(shots[best].p, tmp "\" shots[best].n, 1)
            shots.RemoveAt(best)
        }
        FileAppend("What happened: " desc "`n`n" SysInfo(), tmp "\system.txt", "UTF-8")
        q := "'"
        RunWait('powershell -NoProfile -ExecutionPolicy Bypass -Command "Compress-Archive -Path '
            . q tmp "\*" q " -DestinationPath " q zip q ' -Force"', , "Hide")
        DirDelete(tmp, 1)
    } catch as err {
        MsgBox("สร้างไฟล์รายงานไม่สำเร็จ: " err.Message, "AA Dungeon", "Icon!")
        return
    }
    if !FileExist(zip) {
        MsgBox("สร้างไฟล์ zip ไม่สำเร็จ`nไฟล์อยู่ที่: " tmp, "AA Dungeon", "Icon!")
        return
    }
    ; 1) Discord webhook: send it straight away
    if (REPORT_WEBHOOK != "") {
        msg := "Bug report " stamp "`n" SubStr(StrReplace(desc, '"', "'"), 1, 1500)
        code := RunWait('curl.exe -sf -o NUL -F "content=' msg '" -F "file=@' zip '" "' REPORT_WEBHOOK '"', , "Hide")
        if (code = 0) {
            MsgBox("ส่งรายงานให้ผู้พัฒนาแล้ว ขอบคุณครับ`n`nสำเนาเก็บไว้ที่: " zip, "AA Dungeon", "Iconi")
            return
        }
        MsgBox("ส่งเข้า Discord ไม่สำเร็จ จะเปิดหน้า GitHub ให้ส่งแทน", "AA Dungeon", "Icon!")
    }
    ; 2) GitHub: the log goes in as text (pasted from the clipboard), so the
    ;    report works even when a file upload fails. The zip is extra.
    logtxt := "== system ==`n" SysInfo() "`n== AADungeon.log (newest part) ==`n"
    lf := A_ScriptDir "\AADungeon.log"
    if FileExist(lf) {
        lines := StrSplit(FileRead(lf, "UTF-8"), "`n", "`r"), tail := "", i := lines.Length
        while (i >= 1 && StrLen(tail) + StrLen(lines[i]) < 45000)    ; GitHub limit is 65536
            tail := lines[i] "`n" tail, i--
        logtxt .= tail
    } else
        logtxt .= "(no log file)"
    A_Clipboard := logtxt
    title := "[บั๊ก] " SubStr(StrReplace(desc, "`n", " "), 1, 70)
    Run(ISSUE_URL "&title=" UrlEnc(title) "&what=" UrlEnc(SubStr(desc, 1, 500)))
    Run('explorer.exe /select,"' zip '"')
    MsgBox("หน้าแจ้งบั๊กบน GitHub เปิดขึ้นมาแล้ว (ต้องล็อกอิน GitHub) ช่อง 'เกิดอะไรขึ้น' กรอกให้แล้ว`n`n"
        . "1. คลิกช่อง 'log ของมาโคร' แล้วกด Ctrl+V  (log ถูกคัดลอกไว้ให้แล้ว)`n"
        . "2. ถ้ามีภาพหน้าจอ ลากมาวางในช่องไฟล์ได้ (zip ก็ได้ แต่ไม่จำเป็นแล้ว)`n"
        . "3. กด Create`n`n"
        . "ไฟล์ zip สำรองไว้ที่: " zip, "AA Dungeon", "Iconi")
}

UrlEnc(str) {
    buf := Buffer(StrPut(str, "UTF-8"))
    StrPut(str, buf, "UTF-8")
    out := ""
    Loop buf.Size - 1 {
        b := NumGet(buf, A_Index - 1, "UChar")
        if ((b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
            || b = 0x2D || b = 0x2E || b = 0x5F || b = 0x7E)
            out .= Chr(b)
        else
            out .= Format("%{:02X}", b)
    }
    return out
}

SysInfo() {
    t := "Time: " A_YYYY "-" A_MM "-" A_DD " " A_Hour ":" A_Min ":" A_Sec "`n"
    t .= "Windows: " A_OSVersion (A_Is64bitOS ? " 64-bit" : "") "`n"
    t .= "AutoHotkey: " A_AhkVersion "`n"
    try t .= "Macro file date: " FileGetTime(MACRO) "`n"
    t .= "Screen: " A_ScreenWidth "x" A_ScreenHeight "  scale " Round(A_ScreenDPI / 96 * 100) "%  monitors " MonitorGetCount() "`n"
    try {
        if WinExist("ahk_exe RobloxPlayerBeta.exe") {
            WinGetClientPos(&x, &y, &w, &h)
            t .= "Roblox client: " w "x" h " at " x "," y (WinGetMinMax() = 1 ? " (maximised)" : "") "`n"
        } else
            t .= "Roblox: not running`n"
    }
    try {
        langs := StrReplace(Trim(OCR.GetAvailableLanguages(), "`n "), "`n", ", ")
        t .= "OCR languages: " (langs = "" ? "(none)" : langs) "`n"
    } catch {
        try {
            OCR.LoadLanguage("en-US")
            t .= "OCR en-US: OK`n"
        } catch
            t .= "OCR en-US: MISSING (install English OCR)`n"
    }
    return t
}

