#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook
Persistent
InstallKeybdHook

; ==================== 1. Initialization & Configuration ====================
ConfigFile := A_ScriptDir "\config.json"

; Default Configuration
defaultConfig := Map(
    "shortPressTime", 0.30, 
    "shortActions", Array(Map("type", "run", "command", "notepad.exe")),
    "longActions",  Array(Map("type", "run", "command", "calc.exe")),
    "hideTray", false,
    "autoStart", false
)

global config := Map()
global PressCount := 0
global guiConfig := unset

LoadConfigSafe()

; Tray Menu Setup
A_TrayMenu.Delete()
A_TrayMenu.Add("Settings", (*) => ShowConfig())
A_TrayMenu.Add("Restart", (*) => Reload())
A_TrayMenu.Add("Exit", (*) => ExitApp())
A_TrayMenu.Default := "Settings"
A_TrayMenu.ClickCount := 2

if config.Has("hideTray") && config["hideTray"]
    A_IconHidden := true

SetAutoStart(config.Has("autoStart") ? config["autoStart"] : false)

; ==================== 2. Core Hotkey Logic ====================

SC10A:: {
    global PressCount
    PressCount += 1
    
    ; Use default of 0.3 if config is missing
    waitTime := config.Has("shortPressTime") ? config["shortPressTime"] : 0.3
    
    if (PressCount == 1) {
        ; Start timer. Negative value = run once.
        SetTimer(CheckClickCount, -Abs(waitTime * 1000))
    } else if (PressCount >= 2) {
        SetTimer(CheckClickCount, 0) ; Cancel single press timer
        PressCount := 0
        
        ToolTip("⚡ Double Press Detected")
        SetTimer () => ToolTip(), -1000
        
        if config.Has("longActions")
            ExecuteActions(config["longActions"])
    }
}

CheckClickCount() {
    global PressCount
    if (PressCount == 1) {
        ToolTip("⚡ Single Press Detected")
        SetTimer () => ToolTip(), -1000
        
        if config.Has("shortActions")
            ExecuteActions(config["shortActions"])
    }
    PressCount := 0 
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
            MsgBox("Action Failed: " cmd "`nReason: " e.Message)
        }
    }
}

; ==================== 3. Configuration Management & GUI ====================

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
    global guiConfig
    guiObj := ctrl.Gui
    
    ; Read Values directly from controls
    rawTime := guiObj["ShortTime"].Value
    if !IsNumber(rawTime) {
        MsgBox("Error: Time must be a number (e.g. 0.3)")
        return
    }

    config["shortPressTime"] := Number(rawTime)
    config["hideTray"] := guiObj["HideTray"].Value
    config["autoStart"] := guiObj["AutoStart"].Value
    
    ; Atomic Save
    tmpFile := ConfigFile ".tmp"
    
    try {
        if FileExist(tmpFile)
            FileDelete(tmpFile)
            
        jsonStr := SimpleJSON.Dump(config)
        FileAppend(jsonStr, tmpFile, "UTF-8")
        
        if FileExist(ConfigFile)
            FileDelete(ConfigFile)
        FileMove(tmpFile, ConfigFile)
        
        MsgBox("✅ Configuration Saved!", "Success")
    } catch as e {
        MsgBox("❌ Save Failed: " e.Message)
    }
    
    A_IconHidden := config["hideTray"]
    SetAutoStart(config["autoStart"])
    
    guiObj.Destroy()
    guiConfig := unset 
}

ShowConfig() {
    global guiConfig
    if IsSet(guiConfig) && guiConfig {
        guiConfig.Show()
        return
    }

    ; Create GUI
    guiConfig := Gui("+Resize +MinSize500x400", "Key Config Utility")
    guiConfig.OnEvent("Close", (*) => (guiConfig.Destroy(), guiConfig := unset))
    
    ; FIX: Reduced Tab height to 350 so it doesn't cover the Save button at y360
    tab := guiConfig.AddTab3("w500 h350", ["General", "Single Press", "Double Press"])
    
    ; --- Tab 1: General ---
    tab.UseTab(1)
    guiConfig.AddText("x20 y40", "Double Press Interval (sec):`nRecommended 0.25 - 0.4")
    
    rawVal := config.Has("shortPressTime") ? config["shortPressTime"] : 0.3
    formattedVal := Format("{:.2f}", rawVal)
    
    guiConfig.AddEdit("x200 y45 w80 vShortTime", formattedVal)
    
    chkHide := (config.Has("hideTray") && config["hideTray"]) ? 1 : 0
    chkAuto := (config.Has("autoStart") && config["autoStart"]) ? 1 : 0
    guiConfig.AddCheckbox("x20 y100 vHideTray Checked" chkHide, "Hide Tray Icon")
    guiConfig.AddCheckbox("x20 y130 vAutoStart Checked" chkAuto, "Run on Startup")

    ; --- Tab 2: Single Press ---
    tab.UseTab(2)
    shortLV := guiConfig.AddListView("x20 y40 w460 h280 vShortLV +Grid +LV0x4000", ["Type", "Command/Path"])
    if config.Has("shortActions")
        UpdateListView(shortLV, config["shortActions"])
    AddActionButtons(guiConfig, shortLV, config["shortActions"])

    ; --- Tab 3: Double Press ---
    tab.UseTab(3)
    longLV := guiConfig.AddListView("x20 y40 w460 h280 vLongLV +Grid +LV0x4000", ["Type", "Command/Path"])
    if config.Has("longActions")
        UpdateListView(longLV, config["longActions"])
    AddActionButtons(guiConfig, longLV, config["longActions"])
    
    tab.UseTab() ; End Tabs
    
    ; FIX: This button is at y360. Since Tab is h350, they no longer overlap.
    guiConfig.AddButton("x380 y360 w100 h30 Default", "Save").OnEvent("Click", SaveConfig)
    
    guiConfig.Show()
}

AddActionButtons(guiObj, lvObj, dataList) {
    yPos := 330
    guiObj.AddButton("x20 y" yPos " w80", "Add").OnEvent("Click", (*) => EditActionWindow(guiObj, lvObj, dataList, 0))
    guiObj.AddButton("x110 y" yPos " w80", "Edit").OnEvent("Click", (*) => EditActionWindow(guiObj, lvObj, dataList, 1))
    guiObj.AddButton("x200 y" yPos " w80", "Delete").OnEvent("Click", (*) => DeleteAction(lvObj, dataList))
}

UpdateListView(lv, dataList) {
    lv.Delete()
    for item in dataList
        lv.Add(, item.Has("type")?item["type"]:"", item.Has("command")?item["command"]:"")
    lv.ModifyCol(1, 80)
    lv.ModifyCol(2, "AutoHdr") 
}

EditActionWindow(parent, lv, dataList, mode) {
    row := (mode == 1) ? lv.GetNext() : 0
    if (mode == 1 && row == 0)
        return MsgBox("Please select a row first.")

    sub := Gui("+Owner" parent.Hwnd, mode ? "Edit Action" : "Add Action")
    sub.AddText("x10 y20", "Type:")
    ddl := sub.AddDropDownList("x60 y15 w100 vType Choose1", ["run", "url", "shell", "cmd"])
    sub.AddText("x10 y60", "Cmd:")
    cmdBox := sub.AddEdit("x60 y58 w250 vCommand")
    
    if (mode == 1) {
        try ddl.Text := dataList[row]["type"]
        try cmdBox.Text := dataList[row]["command"]
    }
    
    sub.AddButton("x100 y100 w80 Default", "OK").OnEvent("Click", SubmitInternal)
    sub.Show()

    SubmitInternal(*) {
        res := sub.Submit()
        if res.Command == ""
            return MsgBox("Command cannot be empty.")
            
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
            RegWrite('"' A_ScriptFullPath '"', "REG_SZ", key, "AHK_Button_Tool")
        else
            RegDelete(key, "AHK_Button_Tool")
    }
}

; ==================== 4. JSON Helper Class ====================
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
