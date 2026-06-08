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
        ConfigManager.StartProcessMonitor()
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
        A_TrayMenu.Add(I18n.T("ExportConfig"), (*) => ConfigManager.Export())
        A_TrayMenu.Add(I18n.T("ImportConfig"), (*) => ConfigManager.Import())
        A_TrayMenu.Add(I18n.T("ProcessGroupsMenu"), (*) => UIManager.ShowProcessGroups())
        A_TrayMenu.Add() ; 分隔线
        A_TrayMenu.Add(I18n.T("LogView"), (*) => LogManager.View())
        A_TrayMenu.Add(I18n.T("LogClear"), (*) => LogManager.Clear())
        A_TrayMenu.Add(I18n.T("LogSettings"), (*) => LogManager.ShowSettings())
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
    static ProcessGroups := []
    static LogPath := ""
    static LogFile := "hotkey_log.txt"
    static LogClearDays := 30 

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
                this.ProcessGroups := loadedData.Has("processGroups") ? loadedData["processGroups"] : []
                this.LogPath := loadedData.Has("logPath") ? loadedData["logPath"] : ""
                this.LogFile := loadedData.Has("logFile") ? loadedData["logFile"] : "hotkey_log.txt"
                this.LogClearDays := loadedData.Has("logClearDays") ? loadedData["logClearDays"] : 30
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
                if (!rule.Has("triggerType")) {
                    rule["triggerType"] := "click"
                }
                if (!rule.Has("holdTime")) {
                    rule["holdTime"] := 500
                }
                if (!rule.Has("repeatInterval")) {
                    rule["repeatInterval"] := 0
                }
                if (!rule.Has("timeStart")) {
                    rule["timeStart"] := ""
                }
                if (!rule.Has("timeEnd")) {
                    rule["timeEnd"] := ""
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
            configObj["processGroups"] := this.ProcessGroups
            configObj["logPath"] := this.LogPath
            configObj["logFile"] := this.LogFile
            configObj["logClearDays"] := this.LogClearDays

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

    static Export() {
        savePath := FileSelect("S16", "HotkeyV2_Backup.json", I18n.T("ExportTitle"), "JSON (*.json)")
        if (savePath = "") {
            return
        }
        try {
            configObj := Map()
            configObj["runOnStartup"] := this.RunOnStartup
            configObj["language"] := this.AppLang
            configObj["rules"] := this.Rules
            FileOpen(savePath, "w").Write(JSON.Dump(configObj, "    "))
            MsgBox(I18n.T("ExportSuccess") "`n" savePath)
        } catch as err {
            MsgBox(I18n.T("ExportFail") "`n" err.Message)
        }
    }

    static Import() {
        openPath := FileSelect(1, "", I18n.T("ImportTitle"), "JSON (*.json)")
        if (openPath = "") {
            return
        }
        try {
            text := FileRead(openPath)
            loadedData := JSON.Load(text)
            importRules := loadedData.Has("rules") ? loadedData["rules"] : (loadedData is Array ? loadedData : [])
            
            if (importRules.Length == 0) {
                MsgBox(I18n.T("ImportEmpty"))
                return
            }
            
            result := MsgBox(I18n.T("ImportMergePrompt") " (" importRules.Length " " I18n.T("ImportRulesCount") ")", I18n.T("ImportTitle"), 0x3)
            if (result == "Yes") {
                ; 合并：追加不冲突的规则
                for newRule in importRules {
                    dup := false
                    for existRule in this.Rules {
                        if (existRule["key"] == newRule["key"] && existRule.Has("triggerType") && newRule.Has("triggerType") && existRule["triggerType"] == newRule["triggerType"]) {
                            dup := true
                            break
                        }
                    }
                    if (!dup) {
                        this.Rules.Push(newRule)
                    }
                }
            } else if (result == "No") {
                ; 替换
                this.Rules := importRules
            } else {
                return
            }
            this.Save()
            MsgBox(I18n.T("ImportSuccess"))
        } catch as err {
            MsgBox(I18n.T("ImportFail") "`n" err.Message)
        }
    }

    static StartProcessMonitor() {
        SetTimer(this.CheckProcesses.Bind(this), 2000)
    }

    static CheckProcesses() {
        for pg in this.ProcessGroups {
            if (!pg.Has("exe") || !pg.Has("group") || pg["exe"] = "" || pg["group"] = "") {
                continue
            }
            isRunning := ProcessExist(pg["exe"]) ? true : false
            shouldEnable := pg.Has("enabled") ? pg["enabled"] : true
            
            ; 切换该分组下所有规则的启用状态
            for rule in this.Rules {
                ruleGroup := rule.Has("group") ? rule["group"] : "Default"
                if (ruleGroup == pg["group"]) {
                    if (isRunning && shouldEnable) {
                        rule["enabled"] := true
                    } else if (!isRunning) {
                        rule["enabled"] := false
                    }
                }
            }
        }
        
        ; 重新应用热键
        HotkeyEngine.ApplyAll(this.Rules)
        if (UIManager.lvRules) {
            UIManager.UpdateMainListView()
        }
    }
}

; ==============================================================================
; HOTKEY REGISTRATION & TRIGGER ENGINE
; ==============================================================================
class HotkeyEngine {
    static ActiveHotkeys := Map()
    static ActiveUpHotkeys := Map()
    static KeyPresses := Map()

    static ApplyAll(rules) {
        ; 清场：卸载并挂起所有旧热键
        for keyName, _ in this.ActiveHotkeys {
            try Hotkey(keyName, "Off")
        }
        this.ActiveHotkeys.Clear()
        for keyName, _ in this.ActiveUpHotkeys {
            try Hotkey(keyName, "Off")
        }
        this.ActiveUpHotkeys.Clear()

        KeyMap := Map()
        LongpressKeys := Map()
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
            
            ; 记录哪些键有长按规则，以便注册 UP 热键
            if (rule.Has("triggerType") && rule["triggerType"] == "longpress") {
                LongpressKeys[hookKey] := true
            }
        }

        ; 重新注册 DOWN 热键
        for k, _ in KeyMap {
            try {
                Hotkey(k, this.OnTrigger.Bind(this), "On")
                this.ActiveHotkeys[k] := true
            } catch as err {
                MsgBox("Error registering key '" k "':`n" err.Message)
            }
        }
        
        ; 为有长按规则的键注册 UP 热键（去掉 $ 前缀，UP 不需要防递归）
        for k, _ in LongpressKeys {
            cleanK := RegExReplace(k, "^[\$\~]+", "")
            upKey := cleanK " Up"
            try {
                Hotkey(upKey, this.OnKeyUp.Bind(this), "On")
                this.ActiveUpHotkeys[upKey] := true
            } catch as err {
                MsgBox("Error registering UP key '" upKey "':`n" err.Message)
            }
        }
    }

    static OnTrigger(ThisHotkey) {
        if (!this.KeyPresses.Has(ThisHotkey)) {
            this.KeyPresses[ThisHotkey] := {count: 0, timerFn: "", holdTimers: [], consumed: false, clickMatched: false, clickUnmatched: false, repeatTimer: ""}
        }
        
        data := this.KeyPresses[ThisHotkey]
        data.count += 1
        data.consumed := false
        data.clickMatched := false
        data.clickUnmatched := false
        
        maxTimeout := 0
        maxRuleCount := 1
        clickRules := []
        longpressRules := []
        
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
                ; 时间段过滤
                if (rule.Has("timeStart") && rule["timeStart"] != "" || rule.Has("timeEnd") && rule["timeEnd"] != "") {
                    if (!this.IsInTimeWindow(rule["timeStart"], rule["timeEnd"])) {
                        continue
                    }
                }
                triggerType := rule.Has("triggerType") ? rule["triggerType"] : "click"
                
                if (triggerType == "longpress") {
                    longpressRules.Push(rule)
                } else {
                    clickRules.Push(rule)
                    if (rule.Has("timeout") && rule["timeout"] > maxTimeout) {
                        maxTimeout := rule["timeout"]
                    }
                    ruleCount := rule.Has("count") ? rule["count"] : 1
                    if (ruleCount > maxRuleCount) {
                        maxRuleCount := ruleCount
                    }
                }
            }
        }
        
        ; [长按] 为每个长按规则启动独立的 hold timer
        for lpRule in longpressRules {
            holdTime := lpRule.Has("holdTime") ? lpRule["holdTime"] : 500
            timerFn := this.FireLongpress.Bind(this, ThisHotkey, lpRule)
            data.holdTimers.Push(timerFn)
            SetTimer(timerFn, -holdTime)
        }
        
        ; [点击] 点击计数逻辑（仅当有 click 规则时）
        if (clickRules.Length > 0) {
            if (maxTimeout == 0) {
                maxTimeout := 300
            }

            if (data.timerFn) {
                SetTimer(data.timerFn, 0)
            }
            
            CurrentCallback := this.ProcessTrigger.Bind(this, ThisHotkey, data.count, clickRules)
            data.timerFn := CurrentCallback
            
            ; [架构优化2] 状态机零延迟短路
            ; 如果当前击键次数已经达到了该键所配置的“最高次数”，无需继续等待超时，立刻全速分发！
            if (data.count >= maxRuleCount) {
                CurrentCallback()
            } else {
                SetTimer(CurrentCallback, -maxTimeout)
            }
        }
    }

    static FireLongpress(key, rule) {
        if (!this.KeyPresses.Has(key)) {
            return
        }
        data := this.KeyPresses[key]
        data.consumed := true
        ActionExecutor.Execute(rule)
        
        ; 长按连发：如果配置了 repeatInterval > 0，启动重复计时器
        repeatInterval := rule.Has("repeatInterval") ? rule["repeatInterval"] : 0
        if (repeatInterval > 0) {
            repeatFn := this.DoRepeat.Bind(this, key, rule)
            data.repeatTimer := repeatFn
            SetTimer(repeatFn, repeatInterval)
        }
    }

    static DoRepeat(key, rule) {
        if (!this.KeyPresses.Has(key)) {
            return
        }
        ActionExecutor.Execute(rule)
    }

    static OnKeyUp(ThisHotkey) {
        ; 将 UP 热键名转回 DOWN 热键名: "F10 Up" -> "$F10"
        downKey := RegExReplace(ThisHotkey, "\s+Up$", "")
        ; KeyPresses 中的 key 可能带 $ 前缀，尝试匹配
        if (!this.KeyPresses.Has(downKey)) {
            downKey := "$" downKey
            if (!this.KeyPresses.Has(downKey)) {
                return
            }
        }
        
        data := this.KeyPresses[downKey]
        
        ; 取消所有长按计时器
        for timerFn in data.holdTimers {
            SetTimer(timerFn, 0)
        }
        data.holdTimers := []
        
        ; 取消连发计时器
        if (data.repeatTimer) {
            SetTimer(data.repeatTimer, 0)
            data.repeatTimer := ""
        }
        
        ; 长按已触发，不再透传
        if (data.consumed) {
            data.consumed := false
            return
        }
        
        ; 点击已匹配，不再透传
        if (data.clickMatched) {
            data.clickMatched := false
            return
        }
        
        ; ProcessTrigger 运行了但没匹配到，且当时有长按计时器在跑 → 现在透传
        if (data.clickUnmatched) {
            data.clickUnmatched := false
            this.PassThrough(downKey, 1)
            return
        }
        
        ; 短按：取消可能还在跑的 click 计时器，透传原生按键
        if (data.timerFn) {
            SetTimer(data.timerFn, 0)
            data.timerFn := ""
        }
        this.PassThrough(downKey, 1)
        data.count := 0
    }

    static ProcessTrigger(key, count, rulesList) {
        if (this.KeyPresses.Has(key)) {
            data := this.KeyPresses[key]
            data.count := 0
            data.timerFn := ""
        }
        
        matched := false
        for rule in rulesList {
            ruleCount := rule.Has("count") ? rule["count"] : 1
            if (ruleCount == count) {
                ActionExecutor.Execute(rule)
                matched := true
                if (this.KeyPresses.Has(key)) {
                    this.KeyPresses[key].clickMatched := true
                }
                return
            }
        }

        ; [架构优化3] 事件漏斗兜底机制 (Pass-Through)
        ; 如果该次击键没有命中任何自定义规则
        ; 检查是否有长按计时器还在跑 → 有则推迟透传，等 OnKeyUp 处理
        if (!matched) {
            if (this.KeyPresses.Has(key) && this.KeyPresses[key].holdTimers.Length > 0) {
                this.KeyPresses[key].clickUnmatched := true
            } else {
                this.PassThrough(key, count)
            }
        }
    }

    static IsInTimeWindow(tStart, tEnd) {
        ; 空字符串表示不限制
        now := A_Hour ":" Format("{:02d}", A_Min)
        if (tStart != "" && tStart > now) {
            return false
        }
        if (tEnd != "" && tEnd < now) {
            return false
        }
        return true
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
        
        ; 写入执行日志
        LogManager.Write(displayStr, rule["key"], rule["actions"])

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
                case "volumeup":
                    step := IsInteger(cmd) ? Integer(cmd) : 2
                    curVol := SoundGetVolume()
                    SoundSetVolume(Min(curVol + step, 100))
                case "volumedown":
                    step := IsInteger(cmd) ? Integer(cmd) : 2
                    curVol := SoundGetVolume()
                    SoundSetVolume(Max(curVol - step, 0))
                case "volumemute":
                    SoundSetMute(-1)
                case "lockscreen":
                    DllCall("user32\LockWorkStation")
                case "screenshot":
                    Run("snippingtool.exe")
                case "sleep":
                    DllCall("PowrProf\SetSuspendState", "int", 0, "int", 0, "int", 0)
                case "shutdown":
                    result := MsgBox(I18n.T("ShutdownConfirm"), I18n.T("ShutdownTitle"), 0x4)
                    if (result == "Yes") {
                        Shutdown(9)
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

        this.lvRules := this.MainGui.Add("ListView", "x10 y10 w780 h380 Grid Checked", [I18n.T("ColGroup"), I18n.T("ColDesc"), I18n.T("ColKey"), I18n.T("ColTrigger"), I18n.T("ColWindow"), I18n.T("ColCount"), I18n.T("ColHoldTime"), I18n.T("ColActions")])
        
        this.lvRules.ModifyCol(1, 70)
        this.lvRules.ModifyCol(2, 180)
        this.lvRules.ModifyCol(3, 100)
        this.lvRules.ModifyCol(4, 85)
        this.lvRules.ModifyCol(5, 130)
        this.lvRules.ModifyCol(6, 50)
        this.lvRules.ModifyCol(7, 70)
        this.lvRules.ModifyCol(8, 70)

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
            tt := rule.Has("triggerType") && rule["triggerType"] == "longpress" ? I18n.T("TrigLongpress") : I18n.T("TrigClick")
            w := rule.Has("window") && rule["window"] != "" ? rule["window"] : I18n.T("GlobalWindow")
            c := rule.Has("count") ? rule["count"] : "1"
            h := rule.Has("triggerType") && rule["triggerType"] == "longpress" ? (rule.Has("holdTime") ? rule["holdTime"] : "500") : "-"
            a := rule.Has("actions") ? rule["actions"].Length : 0
            
            this.lvRules.Add(rule["enabled"] ? "Check" : "-Check", g, d, k, tt, w, c, h, a " " I18n.T("Actions"))
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

    static ShowProcessGroups() {
        pgGui := Gui("+Owner", I18n.T("ProcessGroupsTitle"))
        pgGui.SetFont("s9", "Segoe UI")
        pgGui.OnEvent("Close", (*) => pgGui.Destroy())
        
        pgGui.Add("Text", "x15 y15 w500", I18n.T("ProcessGroupsDesc"))
        
        lvPG := pgGui.Add("ListView", "x15 y45 w500 h200 Grid", [I18n.T("ProcessExe"), I18n.T("ProcessGroup"), I18n.T("ProcessEnabled")])
        lvPG.ModifyCol(1, 180)
        lvPG.ModifyCol(2, 180)
        lvPG.ModifyCol(3, 110)
        
        for pg in ConfigManager.ProcessGroups {
            exeName := pg.Has("exe") ? pg["exe"] : ""
            groupName := pg.Has("group") ? pg["group"] : ""
            enabled := pg.Has("enabled") ? pg["enabled"] : true
            lvPG.Add(, exeName, groupName, enabled ? I18n.T("Yes") : I18n.T("No"))
        }
        
        pgGui.Add("Text", "x15 y260 w60", I18n.T("ProcessExe") ":")
        edExe := pgGui.Add("Edit", "x80 y257 w150", "")
        pgGui.Add("Text", "x240 y260 w60", I18n.T("ProcessGroup") ":")
        edGroup := pgGui.Add("Edit", "x305 y257 w100", "")
        cbEnabled := pgGui.Add("CheckBox", "x420 y258 w60", I18n.T("ProcessEnabled"))
        cbEnabled.Value := 1
        
        btnAddPG := pgGui.Add("Button", "x15 y295 w80", I18n.T("BtnAdd"))
        btnAddPG.OnEvent("Click", (*) => AddPG())
        AddPG() {
            exeVal := edExe.Value
            groupVal := edGroup.Value
            if (exeVal = "" || groupVal = "") {
                return
            }
            newPG := Map("exe", exeVal, "group", groupVal, "enabled", cbEnabled.Value ? true : false)
            ConfigManager.ProcessGroups.Push(newPG)
            ConfigManager.Save()
            lvPG.Add(, exeVal, groupVal, cbEnabled.Value ? I18n.T("Yes") : I18n.T("No"))
            edExe.Value := ""
            edGroup.Value := ""
        }
        
        lvPG.OnEvent("ContextMenu", LvPGContextMenu)
        LvPGContextMenu(ctrl, item, isRight, x, y) {
            if (item == 0) {
                return
            }
            ctx := Menu()
            ctx.Add(I18n.T("DeleteRule"), (*) => DelPG(item))
            ctx.Show()
        }
        DelPG(idx) {
            ConfigManager.ProcessGroups.RemoveAt(idx)
            ConfigManager.Save()
            lvPG.Delete(idx)
            ; 恢复被该分组禁用的规则
            for rule in ConfigManager.Rules {
                rule["enabled"] := true
            }
            ConfigManager.Save()
        }
        
        pgGui.Show("AutoSize")
    }

    static ShowEditRule(existingRule := "", ruleIndex := 0) {
        wasSuspended := A_IsSuspended
        Suspend(true)
        RestoreState := (*) => (!wasSuspended ? Suspend(false) : "")
        
        editGui := Gui("+Owner" this.MainGui.Hwnd, I18n.T("EditRule"))
        editGui.SetFont("s9", "Segoe UI")
        editGui.OnEvent("Close", (*) => (RestoreState(), editGui.Destroy()))
        
        editGui.Add("GroupBox", "x15 y15 w590 h225", I18n.T("TrigGroup"))
        
        editGui.Add("Text", "x30 y42 w75", I18n.T("GroupLabel"))
        edGroup := editGui.Add("Edit", "x105 y39 w140", existingRule ? existingRule["group"] : "Default")
        
        editGui.Add("Text", "x270 y42 w75", I18n.T("DescLabel"))
        edDesc := editGui.Add("Edit", "x345 y39 w240", existingRule ? existingRule["desc"] : "")

        editGui.Add("Text", "x30 y80 w75", I18n.T("KeyLabel"))
        edKey := editGui.Add("Edit", "x105 y77 w140", existingRule ? existingRule["key"] : "")
        btnCapture := editGui.Add("Button", "x255 y76 w85", I18n.T("BtnCapture"))
        btnCapture.OnEvent("Click", (*) => KeyUtil.CaptureKey(edKey, editGui))

        ; --- 触发类型选择 ---
        editGui.Add("Text", "x365 y80 w55", I18n.T("TrigTypeLabel"))
        trigTypeMap := ["click", "longpress"]
        trigDisplay := [I18n.T("TrigClick"), I18n.T("TrigLongpress")]
        defaultTrig := (existingRule && existingRule.Has("triggerType") && existingRule["triggerType"] == "longpress") ? 2 : 1
        ddlTrigType := editGui.Add("DropDownList", "x420 y77 w90 Choose" defaultTrig, trigDisplay)
        
        ; --- 长按时长（仅长按时显示）---
        txtHoldTime := editGui.Add("Text", "x30 y118 w75", I18n.T("HoldTimeLabel"))
        edHoldTime := editGui.Add("Edit", "x105 y115 w60 Number", existingRule && existingRule.Has("holdTime") ? existingRule["holdTime"] : "500")
        txtHoldMs := editGui.Add("Text", "x170 y118 w30", "ms")
        
        ; --- 连发间隔（仅长按时显示）---
        txtRepeat := editGui.Add("Text", "x220 y118 w55", I18n.T("RepeatLabel"))
        edRepeat := editGui.Add("Edit", "x275 y115 w55 Number", existingRule && existingRule.Has("repeatInterval") ? existingRule["repeatInterval"] : "0")
        txtRepeatMs := editGui.Add("Text", "x335 y118 w60", "ms (0=" I18n.T("RepeatOff") ")")
        
        ; --- 点击次数与超时（仅点击时显示）---
        txtCount := editGui.Add("Text", "x30 y118 w75", I18n.T("CountLabel"))
        edCount := editGui.Add("Edit", "x105 y115 w50 Number", existingRule && existingRule.Has("count") ? existingRule["count"] : "1")
        
        txtTimeout := editGui.Add("Text", "x175 y118 w50", I18n.T("TimeoutLabel"))
        edTimeout := editGui.Add("Edit", "x225 y115 w55 Number", existingRule && existingRule.Has("timeout") ? existingRule["timeout"] : "300")
        txtTimeoutMs := editGui.Add("Text", "x285 y118 w30", "ms")

        ; 根据触发类型动态显示/隐藏字段
        UpdateTriggerFields() {
            isLP := (trigTypeMap[ddlTrigType.Value] == "longpress")
            txtHoldTime.Visible := isLP
            edHoldTime.Visible := isLP
            txtHoldMs.Visible := isLP
            txtRepeat.Visible := isLP
            edRepeat.Visible := isLP
            txtRepeatMs.Visible := isLP
            txtCount.Visible := !isLP
            edCount.Visible := !isLP
            txtTimeout.Visible := !isLP
            edTimeout.Visible := !isLP
            txtTimeoutMs.Visible := !isLP
        }
        ddlTrigType.OnEvent("Change", (*) => UpdateTriggerFields())
        UpdateTriggerFields()

        editGui.Add("Text", "x30 y155 w75", I18n.T("WindowLabel"))
        edWindow := editGui.Add("Edit", "x105 y152 w235", existingRule && existingRule.Has("window") ? existingRule["window"] : "")
        btnCaptureWin := editGui.Add("Button", "x350 y151 w110", I18n.T("BtnCaptureWin"))
        btnCaptureWin.OnEvent("Click", (*) => KeyUtil.CaptureWindow(edWindow, editGui))
        
        editGui.Add("Text", "x470 y155 w120 cGray", I18n.T("GlobalHint"))

        ; --- 时间段过滤 ---
        editGui.Add("Text", "x30 y192 w75", I18n.T("TimeRangeLabel"))
        edTimeStart := editGui.Add("Edit", "x105 y189 w55", existingRule && existingRule.Has("timeStart") ? existingRule["timeStart"] : "")
        editGui.Add("Text", "x165 y192 w15", "-")
        edTimeEnd := editGui.Add("Edit", "x180 y189 w55", existingRule && existingRule.Has("timeEnd") ? existingRule["timeEnd"] : "")
        editGui.Add("Text", "x240 y192 w140 cGray", I18n.T("TimeRangeHint"))

        editGui.Add("GroupBox", "x15 y255 w590 h320", I18n.T("ActGroup"))
        
        typeMap := ["Run", "URL", "CMD", "Send", "Paste", "KeyCombo", "Delay", "VolumeUp", "VolumeDown", "VolumeMute", "LockScreen", "Screenshot", "Sleep", "Shutdown"]
        displayTypes := []
        for t in typeMap {
            displayTypes.Push(I18n.T("Act_" t))
        }
        editGui.Add("Text", "x30 y285 w75", I18n.T("TypeLabel"))
        ddlType := editGui.Add("DropDownList", "x105 y282 w140 Choose1", displayTypes)
        
        editGui.Add("Text", "x265 y285 w75", I18n.T("CmdLabel")) 
        edCommand := editGui.Add("Edit", "x340 y282 w155", "")
        btnCaptureCmd := editGui.Add("Button", "x505 y281 w80", I18n.T("BtnCaptureCmd"))
        btnCaptureCmd.OnEvent("Click", (*) => KeyUtil.CaptureKey(edCommand, editGui))

        btnAddAction := editGui.Add("Button", "x385 y320 w65", I18n.T("BtnAdd"))
        btnUpdateAction := editGui.Add("Button", "x455 y320 w65", I18n.T("BtnUpdate"))
        btnDelAction := editGui.Add("Button", "x525 y320 w65", I18n.T("BtnDelete"))
        
        lvActions := editGui.Add("ListView", "x30 y355 w560 h200 Grid", [I18n.T("TypeLabel"), I18n.T("CmdLabel")])
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

        btnSave := editGui.Add("Button", "x200 y595 w100 h35", I18n.T("BtnSave"))
        btnCancel := editGui.Add("Button", "x320 y595 w100 h35", I18n.T("BtnCancel"))

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
            newRule["triggerType"] := trigTypeMap[ddlTrigType.Value]
            newRule["count"] := Integer(edCount.Value)
            newRule["timeout"] := Integer(edTimeout.Value)
            newRule["holdTime"] := Integer(edHoldTime.Value)
            newRule["repeatInterval"] := Integer(edRepeat.Value)
            newRule["timeStart"] := edTimeStart.Value
            newRule["timeEnd"] := edTimeEnd.Value
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
; EXECUTION LOG MANAGER
; ==============================================================================
class LogManager {
    static GetFullPath() {
        dir := ConfigManager.LogPath != "" ? ConfigManager.LogPath : A_ScriptDir
        if (SubStr(dir, -1) != "\") {
            dir .= "\"
        }
        return dir ConfigManager.LogFile
    }

    static Write(ruleDesc, ruleKey, actions) {
        if (ConfigManager.LogPath == "" && ConfigManager.LogFile == "hotkey_log.txt" && ConfigManager.LogClearDays == 30) {
            ; 默认值 = 未配置日志，跳过
            return
        }
        try {
            fullPath := this.GetFullPath()
            SplitPath(fullPath, , &dir)
            if (!DirExist(dir)) {
                DirCreate(dir)
            }
            actStr := ""
            for act in actions {
                if (actStr != "") {
                    actStr .= "; "
                }
                actStr .= act["type"] ":" act["command"]
            }
            timestamp := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
            line := "[" timestamp "] " ruleDesc " | Key: " ruleKey " | Actions: " actStr "`n"
            FileAppend(line, fullPath)
            this.AutoClear()
        }
    }

    static AutoClear() {
        if (ConfigManager.LogClearDays <= 0) {
            return
        }
        try {
            fullPath := this.GetFullPath()
            if (!FileExist(fullPath)) {
                return
            }
            cutoff := DateAdd(A_Now, -ConfigManager.LogClearDays, "Days")
            tempPath := fullPath ".tmp"
            keepFile := FileOpen(tempPath, "w")
            readFile := FileOpen(fullPath, "r")
            kept := 0
            while (!readFile.AtEOF) {
                line := readFile.ReadLine()
                ; 提取时间戳: [yyyy-MM-dd HH:mm:ss]
                if (RegExMatch(line, "^\[(\d{4}-\d{2}-\d{2})", &m)) {
                    lineDate := m[1]
                    if (lineDate >= FormatTime(cutoff, "yyyy-MM-dd")) {
                        keepFile.WriteLine(line)
                        kept++
                    }
                } else {
                    keepFile.WriteLine(line)
                    kept++
                }
            }
            readFile.Close()
            keepFile.Close()
            FileMove(tempPath, fullPath, 1)
        }
    }

    static Clear() {
        try {
            fullPath := this.GetFullPath()
            if (FileExist(fullPath)) {
                FileDelete(fullPath)
            }
            MsgBox(I18n.T("LogCleared"))
        } catch as err {
            MsgBox(I18n.T("LogClearFail") "`n" err.Message)
        }
    }

    static View() {
        fullPath := this.GetFullPath()
        if (!FileExist(fullPath)) {
            MsgBox(I18n.T("LogEmpty"))
            return
        }
        Run(fullPath)
    }

    static ShowSettings() {
        setGui := Gui("+Owner", I18n.T("LogSettingsTitle"))
        setGui.SetFont("s9", "Segoe UI")
        setGui.OnEvent("Close", (*) => setGui.Destroy())
        
        setGui.Add("Text", "x15 y15 w80", I18n.T("LogPathLabel"))
        edLogPath := setGui.Add("Edit", "x100 y12 w300", ConfigManager.LogPath)
        btnBrowse := setGui.Add("Button", "x410 y11 w80", I18n.T("LogBrowse"))
        btnBrowse.OnEvent("Click", (*) => BrowseLogPath())
        BrowseLogPath() {
            dir := DirSelect(ConfigManager.LogPath, 0, I18n.T("LogBrowse"))
            if (dir != "") {
                edLogPath.Value := dir
            }
        }
        
        setGui.Add("Text", "x15 y50 w80", I18n.T("LogFileLabel"))
        edLogFile := setGui.Add("Edit", "x100 y47 w150", ConfigManager.LogFile)
        
        setGui.Add("Text", "x15 y85 w80", I18n.T("LogClearDaysLabel"))
        edLogClear := setGui.Add("Edit", "x100 y82 w60 Number", ConfigManager.LogClearDays)
        setGui.Add("Text", "x165 y85 w100", I18n.T("LogClearDaysHint"))
        
        btnSave := setGui.Add("Button", "x100 y125 w80", I18n.T("BtnSave"))
        btnSave.OnEvent("Click", (*) => SaveLogSettings())
        SaveLogSettings() {
            ConfigManager.LogPath := edLogPath.Value
            ConfigManager.LogFile := edLogFile.Value != "" ? edLogFile.Value : "hotkey_log.txt"
            ConfigManager.LogClearDays := Integer(edLogClear.Value)
            ConfigManager.Save()
            setGui.Destroy()
        }
        
        setGui.Show("AutoSize")
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
            "ColCount", "Count", "ColTimeout", "Timeout(ms)", "ColHoldTime", "Hold(ms)", "ColActions", "Actions",
            "ColTrigger", "Trigger",
            "TrigGroup", "Trigger Config", "GroupLabel", "Group:", "DescLabel", "Desc:",
            "KeyLabel", "Key:", "WindowLabel", "Window:", "CountLabel", "Count:",
            "TimeoutLabel", "Timeout:", "TrigTypeLabel", "Type:", "TrigClick", "Click", "TrigLongpress", "Long Press",
            "HoldTimeLabel", "Hold Time:", "RepeatLabel", "Repeat:", "RepeatOff", "off",
            "TimeRangeLabel", "Time:", "TimeRangeHint", "(e.g. 09:00-18:00, blank=always)",
            "ActGroup", "Actions List", "TypeLabel", "Type:",
            "CmdLabel", "Command:", "BtnCapture", "Capture Key", "BtnCaptureWin", "Capture Window",
            "BtnCaptureCmd", "Capture Combo", "BtnAdd", "Add", "BtnUpdate", "Update",
            "BtnDelete", "Delete", "BtnSave", "Save Config", "BtnCancel", "Cancel",
            "GlobalWindow", "[Global]", "GlobalHint", "(Leave blank for Global)",
            "Act_Run", "Run Program", "Act_URL", "Open URL", "Act_CMD", "Command Line",
            "Act_Send", "Send Text", "Act_Paste", "Fast Paste", "Act_KeyCombo", "Key Combo", "Act_Delay", "Delay(ms)",
            "Act_VolumeUp", "Volume Up", "Act_VolumeDown", "Volume Down", "Act_VolumeMute", "Volume Mute",
            "Act_LockScreen", "Lock Screen", "Act_Screenshot", "Screenshot", "Act_Sleep", "Sleep", "Act_Shutdown", "Shutdown",
            "MsgEmptyCmd", "Empty command.", "MsgSelectToUpdate", "Select action first.",
            "MsgEmptyKey", "Key cannot be empty.", "TrayShow", "Dashboard", "TrayPause", "Pause Hotkeys",
            "TrayExit", "Exit", "ExecFeedback", "Executing: ", "PressKey", "Press Key...",
            "CaptureModeTitle", "--- Window Capture Mode ---",
            "CaptureModeHover", "Target: ",
            "EnableThisGroup", "Enable Group", "DisableThisGroup", "Disable Group",
            "ExportConfig", "Export Config", "ImportConfig", "Import Config",
            "ExportTitle", "Export Config", "ImportTitle", "Import Config",
            "ExportSuccess", "Config exported to:", "ExportFail", "Export failed:",
            "ImportEmpty", "No valid rules found in file.",
            "ImportMergePrompt", "Merge (Yes) or Replace (No)?",
            "ImportRulesCount", "rules",
            "ImportSuccess", "Config imported and saved.", "ImportFail", "Import failed:",
            "ProcessGroupsMenu", "Process Monitor",
            "ProcessGroupsTitle", "Process-Aware Groups",
            "ProcessGroupsDesc", "When a process is running, its linked rule group will be auto-enabled.",
            "ProcessExe", "Process (exe)", "ProcessGroup", "Group", "ProcessEnabled", "Active",
            "Yes", "Yes", "No", "No",
            "LogView", "View Log", "LogClear", "Clear Log", "LogSettings", "Log Settings",
            "LogSettingsTitle", "Log Settings", "LogPathLabel", "Path:",
            "LogFileLabel", "Filename:", "LogClearDaysLabel", "Auto-clear:",
            "LogClearDaysHint", "days (0=never)",
            "LogBrowse", "Browse...", "LogEmpty", "Log is empty.",
            "LogCleared", "Log cleared.", "LogClearFail", "Failed to clear log:",
            "ShutdownConfirm", "Are you sure you want to shutdown?",
            "ShutdownTitle", "Shutdown"
        ),
        "zh", Map(
            "Title", "快捷键管理器 V2.5 (极简版)",
            "AddRule", "添加规则", "EditRule", "编辑当前规则", "DeleteRule", "删除当前规则",
            "Startup", "开机自启", "LangSwitch", "English / 中文",
            "ColGroup", "分组", "ColDesc", "动作描述", "ColKey", "触发按键", "ColWindow", "目标窗口",
            "ColCount", "点击数", "ColTimeout", "超时(ms)", "ColHoldTime", "长按(ms)", "ColActions", "动作数量",
            "ColTrigger", "触发方式",
            "TrigGroup", "触发配置", "GroupLabel", "分组名:", "DescLabel", "动作描述:",
            "KeyLabel", "触发键:", "WindowLabel", "生效窗口:", "CountLabel", "次数:",
            "TimeoutLabel", "超时:", "TrigTypeLabel", "方式:", "TrigClick", "点击", "TrigLongpress", "长按",
            "HoldTimeLabel", "长按时长:", "RepeatLabel", "连发:", "RepeatOff", "关",
            "TimeRangeLabel", "时段:", "TimeRangeHint", "(如 09:00-18:00, 留空=全天)",
            "ActGroup", "动作执行序列", "TypeLabel", "动作类型:",
            "CmdLabel", "命令内容:", "BtnCapture", "捕获按键", "BtnCaptureWin", "捕获窗口",
            "BtnCaptureCmd", "捕获组合键", "BtnAdd", "添加", "BtnUpdate", "修改",
            "BtnDelete", "删除", "BtnSave", "保存配置", "BtnCancel", "取消",
            "GlobalWindow", "【全局生效】", "GlobalHint", "(留空即全局生效)",
            "Act_Run", "运行程序 (Run)", "Act_URL", "打开网址 (URL)", "Act_CMD", "命令行 (CMD)",
            "Act_Send", "发送文本 (Send)", "Act_Paste", "极速粘贴 (Paste)", "Act_KeyCombo", "发送组合键 (Combo)", "Act_Delay", "延时等待 (Delay)",
            "Act_VolumeUp", "音量+", "Act_VolumeDown", "音量-", "Act_VolumeMute", "静音切换",
            "Act_LockScreen", "锁屏", "Act_Screenshot", "截图", "Act_Sleep", "休眠", "Act_Shutdown", "关机",
            "MsgEmptyCmd", "内容不可为空。", "MsgSelectToUpdate", "请先在列表中选中项。",
            "MsgEmptyKey", "触发键不可为空。", "TrayShow", "打开控制台", "TrayPause", "挂起快捷键",
            "TrayExit", "退出程序", "ExecFeedback", "正在执行动作：", "PressKey", "请按键...",
            "CaptureModeTitle", "【 窗口捕获模式 】`n[左键] 选定目标`n[右键 / Esc] 取消捕获`n",
            "CaptureModeHover", "当前指向: ",
            "EnableThisGroup", "使能当前分组", "DisableThisGroup", "失能当前分组",
            "ExportConfig", "导出配置", "ImportConfig", "导入配置",
            "ExportTitle", "导出配置", "ImportTitle", "导入配置",
            "ExportSuccess", "配置已导出到:", "ExportFail", "导出失败:",
            "ImportEmpty", "文件中未找到有效规则。",
            "ImportMergePrompt", "合并(是) 还是 替换(否)?",
            "ImportRulesCount", "条规则",
            "ImportSuccess", "配置已导入并保存。", "ImportFail", "导入失败:",
            "ProcessGroupsMenu", "进程感知",
            "ProcessGroupsTitle", "进程感知分组",
            "ProcessGroupsDesc", "当指定进程运行时，自动启用关联的规则分组。",
            "ProcessExe", "进程名(exe)", "ProcessGroup", "分组", "ProcessEnabled", "启用",
            "Yes", "是", "No", "否",
            "LogView", "查看日志", "LogClear", "清除日志", "LogSettings", "日志设置",
            "LogSettingsTitle", "日志设置", "LogPathLabel", "路径:",
            "LogFileLabel", "文件名:", "LogClearDaysLabel", "自动清除:",
            "LogClearDaysHint", "天 (0=不清除)",
            "LogBrowse", "浏览...", "LogEmpty", "日志为空。",
            "LogCleared", "日志已清除。", "LogClearFail", "清除日志失败:",
            "ShutdownConfirm", "确定要关机吗？",
            "ShutdownTitle", "关机确认"
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