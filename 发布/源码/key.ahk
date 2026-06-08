#Requires AutoHotkey v2.0
#SingleInstance Force
#Include JSON.ahk

; ==============================================================================
; SYSTEM INITIALIZATION & PRIVILEGE ESCALATION
; ==============================================================================
; 自动提权：突破 Windows UIPI 权限隔离墙，确保在 Qt/Electron 及高权限窗口中生效
if not A_IsAdmin {
    try {
        Run('*RunAs "' A_ScriptFullPath '"')
    }
    ExitApp()
}

Persistent(true)
AppCore.Init()

class AppCore {
    static Init() {
        ; [UI修复] 冻结当前系统托盘图标，剥夺 AHK 底层状态机(Suspend/Pause)自动重绘图标的权限
        try TraySetIcon(,, true)

        ConfigManager.Load()
        this.BuildTrayMenu()
        UIManager.BuildMain()
        HotkeyEngine.ApplyAll(ConfigManager.Rules)
    }

    static BuildTrayMenu() {
        A_TrayMenu.Delete()
        A_TrayMenu.Add(I18n.T("TrayShow"), (*) => UIManager.ShowMain())
        A_TrayMenu.Add(I18n.T("AddRule"), (*) => UIManager.ShowEditRule())
        A_TrayMenu.Add() ; 分隔线
        A_TrayMenu.Add(I18n.T("Startup"), (*) => UIManager.ToggleStartupFromTray())
        if (ConfigManager.RunOnStartup) {
            A_TrayMenu.Check(I18n.T("Startup"))
        }
        A_TrayMenu.Add(I18n.T("LangSwitch"), (*) => UIManager.SwitchLanguage())
        A_TrayMenu.Add() ; 分隔线
        A_TrayMenu.Add(I18n.T("TrayPause"), (*) => this.ToggleSuspend())
        A_TrayMenu.Add(I18n.T("TrayExit"), (*) => ExitApp())
        
        A_TrayMenu.Default := I18n.T("TrayShow")
        A_TrayMenu.ClickCount := 2
    }

    static ToggleSuspend() {
        Suspend(-1)
        if (A_IsSuspended) {
            A_TrayMenu.Check(I18n.T("TrayPause"))
        } else {
            A_TrayMenu.UnCheck(I18n.T("TrayPause"))
        }
    }
}

; ==============================================================================
; CONFIGURATION & STATE MANAGEMENT
; ==============================================================================
class ConfigManager {
    static FilePath := "config.json"
    static Rules := []
    static RunOnStartup := false
    static AppLang := "zh" 

    static Load() {
        if (!FileExist(this.FilePath)) {
            this.Rules := []
            return
        }
        try {
            text := FileRead(this.FilePath)
            loadedData := JSON.Load(text)
            
            if (loadedData is Array) {
                this.Rules := loadedData
            } else {
                this.Rules := loadedData.Has("rules") ? loadedData["rules"] : []
                this.RunOnStartup := loadedData.Has("runOnStartup") ? loadedData["runOnStartup"] : false
                this.AppLang := loadedData.Has("language") ? loadedData["language"] : "zh"
            }

            for rule in this.Rules {
                if (!rule.Has("actions")) {
                    rule["actions"] := []
                }
                if (!rule.Has("desc")) {
                    rule["desc"] := ""
                }
                if (!rule.Has("group")) {
                    rule["group"] := "Default"
                }
                if (!rule.Has("enabled")) {
                    rule["enabled"] := true
                }
            }
        } catch as err {
            MsgBox("Error loading config.json:`n" err.Message)
            this.Rules := []
        }
    }

    static Save() {
        try {
            configObj := Map()
            configObj["runOnStartup"] := this.RunOnStartup
            configObj["language"] := this.AppLang
            configObj["rules"] := this.Rules

            FileOpen(this.FilePath, "w").Write(JSON.Dump(configObj, "    "))
            this.ManageStartupShortcut(this.RunOnStartup)

            this.Load()
            UIManager.UpdateMainListView()
            HotkeyEngine.ApplyAll(this.Rules)
        } catch as err {
            MsgBox("Error saving config:`n" err.Message)
        }
    }

    static ManageStartupShortcut(enable) {
        shortcutPath := A_Startup "\HotkeyV2.lnk"
        if (enable) {
            if (!FileExist(shortcutPath)) {
                FileCreateShortcut(A_ScriptFullPath, shortcutPath)
            }
        } else {
            if (FileExist(shortcutPath)) {
                FileDelete(shortcutPath)
            }
        }
    }
}

; ==============================================================================
; HOTKEY REGISTRATION & TRIGGER ENGINE
; ==============================================================================
class HotkeyEngine {
    static ActiveHotkeys := Map()
    static KeyPresses := Map()

    static ApplyAll(rules) {
        ; 清场：卸载并挂起所有旧热键
        for keyName, _ in this.ActiveHotkeys {
            try Hotkey(keyName, "Off")
        }
        this.ActiveHotkeys.Clear()

        KeyMap := Map()
        for rule in rules {
            if (!rule.Has("key") || rule["key"] = "" || !rule["enabled"]) {
                continue
            }
            ahkKey := KeyUtil.ToAhkKey(rule["key"])
            
            ; [架构优化1] 强制挂载 $ 前缀 (底层键盘 Hook)
            ; 目的：为了防止后面重投递(PassThrough)按键时，自己 Send 触发自己的死循环
            hookKey := RegExMatch(ahkKey, "^[\$\~]") ? ahkKey : "$" ahkKey
            
            if (!KeyMap.Has(hookKey)) {
                KeyMap[hookKey] := []
            }
            KeyMap[hookKey].Push(rule)
        }

        ; 重新注册
        for k, _ in KeyMap {
            try {
                Hotkey(k, this.OnTrigger.Bind(this), "On")
                this.ActiveHotkeys[k] := true
            } catch as err {
                MsgBox("Error registering key '" k "':`n" err.Message)
            }
        }
    }

    static OnTrigger(ThisHotkey) {
        if (!this.KeyPresses.Has(ThisHotkey)) {
            this.KeyPresses[ThisHotkey] := {count: 0, timerFn: ""}
        }
        
        data := this.KeyPresses[ThisHotkey]
        data.count += 1
        maxTimeout := 0
        maxRuleCount := 1
        relevantRules := []
        
        ; 剥离前缀：比对配置时，忽略底层强加的钩子符号
        cleanThis := RegExReplace(ThisHotkey, "^[\$\~]+", "")

        for rule in ConfigManager.Rules {
            if (!rule["enabled"]) {
                continue
            }
            ruleAhk := KeyUtil.ToAhkKey(rule["key"])
            cleanRule := RegExReplace(ruleAhk, "^[\$\~]+", "")

            if (StrCompare(cleanThis, cleanRule, false) == 0) {
                if (rule.Has("window") && rule["window"] != "") {
                    if (!WinActive(rule["window"])) {
                        continue
                    }
                }
                relevantRules.Push(rule)
                if (rule.Has("timeout") && rule["timeout"] > maxTimeout) {
                    maxTimeout := rule["timeout"]
                }
                ruleCount := rule.Has("count") ? rule["count"] : 1
                if (ruleCount > maxRuleCount) {
                    maxRuleCount := ruleCount
                }
            }
        }
        
        if (maxTimeout == 0) {
            maxTimeout := 300
        }

        if (data.timerFn) {
            SetTimer(data.timerFn, 0)
        }
        
        CurrentCallback := this.ProcessTrigger.Bind(this, ThisHotkey, data.count, relevantRules)
        data.timerFn := CurrentCallback
        
        ; [架构优化2] 状态机零延迟短路
        ; 如果当前击键次数已经达到了该键所配置的“最高次数”，无需继续等待超时，立刻全速分发！
        if (data.count >= maxRuleCount) {
            CurrentCallback()
        } else {
            SetTimer(CurrentCallback, -maxTimeout)
        }
    }

    static ProcessTrigger(key, count, rulesList) {
        if (this.KeyPresses.Has(key)) {
            this.KeyPresses[key].count := 0
            this.KeyPresses[key].timerFn := ""
        }
        
        matched := false
        for rule in rulesList {
            ruleCount := rule.Has("count") ? rule["count"] : 1
            if (ruleCount == count) {
                ActionExecutor.Execute(rule)
                matched := true
                return
            }
        }

        ; [架构优化3] 事件漏斗兜底机制 (Pass-Through)
        ; 如果该次击键没有命中任何自定义规则 (例如配置了双击拦截，但用户只进行了一次单击)
        ; 则将干净的按键投递回 OS 的消息队列，恢复原生打字/操作功能
        if (!matched) {
            this.PassThrough(key, count)
        }
    }

    static PassThrough(hk, count) {
        ; 清洗按键：剥离拦截专用符
        cleanHk := RegExReplace(hk, "^[\$\~]+", "")
        modifiers := ""
        keyName := cleanHk
        
        ; 提取 ^(Ctrl) !(Alt) +(Shift) #(Win) 等修饰符
        while RegExMatch(keyName, "^([!#\^\+<>])", &match) {
            modifiers .= match[1]
            keyName := SubStr(keyName, 2)
        }
        
        ; 大括号封套：安全包装实体键，防止原义被误解析 (如 * 变通配符)
        sendStr := modifiers "{" keyName "}"
        
        Loop count {
            ; 兜底发送采用较低级别的 SendEvent 并给予微小间隙，防止目标游戏/应用粘键
            SendEvent(sendStr)
            Sleep(10)
        }
    }
}

; ==============================================================================
; ACTION DISPATCHER & EXECUTOR
; ==============================================================================
class ActionExecutor {
    static Execute(rule) {
        if (!rule.Has("actions")) {
            return
        }

        displayStr := (rule.Has("desc") && rule["desc"] != "") ? rule["desc"] : rule["key"]
        ToolTip(I18n.T("ExecFeedback") displayStr " ...")
        SetTimer(() => ToolTip(), -1500)

        for action in rule["actions"] {
            if (!action.Has("type") || !action.Has("command")) {
                continue
            }
            this.Dispatch(StrLower(action["type"]), action["command"])
            Sleep(50)
        }
    }

    static Dispatch(actType, cmd) {
        try {
            switch actType {
                case "run", "url": 
                    Run(cmd)
                case "cmd": 
                    Run(A_ComSpec " /k " cmd)
                case "send": 
                    ; 放弃极速的 SendInput，改为带延迟的 SendEvent，解决 Qt/游戏 丢键吞字问题
                    SetKeyDelay(30, 30)
                    SendEvent("{Text}" cmd)
                case "paste":
                    savedClip := ClipboardAll()
                    A_Clipboard := cmd
                    Sleep(10)
                    SendInput("^v")
                    Sleep(50)
                    A_Clipboard := savedClip
                    savedClip := ""
                case "keycombo":
                    SetKeyDelay(50, 50)
                    SendEvent(KeyUtil.ToAhkKey(cmd))
                case "delay":
                    if (IsInteger(cmd)) {
                        Sleep(Integer(cmd))
                    }
                default:
                    MsgBox("Unknown action type: " actType)
            }
        } catch as err {
            MsgBox("Error executing action: " err.Message)
        }
    }
}

; ==============================================================================
; KEY UTILITY HELPERS
; ==============================================================================
class KeyUtil {
    static ToAhkKey(readableKey) {
        k := readableKey
        k := StrReplace(k, "Ctrl + ", "^")
        k := StrReplace(k, "Shift + ", "+")
        k := StrReplace(k, "Alt + ", "!")
        k := StrReplace(k, "Win + ", "#")
        k := StrReplace(k, "Ctrl+", "^")
        k := StrReplace(k, "Shift+", "+")
        k := StrReplace(k, "Alt+", "!")
        k := StrReplace(k, "Win+", "#")
        return k
    }

    static CaptureKey(ctrl, parentGui) {
        wasSuspended := A_IsSuspended
        Suspend(true)
        ctrl.Value := I18n.T("PressKey")
        ih := InputHook("L0 T5") 
        ih.VisibleNonText := false
        ih.KeyOpt("{All}", "E")
        ih.KeyOpt("{LCtrl}{RCtrl}{LAlt}{RAlt}{LShift}{RShift}{LWin}{RWin}", "-E") 
        ih.Start()
        ih.Wait()
        if (ih.EndKey != "") {
            mods := ""
            if (GetKeyState("Ctrl")) {
                mods .= "Ctrl + "
            }
            if (GetKeyState("Shift")) {
                mods .= "Shift + "
            }
            if (GetKeyState("Alt")) {
                mods .= "Alt + "
            }
            if (GetKeyState("LWin") || GetKeyState("RWin")) {
                mods .= "Win + "
            }
            ctrl.Value := mods . ih.EndKey
        }
        if (!wasSuspended) {
            Suspend(false)
        }
    }

    ; ==========================================================================
    ; 动态悬浮探针式窗口捕获 (防闪烁 + 全局中断 + 状态解挂)
    ; ==========================================================================
    static CaptureWindow(ctrl, parentGui) {
        parentGui.Hide()
        Sleep(150) ; 等待界面完全隐藏，防焦点争抢

        wasSuspended := A_IsSuspended
        if (wasSuspended) {
            Suspend(false) ; 必须解挂，否则鼠标中断钩子无效
        }

        state := {flag: 0} ; 闭包对象包裹，0: 等待, 1: 成功捕获, -1: 取消
        lastProc := ""
        lastX := 0
        lastY := 0

        HoverProbe() {
            try {
                MouseGetPos(&mX, &mY, &hWnd)
                procName := WinGetProcessName("ahk_id " hWnd)
                
                ; 脏数据差值检查，解决刷新闪烁
                if (procName != lastProc || Abs(mX - lastX) > 40 || Abs(mY - lastY) > 40) {
                    lastProc := procName
                    lastX := mX
                    lastY := mY
                    probeText := I18n.T("CaptureModeTitle") "`n" I18n.T("CaptureModeHover") " ahk_exe " procName
                    ToolTip(probeText)
                }
            }
        }

        OnClick(hk) {
            state.flag := 1
        }
        OnCancel(hk) {
            state.flag := -1
        }

        try {
            Hotkey("LButton", OnClick, "On")
            Hotkey("RButton", OnCancel, "On")
            Hotkey("Escape", OnCancel, "On")

            SetTimer(HoverProbe, 50)

            while (state.flag == 0) {
                Sleep(20)
            }
        } finally {
            SetTimer(HoverProbe, 0)
            ToolTip() 
            try Hotkey("LButton", "Off")
            try Hotkey("RButton", "Off")
            try Hotkey("Escape", "Off")

            if (wasSuspended) {
                Suspend(true)
            }
        }

        if (state.flag == 1) {
            MouseGetPos(,, &hWnd)
            try {
                ctrl.Value := "ahk_exe " WinGetProcessName("ahk_id " hWnd)
            }
        }
        
        parentGui.Show()
    }
}

; ==============================================================================
; USER INTERFACE MANAGER
; ==============================================================================
class UIManager {
    static MainGui := ""
    static lvRules := ""

    static BuildMain() {
        this.MainGui := Gui("+Resize +MinSize800x400", I18n.T("Title"))
        this.MainGui.SetFont("s9", "Segoe UI")

        this.lvRules := this.MainGui.Add("ListView", "x10 y10 w780 h380 Grid Checked", [I18n.T("ColGroup"), I18n.T("ColDesc"), I18n.T("ColKey"), I18n.T("ColWindow"), I18n.T("ColCount"), I18n.T("ColTimeout"), I18n.T("ColActions")])
        
        this.lvRules.ModifyCol(1, 80)
        this.lvRules.ModifyCol(2, 220)
        this.lvRules.ModifyCol(3, 110)
        this.lvRules.ModifyCol(4, 150)
        this.lvRules.ModifyCol(5, 55)
        this.lvRules.ModifyCol(6, 75)
        this.lvRules.ModifyCol(7, 80)

        this.lvRules.OnEvent("ItemCheck", this.OnRuleCheck.Bind(this))
        this.lvRules.OnEvent("ContextMenu", this.ShowContextMenu.Bind(this))
        this.lvRules.OnEvent("DoubleClick", this.OnDoubleClick.Bind(this))

        this.MainGui.OnEvent("Size", this.OnGuiSize.Bind(this))
        this.MainGui.OnEvent("Close", (*) => this.MainGui.Hide())

        this.UpdateMainListView()
    }

    static ShowMain() {
        if (!this.MainGui) {
            this.BuildMain()
        }
        this.MainGui.Show()
    }

    static OnGuiSize(guiObj, minMax, width, height) {
        if (minMax == -1) {
            return
        }
        try {
            this.lvRules.Move(10, 10, width - 20, height - 20)
        }
    }

    static UpdateMainListView() {
        if (!this.lvRules) {
            return
        }
        this.lvRules.Delete()
        for i, rule in ConfigManager.Rules {
            g := rule.Has("group") ? rule["group"] : "Default"
            d := rule.Has("desc") ? rule["desc"] : ""
            k := rule.Has("key") ? rule["key"] : "?"
            w := rule.Has("window") && rule["window"] != "" ? rule["window"] : I18n.T("GlobalWindow")
            c := rule.Has("count") ? rule["count"] : "1"
            t := rule.Has("timeout") ? rule["timeout"] : "300"
            a := rule.Has("actions") ? rule["actions"].Length : 0
            
            this.lvRules.Add(rule["enabled"] ? "Check" : "-Check", g, d, k, w, c, t, a " " I18n.T("Actions"))
        }
    }

    static OnRuleCheck(ctrl, item, checked) {
        ConfigManager.Rules[item]["enabled"] := (checked == 1)
        ConfigManager.Save()
    }

    static OnDoubleClick(ctrl, item) {
        if (item == 0) {
            return
        }
        this.ShowEditRule(ConfigManager.Rules[item], item)
    }

    static ShowContextMenu(ctrl, item, isRightClick, x, y) {
        ctxMenu := Menu()
        ctxMenu.Add(I18n.T("AddRule"), (*) => this.ShowEditRule())
        
        if (item > 0) {
            ctxMenu.Add()
            ctxMenu.Add(I18n.T("EditRule"), (*) => this.ShowEditRule(ConfigManager.Rules[item], item))
            ctxMenu.Add(I18n.T("DeleteRule"), (*) => this.DeleteRuleCallback(item))
            ctxMenu.Add()
            currentGroup := ConfigManager.Rules[item]["group"]
            ctxMenu.Add(I18n.T("EnableThisGroup") " [" currentGroup "]", (*) => this.ToggleGroup(currentGroup, true))
            ctxMenu.Add(I18n.T("DisableThisGroup") " [" currentGroup "]", (*) => this.ToggleGroup(currentGroup, false))
        }
        ctxMenu.Show()
    }

    static DeleteRuleCallback(itemIndex) {
        ConfigManager.Rules.RemoveAt(itemIndex)
        ConfigManager.Save()
    }

    static ToggleGroup(targetGroup, state) {
        for rule in ConfigManager.Rules {
            if (rule["group"] == targetGroup) {
                rule["enabled"] := state
            }
        }
        ConfigManager.Save()
    }

    static ToggleStartupFromTray() {
        ConfigManager.RunOnStartup := !ConfigManager.RunOnStartup
        ConfigManager.Save()
        if (ConfigManager.RunOnStartup) {
            A_TrayMenu.Check(I18n.T("Startup"))
        } else {
            A_TrayMenu.UnCheck(I18n.T("Startup"))
        }
    }

    static SwitchLanguage() {
        ConfigManager.AppLang := (ConfigManager.AppLang == "en") ? "zh" : "en"
        ConfigManager.Save()
        Reload()
    }

    static ShowEditRule(existingRule := "", ruleIndex := 0) {
        wasSuspended := A_IsSuspended
        Suspend(true)
        RestoreState := (*) => (!wasSuspended ? Suspend(false) : "")
        
        editGui := Gui("+Owner" this.MainGui.Hwnd, I18n.T("EditRule"))
        editGui.SetFont("s9", "Segoe UI")
        editGui.OnEvent("Close", (*) => (RestoreState(), editGui.Destroy()))
        
        editGui.Add("GroupBox", "x15 y15 w590 h155", I18n.T("TrigGroup"))
        
        editGui.Add("Text", "x30 y45 w75", I18n.T("GroupLabel"))
        edGroup := editGui.Add("Edit", "x105 y42 w140", existingRule ? existingRule["group"] : "Default")
        
        editGui.Add("Text", "x270 y45 w75", I18n.T("DescLabel"))
        edDesc := editGui.Add("Edit", "x345 y42 w240", existingRule ? existingRule["desc"] : "")

        editGui.Add("Text", "x30 y85 w75", I18n.T("KeyLabel"))
        edKey := editGui.Add("Edit", "x105 y82 w140", existingRule ? existingRule["key"] : "")
        btnCapture := editGui.Add("Button", "x255 y81 w85", I18n.T("BtnCapture"))
        btnCapture.OnEvent("Click", (*) => KeyUtil.CaptureKey(edKey, editGui))

        editGui.Add("Text", "x365 y85 w45", I18n.T("CountLabel"))
        edCount := editGui.Add("Edit", "x410 y82 w50 Number", existingRule && existingRule.Has("count") ? existingRule["count"] : "1")
        
        editGui.Add("Text", "x480 y85 w50", I18n.T("TimeoutLabel"))
        edTimeout := editGui.Add("Edit", "x530 y82 w55 Number", existingRule && existingRule.Has("timeout") ? existingRule["timeout"] : "300")

        editGui.Add("Text", "x30 y125 w75", I18n.T("WindowLabel"))
        edWindow := editGui.Add("Edit", "x105 y122 w235", existingRule && existingRule.Has("window") ? existingRule["window"] : "")
        btnCaptureWin := editGui.Add("Button", "x350 y121 w110", I18n.T("BtnCaptureWin"))
        btnCaptureWin.OnEvent("Click", (*) => KeyUtil.CaptureWindow(edWindow, editGui))
        
        editGui.Add("Text", "x470 y125 w120 cGray", I18n.T("GlobalHint"))

        editGui.Add("GroupBox", "x15 y185 w590 h320", I18n.T("ActGroup"))
        
        editGui.Add("Text", "x30 y215 w75", I18n.T("TypeLabel"))
        typeMap := ["Run", "URL", "CMD", "Send", "Paste", "KeyCombo", "Delay"]
        displayTypes := []
        for t in typeMap {
            displayTypes.Push(I18n.T("Act_" t))
        }
        ddlType := editGui.Add("DropDownList", "x105 y212 w140 Choose1", displayTypes)
        
        editGui.Add("Text", "x265 y215 w75", I18n.T("CmdLabel")) 
        edCommand := editGui.Add("Edit", "x340 y212 w155", "")
        btnCaptureCmd := editGui.Add("Button", "x505 y211 w80", I18n.T("BtnCaptureCmd"))
        btnCaptureCmd.OnEvent("Click", (*) => KeyUtil.CaptureKey(edCommand, editGui))

        btnAddAction := editGui.Add("Button", "x385 y250 w65", I18n.T("BtnAdd"))
        btnUpdateAction := editGui.Add("Button", "x455 y250 w65", I18n.T("BtnUpdate"))
        btnDelAction := editGui.Add("Button", "x525 y250 w65", I18n.T("BtnDelete"))
        
        lvActions := editGui.Add("ListView", "x30 y285 w560 h200 Grid", [I18n.T("TypeLabel"), I18n.T("CmdLabel")])
        lvActions.ModifyCol(1, 140)
        lvActions.ModifyCol(2, 395)

        tempActions := []
        if (existingRule && existingRule.Has("actions")) {
            for act in existingRule["actions"] {
                lvActions.Add(, I18n.T("Act_" act["type"]), act["command"])
                tempActions.Push(act.Clone())
            }
        }

        GetActualType := () => typeMap[ddlType.Value]

        btnAddAction.OnEvent("Click", (*) => AddActionToUI())
        AddActionToUI() {
            t := GetActualType()
            c := edCommand.Value
            if (c = "") {
                MsgBox(I18n.T("MsgEmptyCmd"))
                return
            }
            lvActions.Add(, I18n.T("Act_" t), c)
            tempActions.Push(Map("type", t, "command", c))
            edCommand.Value := ""
        }
        
        lvActions.OnEvent("ItemSelect", OnActionSelect)
        OnActionSelect(ctrl, item, selected) {
            if (selected && item > 0 && item <= tempActions.Length) {
                targetType := tempActions[item]["type"]
                for idx, val in typeMap {
                    if (val = targetType || val = StrTitle(targetType)) {
                        ddlType.Choose(idx)
                    }
                }
                edCommand.Value := tempActions[item]["command"]
            }
        }

        btnUpdateAction.OnEvent("Click", (*) => UpdateActionInUI())
        UpdateActionInUI() {
            row := lvActions.GetNext(0)
            if (row == 0) {
                MsgBox(I18n.T("MsgSelectToUpdate"))
                return
            }
            t := GetActualType()
            c := edCommand.Value
            if (c = "") {
                MsgBox(I18n.T("MsgEmptyCmd"))
                return
            }
            lvActions.Modify(row, , I18n.T("Act_" t), c)
            tempActions[row] := Map("type", t, "command", c)
        }

        btnDelAction.OnEvent("Click", (*) => DeleteActionFromUI())
        DeleteActionFromUI() {
            row := lvActions.GetNext(0)
            if (row == 0) {
                return
            }
            lvActions.Delete(row)
            tempActions.RemoveAt(row)
        }

        btnSave := editGui.Add("Button", "x200 y525 w100 h35", I18n.T("BtnSave"))
        btnCancel := editGui.Add("Button", "x320 y525 w100 h35", I18n.T("BtnCancel"))

        btnSave.OnEvent("Click", (*) => SaveTheRule())
        btnCancel.OnEvent("Click", (*) => (RestoreState(), editGui.Destroy()))

        SaveTheRule() {
            newKey := edKey.Value
            if (newKey = "") {
                MsgBox(I18n.T("MsgEmptyKey"))
                return
            }

            newRule := Map()
            newRule["enabled"] := existingRule ? existingRule["enabled"] : true
            newRule["group"] := edGroup.Value != "" ? edGroup.Value : "Default"
            newRule["desc"] := edDesc.Value
            newRule["key"] := newKey
            newRule["window"] := edWindow.Value
            newRule["count"] := Integer(edCount.Value)
            newRule["timeout"] := Integer(edTimeout.Value)
            newRule["actions"] := tempActions

            if (ruleIndex > 0) {
                ConfigManager.Rules[ruleIndex] := newRule
            } else {
                ConfigManager.Rules.Push(newRule)
            }

            ConfigManager.Save()
            RestoreState()
            editGui.Destroy()
        }
        
        editGui.Show("AutoSize")
    }
}

; ==============================================================================
; INTERNATIONALIZATION (I18N)
; ==============================================================================
class I18n {
    static Dict := Map(
        "en", Map(
            "Title", "Hotkey Manager V2.5 (Pro)",
            "AddRule", "Add Rule", "EditRule", "Edit Rule", "DeleteRule", "Delete Rule",
            "Startup", "Run at startup", "LangSwitch", "中文 / English",
            "ColGroup", "Group", "ColDesc", "Description", "ColKey", "Key", "ColWindow", "Window",
            "ColCount", "Count", "ColTimeout", "Timeout", "ColActions", "Actions",
            "TrigGroup", "Trigger Config", "GroupLabel", "Group:", "DescLabel", "Desc:",
            "KeyLabel", "Key:", "WindowLabel", "Window:", "CountLabel", "Count:",
            "TimeoutLabel", "Timeout:", "ActGroup", "Actions List", "TypeLabel", "Type:",
            "CmdLabel", "Command:", "BtnCapture", "Capture Key", "BtnCaptureWin", "Capture Window",
            "BtnCaptureCmd", "Capture Combo", "BtnAdd", "Add", "BtnUpdate", "Update",
            "BtnDelete", "Delete", "BtnSave", "Save Config", "BtnCancel", "Cancel",
            "GlobalWindow", "[Global]", "GlobalHint", "(Leave blank for Global)",
            "Act_Run", "Run Program", "Act_URL", "Open URL", "Act_CMD", "Command Line",
            "Act_Send", "Send Text", "Act_Paste", "Fast Paste", "Act_KeyCombo", "Key Combo", "Act_Delay", "Delay(ms)",
            "MsgEmptyCmd", "Empty command.", "MsgSelectToUpdate", "Select action first.",
            "MsgEmptyKey", "Key cannot be empty.", "TrayShow", "Dashboard", "TrayPause", "Pause Hotkeys",
            "TrayExit", "Exit", "ExecFeedback", "Executing: ", "PressKey", "Press Key...",
            "CaptureModeTitle", "--- Window Capture Mode ---",
            "CaptureModeHover", "Target: ",
            "EnableThisGroup", "Enable Group", "DisableThisGroup", "Disable Group"
        ),
        "zh", Map(
            "Title", "快捷键管理器 V2.5 (极简版)",
            "AddRule", "添加规则", "EditRule", "编辑当前规则", "DeleteRule", "删除当前规则",
            "Startup", "开机自启", "LangSwitch", "English / 中文",
            "ColGroup", "分组", "ColDesc", "动作描述", "ColKey", "触发按键", "ColWindow", "目标窗口",
            "ColCount", "点击数", "ColTimeout", "超时(ms)", "ColActions", "动作数量",
            "TrigGroup", "触发配置", "GroupLabel", "分组名:", "DescLabel", "动作描述:",
            "KeyLabel", "触发键:", "WindowLabel", "生效窗口:", "CountLabel", "次数:",
            "TimeoutLabel", "超时:", "ActGroup", "动作执行序列", "TypeLabel", "动作类型:",
            "CmdLabel", "命令内容:", "BtnCapture", "捕获按键", "BtnCaptureWin", "捕获窗口",
            "BtnCaptureCmd", "捕获组合键", "BtnAdd", "添加", "BtnUpdate", "修改",
            "BtnDelete", "删除", "BtnSave", "保存配置", "BtnCancel", "取消",
            "GlobalWindow", "【全局生效】", "GlobalHint", "(留空即全局生效)",
            "Act_Run", "运行程序 (Run)", "Act_URL", "打开网址 (URL)", "Act_CMD", "命令行 (CMD)",
            "Act_Send", "发送文本 (Send)", "Act_Paste", "极速粘贴 (Paste)", "Act_KeyCombo", "发送组合键 (Combo)", "Act_Delay", "延时等待 (Delay)",
            "MsgEmptyCmd", "内容不可为空。", "MsgSelectToUpdate", "请先在列表中选中项。",
            "MsgEmptyKey", "触发键不可为空。", "TrayShow", "打开控制台", "TrayPause", "挂起快捷键",
            "TrayExit", "退出程序", "ExecFeedback", "正在执行动作：", "PressKey", "请按键...",
            "CaptureModeTitle", "【 窗口捕获模式 】`n[左键] 选定目标`n[右键 / Esc] 取消捕获`n",
            "CaptureModeHover", "当前指向: ",
            "EnableThisGroup", "使能当前分组", "DisableThisGroup", "失能当前分组"
        )
    )

    static T(key) {
        lang := ConfigManager.AppLang
        if (this.Dict.Has(lang) && this.Dict[lang].Has(key)) {
            return this.Dict[lang][key]
        }
        if (this.Dict["en"].Has(key)) {
            return this.Dict["en"][key]
        }
        return key
    }
}