#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook
Persistent
InstallKeybdHook

; Load the library you provided (Must be in the same folder)
#Include "JSON.ahk" 

ConfigFile := A_ScriptDir "\config.json"
global config := []
global activeHotkeys := Map()
global keyState := Map()
global guiMain := unset

LoadConfigSafe()
ApplyHotkeys()

A_TrayMenu.Delete()
A_TrayMenu.Add("Settings", (*) => ShowMainGui())
A_TrayMenu.Add("Restart", (*) => Reload())
A_TrayMenu.Add("Exit", (*) => ExitApp())
A_TrayMenu.Default := "Settings"
A_TrayMenu.ClickCount := 2

; ==================== Logic Core ====================

ApplyHotkeys() {
    global config, activeHotkeys
    
    ; Clear old hotkeys
    for keyName in activeHotkeys {
        try Hotkey(keyName, "Off")
    }
    activeHotkeys := Map()
    
    ; Register new hotkeys
    for rule in config {
        if (rule.Has("key") && rule["key"] != "") {
            keyName := rule["key"]
            if (!activeHotkeys.Has(keyName)) {
                try {
                    Hotkey(keyName, MasterHotkeyHandler.Bind(keyName), "On")
                    activeHotkeys[keyName] := true
                }
            }
        }
    }
}

MasterHotkeyHandler(thisKey, *) {
    global keyState
    if !keyState.Has(thisKey)
        keyState[thisKey] := {Count: 0}
    
    state := keyState[thisKey]
    state.Count += 1
    
    ; 1. Get Timeout (Safe Number)
    timeout := GetTimeoutForKey(thisKey)
    
    ; 2. Calculate Delay (Negative = Run Once)
    ; We explicitly cast to Integer to prevent "Type Mismatch" errors
    delay := -Integer(timeout * 1000)
    
    SetTimer(ProcessKeyParams.Bind(thisKey), delay)
}

ProcessKeyParams(keyName) {
    global keyState, config
    if !keyState.Has(keyName)
        return
    
    count := keyState[keyName].Count
    keyState[keyName].Count := 0
    
    for rule in config {
        ; Strict type comparison: Ensure both are Numbers
        if (rule["key"] = keyName && Integer(rule["count"]) = count) {
            ExecuteRule(rule)
            return
        }
    }
}

GetTimeoutForKey(keyName) {
    global config
    maxTime := 0.3
    for rule in config {
        if (rule["key"] = keyName) {
            ; Ensure we read a valid number, default to 0.3
            val := rule.Has("timeout") ? rule["timeout"] : 0.3
            t := IsNumber(val) ? val : 0.3
            if (t > maxTime)
                maxTime := t
        }
    }
    return maxTime
}

ExecuteRule(rule) {
    if !rule.Has("type") || !rule.Has("command")
        return
    cmd := rule["command"]
    try {
        switch rule["type"] {
            case "run":   Run(cmd)
            case "url":   Run(cmd)
            case "shell": Run(A_ComSpec ' /c "' cmd '"')
            case "cmd":   Run(A_ComSpec ' /k "' cmd '"')
        }
        ToolTip("⚡ Executed: " cmd)
        SetTimer(() => ToolTip(), -1500)
    } catch as e {
        MsgBox("Execution Failed: " cmd "`nError: " e.Message)
    }
}

; ==================== GUI Section ====================

ShowMainGui() {
    global guiMain, lvRules
    if IsSet(guiMain) && guiMain {
        guiMain.Show()
        return
    }
    
    guiMain := Gui("+Resize +MinSize660x460", "Hotkey Manager")
    guiMain.OnEvent("Close", (*) => (guiMain.Destroy(), guiMain := unset))
    guiMain.SetFont("s10", "Segoe UI")
    
    guiMain.AddButton("x20 y15 w100 h30", "➕ Add Rule").OnEvent("Click", (*) => EditRuleWindow(0))
    guiMain.AddButton("x130 y15 w100 h30", "✏️ Edit").OnEvent("Click", (*) => EditRuleWindow(1))
    guiMain.AddButton("x240 y15 w100 h30", "❌ Delete").OnEvent("Click", DeleteRule)
    guiMain.AddButton("x+50 y15 w140 h30", "💾 Save & Apply").OnEvent("Click", SaveAndApply)
    
    lvRules := guiMain.AddListView("x20 y60 w620 h340 +Grid +LV0x4000", ["Key", "Clicks", "Type", "Command", "Timeout (s)"])
    RefreshList()
    
    guiMain.Show()
}

RefreshList() {
    global lvRules, config
    lvRules.Delete()
    for i, rule in config {
        k := rule.Has("key") ? rule["key"] : "?"
        c := rule.Has("count") ? rule["count"] : "1"
        t := rule.Has("type") ? rule["type"] : "-"
        cmd := rule.Has("command") ? rule["command"] : "-"
        
        ; Display timeout nicely formatted
        rawT := rule.Has("timeout") ? rule["timeout"] : 0.3
        tm := IsNumber(rawT) ? Format("{:.1f}", rawT) : "0.3"
        
        lvRules.Add(, k, c, t, cmd, tm)
    }
    lvRules.ModifyCol(1, 120)
    lvRules.ModifyCol(2, 80)
    lvRules.ModifyCol(3, 80)
    lvRules.ModifyCol(4, 220)
    lvRules.ModifyCol(5, 100)
}

EditRuleWindow(mode) {
    global lvRules, config
    row := (mode == 1) ? lvRules.GetNext() : 0
    if (mode == 1 && row == 0) {
        MsgBox("Please select a row first")
        return
    }
    
    sub := Gui("+Owner" guiMain.Hwnd, mode ? "Edit Rule" : "Add Rule")
    sub.SetFont("s10", "Segoe UI")
    
    sub.AddGroupBox("x10 y10 w400 h90", "Trigger")
    sub.AddText("x25 y35", "Key Code:")
    edtKey := sub.AddEdit("x100 y32 w180 vKey ReadOnly")
    sub.AddButton("x290 y30 w100", "Capture").OnEvent("Click", (btn, *) => CaptureKeyUltimate(btn, edtKey))
    
    sub.AddGroupBox("x10 y110 w400 h90", "Conditions")
    sub.AddText("x25 y135", "Clicks:")
    edtCount := sub.AddEdit("x110 y132 w60 vCount Number", "1")
    sub.AddUpDown("Range1-10", 1)
    sub.AddText("x200 y135", "Timeout (sec):")
    edtTimeout := sub.AddEdit("x300 y132 w80 vTimeout", "0.3")
    
    sub.AddGroupBox("x10 y210 w400 h110", "Action")
    sub.AddText("x25 y235", "Type:")
    ddlType := sub.AddDropDownList("x80 y232 w200 vType Choose1", ["run", "url", "cmd", "shell"])
    sub.AddText("x25 y275", "Command:")
    sub.AddEdit("x100 y272 w280 vCommand")
    
    if (mode == 1) {
        rule := config[row]
        edtKey.Value := rule["key"]
        edtCount.Value := rule["count"]
        
        safeT := (rule.Has("timeout") && IsNumber(rule["timeout"])) ? rule["timeout"] : 0.3
        edtTimeout.Value := Format("{:.1f}", safeT)
        ddlType.Text := rule["type"]
        sub["Command"].Value := rule["command"]
    }
    
    sub.AddButton("x120 y340 w100 h35 Default", "OK").OnEvent("Click", Commit)
    sub.AddButton("x240 y340 w100 h35", "Cancel").OnEvent("Click", (*) => sub.Destroy())
    sub.Show("w430 h390")
    
    Commit(*) {
        res := sub.Submit()
        if (res.Key == "") {
            MsgBox("Please capture a key first.")
            return
        }
        if (res.Command == "") {
            MsgBox("Command cannot be empty.")
            return
        }
        
        ; [CRITICAL] Convert GUI String inputs to Real Numbers
        ; This ensures JSON.stringify saves them as numbers (0.3), not strings ("0.3")
        finalTimeout := 0.3
        if IsNumber(res.Timeout)
            finalTimeout := Float(res.Timeout)
            
        finalCount := Integer(res.Count)

        newRule := Map(
            "key", res.Key,
            "count", finalCount,
            "timeout", finalTimeout,
            "type", res.Type,
            "command", res.Command
        )
        if (mode == 1)
            config[row] := newRule
        else
            config.Push(newRule)
        
        RefreshList()
        sub.Destroy()
        ApplyHotkeys()
    }
}

CaptureKeyUltimate(btnCtrl, editCtrl) {
    btnCtrl.Text := "Press any key..."
    btnCtrl.Enabled := false
    editCtrl.Value := "Listening..."
    
    ih := InputHook("V")
    ih.KeyOpt("{All}", "N") ; Notify on any key
    
    capturedVK := 0
    capturedSC := 0
    
    ih.OnKeyDown := (hook, vk, sc) => (
        capturedVK := vk,
        capturedSC := sc,
        hook.Stop()
    )
    
    ih.Start()
    reason := ih.Wait(5) ; 5 sec timeout
    
    try {
        if (reason == "Timeout") {
            editCtrl.Value := "Timeout"
        } else if (capturedSC == 0 && capturedVK == 0) {
            editCtrl.Value := "Error"
        } else {
            finalKey := GetBestAhkKeyName(capturedVK, capturedSC)
            editCtrl.Value := finalKey
        }
        btnCtrl.Text := "Capture"
        btnCtrl.Enabled := true
    } catch {
        ; Handle GUI closed during capture
    }
}

GetBestAhkKeyName(vk, sc) {
    if (sc == 0 && vk == 0)
        return "Error"
    
    full := Format("vk{:02X}sc{:03X}", vk, sc)
    name := GetKeyName(full)
    
    ; If standard name found (A, B, F1), use it
    if (name != "" && !RegExMatch(name, "^(?i)(vk|sc)"))
        return name
    
    ; Special handling for keys that map to "Paste" or Volume controls
    fake := Map("Paste",1, "Launch_Mail",1, "Launch_Media",1, "Volume_Mute",1, "Volume_Down",1, "Volume_Up",1, "Media_Play_Pause",1)
    if (fake.Has(name))
        return Format("SC{:03X}", sc)
    
    if (sc > 0)
        return Format("SC{:03X}", sc)
    
    return Format("vk{:02X}", vk)
}

DeleteRule(*) {
    global lvRules, config
    row := lvRules.GetNext()
    if (row > 0) {
        config.RemoveAt(row)
        RefreshList()
        ApplyHotkeys()
    } else {
        MsgBox("Select a row to delete.")
    }
}

SaveAndApply(*) {
    global config
    try {
        ; Use the library to stringify with indentation
        jsonStr := JSON.stringify(config, , "    ")
        
        if FileExist(ConfigFile)
             FileDelete(ConfigFile)
        FileAppend(jsonStr, ConfigFile, "UTF-8")
        MsgBox("Saved successfully!", "Success", 64)
    } catch as e {
        MsgBox("Save Failed:`n" e.Message)
        return
    }
    ApplyHotkeys()
}

LoadConfigSafe() {
    global config
    config := []
    try {
        if FileExist(ConfigFile) {
            content := FileRead(ConfigFile, "UTF-8")
            ; Parse JSON string into AHK Objects/Maps
            loaded := JSON.parse(content)
            
            if (Type(loaded) = "Array") {
                for rule in loaded {
                    ; Validate and reconstruct map to ensure clean data types
                    cleaned := Map()
                    cleaned["key"] := rule.Has("key") ? rule["key"] : ""
                    cleaned["count"] := rule.Has("count") ? Integer(rule["count"]) : 1
                    
                    t := 0.3
                    if rule.Has("timeout") && IsNumber(rule["timeout"])
                        t := Float(rule["timeout"])
                    cleaned["timeout"] := t
                    
                    cleaned["type"] := rule.Has("type") ? rule["type"] : "run"
                    cleaned["command"] := rule.Has("command") ? rule["command"] : ""
                    config.Push(cleaned)
                }
            }
        }
    } catch {
        config := []
    }
}
