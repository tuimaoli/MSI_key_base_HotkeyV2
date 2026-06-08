#Requires AutoHotkey v2.0

class JSON {
    static Load(str) {
        if str == ""
            return []
        
        try {
            return JSON._Parse(str)
        } catch as e {
            throw Error("Invalid JSON: " e.Message)
        }
    }

    static Dump(obj, indent := "") {
        return JSON._Stringify(obj, indent)
    }

    static _Parse(str) {
        str := Trim(str)
        if str == ""
            return ""
        
        index := 1
        return ParseValue(str, &index)
        
        ParseValue(jsonStr, &idx) {
            SkipWhitespace(jsonStr, &idx)
            if idx > StrLen(jsonStr)
                return ""
                
            char := SubStr(jsonStr, idx, 1)
            
            if char == "{" {
                idx++
                res := Map()
                SkipWhitespace(jsonStr, &idx)
                if SubStr(jsonStr, idx, 1) == "}" {
                    idx++
                    return res
                }
                Loop {
                    SkipWhitespace(jsonStr, &idx)
                    key := ParseString(jsonStr, &idx)
                    SkipWhitespace(jsonStr, &idx)
                    if SubStr(jsonStr, idx, 1) != ":"
                        throw Error("Expected ':' at " idx)
                    idx++
                    val := ParseValue(jsonStr, &idx)
                    res[key] := val
                    SkipWhitespace(jsonStr, &idx)
                    nextChar := SubStr(jsonStr, idx, 1)
                    idx++
                    if nextChar == "}"
                        break
                    if nextChar != ","
                        throw Error("Expected ',' or '}' at " idx)
                }
                return res
            } else if char == "[" {
                idx++
                res := []
                SkipWhitespace(jsonStr, &idx)
                if SubStr(jsonStr, idx, 1) == "]" {
                    idx++
                    return res
                }
                Loop {
                    res.Push(ParseValue(jsonStr, &idx))
                    SkipWhitespace(jsonStr, &idx)
                    nextChar := SubStr(jsonStr, idx, 1)
                    idx++
                    if nextChar == "]"
                        break
                    if nextChar != ","
                        throw Error("Expected ',' or ']' at " idx)
                }
                return res
            } else if char == '"' {
                return ParseString(jsonStr, &idx)
            } else {
                ; Number, true, false, null
                start := idx
                while (idx <= StrLen(jsonStr) && InStr("0123456789.+-eElnrutfs", SubStr(jsonStr, idx, 1)))
                    idx++
                token := SubStr(jsonStr, start, idx - start)
                if token == "true"
                    return true
                if token == "false"
                    return false
                if token == "null"
                    return ""
                if IsNumber(token)
                    return Number(token)
                return token
            }
        }
        
        ParseString(jsonStr, &idx) {
            if SubStr(jsonStr, idx, 1) != '"'
                throw Error("Expected string at " idx)
            idx++
            
            res := ""
            while (idx <= StrLen(jsonStr)) {
                char := SubStr(jsonStr, idx, 1)
                
                if char == '"' {
                    idx++
                    return res
                }
                
                if char == "\" {
                    idx++
                    nextChar := SubStr(jsonStr, idx, 1)
                    switch nextChar {
                        case '"': res .= '"'
                        case '\': res .= "\"
                        case '/': res .= "/"
                        case 'b': res .= "`b"
                        case 'f': res .= "`f"
                        case 'n': res .= "`n"
                        case 'r': res .= "`r"
                        case 't': res .= "`t"
                        case 'u': 
                            idx++
                            hex := SubStr(jsonStr, idx, 4)
                            try {
                                res .= Chr("0x" hex)
                            }
                            idx += 3
                        default: res .= nextChar
                    }
                } else {
                    res .= char
                }
                idx++
            }
            throw Error("Unclosed string")
        }
        
        SkipWhitespace(jsonStr, &idx) {
            while (idx <= StrLen(jsonStr) && InStr(" `t`r`n", SubStr(jsonStr, idx, 1)))
                idx++
        }
    }

    static _Stringify(obj, indent := "") {
        if IsObject(obj) {
            isMap := obj is Map
            isArray := obj is Array
            if !isMap && !isArray
                return "{}"
            
            out := ""
            if isArray {
                out .= "["
                for i, v in obj {
                    out .= (i > 1 ? "," : "") 
                    out .= (indent ? "`n" indent : "")
                    out .= JSON._Stringify(v, indent ? indent "    " : "")
                }
                out .= (indent ? "`n" SubStr(indent, 1, StrLen(indent)-4) : "")
                out .= "]"
            } else {
                out .= "{"
                first := true
                for k, v in obj {
                    if !first
                        out .= ","
                    first := false
                    out .= (indent ? "`n" indent : "")
                    out .= '"' k '":' . (indent ? " " : "") . JSON._Stringify(v, indent ? indent "    " : "")
                }
                out .= (indent ? "`n" SubStr(indent, 1, StrLen(indent)-4) : "")
                out .= "}"
            }
            return out
        } else if IsNumber(obj) {
            return obj
        } else {
            ; String escaping
            s := String(obj)
            s := StrReplace(s, "\", "\\")
            s := StrReplace(s, '"', '\"')
            s := StrReplace(s, "`n", "\n")
            s := StrReplace(s, "`r", "\r")
            s := StrReplace(s, "`t", "\t")
            return '"' s '"'
        }
    }
}