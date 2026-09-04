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
        HotkeyEngine.StartRepeatGuard()
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
        A_TrayMenu.Add(I18n.T("About"), (*) => UIManager.ShowAbout())
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
            text := FileRead(this.FilePath, "UTF-8")
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
                this.NormalizeRule(rule)
            }
        } catch as err {
            MsgBox("Error loading config.json:`n" err.Message)
            this.Rules := []
        }
    }

    static NormalizeRule(rule) {
        ; 补齐缺失字段，防止导入/手工编辑的配置缺字段导致访问崩溃
        if (!rule.Has("key")) {
            rule["key"] := ""
        }
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
        if (!rule.Has("count")) {
            rule["count"] := 1
        }
        if (!rule.Has("timeout")) {
            rule["timeout"] := 300
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
        if (!rule.Has("days")) {
            rule["days"] := ""
        }
        if (!rule.Has("window")) {
            rule["window"] := ""
        }
        if (!rule.Has("cycle")) {
            rule["cycle"] := []
        }
        return rule
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

            f := FileOpen(this.FilePath, "w", "UTF-8")
            f.Write(JSON.Dump(configObj, "    "))
            f.Close()
            this.ManageStartupShortcut(this.RunOnStartup)

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
            f := FileOpen(savePath, "w", "UTF-8")
            f.Write(JSON.Dump(configObj, "    "))
            f.Close()
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
            try {
                text := FileRead(openPath, "UTF-8")
            } catch {
                text := FileRead(openPath)  ; 兼容旧版 GBK 导出
            }
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
                    this.NormalizeRule(newRule)
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
                for newRule in importRules {
                    this.NormalizeRule(newRule)
                }
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
        if (this.ProcessGroups.Length == 0) {
            return
        }
        changed := false
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
                    targetState := (isRunning && shouldEnable) ? true : false
                    if (rule["enabled"] != targetState) {
                        rule["enabled"] := targetState
                        changed := true
                    }
                }
            }
        }
        
        ; 仅在规则实际变化时才重建热键和刷新列表
        if (changed) {
            HotkeyEngine.ApplyAll(this.Rules)
            if (UIManager.lvRules) {
                UIManager.UpdateMainListView()
            }
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
    static DownState := Map()

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
        
        ; 为有长按规则的键注册 UP 热键（~前缀=不吞键，$防Send递归）
        for k, _ in LongpressKeys {
            upKey := k " Up"
            try {
                Hotkey(upKey, this.OnKeyUp.Bind(this), "On")
                this.ActiveUpHotkeys[upKey] := true
            } catch as err {
                ; 降级尝试：去掉 $ 前缀
                cleanK := RegExReplace(k, "^[\$\~]+", "")
                upKey2 := cleanK " Up"
                try {
                    Hotkey(upKey2, this.OnKeyUp.Bind(this), "On")
                    this.ActiveUpHotkeys[upKey2] := true
                } catch as err2 {
                    MsgBox("Error registering UP key:`n" err.Message "`n" err2.Message)
                }
            }
        }
    }

    static GetPhysicalKey(hk) {
        ; 从热键名提取物理键名，剥离 $ ~ ^ ! + # < > 前缀及 {} 包裹
        k := RegExReplace(hk, "^[\$\~\^\!\+\#\<\>]+", "")
        k := RegExReplace(k, "^\{([^}]+)\}$", "$1")
        return k
    }

    static IsKeyPhysicallyDown(key) {
        ; GetKeyState 无法解析的键名（如自定义 SC 码 sc10A）返回 false，防止运行时崩溃
        try {
            return GetKeyState(key, "P")
        } catch {
            return false
        }
    }

    static StartRepeatGuard() {
        SetTimer(this.CheckDownState.Bind(this), 30)
    }

    static CheckDownState() {
        ; 轮询清除已物理松开的键，供 OnTrigger 判断键盘自动重复
        ; 无法解析的键名（如 sc10A）视为已松开，避免崩溃并让其恢复原触发行为
        for key, _ in this.DownState {
            if (!this.IsKeyPhysicallyDown(key)) {
                this.DownState.Delete(key)
            }
        }
    }

    static OnTrigger(ThisHotkey) {
        physKey := this.GetPhysicalKey(ThisHotkey)
        ; [去抖] 忽略键盘自动重复：键物理上尚未松开时的再次触发视为系统 repeat
        if (this.DownState.Has(physKey) && this.DownState[physKey]) {
            return
        }
        this.DownState[physKey] := true
        if (!this.KeyPresses.Has(ThisHotkey)) {
            this.KeyPresses[ThisHotkey] := {count: 0, timerFn: "", holdTimers: [], consumed: false, clickMatched: false, clickUnmatched: false, repeatTimer: ""}
        }
        
        data := this.KeyPresses[ThisHotkey]
        data.count += 1
        data.consumed := false
        data.clickMatched := false
        data.clickUnmatched := false
        data.holdTimers := []
        data.repeatTimer := ""
        
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
                ; 时间段 + 星期过滤
                ts := rule.Has("timeStart") ? rule["timeStart"] : ""
                te := rule.Has("timeEnd") ? rule["timeEnd"] : ""
                td := rule.Has("days") ? rule["days"] : ""
                if (ts != "" || te != "" || (td != "" && td != "*")) {
                    if (!this.IsInTimeWindow(ts, te, td)) {
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
        ; 防止同键多长按规则同时触发
        if (data.consumed) {
            return
        }
        data.consumed := true
        ; 长按已触发 → 取消可能还在跑的点击计时器，防止后续多余透传
        if (data.timerFn) {
            SetTimer(data.timerFn, 0)
            data.timerFn := ""
        }
        ; [轮换] 长按触发：执行当前组并推进；本轮组号暂存供连发重复
        if (ActionExecutor.IsCycle(rule)) {
            data.cycleIdx := CycleManager.GetGroup(rule)
            ActionExecutor.ExecuteCycleGroup(rule, data.cycleIdx)
            CycleManager.Advance(rule)
        } else {
            ActionExecutor.Execute(rule)
        }
        
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
        data := this.KeyPresses[key]
        ; 兜底：如果 OnKeyUp 已经把 repeatTimer 清掉，停止执行
        if (!data.repeatTimer) {
            return
        }
        ; 物理按键检测兜底：如果键已被松开，主动停掉 repeat
        cleanKey := this.GetPhysicalKey(key)
        if (!this.IsKeyPhysicallyDown(cleanKey)) {
            SetTimer(data.repeatTimer, 0)
            data.repeatTimer := ""
            return
        }
        ; [轮换] 连发期间重复本次触发组，不推进指针
        if (data.HasOwnProp("cycleIdx")) {
            ActionExecutor.RepeatExecute(rule, data.cycleIdx)
        } else {
            ActionExecutor.Execute(rule)
        }
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
        
        ; 点击计时器还在跑 → 留给它处理（双击检测/透传），不在此处拍板
        if (data.timerFn) {
            return
        }
        ; 无点击计时器 → 直接透传
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
                ; 点击已匹配 → 取消所有待处理的长按计时器，防止"点击+继续按住"双触发
                if (this.KeyPresses.Has(key)) {
                    for timerFn in this.KeyPresses[key].holdTimers {
                        SetTimer(timerFn, 0)
                    }
                    this.KeyPresses[key].holdTimers := []
                    this.KeyPresses[key].clickMatched := true
                }
                ActionExecutor.Execute(rule)
                matched := true
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

    static IsInTimeWindow(tStart, tEnd, days) {
        ; 检查星期
        if (days != "" && days != "*") {
            ; days 格式: "1,2,3,4,5" (1=周一..7=周日)
            ; A_WDay: 1=Sun, 2=Mon..7=Sat
            userDay := (A_WDay == 1) ? 7 : A_WDay - 1
            if (!InStr("," days ",", "," userDay ",")) {
                return false
            }
        }
        ; 检查时间 — 空字符串表示不限制
        if (tStart == "" && tEnd == "") {
            return true
        }
        nowMin := A_Hour * 60 + A_Min
        startMin := tStart != "" ? this.TimeStrToMin(tStart) : 0
        endMin := tEnd != "" ? this.TimeStrToMin(tEnd) : 1439
        
        if (startMin <= endMin) {
            ; 正常区间: 09:00 ~ 18:00
            return nowMin >= startMin && nowMin <= endMin
        } else {
            ; 跨天区间: 21:00 ~ 09:00 (start > end)
            return nowMin >= startMin || nowMin <= endMin
        }
    }

    static TimeStrToMin(t) {
        ; "09:36" or "9:36" -> 576
        if (!RegExMatch(t, "^(\d{1,2}):(\d{2})$", &m)) {
            return 0
        }
        return Integer(m[1]) * 60 + Integer(m[2])
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
; CYCLE ROTATION STATE (轮换触发状态机)
; ==============================================================================
class CycleManager {
    static State := Map()

    ; 当前应执行第几组（0 起）；组数变小也不会越界
    static GetGroup(rule) {
        n := rule.Has("cycle") ? rule["cycle"].Length : 0
        if (n <= 1) {
            return 0
        }
        return Mod(this.State.Has(rule) ? this.State[rule] : 0, n)
    }

    ; 执行后推进指针（取余回绕）
    static Advance(rule) {
        n := rule.Has("cycle") ? rule["cycle"].Length : 0
        if (n <= 1) {
            return
        }
        this.State[rule] := Mod((this.State.Has(rule) ? this.State[rule] : 0) + 1, n)
    }
}

; ==============================================================================
; ACTION DISPATCHER & EXECUTOR
; ==============================================================================
class ActionExecutor {
    static IsCycle(rule) {
        return rule.Has("cycle") && IsObject(rule["cycle"]) && rule["cycle"].Length > 0
    }

    ; 触发入口（点击匹配 / 长按触发）
    static Execute(rule) {
        ; [轮换] 多组动作：执行当前组后自动推进指针
        if (this.IsCycle(rule)) {
            idx := CycleManager.GetGroup(rule)
            this.ExecuteCycleGroup(rule, idx)
            CycleManager.Advance(rule)
            return
        }
        if (!rule.Has("actions")) {
            return
        }
        displayStr := (rule.Has("desc") && rule["desc"] != "") ? rule["desc"] : rule["key"]
        this.RunActions(rule["actions"], displayStr, rule["key"])
    }

    ; 连发重复：轮换规则重复"本次触发组"不推进；普通规则等同 Execute
    static RepeatExecute(rule, groupIdx := -1) {
        if (this.IsCycle(rule)) {
            idx := (groupIdx >= 0) ? groupIdx : CycleManager.GetGroup(rule)
            this.ExecuteCycleGroup(rule, idx)
            return
        }
        this.Execute(rule)
    }

    ; 执行轮换规则的第 idx 组（0 起）；组数运行时变化时取余防御
    static ExecuteCycleGroup(rule, idx) {
        cycleList := rule["cycle"]
        n := cycleList.Length
        if (n == 0) {
            return
        }
        gIdx := Mod(idx, n)
        group := cycleList[gIdx + 1]
        if (!group.Has("actions")) {
            return
        }
        base := (rule.Has("desc") && rule["desc"] != "") ? rule["desc"] : rule["key"]
        gDesc := (group.Has("desc") && group["desc"] != "") ? group["desc"] : base
        this.RunActions(group["actions"], Format("[{1}/{2}] {3}", gIdx + 1, n, gDesc), rule["key"])
    }

    ; 共享执行体：ToolTip 提示 + 执行日志 + 动作分发
    static RunActions(actions, displayStr, ruleKey) {
        ToolTip(I18n.T("ExecFeedback") displayStr " ...")
        SetTimer(() => ToolTip(), -1500)

        ; 写入执行日志
        LogManager.Write(displayStr, ruleKey, actions)

        for action in actions {
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
                    SendEvent(KeyUtil.ToSendCombo(cmd))
                case "delay":
                    if (IsInteger(cmd)) {
                        Sleep(Integer(cmd))
                    }
                case "lockscreen":
                    DllCall("user32\LockWorkStation")
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

    static ToSendCombo(readableKey) {
        ; 将可读组合键转成 Send 可识别的键串，实体键用 {} 包裹，
        ; 否则 Left/Right/Up/Down 等方向键会被当作纯文本 "Left" 发送
        ahkKey := this.ToAhkKey(readableKey)
        modifiers := ""
        keyName := ahkKey
        while RegExMatch(keyName, "^([!#\^\+<>])", &match) {
            modifiers .= match[1]
            keyName := SubStr(keyName, 2)
        }
        return modifiers "{" keyName "}"
    }

    static CaptureKey(ctrl, parentGui) {
        wasSuspended := A_IsSuspended
        Suspend(true)
        savedVal := ctrl.Value
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
        } else {
            ctrl.Value := savedVal
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
    static ddlGroupFilter := ""
    static btnSort := ""
    static GroupFilter := ""        ; 当前分组筛选 ("" = 全部)
    static SortByGroup := false      ; 是否按分组排序
    static RowToRule := []           ; 列表显示行号 → 规则数组索引
    ; 赞赏二维码图片数据（Base64，随 exe 编译写死、运行期解码显示，外部无法替换）。
    ; 制作流程：用仓库根目录 二维码转码.html 或图片处理脚本生成 Base64 → 替换 GetDonateQR() 中的 b64 拼接内容。

    static GetDonateQR() {
        static b64 := ""
        if (b64 == "") {
            b64 .= "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"
            b64 .= "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"
            b64 .= "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"
            b64 .= "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"
            b64 .= "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"
            b64 .= "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"
            b64 .= "lfy4mfGdoJrH8PeIU8RQXBihaHyiF+Zgc5FecdpzX/CvL3/oJp+TUf8ACvL3/oJp+TVM3gXUyxP9sn/x7/GtrwzoF1oxuPtN79p80AL1+XGfU0AQ+FPDEugXM8ktwk3mqFG1SMYNch4f8Qx+H9SvnkgabzWwApxjBNb2ZvBEjXN5M98l0SioGI2Y575rmtC0F/El5deVMsOz5/mBOcmgDtvDWgyWl7NqMs6yx3abljI+5uOa4/Stbh0LxDfzy25mV2dAowMfNn+lGiaRfatqVzYx6i8RtgeSzEHBx0zSeJPCk2hWqXMt0k3mSbcBSDnGc0AbcZbww516ZjPDfcJCpwU3fMPbtitPw1ojx6rJrhmXy75DKsWOVDkNgn2p1/ob6/4U062jmWIokb7mGc/JjH61mCaTW418N2ztbTaeNjT7uH2fKeBzz1oAzJdZTR/G1/cTRtMgd12A+tdD4e0WWTV114TgQ3SmRYMHKhug9OK8+1W1kstTuLaWTzXicqz/AN4+tes+GP8AkWtP/wCvdP5UAULbwy8XiuXV3mRo5C37vbyMjFLF4blTxW+qmdDA2f3O0/3cfSprbxLHceJJNIFu4ePP7zcMHAz0rhPGV3cx+KL1I7iVVDLhVcgD5RQBe1zUk0nx9JcvGZIowMxg4zlMf1rY0jTZNY1iDxFFKIYHbItyORgbe3HUVxGk2EuuarHambEkufnfLdAT/Sui1PV/7B0ebw5tdp4xgXCNtHJ3dOvfFAGxr2lvYa2/iRpA8UAUmED5jxt61hW+sjW/HVjdRo8SFlXYWz0Brd8P6gLTwH9sukNyI2YsrHO75veuJ17VY9S1X7XaQm1G0AKpAII78UAdt4k8Gz61qzXkd2kQKhdpUk8Vm/8ACvL3/oJp+TVx/wBuu/8An6n/AO/hrrPB3iwWiQ6dNFLNJNOAJS/Tdgd6AJP+FeXv/QTT8mqWz8AXVtf29w9/G4ikV8bTkgEHFU/iNczw67EsU0iDyAcKxHc1H4Q0i+1dlvRqDqlvOu5GZjuxg+tAHpVV9R/5B1x/1yb+RqxVfUf+Qdcf9cm/kaqO6JlszgqKKK+iR4wUUUUwJIep+lS1FD1P0qWvDzD+IYVNwooorzjMKKKKACum8M/8eD/9dD/IVzNdN4Z/48H/AOuh/kKuG52YL+L8jXooorU9oqaolm9k41Hy/s3G7zT8vXj9cVzWs20kHhy7sTe/bJrkq9tCv3ggI4UdwAK6m9s7e/tWtrqMSRPjcpJGcHI6fSsuS58PLeQzPdWgntl8uMmYZQdMdaAOaeOTTns7O9u9l5NCHhvZPlNquPufoR+NOOnpq5NgNHaGSXj+0ypIbHJf/gWPXvWhNdWHiGzu799IN7JZyeTGiSEmQZ6jH1zU41JvDmjvNeXAlZwrwWjEI8a8DYO5x647UAZVjp8nhi3uL+21VbuC2b9/bRjG5umCcnB5/SqWnXtxeTXHiS4maRLCQ7Ldj/C2eAe2M+ldhDZaV/Y0s00EcFteBZpw7kAk88nPqaydU06xsI0FgY3tpl3tp0Zybv0IOSeOvHpQBY06a88R3dvesk9hbwdYSTicMODkY6Uk0+om6mureC5hhsXKm25P2vnAIPb9ah1vVL7SF0u5trWdLFIczwAcLwAFLEcYqfWPGSaVbWMpsjKLuLzQBJjb046c9aALOu6hI/hxhGWt7+4iDRQhsSZ4yAOuRSWGqWA0q0i1C8t/PSNRKs8g3BgOcg9+tZWnomq63ZajNrcDsGLxWfG5Aw+5kHnH07VT17w7aadqE+qXt5FKryNKLNhsaQZ6A59/SgGrnWBrXULG4i0m7gSQrjzIcNsJ6Hj8ap6rcXlhYW9mXkZpUKSX44EJGPnP/wCuuVkstX0uKK90HzhDqA80wwxb/KH8Kk856mn6drOqX9tfadqQldJMRyXDqAtt1yWGP546UAklsWdXsLxdOxL5muNcofInVSfI9x168flVfWri8Xwvp9pZvJ+5gZb2NBkoMDhx279auGPW9CGntZXcuq2WP9XBEANoxgZGeuf0q/8AbrAZI00Fr/jUR5h/0f8A66enU+nSgB+hSWWjeGra4jijF1cQBhGDhp2HYep5qvo9xJresyS20LaXJbyK12h5M+egPTGMH86p3oGub10f9x/YuTB5f7zzc9Nvp93361N4We61C+Yrusrq3ZTfFhk3PoCP4cYPT1oA7aiiigBK5HXP+QtN+H8hXXVyOuf8hab8P5ConscOO/h/Mo0UUVkeOQxf61P94V6CvQV59F/rU/3hXoK9BXs5hvE9nCdRJmCQuxGQqkketcI6P4tBm0Vv7OS2GJF+7vJ5B+Wu9YBhg8g9RXL+I/DV5eyw/wBjyw2aKpEgVjHuPb7o5/GvOO0o/De4nuV1ATTSSY2Y3sTj71YXiHTNV0HyDPqUknnEgbJW4xj/ABrY0s/8ICZP7V/ffa8FPs3zY25zndj1qzceO9Du8CawuJMfd8yFDj82oAqRxP4UQXGtN/aMdwAsaff2Hrn5v6UyLwNqZZp7bUIoVm+bCll4PIHFbHh3w7eW880mqyw3cLqPKRmMmzn0Yccelc/4t8VxX6wwacbq3aB2DnIQHtxg+1AFyztJPAkzX1+4uluR5QEXUHrk5+lTz/EDS7hQs2nTSAHIDhSK6e0t4rzSrT7TEk37pD+8UNzt96wdA8ISWGsXVzeraTQShtiAbtuWyOCMDigCpJqv/CYxrp+lGSxkh/elmO0FRxj5fqPyrB0TU18M+I7trwPcMm+Fih5Zt3Xn6V0vj6KPTdIhlsUW1kac"
            b64 .= "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"
            b64 .= "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"
            b64 .= "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"
            b64 .= "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"
            b64 .= "2v8AvnGE+6R948UAKZPEJ10at/Z0v2kf9MG29MdPpUmj3N3d+Praa/i8q4Z/mXaVx8nHB9q3dZ8T6xBqUkemWaXVqMbJVjZweOeQcdaxtMkv7jxjBqmo2r2ybv3jtGyIuFwOT0oAb49sbptfuLlbeU24VMyBDt6DvWZ4T/5Gew/66/0rsdY1SXUtUfTWVDo8oAe7QcDjP3/u9a5rUbL+wdbS70hXubaABxMRvTPcEjigDsr/AFPWIvFENrb226wYoHk8onGevNcn8SOPESf9cF/matJ43157czpYxNCOsgiYqPxzWY73vivWrae4tn8tnSF3hQ7VGeeefWgDq/hrzoEv/Xc/yFbGo+HrPUtRt72cy+bb42bWAHBzzx61zN/NfeDWNppNs09qV855JULbT0PIwOgqtp/j7U7rUbaB4rYLLKqEhTnBIHrQB6JVbUf+Qdcf9cm/kasVX1H/AJB1x/1yb+Rqo7omWzOCooor6JHjBRRRTAkh6n6VLUUAJJwCeO1S14eYfxDGotQooorzjIKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigCGL/AFqf7wr0Fegrz6L/AFqf7wr0Fegr2cw3iezhOoy7/wCPSb/cb+VcX8M/+PDUf95f5Gu0u+bWUDn5G/lXl/h3WdR8PxzJDpzyiUgnejDGK847TJbSNR3H/QLnr/zyb/Cuy+HFnc2p1D7Rbyw7lXHmIVz19ai/4TvVv+gR/wCOt/hQfHWrEEf2R1/2WoAb8Nv+QrqP+4P/AEI1m6X4egvL+7/taSWxQMTG74QPyc4Lda1PhvDMmpXzywvGHQY3KR3966bxH4ei1+KFJZniERJBUA5zQBw+veGrK1t420i6kv5WfDohD7Rjr8vvXU+HtBsfDgS+ku2jaeIKwnZVAJwSKzptMbwOBeWAkvXn/dMjr90dc8fSt7V9HTxJpNslxI0J+WU7RnBK9OfrQBnfEKGS90O3+yRvPmcN+6UtxtPPFZFl4n1+ysoLZNGLLDGsYJhfJAGK6TW7+fw5otsLOA3RQrFgg9Ap54+lVfDXia+1jUWgurH7OgjLbsHk5HHNAFTxjcTXfgiCe4j8qaR0Z0wRtPPHNcC9ldRwCd7eVYTgiQoQpz716/r2jx65p/2WWVol3BtyjJ4rF8W2BtPBSWUIeXyTGgwMkgd8CgDifDGlRazq6Wc0jojKzZTGeB711YtLiaf/AIRdoJRpidLvYdxx83Xp146Vyuh3F7oupLeR2UkjKpG1kYDkV6DLrt2nhNNUFpm4OMw4PHzY+tAGHd6vqHhLdp9nZefZW/Kzyo3OeTkjjqcVSv8AxNrOt6VJbjS8wzDG+KNz37flW5q95cat4BmuJLcxzSYzGoJIw4/GnaHdT6X4BSdIGeaIMRGwOT85/wAaAM22+T4ey6e/y3rbsW5/1h+bP3evSsKDV9Rs9Ik0I2X+uzwyN5nPoPwrrtE0w6zfQ+IbnfBcZI8gLxx8vfmtG68Nw3PiKLVjO4kixhABg4oA4K21vUbDSJND+xD98GGGRvM+b0FTaP4j1Lw9ANPSwUu77wsqMGJOB0/Cus8QaEi3z68kjtPbIHSEDhivQetcZqOq6hqGuQam+nujwFSECNg7TmgDs4tSvNU8I6lNf2v2aURyKE2lcjb15+tc54H8OW+qJ9ulllSS2nUqqYwcYPOa6rSLyfxLoVyt5AbVpN0WAD0IHPP1qz4d0KLQLWWCKV5VkfflhjHGKANWq+o/8g64/wCuTfyNWaraj/yDrj/rk38jVR3RMtmcFRRRX0SPGCiiimBqeHf+P5vpXUSWNtMP3kCNnvjmuX8Of8fzfSuwXpXj43+Iehh0pQ1RmS+H7R87N6H2NVJPDTf8s7jP+8tdBRXDyo0lhqUt0crJoF6n3VR/o1VpNNvIz81vJ+AzXZ0hqeRGEsDTezOFeN0OHRlPuMU2u7KK3UA1E9lbyffgjP1UUuQyeX9pHE0V176PYv1t1H04qF9Asm6K6/RqXIzJ4Cp0Zy1FdI/hu3P3ZZB+VRt4aX+G4b8Vo5GQ8HWXQ5+ittvDUn8Nwv4r/wDXph8OXA6Sxn86XKyXhay6GPRWsfDt32eL8z/hTT4fvPWP/vo/4UcrJ+r1f5TLorTOgXvon/fVIdBvf7qf99UcrF9Xq/ymbRWj/YN7/cT/AL6pf7Bvf7qf99UcrD2FX+UzaK0/7AvPSP8A76pR4evD3iH/AAI/4UcrH9Xq/wApl0VrDw7dd3iH4n/Cnjw3P3mjH4GjlY1hqv8AKY1Fbi+Gm/iuR+Cf/XqRfDUf8U7H6DFHIylg6z6HP0V0q+HLUfeeRvxFTLoNkvWMt9WNPkZawNXqcpRXYppVknS3T8RmpktYU+5Eg+iinyGiwEurOKEbkZCN+VFdzsHoKKOQv+z1/MefRf61P94V6CvQV59F/rU/3hXoK9BXq5hvE1wnUdRRRXnHaFFNk6VHn3oAmoqBydvWo8n1NAFuiqoJz1NOyfU0AWKKrgnPU078aAJqKhz71Hk+poAtUVVyfU0oJx1NAFmiq+T6mjJ9TQBYoqtk+pqRCdvWgCWio8n1pynIoAdRRRQAVW1H/kHXH/XJv5GrNVtR/wCQdcf9cm/kaqO6JlszgqKKK+iR4wUUUUwNTw5/x/N9K7Belcf4c/4/m+ldgvSvHxv8Q9HC/AOoooriOoKKKKACiiigAopKZJNHEMySKo9zigTaW5JRVUahaE4FzFn/AHhVhXVxlWBHqDQCknsx1FJS0DCi"
            b64 .= "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"
        }
        return b64
    }
    static BuildMain() {
        this.MainGui := Gui("+Resize +MinSize800x400", I18n.T("Title"))
        this.MainGui.SetFont("s9", "Segoe UI")

        ; --- 顶部工具栏：分组筛选 + 按分组排序 ---
        this.MainGui.Add("Text", "x10 y12", I18n.T("FilterLabel"))
        this.ddlGroupFilter := this.MainGui.Add("DropDownList", "x75 y9 w140", [I18n.T("FilterAll")])
        this.ddlGroupFilter.OnEvent("Change", (*) => this.OnFilterChange())
        this.btnSort := this.MainGui.Add("Button", "x225 y7 w110", I18n.T("SortByGroup"))
        this.btnSort.OnEvent("Click", (*) => this.ToggleGroupSort())

        this.lvRules := this.MainGui.Add("ListView", "x10 y38 w780 h350 Grid Checked NoSort", [I18n.T("ColGroup"), I18n.T("ColDesc"), I18n.T("ColKey"), I18n.T("ColTrigger"), I18n.T("ColWindow"), I18n.T("ColCount"), I18n.T("ColHoldTime"), I18n.T("ColActions")])
        
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
        ; 点击"分组"表头切换按分组排序
        this.lvRules.OnEvent("ColClick", (ctrl, col) => (col == 1 ? this.ToggleGroupSort() : ""))

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
            this.lvRules.Move(10, 38, width - 20, height - 48)
        }
    }

    static UpdateMainListView() {
        if (!this.lvRules) {
            return
        }
        ; --- 刷新筛选下拉框（保留当前选择） ---
        if (this.ddlGroupFilter) {
            this.ddlGroupFilter.Delete()
            filterList := [I18n.T("FilterAll")]
            for g in this.GetGroupList() {
                filterList.Push(g)
            }
            this.ddlGroupFilter.Add(filterList)
            curIdx := 1
            if (this.GroupFilter != "") {
                for i, g in filterList {
                    if (g == this.GroupFilter) {
                        curIdx := i
                        break
                    }
                }
            }
            this.ddlGroupFilter.Choose(curIdx)
        }
        ; --- 排序按钮状态 ---
        if (this.btnSort) {
            this.btnSort.Text := I18n.T("SortByGroup") . (this.SortByGroup ? " ✓" : "")
        }
        ; --- 计算显示集合（筛选 + 排序） ---
        displayIdx := []
        for i, rule in ConfigManager.Rules {
            g := rule.Has("group") ? rule["group"] : "Default"
            if (this.GroupFilter != "" && g != this.GroupFilter) {
                continue
            }
            displayIdx.Push(i)
        }
        if (this.SortByGroup && displayIdx.Length > 1) {
            ; 按分组名稳定插入排序（相同分组保持原顺序）
            Loop displayIdx.Length - 1 {
                i := A_Index + 1
                cur := displayIdx[i]
                curG := ConfigManager.Rules[cur].Has("group") ? ConfigManager.Rules[cur]["group"] : "Default"
                j := i - 1
                while (j >= 1) {
                    jG := ConfigManager.Rules[displayIdx[j]].Has("group") ? ConfigManager.Rules[displayIdx[j]]["group"] : "Default"
                    if (StrCompare(jG, curG) <= 0) {
                        break
                    }
                    displayIdx[j + 1] := displayIdx[j]
                    j--
                }
                displayIdx[j + 1] := cur
            }
        }
        ; --- 重建列表 + 行号→规则索引映射 ---
        this.RowToRule := []
        this.lvRules.Delete()
        for pos, idx in displayIdx {
            rule := ConfigManager.Rules[idx]
            this.RowToRule.Push(idx)
            g := rule.Has("group") ? rule["group"] : "Default"
            d := rule.Has("desc") ? rule["desc"] : ""
            k := rule.Has("key") ? rule["key"] : "?"
            tt := rule.Has("triggerType") && rule["triggerType"] == "longpress" ? I18n.T("TrigLongpress") : I18n.T("TrigClick")
            w := rule.Has("window") && rule["window"] != "" ? rule["window"] : I18n.T("GlobalWindow")
            c := rule.Has("count") ? rule["count"] : "1"
            h := rule.Has("triggerType") && rule["triggerType"] == "longpress" ? (rule.Has("holdTime") ? rule["holdTime"] : "500") : "-"
            a := ActionExecutor.IsCycle(rule) ? (I18n.T("CycleShort") "×" rule["cycle"].Length) : ((rule.Has("actions") ? rule["actions"].Length : 0) " " I18n.T("Actions"))

            this.lvRules.Add(rule["enabled"] ? "Check" : "-Check", g, d, k, tt, w, c, h, a)
        }
    }

    static OnRuleCheck(ctrl, item, checked) {
        idx := this.RowToRule.Has(item) ? this.RowToRule[item] : item
        ConfigManager.Rules[idx]["enabled"] := (checked == 1)
        ConfigManager.Save()
    }

    static OnDoubleClick(ctrl, item) {
        if (item == 0) {
            return
        }
        idx := this.RowToRule.Has(item) ? this.RowToRule[item] : item
        this.ShowEditRule(ConfigManager.Rules[idx], idx)
    }

    static ShowContextMenu(ctrl, item, isRightClick, x, y) {
        ; 收集当前选中行（Ctrl/Shift 多选）
        selRows := []
        r := 0
        while (r := ctrl.GetNext(r)) {
            selRows.Push(r)
        }
        ; 右键落在某行时：该行已在选中集内 → 操作整个选中集，否则仅该行
        workRows := []
        if (item > 0) {
            hit := false
            for sr in selRows {
                if (sr == item) {
                    hit := true
                    break
                }
            }
            workRows := hit ? selRows : [item]
        } else {
            workRows := selRows
        }
        ; 显示行号 → 规则索引
        workIndices := []
        for row in workRows {
            if (this.RowToRule.Has(row)) {
                workIndices.Push(this.RowToRule[row])
            }
        }

        ctxMenu := Menu()
        ctxMenu.Add(I18n.T("AddRule"), (*) => this.ShowEditRule())

        if (workIndices.Length > 0) {
            ctxMenu.Add()
            if (workIndices.Length == 1) {
                ctxMenu.Add(I18n.T("EditRule"), (*) => this.ShowEditRule(ConfigManager.Rules[workIndices[1]], workIndices[1]))
                ctxMenu.Add(I18n.T("DuplicateRule"), (*) => this.DuplicateRuleCallback(workIndices[1]))
            }
            ctxMenu.Add()
            ; 迁移到分组子菜单：已有分组 + 新建分组
            migMenu := Menu()
            for g in this.GetGroupList() {
                migMenu.Add(g, this.MigrateToGroup.Bind(this, workIndices, g))
            }
            migMenu.Add()
            migMenu.Add(I18n.T("NewGroup"), (*) => this.PromptNewGroupAndMigrate(workIndices))
            migLabel := workIndices.Length > 1 ? I18n.T("MigrateSelected") : I18n.T("MigrateRule")
            ctxMenu.Add(migLabel, migMenu)
            ctxMenu.Add()
            delLabel := workIndices.Length > 1 ? (I18n.T("DeleteSelected") " (" workIndices.Length ")") : I18n.T("DeleteRule")
            ctxMenu.Add(delLabel, (*) => this.DeleteSelectedCallback(workIndices))
            ctxMenu.Add()
            currentGroup := ConfigManager.Rules[workIndices[1]]["group"]
            ctxMenu.Add(I18n.T("EnableThisGroup") " [" currentGroup "]", (*) => this.ToggleGroup(currentGroup, true))
            ctxMenu.Add(I18n.T("DisableThisGroup") " [" currentGroup "]", (*) => this.ToggleGroup(currentGroup, false))
        }
        ctxMenu.Show()
    }

    static DuplicateRuleCallback(itemIndex) {
        cloned := ConfigManager.Rules[itemIndex].Clone()
        cloned["enabled"] := true
        ConfigManager.Rules.InsertAt(itemIndex + 1, cloned)
        ConfigManager.Save()
    }

    static DeleteSelectedCallback(indices) {
        if (indices.Length == 0) {
            return
        }
        if (indices.Length == 1) {
            result := MsgBox(I18n.T("DeleteConfirm"), I18n.T("DeleteTitle"), 0x4)
        } else {
            result := MsgBox(Format(I18n.T("DeleteMultiConfirm"), indices.Length), I18n.T("DeleteTitle"), 0x4)
        }
        if (result != "Yes") {
            return
        }
        ; 从后往前删，避免索引错位
        Loop indices.Length {
            ConfigManager.Rules.RemoveAt(indices[indices.Length - A_Index + 1])
        }
        ConfigManager.Save()
    }

    static MigrateToGroup(indices, targetGroup, *) {
        if (targetGroup = "") {
            return
        }
        changed := false
        for idx in indices {
            if (ConfigManager.Rules.Has(idx)) {
                if (ConfigManager.Rules[idx]["group"] != targetGroup) {
                    ConfigManager.Rules[idx]["group"] := targetGroup
                    changed := true
                }
            }
        }
        if (changed) {
            ConfigManager.Save()
        }
    }

    static PromptNewGroupAndMigrate(indices) {
        input := InputBox(I18n.T("NewGroupPrompt"), I18n.T("NewGroup"))
        if (input.Result != "OK") {
            return
        }
        gName := Trim(input.Value)
        if (gName = "") {
            return
        }
        this.MigrateToGroup(indices, gName)
    }

    static GetGroupList() {
        seen := Map()
        list := []
        for rule in ConfigManager.Rules {
            g := (rule.Has("group") && rule["group"] != "") ? rule["group"] : "Default"
            if (!seen.Has(g)) {
                seen[g] := true
                list.Push(g)
            }
        }
        return list
    }

    static OnFilterChange() {
        if (!this.ddlGroupFilter) {
            return
        }
        sel := this.ddlGroupFilter.Text
        this.GroupFilter := (sel == I18n.T("FilterAll")) ? "" : sel
        this.UpdateMainListView()
    }

    static ToggleGroupSort() {
        this.SortByGroup := !this.SortByGroup
        this.UpdateMainListView()
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
        pgGui.OnEvent("Escape", (*) => pgGui.Destroy())
        
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

    ; ============================================================
    ; 关于窗口 & 赞赏二维码（二维码数据写死在 GetDonateQR，不可被外部文件替换）
    ; ============================================================
    static ShowAbout() {
        aboutGui := Gui("+Owner", I18n.T("AboutTitle"))
        aboutGui.SetFont("s10", "Segoe UI")
        CleanQR() {
            try FileDelete(A_Temp "\HotkeyDonateQR.png")
        }
        aboutGui.OnEvent("Close", (*) => (CleanQR(), aboutGui.Destroy()))
        aboutGui.OnEvent("Escape", (*) => (CleanQR(), aboutGui.Destroy()))

        aboutGui.Add("Text", "x20 y14 w483 Center", I18n.T("Title"))
        aboutGui.Add("Text", "x20 y40 w483 Center cGray", "AutoHotkey " A_AhkVersion)

        ; 占位数据（1x1 像素）长度不足 120 → 判定未嵌入真图，显示占位文案
        qrData := this.GetDonateQR()
        qrReady := StrLen(qrData) > 120
        if (qrReady) {
            tmpQR := A_Temp "\HotkeyDonateQR.png"
            if (this.Base64ToFile(qrData, tmpQR)) {
                ; 不指定宽高，按嵌入图片的原始尺寸显示
                pic := aboutGui.Add("Picture", "x20 y70", tmpQR)
                pic.GetPos(,, &picW, &picH)
            } else {
                qrReady := false
            }
        }
        if (!qrReady) {
            aboutGui.Add("Text", "x20 y80 w483 Center cGray", I18n.T("DonatePlaceholder"))
        }
        ; 根据图片实际高度动态放置提示文字，避免提示语覆盖二维码
        tipY := qrReady ? (70 + picH + 15) : 340
        aboutGui.Add("Text", "x20 y" tipY " w483 Center", I18n.T("DonateTip"))
        aboutGui.Show("AutoSize")
    }

    static Base64ToFile(b64, filePath) {
        size := 0
        DllCall("crypt32.dll\CryptStringToBinary", "Ptr", StrPtr(b64), "UInt", 0, "UInt", 1, "Ptr", 0, "UInt*", &size, "Ptr", 0, "Ptr", 0)
        if (size <= 0) {
            return false
        }
        buf := Buffer(size)
        DllCall("crypt32.dll\CryptStringToBinary", "Ptr", StrPtr(b64), "UInt", 0, "UInt", 1, "Ptr", buf, "UInt*", &size, "Ptr", 0, "Ptr", 0)
        f := FileOpen(filePath, "w")
        f.RawWrite(buf, size)
        f.Close()
        return true
    }

    static ShowEditRule(existingRule := "", ruleIndex := 0) {
        ; 从托盘创建新规则时，先呼出主窗口（避免修改窗口孤悬）
        if (!existingRule) {
            this.ShowMain()
        }
        wasSuspended := A_IsSuspended
        Suspend(true)
        RestoreState := (*) => (!wasSuspended ? Suspend(false) : "")
        
        editGui := Gui("+Owner" this.MainGui.Hwnd, I18n.T("EditRule"))
        editGui.SetFont("s9", "Segoe UI")
        editGui.OnEvent("Close", (*) => (RestoreState(), editGui.Destroy()))
        editGui.OnEvent("Escape", (*) => (RestoreState(), editGui.Destroy()))
        
        editGui.Add("GroupBox", "x15 y15 w590 h250", I18n.T("TrigGroup"))
        
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
            isLP := (ddlTrigType.Text == I18n.T("TrigLongpress"))
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

        ; --- 时间段过滤 (下拉框防误输入) ---
        editGui.Add("Text", "x30 y192 w45", I18n.T("TimeStartLabel"))
        ; 解析已有时间值
        sh := "", sm := "", eh := "", em := ""
        if (existingRule && existingRule.Has("timeStart") && existingRule["timeStart"] != "") {
            parts := StrSplit(existingRule["timeStart"], ":")
            if (parts.Length == 2) {
                sh := parts[1], sm := parts[2]
            }
        }
        if (existingRule && existingRule.Has("timeEnd") && existingRule["timeEnd"] != "") {
            parts := StrSplit(existingRule["timeEnd"], ":")
            if (parts.Length == 2) {
                eh := parts[1], em := parts[2]
            }
        }
        hourList := [I18n.T("TimeOff")]
        Loop 24 {
            hourList.Push(Format("{:02d}", A_Index - 1))
        }
        minList := [I18n.T("TimeOff")]
        Loop 60 {
            minList.Push(Format("{:02d}", A_Index - 1))
        }
        hIdx := (sh != "") ? (Integer(sh) + 2) : 1
        mIdx := (sm != "") ? (Integer(sm) + 2) : 1
        ddlStartH := editGui.Add("DropDownList", "x78 y189 w50 Choose" hIdx, hourList)
        ddlStartM := editGui.Add("DropDownList", "x132 y189 w50 Choose" mIdx, minList)
        editGui.Add("Text", "x188 y192 w15", "-")
        ehIdx := (eh != "") ? (Integer(eh) + 2) : 1
        emIdx := (em != "") ? (Integer(em) + 2) : 1
        ddlEndH := editGui.Add("DropDownList", "x205 y189 w50 Choose" ehIdx, hourList)
        ddlEndM := editGui.Add("DropDownList", "x259 y189 w50 Choose" emIdx, minList)
        editGui.Add("Text", "x315 y192 w120 cGray", I18n.T("TimeRangeHint"))
        
        ; --- 星期过滤 ---
        editGui.Add("Text", "x30 y225 w45", I18n.T("DaysLabel"))
        dayNames := [I18n.T("DayMon"), I18n.T("DayTue"), I18n.T("DayWed"), I18n.T("DayThu"), I18n.T("DayFri"), I18n.T("DaySat"), I18n.T("DaySun")]
        cbDays := []
        existingDays := (existingRule && existingRule.Has("days") && existingRule["days"] != "" && existingRule["days"] != "*") ? existingRule["days"] : ""
        xPos := 78
        Loop 7 {
            checked := (existingDays == "" || InStr("," existingDays ",", "," A_Index ",")) ? "Checked" : ""
            cb := editGui.Add("CheckBox", "x" xPos " y222 w32 " checked, dayNames[A_Index])
            cbDays.Push(cb)
            xPos += 36
        }

        editGui.Add("GroupBox", "x15 y270 w590 h370", I18n.T("ActGroup"))

        ; --- 轮换触发开关：多组动作按触发次数循环切换 ---
        cbCycle := editGui.Add("CheckBox", "x30 y294 w560", I18n.T("EnableCycle"))
        ; --- 轮换组管理行（启用轮换后可见） ---
        txtCycleLabel := editGui.Add("Text", "x30 y324 w65", I18n.T("CycleGroupLabel"))
        ddlCycle := editGui.Add("DropDownList", "x95 y321 w150")
        btnAddCycle := editGui.Add("Button", "x255 y320 w70", I18n.T("CycleAddGroup"))
        btnDelCycle := editGui.Add("Button", "x330 y320 w70", I18n.T("CycleDelGroup"))
        
        typeMap := ["Run", "URL", "CMD", "Send", "Paste", "KeyCombo", "Delay", "LockScreen", "Sleep", "Shutdown"]
        displayTypes := []
        for t in typeMap {
            displayTypes.Push(I18n.T("Act_" t))
        }
        txtTypeLabel := editGui.Add("Text", "x30 y354 w75", I18n.T("TypeLabel"))
        ddlType := editGui.Add("DropDownList", "x105 y351 w140 Choose1", displayTypes)
        
        txtCmdLabel := editGui.Add("Text", "x265 y354 w75", I18n.T("CmdLabel")) 
        edCommand := editGui.Add("Edit", "x340 y351 w155", "")
        btnCaptureCmd := editGui.Add("Button", "x505 y350 w80", I18n.T("BtnCaptureCmd"))
        btnCaptureCmd.OnEvent("Click", (*) => KeyUtil.CaptureKey(edCommand, editGui))

        btnAddAction := editGui.Add("Button", "x385 y389 w65", I18n.T("BtnAdd"))
        btnUpdateAction := editGui.Add("Button", "x455 y389 w65", I18n.T("BtnUpdate"))
        btnDelAction := editGui.Add("Button", "x525 y389 w65", I18n.T("BtnDelete"))
        
        lvActions := editGui.Add("ListView", "x30 y424 w560 h200 Grid", [I18n.T("TypeLabel"), I18n.T("CmdLabel")])
        lvActions.ModifyCol(1, 140)
        lvActions.ModifyCol(2, 395)

        ; --- 动作组数据模型（支持轮换多组；未启用轮换时仅组1生效） ---
        cycleMode := (existingRule && ActionExecutor.IsCycle(existingRule))
        tempGroups := []
        if (cycleMode) {
            for cg in existingRule["cycle"] {
                acts := []
                if (cg.Has("actions")) {
                    for act in cg["actions"] {
                        acts.Push(act.Clone())
                    }
                }
                tempGroups.Push(Map("desc", cg.Has("desc") ? cg["desc"] : "", "actions", acts))
            }
        } else {
            acts := []
            if (existingRule && existingRule.Has("actions")) {
                for act in existingRule["actions"] {
                    acts.Push(act.Clone())
                }
            }
            tempGroups.Push(Map("desc", "", "actions", acts))
        }
        curGroup := 1
        GetCurActions() {
            return tempGroups[curGroup]["actions"]
        }
        CycleLoadActions() {
            lvActions.Delete()
            for act in GetCurActions() {
                lvActions.Add(, I18n.T("Act_" act["type"]), act["command"])
            }
        }
        CycleRefreshDDL() {
            ddlCycle.Delete()
            items := []
            for i, g in tempGroups {
                items.Push(I18n.T("CycleGroup") " " i)
            }
            ddlCycle.Add(items)
            ddlCycle.Choose(curGroup)
        }
        CycleSwitch() {
            sel := ddlCycle.Value
            if (sel >= 1 && sel <= tempGroups.Length) {
                curGroup := sel
            }
            CycleLoadActions()
        }
        CycleAddGroup() {
            tempGroups.Push(Map("desc", "", "actions", []))
            curGroup := tempGroups.Length
            CycleRefreshDDL()
            CycleLoadActions()
        }
        CycleDelGroup() {
            if (tempGroups.Length <= 1) {
                return
            }
            tempGroups.RemoveAt(curGroup)
            if (curGroup > tempGroups.Length) {
                curGroup := tempGroups.Length
            }
            CycleRefreshDDL()
            CycleLoadActions()
        }
        UpdateCycleVisibility() {
            isCy := cbCycle.Value
            txtCycleLabel.Visible := isCy
            ddlCycle.Visible := isCy
            btnAddCycle.Visible := isCy
            btnDelCycle.Visible := isCy
            inputY := isCy ? 354 : 326
            fieldY := isCy ? 351 : 323
            capY := isCy ? 350 : 322
            btnY := isCy ? 389 : 361
            listY := isCy ? 424 : 396
            txtTypeLabel.Move(30, inputY)
            ddlType.Move(105, fieldY)
            txtCmdLabel.Move(265, inputY)
            edCommand.Move(340, fieldY)
            btnCaptureCmd.Move(505, capY)
            btnAddAction.Move(385, btnY)
            btnUpdateAction.Move(455, btnY)
            btnDelAction.Move(525, btnY)
            lvActions.Move(30, listY)
        }
        cbCycle.Value := cycleMode ? 1 : 0
        cbCycle.OnEvent("Click", (*) => UpdateCycleVisibility())
        ddlCycle.OnEvent("Change", (*) => CycleSwitch())
        btnAddCycle.OnEvent("Click", (*) => CycleAddGroup())
        btnDelCycle.OnEvent("Click", (*) => CycleDelGroup())
        UpdateCycleVisibility()
        CycleRefreshDDL()
        CycleLoadActions()

        GetActualType() {
            selText := ddlType.Text
            for idx, t in typeMap {
                if (I18n.T("Act_" t) == selText) {
                    return t
                }
            }
            return typeMap[1]
        }

        btnAddAction.OnEvent("Click", (*) => AddActionToUI())
        AddActionToUI() {
            t := GetActualType()
            c := edCommand.Value
            if (c = "") {
                MsgBox(I18n.T("MsgEmptyCmd"))
                return
            }
            lvActions.Add(, I18n.T("Act_" t), c)
            GetCurActions().Push(Map("type", t, "command", c))
            edCommand.Value := ""
        }
        
        lvActions.OnEvent("ItemSelect", OnActionSelect)
        OnActionSelect(ctrl, item, selected) {
            acts := GetCurActions()
            if (selected && item > 0 && item <= acts.Length) {
                targetType := acts[item]["type"]
                for idx, val in typeMap {
                    if (val = targetType || val = StrTitle(targetType)) {
                        ddlType.Choose(idx)
                    }
                }
                edCommand.Value := acts[item]["command"]
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
            GetCurActions()[row] := Map("type", t, "command", c)
        }

        btnDelAction.OnEvent("Click", (*) => DeleteActionFromUI())
        DeleteActionFromUI() {
            row := lvActions.GetNext(0)
            if (row == 0) {
                return
            }
            lvActions.Delete(row)
            GetCurActions().RemoveAt(row)
        }

        btnSave := editGui.Add("Button", "x200 y660 w100 h35", I18n.T("BtnSave"))
        btnCancel := editGui.Add("Button", "x320 y660 w100 h35", I18n.T("BtnCancel"))

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
            newRule["triggerType"] := (ddlTrigType.Text == I18n.T("TrigClick")) ? "click" : "longpress"
            newRule["count"] := Integer(edCount.Value)
            newRule["timeout"] := Integer(edTimeout.Value)
            newRule["holdTime"] := Integer(edHoldTime.Value)
            newRule["repeatInterval"] := Integer(edRepeat.Value)
            ; 时间：从下拉框取值(选"不限"→空)
            offText := I18n.T("TimeOff")
            sH := ddlStartH.Text, sM := ddlStartM.Text
            eH := ddlEndH.Text, eM := ddlEndM.Text
            newRule["timeStart"] := (sH != offText && sM != offText) ? sH ":" sM : ""
            newRule["timeEnd"] := (eH != offText && eM != offText) ? eH ":" eM : ""
            ; 星期：从复选框取值(全选→"")
            dayStr := ""
            for i, cb in cbDays {
                if (cb.Value) {
                    dayStr .= (dayStr != "" ? "," : "") i
                }
            }
            newRule["days"] := (dayStr == "1,2,3,4,5,6,7") ? "" : dayStr
            ; [轮换] 启用轮换 → 写 cycle 组列表；否则写单组 actions（互斥字段）
            if (cbCycle.Value) {
                newRule["cycle"] := tempGroups
            } else {
                newRule["actions"] := GetCurActions()
            }

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
    static LastClearDate := ""

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
            FileAppend(line, fullPath, "UTF-8")
            today := FormatTime(A_Now, "yyyy-MM-dd")
            if (today != this.LastClearDate) {
                this.LastClearDate := today
                this.AutoClear()
            }
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
            keepFile := FileOpen(tempPath, "w", "UTF-8")
            readFile := FileOpen(fullPath, "r", "UTF-8")
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
        setGui.OnEvent("Escape", (*) => setGui.Destroy())
        
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
            "Title", "Hotkey Manager V2.7 (Pro)",
            "AddRule", "Add Rule", "EditRule", "Edit Rule", "DuplicateRule", "Duplicate Rule", "DeleteRule", "Delete Rule",
            "Startup", "Run at startup", "LangSwitch", "中文 / English",
            "ColGroup", "Group", "ColDesc", "Description", "ColKey", "Key", "ColWindow", "Window",
            "ColCount", "Count", "ColTimeout", "Timeout(ms)", "ColHoldTime", "Hold(ms)", "ColActions", "Actions",
            "ColTrigger", "Trigger",
            "TrigGroup", "Trigger Config", "GroupLabel", "Group:", "DescLabel", "Desc:",
            "KeyLabel", "Key:", "WindowLabel", "Window:", "CountLabel", "Count:",
            "TimeoutLabel", "Timeout:", "TrigTypeLabel", "Type:", "TrigClick", "Click", "TrigLongpress", "Long Press",
            "HoldTimeLabel", "Hold Time:", "RepeatLabel", "Repeat:", "RepeatOff", "off",
            "TimeStartLabel", "Start:", "TimeRangeHint", "(start>end=cross midnight)",
            "DaysLabel", "Days:", "TimeOff", "--",
            "DayMon", "Mon", "DayTue", "Tue", "DayWed", "Wed", "DayThu", "Thu", "DayFri", "Fri", "DaySat", "Sat", "DaySun", "Sun",
            "ActGroup", "Actions List", "TypeLabel", "Type:",
            "CmdLabel", "Command:", "BtnCapture", "Capture Key", "BtnCaptureWin", "Capture Window",
            "BtnCaptureCmd", "Capture Combo", "BtnAdd", "Add", "BtnUpdate", "Update",
            "BtnDelete", "Delete", "BtnSave", "Save Config", "BtnCancel", "Cancel",
            "GlobalWindow", "[Global]", "GlobalHint", "(Leave blank for Global)",
            "Act_Run", "Run Program", "Act_URL", "Open URL", "Act_CMD", "Command Line",
            "Act_Send", "Send Text", "Act_Paste", "Fast Paste", "Act_KeyCombo", "Key Combo", "Act_Delay", "Delay(ms)",
            "Act_LockScreen", "Lock Screen", "Act_Sleep", "Sleep", "Act_Shutdown", "Shutdown",
            "MsgEmptyCmd", "Empty command.", "MsgSelectToUpdate", "Select action first.",
            "MsgEmptyKey", "Key cannot be empty.", "TrayShow", "Dashboard", "TrayPause", "Pause Hotkeys",
            "TrayExit", "Exit", "ExecFeedback", "Executing: ", "PressKey", "Press Key...",
            "CaptureModeTitle", "--- Window Capture Mode ---",
            "CaptureModeHover", "Target: ",
            "EnableThisGroup", "Enable Group", "DisableThisGroup", "Disable Group",
            "FilterLabel", "Filter:", "FilterAll", "All",
            "SortByGroup", "Sort by Group",
            "MigrateRule", "Move to Group", "MigrateSelected", "Move Selected to Group",
            "NewGroup", "New Group...", "NewGroupPrompt", "Enter the new group name:",
            "DeleteSelected", "Delete Selected", "DeleteMultiConfirm", "Delete the selected {1} rules?",
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
            "ShutdownTitle", "Shutdown",
            "DeleteConfirm", "Delete this rule?",
            "DeleteTitle", "Delete Rule",
            "CycleShort", "Cycle", "EnableCycle", "Cycle Mode: multiple action groups, advance on each trigger",
            "CycleGroupLabel", "Group:", "CycleGroup", "Group",
            "CycleAddGroup", "Add Group", "CycleDelGroup", "Remove Group",
            "About", "About", "AboutTitle", "About",
            "DonateTip", "If you find this tool helpful, scan to support the developer :)",
            "DonatePlaceholder", "(Donation QR not embedded yet: convert your image via the QR encoder tool and replace GetDonateQR)"
        ),
        "zh", Map(
            "Title", "快捷键管理器 V2.7 (极简版)",
            "AddRule", "添加规则", "EditRule", "编辑当前规则", "DuplicateRule", "复制规则", "DeleteRule", "删除当前规则",
            "Startup", "开机自启", "LangSwitch", "English / 中文",
            "ColGroup", "分组", "ColDesc", "动作描述", "ColKey", "触发按键", "ColWindow", "目标窗口",
            "ColCount", "点击数", "ColTimeout", "超时(ms)", "ColHoldTime", "长按(ms)", "ColActions", "动作数量",
            "ColTrigger", "触发方式",
            "TrigGroup", "触发配置", "GroupLabel", "分组名:", "DescLabel", "动作描述:",
            "KeyLabel", "触发键:", "WindowLabel", "生效窗口:", "CountLabel", "次数:",
            "TimeoutLabel", "超时:", "TrigTypeLabel", "方式:", "TrigClick", "点击", "TrigLongpress", "长按",
            "HoldTimeLabel", "长按时长:", "RepeatLabel", "连发:", "RepeatOff", "关",
            "TimeStartLabel", "开始:", "TimeRangeHint", "(开始>结束=跨天)",
            "DaysLabel", "星期:", "TimeOff", "不限",
            "DayMon", "一", "DayTue", "二", "DayWed", "三", "DayThu", "四", "DayFri", "五", "DaySat", "六", "DaySun", "日",
            "ActGroup", "动作执行序列", "TypeLabel", "动作类型:",
            "CmdLabel", "命令内容:", "BtnCapture", "捕获按键", "BtnCaptureWin", "捕获窗口",
            "BtnCaptureCmd", "捕获组合键", "BtnAdd", "添加", "BtnUpdate", "修改",
            "BtnDelete", "删除", "BtnSave", "保存配置", "BtnCancel", "取消",
            "GlobalWindow", "【全局生效】", "GlobalHint", "(留空即全局生效)",
            "Act_Run", "运行程序 (Run)", "Act_URL", "打开网址 (URL)", "Act_CMD", "命令行 (CMD)",
            "Act_Send", "发送文本 (Send)", "Act_Paste", "极速粘贴 (Paste)", "Act_KeyCombo", "发送组合键 (Combo)", "Act_Delay", "延时等待 (Delay)",
            "Act_LockScreen", "锁屏", "Act_Sleep", "休眠", "Act_Shutdown", "关机",
            "MsgEmptyCmd", "内容不可为空。", "MsgSelectToUpdate", "请先在列表中选中项。",
            "MsgEmptyKey", "触发键不可为空。", "TrayShow", "打开控制台", "TrayPause", "挂起快捷键",
            "TrayExit", "退出程序", "ExecFeedback", "正在执行动作：", "PressKey", "请按键...",
            "CaptureModeTitle", "【 窗口捕获模式 】`n[左键] 选定目标`n[右键 / Esc] 取消捕获`n",
            "CaptureModeHover", "当前指向: ",
            "EnableThisGroup", "使能当前分组", "DisableThisGroup", "失能当前分组",
            "FilterLabel", "分组筛选:", "FilterAll", "全部",
            "SortByGroup", "按分组排序",
            "MigrateRule", "迁移到分组", "MigrateSelected", "迁移所选规则到分组",
            "NewGroup", "新建分组...", "NewGroupPrompt", "请输入新分组名称：",
            "DeleteSelected", "删除所选规则", "DeleteMultiConfirm", "确定删除所选 {1} 条规则？",
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
            "ShutdownTitle", "关机确认",
            "DeleteConfirm", "确定删除此规则？",
            "DeleteTitle", "删除确认",
            "CycleShort", "轮换", "EnableCycle", "轮换触发：多组动作按触发次数循环切换",
            "CycleGroupLabel", "轮换组:", "CycleGroup", "组",
            "CycleAddGroup", "加组", "CycleDelGroup", "删组",
            "About", "关于", "AboutTitle", "关于",
            "DonateTip", "如果这个工具帮到了你，扫码支持一下作者吧~",
            "DonatePlaceholder", "（赞赏码尚未嵌入：用 二维码转码.html 生成 Base64 后替换 key.ahk 中的 GetDonateQR）"
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
