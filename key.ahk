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
    ; 制作流程：用仓库根目录 二维码转码.html 选择你的赞赏码图片 → 复制生成的代码 → 替换下面这一行。
    static DonateQR := ""

    static GetDonateQR() {
        static b64 := ""
        if (b64 == "") {
            b64 .= "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"
            b64 .= "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"
            b64 .= "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"
            b64 .= "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"
            b64 .= "P+PKL/rp/Q1MtjDE/wAKRzdFFFYngBRRRQAUUUUAFFFFAFaiiivrTrCiiigBK6Dw5ptvcQi5fd5kcnHPFc/VzSZZFv4EV2CmQZAPBrDERcqbs7GtJpS1R2txHHLAyTAFCOQap6XFFDc3SQBRHuXAXp0pdd/5BE/+7VDwh/x7z/7w/lXkRg/ZOVz0HJe0SF16yv7m8VrUMUC4OHA5rT0qKWHT4knz5gHOTmqer62dOuViEO/K5zuxV+wuftlmk5XbvGcZzRPn9mrrQIqPO7PU52/0zU5L2Z41fyyxK4kA4/Oo/DUKvqjCVQSqk884NXrvxIbe5kh+z52MRnd1rn47qWGV5IWKM+c4967qUak6bi1Y5JuEZprU78EEcVzQ1KPT9dvHmV2DcDbWp4eYtpETMSSSck/WmJcWEc063LwiTzT9/GccVxQSjKUWrnVN8yTTsQ/8JRaf88pvyH+NXdP1JNQyY4ZVQfxOABUf2vST/wAtLb9KvqEjjyoCoBnjgVM+VLSLQ4czerI7y7hs4DLM2AOg7muHvbgXV3JMF2hjkCuwk1HTZP8AWTwNj+8Qa53xFLbS3MZtWjKhednrXVg/dlZowxOqumaXhD/j1n/3x/KrM08Vv4g3SuqL5OMscd6reEP+PWf/AHx/KjUhbf8ACQxG6bChBjI4Jz3qKiTrSuXB2pRNG5uNOnISeSFiDwGNW0CRRAKAqKOPQCoZdPtriVJnjUuvINV9cNx/Z7pbRs7NwdvYVzJKTUUza7SbYRz6VFL5iSW6v/eBGazfEuo21xaLDDKsjbs/LziueZGQkOpUjsRTa9OnhIqSlzXOKeIbTjY2/CX/AB/y/wDXP+taXiSxuL2OEW8e8qTnkCs3wl/x/wAv/XP+tbOtao2mpGyxh95I5Nc9ZyWI93c1p2dH3tjE07Rr6HUIJJIMIrgk7hwK6DWIJLjTJool3OwGB+NZdn4kkubuKEwKA7Bc56VsajcmzsZJwoYoOh781nXdV1E5rUukocj5djkv7B1H/n3P/fQ/xrsLVGjsokcYZUAI/Cue/wCEql/590/OuiglM1qkhGN6BsfhTxMqrt7RCoqCvyM4Gb/XP/vH+dXtHME1yIbp3CtwpDkYNUZv9c/+8f50wE5yOtepKHPCxxKXLK51GpaFi2L2byb152lydwrm2klVirO4I6gk103h/U551EE0btgcSY4/Gr11o9pdzLLJH8w644z9a86FZ0W4VFc65UvaLmhoc9ounz30wkkZxApyTk/N7VvaxqCadZnaf3jDCL/Wp7qUWFmWihZ9owERa4u+upry4aSfOew9KIReJqcz0SCT9jCy3IGYsxZjkk5JrU8Mf8hZf901lVq+Gf8AkLL/ALprvrq1JnLS+NGv4s/5B6f79UfCU+25lhJ+8Mj8KveLP+Qen++K57SbkWmoxSscKDhj7VyUYc+GaOipLlrJmr4tgxNDOB94bTU3hD/UXH+8P5Ua9fWd5p5WOdGdSCAKPCH+ouP94fyqG39Vs+hSS9vdFPxX/wAhJP8ArmP5ms7TrM394sAcISCc4zWj4r/5CSf9cx/M1lWtzJaTiWI4ccZxXXRUnQXLuc9S3tXc3P8AhE3/AOflf++as6d4eeyvUnM4YLnjb7Vkf8JBf/8APUf981c0jWby61KKKVwUbORj2rmqQxHI+Z6G0JUeZWRt6rYnULMwhwnIOSM1jf8ACKP/AM/K/wDfNauuXUtnp5lhbD7gM4qhp8mqX9sJo7qNRnGCtYUpVIwvF2RrUUHKzWpRv/Dz2Vo85nDBe23FYwrV1W/vkeWzuJFYDGcDr3rKr08PzuN5u5xVeXm90WiiitzIKKKKACnR/wCsFNp0f+sFTP4WBPRRRXzFT4jle4UUUVmIKKKKACiiigAooooAK7ax/wCPGD/rmv8AKuJrtrH/AI8YP+ua/wAq0gejl/xSJ6KKK0PVCiiigDnvH/8AyKV1/vJ/6GKoeEEsoPBn2y6tY5RF5jsfLVmIB96v+P8A/kUrr/eT/wBDFZmg/wDJNLn/AK5zf1oAb/wmvhv/AKBUv/gPH/8AFVq6Bqmja+8y2mnBDEAW82BBnPpgmvKK7j4W/wDHxf8A+6n8zQBB4NUL47u1UAACUADt81WDNJN8TmtZZHe3L8xMxKH93np061B4P/5H28/7a/8AoVd1/ZNiNQ+3fZY/tWc+bj5umP5UAYXiXxHp2jxXOlfZpVkkhOPKjUJ8wI9R/KvNYLm4gyIJ5It3XY5XP5V3vibw5fan4rguUtxJaDyw5LDoDzxW+fC2i4402DP+7QBzFrDJ4T/0nxC32+G4G2JEJlKt1zh8AcelV/8AhDtT1C5bUtPuLe3iuSZIhvZGVW5AOF4/A1r6FoupXdzMviSP7RbqMwrKwYKc9se1ZWn+In0vxXNb3d3ImnQs6LF1VQOFAFABJ4H8QyoUk1KB1PVWnkIP/jtdH4V8Nf2Rp7RX0drNMZC6uq7sDA7kA9qzZNR1GXWhq8NzJ/YAILHPGAMH5evWk1LUNT1W/jvdDuZDpsQAmIO0ZBy3B56UAM+JlzPbrp/kTSRbvMzsYrn7vpXD/wBpX3/P7cf9/W/xrpPHuuWOsLZfYpvM8rfu+UjGcY6/SuSoA6nTvBmsX1vFqEF5bqZl3hmlcPz6kLWjda3/AMI9olxod888uoeW2JozuUbuR8xIPf0rI8LeJbix1K2jvL2RbCMEFOoAwccfWte70uTxH4ph1S2hFxpjugdmOMheG4PNAFPwx4wg0vTp4b83c8sjEqy4bAxjqWFZekaTqPiiSVI7pT5ADf6RI2OfTg+lejt4Y0RVLHToMAZPy1D4cn0KWWcaKkauAPM2oV45x1/GgDnLlLXxDapoWnW6Q39rjzZpECo2wbWwRknJ9RWt4f1q30ya28OTJK15FlC6AGPPLdSc9PasCXw54jttZuruwjaIySOVdZFBKls0un6Tq2ma7FrOsoRDExaaYsGPIx0H1FAFvxVcTDx3YwCWQQv5QaMMdrZY5yK7eO3ht0YQwxxA9digZ/KvLvGGrwX/AIhjvdPmJCRrtcAghgSe9dT8P9SvNSsr1ry4eZkcBS56cUAY3w8t4bjW75ZokkAjJAdQcfN71rXnizw9Z3k1tJpbl4XKMVt48Eg445rN+G3/ACHb/wD65H/0IVzPiD/kP6h/18Sf+hGgDu9P8UeH9Rv4bSHTHWSZtql7eMAH35rH8ZwRQeMtPWGJI1IjOEUAffPpWF4T/wCRn0//AK7Cug8c/wDI6ad/ux/+hmgD0OiiigAooooAKxvFH/HlF/10/oa2axvFH/HlF/10/oamWxhif4Ujm6KKKxPACiiigAooooAKKKKAK1FFFfWnWFFFFABW54Ys4Z2kllGXjYFTmsOlDMv3WI+hrOtBzhyp2LhJRldnZa/Ki6TMpYAsMAZ61R8InFvPn+8P5VzZZm+8SfqaFdl+6xH0Ncqwlqbhfc3de81Kx3F2bAyD7UYd+ON5GcUsd7YxIES4hVR0AYVwzMWOWJJ96So+o6WcivrWuiO0dtKdizNbFjySSOa4+92fbZ/Lxs8xtuOmM1HSV0UcP7J3vcxqVedbHZeHCP7Hi59f51z+pIsmvyI33WkAP6VQEjqMB2A9AaaSScknPrU08O4TlK+5Uq3NFRtsdePD9hwdrf8AfVXrqSOGyk3MFUIRyfauE82T/no//fRpGd2GGZiPc1i8HOTTlItYiKVkhO5pKWivRSscp03hEgWs+f74/lVtxEddZpNpCwggt25rj1dl+6xH0NDMzH5mJ+prhnhHKblfc6I17RUbbHWaj4ht7ZStuRLJ7dB+NR2nia3lAFwpib16iuWop/UqfLYPrM73O6EljeLndDKPwNZXiKztYNPDwxIrbxyormunSlLswwWJHuaUMI4STUtByrqUbNGz4TOL+X/rn/WrXi4gxW+P7xrnFZlOVJH0NDOzfeYn6mtHh263tLkKranyFnSuNUtv+ug/nXVa8R/Y8/PY"
            b64 .= "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"
            b64 .= "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"
            b64 .= "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"
            b64 .= "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"
            b64 .= "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"
            b64 .= "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"
            b64 .= "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"
            b64 .= "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"
            b64 .= "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"
            b64 .= "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"
            b64 .= "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"
            b64 .= "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"
            b64 .= "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"
            b64 .= "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"
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
    ; 关于窗口 & 赞赏二维码（二维码数据写死在 DonateQR，不可被外部文件替换）
    ; ============================================================
    static ShowAbout() {
        aboutGui := Gui("+Owner", I18n.T("AboutTitle"))
        aboutGui.SetFont("s10", "Segoe UI")
        CleanQR() {
            try FileDelete(A_Temp "\HotkeyDonateQR.png")
        }
        aboutGui.OnEvent("Close", (*) => (CleanQR(), aboutGui.Destroy()))
        aboutGui.OnEvent("Escape", (*) => (CleanQR(), aboutGui.Destroy()))

        aboutGui.Add("Text", "x20 y14 w340 Center", I18n.T("Title"))
        aboutGui.Add("Text", "x20 y40 w340 Center cGray", "AutoHotkey " A_AhkVersion)

        ; 占位数据（1x1 像素）长度不足 120 → 判定未嵌入真图，显示占位文案
        qrData := this.GetDonateQR()
        qrReady := StrLen(qrData) > 120
        if (qrReady) {
            tmpQR := A_Temp "\HotkeyDonateQR.png"
            if (this.Base64ToFile(qrData, tmpQR)) {
                aboutGui.Add("Picture", "x90 y70 w240", tmpQR)
            } else {
                qrReady := false
            }
        }
        if (!qrReady) {
            aboutGui.Add("Text", "x20 y80 w340 Center cGray", I18n.T("DonatePlaceholder"))
        }
        aboutGui.Add("Text", "x20 y340 w340 Center", I18n.T("DonateTip"))
        aboutGui.Show("AutoSize")
    }

    static Base64ToFile(b64, filePath) {
        size := 0
        DllCall("crypt32.dll\CryptStringToBinary", "Ptr", StrPtr(b64), "UInt", 0, "UInt", 1, "Ptr", 0, "UInt*", &size, "Ptr", 0, "Ptr", 0)
        if (size <= 0) {
            return false
        }
        buf := Buffer.Alloc(size)
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
        
        editGui.Add("GroupBox", "x15 y15 w590 h270", I18n.T("TrigGroup"))
        
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

        editGui.Add("GroupBox", "x15 y300 w590 h360", I18n.T("ActGroup"))

        ; --- 轮换触发开关：多组动作按触发次数循环切换 ---
        cbCycle := editGui.Add("CheckBox", "x30 y312 w560", I18n.T("EnableCycle"))
        ; --- 轮换组管理行（启用轮换后可见） ---
        txtCycleLabel := editGui.Add("Text", "x30 y346 w65", I18n.T("CycleGroupLabel"))
        ddlCycle := editGui.Add("DropDownList", "x95 y343 w150")
        btnAddCycle := editGui.Add("Button", "x255 y342 w70", I18n.T("CycleAddGroup"))
        btnDelCycle := editGui.Add("Button", "x330 y342 w70", I18n.T("CycleDelGroup"))
        
        typeMap := ["Run", "URL", "CMD", "Send", "Paste", "KeyCombo", "Delay", "LockScreen", "Sleep", "Shutdown"]
        displayTypes := []
        for t in typeMap {
            displayTypes.Push(I18n.T("Act_" t))
        }
        editGui.Add("Text", "x30 y378 w75", I18n.T("TypeLabel"))
        ddlType := editGui.Add("DropDownList", "x105 y375 w140 Choose1", displayTypes)
        
        editGui.Add("Text", "x265 y378 w75", I18n.T("CmdLabel")) 
        edCommand := editGui.Add("Edit", "x340 y375 w155", "")
        btnCaptureCmd := editGui.Add("Button", "x505 y374 w80", I18n.T("BtnCaptureCmd"))
        btnCaptureCmd.OnEvent("Click", (*) => KeyUtil.CaptureKey(edCommand, editGui))

        btnAddAction := editGui.Add("Button", "x385 y413 w65", I18n.T("BtnAdd"))
        btnUpdateAction := editGui.Add("Button", "x455 y413 w65", I18n.T("BtnUpdate"))
        btnDelAction := editGui.Add("Button", "x525 y413 w65", I18n.T("BtnDelete"))
        
        lvActions := editGui.Add("ListView", "x30 y448 w560 h200 Grid", [I18n.T("TypeLabel"), I18n.T("CmdLabel")])
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

        btnSave := editGui.Add("Button", "x200 y705 w100 h35", I18n.T("BtnSave"))
        btnCancel := editGui.Add("Button", "x320 y705 w100 h35", I18n.T("BtnCancel"))

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
            "DonatePlaceholder", "(Donation QR not embedded yet: convert your image via the QR encoder tool and replace DonateQR)"
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
            "DonatePlaceholder", "（赞赏码尚未嵌入：用 二维码转码.html 生成 Base64 后替换 key.ahk 中的 DonateQR）"
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
