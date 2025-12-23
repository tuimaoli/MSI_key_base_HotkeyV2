#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook
Persistent
InstallKeybdHook

; ==================== 1. 初始化与配置加载 ====================
ConfigFile := A_ScriptDir "\config.json"

; 默认配置
defaultConfig := Map(
    "shortPressTime", 0.3, ;这里变成了“双击判定间隔”，建议 0.3 秒
    "shortActions", Array(Map("type", "run", "command", "notepad.exe")),
    "longActions",  Array(Map("type", "run", "command", "calc.exe")),
    "hideTray", false,
    "autoStart", false
)

global config := Map()
; 用于记录点击次数
global PressCount := 0

LoadConfigSafe()

; 托盘菜单
A_TrayMenu.Delete()
A_TrayMenu.Add("设置界面", (*) => ShowConfig())
A_TrayMenu.Add("重启脚本", (*) => Reload())
A_TrayMenu.Add("退出", (*) => ExitApp())
A_TrayMenu.Default := "设置界面"
A_TrayMenu.ClickCount := 2

if config.Has("hideTray") && config["hideTray"]
    A_IconHidden := true

SetAutoStart(config.Has("autoStart") ? config["autoStart"] : false)

; ==================== 2. 核心按键逻辑 (单击/双击 模式) ====================

; 这种逻辑专门用于处理没有 Up (抬起) 信号的特殊按键
SC10A:: {
    global PressCount
    PressCount += 1
    
    ; 获取用户设置的判定时间 (如果没有设置，默认 0.3秒)
    waitTime := config.Has("shortPressTime") ? config["shortPressTime"] : 0.3
    
    if (PressCount == 1) {
        ; 第一次按下：启动定时器，等待 waitTime 秒
        ; 负数表示只运行一次
        SetTimer(CheckClickCount, -Abs(waitTime * 1000))
    } else if (PressCount >= 2) {
        ; 在等待时间内按下了第二次：触发双击（原本的长按配置）
        SetTimer(CheckClickCount, 0) ; 取消定时器（取消单击判定）
        PressCount := 0 ; 重置计数
        
        ToolTip("⚡ 触发双击动作")
        SetTimer () => ToolTip(), -1000
        
        if config.Has("longActions")
            ExecuteActions(config["longActions"])
    }
}

; 定时器函数：如果时间到了还没按下第二次，就认为是单击
CheckClickCount() {
    global PressCount
    if (PressCount == 1) {
        ; 只有一次点击 -> 触发单击（原本的短按配置）
        ToolTip("⚡ 触发单击动作")
        SetTimer () => ToolTip(), -1000
        
        if config.Has("shortActions")
            ExecuteActions(config["shortActions"])
    }
    PressCount := 0 ; 重置
}

ExecuteActions(actions) {
    if !IsObject(actions) || actions.Length = 0
        return

    for action in actions {
        if !action.Has("type") || !action.Has("command")
            continue

        type := action["type"]
        cmd  := action["command"]
        
        try {
            switch type {
                case "run":   Run(cmd)
                case "url":   Run(cmd)
                case "shell": Run(A_ComSpec ' /c "' cmd '"')
                case "cmd":   Run(A_ComSpec ' /k "' cmd '"')
            }
        } catch as e {
            MsgBox("执行失败: " cmd "`n原因: " e.Message)
        }
    }
}

; ==================== 3. 配置管理与 GUI ====================

LoadConfigSafe() {
    global config
    try {
        if FileExist(ConfigFile) {
            fileContent := FileRead(ConfigFile, "UTF-8")
            config := SimpleJSON.Load(fileContent)
        }
    }
    if !IsObject(config) || config.Count == 0
        config := defaultConfig.Clone()
}

SaveConfig(ctrl, *) {
    guiObj := ctrl.Gui
    saved := guiObj.Submit(false)
    
    config["shortPressTime"] := Number(saved.ShortTime)
    config["hideTray"] := saved.HideTray == 1
    config["autoStart"] := saved.AutoStart == 1
    
    try {
        if FileExist(ConfigFile)
            FileDelete(ConfigFile)
        FileAppend(SimpleJSON.Dump(config), ConfigFile, "UTF-8")
        MsgBox("✅ 配置已保存！", "成功")
    } catch as e {
        MsgBox("❌ 保存失败: " e.Message)
    }
    
    A_IconHidden := config["hideTray"]
    SetAutoStart(config["autoStart"])
    guiObj.Destroy()
}

ShowConfig() {
    global guiConfig
    if IsSet(guiConfig) && guiConfig {
        guiConfig.Show()
        return
    }

    guiConfig := Gui("+Resize +MinSize500x400", "MSI 按键配置")
    guiConfig.OnEvent("Close", (*) => guiConfig.Destroy())
    
    tab := guiConfig.AddTab3("w500 h400", ["常规设置", "单击动作(原短按)", "双击动作(原长按)"])
    
    tab.UseTab(1)
    guiConfig.AddText("x20 y40", "双击判定间隔 (秒):`n建议 0.25 - 0.4")
    valTime := config.Has("shortPressTime") ? config["shortPressTime"] : 0.3
    guiConfig.AddEdit("x160 y45 w80 vShortTime", valTime)
    
    chkHide := (config.Has("hideTray") && config["hideTray"]) ? "Checked" : ""
    chkAuto := (config.Has("autoStart") && config["autoStart"]) ? "Checked" : ""
    guiConfig.AddCheckbox("x20 y100 vHideTray " chkHide, "隐藏托盘图标")
    guiConfig.AddCheckbox("x20 y130 vAutoStart " chkAuto, "开机自启")

    tab.UseTab(2)
    shortLV := guiConfig.AddListView("x20 y40 w460 h280 vShortLV +Grid +LV0x4000", ["类型", "指令/路径"])
    if config.Has("shortActions")
        UpdateListView(shortLV, config["shortActions"])
    AddActionButtons(guiConfig, shortLV, config["shortActions"])

    tab.UseTab(3)
    longLV := guiConfig.AddListView("x20 y40 w460 h280 vLongLV +Grid +LV0x4000", ["类型", "指令/路径"])
    if config.Has("longActions")
        UpdateListView(longLV, config["longActions"])
    AddActionButtons(guiConfig, longLV, config["longActions"])
    
    tab.UseTab()
    guiConfig.AddButton("x380 y360 w100 h30 Default", "保存配置").OnEvent("Click", SaveConfig)
    guiConfig.Show()
}

AddActionButtons(guiObj, lvObj, dataList) {
    yPos := 330
    guiObj.AddButton("x20 y" yPos " w80", "添加").OnEvent("Click", (*) => EditActionWindow(guiObj, lvObj, dataList, 0))
    guiObj.AddButton("x110 y" yPos " w80", "编辑").OnEvent("Click", (*) => EditActionWindow(guiObj, lvObj, dataList, 1))
    guiObj.AddButton("x200 y" yPos " w80", "删除").OnEvent("Click", (*) => DeleteAction(lvObj, dataList))
}

UpdateListView(lv, dataList) {
    lv.Delete()
    for item in dataList
        lv.Add(, item.Has("type")?item["type"]:"", item.Has("command")?item["command"]:"")
    lv.ModifyCol(1, 80)
    lv.ModifyCol(2, 350)
}

EditActionWindow(parent, lv, dataList, mode) {
    row := (mode == 1) ? lv.GetNext() : 0
    if (mode == 1 && row == 0)
        return MsgBox("请先选中一行")

    sub := Gui("+Owner" parent.Hwnd, mode ? "编辑" : "添加")
    sub.AddText("x10 y20", "类型:")
    ddl := sub.AddDropDownList("x60 y15 w100 vType Choose1", ["run", "url", "shell", "cmd"])
    sub.AddText("x10 y60", "命令:")
    cmdBox := sub.AddEdit("x60 y58 w250 vCommand")
    
    if (mode == 1) {
        try ddl.Text := dataList[row]["type"]
        try cmdBox.Text := dataList[row]["command"]
    }
    
    sub.AddButton("x100 y100 w80 Default", "确定").OnEvent("Click", SubmitInternal)
    sub.Show()

    SubmitInternal(*) {
        res := sub.Submit()
        if res.Command == ""
            return MsgBox("指令不能为空")
            
        newItem := Map("type", res.Type, "command", res.Command)
        if (mode == 1)
            dataList[row] := newItem
        else
            dataList.Push(newItem)
        UpdateListView(lv, dataList)
        sub.Destroy()
    }
}

DeleteAction(lv, dataList) {
    row := lv.GetNext()
    if row > 0 {
        dataList.RemoveAt(row)
        UpdateListView(lv, dataList)
    }
}

SetAutoStart(enable) {
    key := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
    try {
        if enable
            RegWrite('"' A_ScriptFullPath '"', "REG_SZ", key, "MSI_Button_Tool")
        else
            RegDelete(key, "MSI_Button_Tool")
    }
}

; ==================== 4. JSON 处理类 ====================
class SimpleJSON {
    static Dump(obj) {
        if IsObject(obj) {
            if Type(obj) = "Array" {
                s := ""
                for v in obj
                    s .= "," . this.Dump(v)
                return "[" . SubStr(s, 2) . "]"
            } else if Type(obj) = "Map" {
                s := ""
                for k, v in obj
                    s .= "," . '"' . k . '":' . this.Dump(v)
                return "{" . SubStr(s, 2) . "}"
            }
        }
        val := String(obj)
        val := StrReplace(val, "\", "\\")
        val := StrReplace(val, '"', '\"')
        return '"' . val . '"'
    }

    static Load(str) {
        s := StrReplace(str, "`n", "")
        s := StrReplace(s, "`r", "")
        return this.ParseValue(s)
    }

    static ParseValue(s) {
        s := Trim(s, " `t")
        if (s == "")
            return ""
        char := SubStr(s, 1, 1)
        if (char == "{") {
            return this.ParseMap(s)
        } else if (char == "[") {
            return this.ParseArray(s)
        } else if (char == '"') {
            if RegExMatch(s, '^"(.*?)(?<!\\)"', &m)
                return StrReplace(m[1], '\\', '\')
        } else {
            if RegExMatch(s, "^[\d\.]+", &m)
                return Number(m[0])
            if (SubStr(s, 1, 4) = "true")
                return 1
            if (SubStr(s, 1, 5) = "false")
                return 0
        }
        return ""
    }

    static ParseMap(str) {
        obj := Map()
        if RegExMatch(str, '"shortPressTime"\s*:\s*([\d\.]+)', &m)
            obj["shortPressTime"] := Number(m[1])
        obj["hideTray"] := (InStr(str, '"hideTray":true') || InStr(str, '"hideTray":1'))
        obj["autoStart"] := (InStr(str, '"autoStart":true') || InStr(str, '"autoStart":1'))
        obj["shortActions"] := this.ParseActionArray(str, "shortActions")
        obj["longActions"]  := this.ParseActionArray(str, "longActions")
        return obj
    }

    static ParseActionArray(fullStr, keyName) {
        res := Array()
        if RegExMatch(fullStr, '"' keyName '"\s*:\s*\[(.*?)\]', &mArr) {
            content := mArr[1]
            p := 1
            while (pos := InStr(content, "{", , p)) {
                endPos := InStr(content, "}", , pos)
                if !endPos 
                    break
                block := SubStr(content, pos, endPos - pos + 1)
                item := Map()
                if RegExMatch(block, '"type"\s*:\s*"(.*?)"', &mt)
                    item["type"] := mt[1]
                if RegExMatch(block, '"command"\s*:\s*"(.*?)"', &mc)
                    item["command"] := StrReplace(mc[1], '\\', '\')
                if item.Count > 0
                    res.Push(item)
                p := endPos + 1
            }
        }
        return res
    }
}
