.pragma library

// Customizable shortcuts: one list feeds the menus and Settings → Shortcuts. "Ctrl" is Command on macOS.
// Linux and Windows defaults avoid Ctrl+Alt+arrows (desktops use them to switch workspaces) and
// Ctrl+Alt+\ (AltGr on many keyboards).
// Settings › Shortcuts shows them in these sections, in this order.
const groups = ["Search and places", "Tabs", "Splits", "Panels", "Reading", "Notes and AI"]
const actions = [
    {id: "search", group: "Search and places", name: "Search", mac: "Ctrl+K", other: "Ctrl+K"},
    {id: "commands", group: "Search and places", name: "Command Palette", mac: "Ctrl+Shift+P", other: "Ctrl+Shift+P"},
    {id: "home", group: "Search and places", name: "Home", mac: "Ctrl+Shift+H", other: "Ctrl+Shift+H"},
    {id: "library", group: "Search and places", name: "Library", mac: "Ctrl+Shift+L", other: "Ctrl+Shift+L"},
    {id: "openWeb", group: "Search and places", name: "Open Web Page", mac: "Ctrl+L", other: "Ctrl+L"},
    {id: "newTab", group: "Tabs", name: "New Tab", mac: "Ctrl+T", other: "Ctrl+T"},
    {id: "closeTab", group: "Tabs", name: "Close Tab", mac: "Ctrl+W", other: "Ctrl+W"},
    {id: "reopenTab", group: "Tabs", name: "Reopen Closed Tab", mac: "Ctrl+Shift+T", other: "Ctrl+Shift+T"},
    {id: "nextTab", group: "Tabs", name: "Next Tab", mac: "Ctrl+Alt+Right", other: "Ctrl+PgDown"},
    {id: "previousTab", group: "Tabs", name: "Previous Tab", mac: "Ctrl+Alt+Left", other: "Ctrl+PgUp"},
    {id: "splitRight", group: "Splits", name: "Duplicate to Right Split", mac: "Ctrl+\\", other: "Ctrl+\\"},
    {id: "splitDown", group: "Splits", name: "Duplicate to Bottom Split", mac: "Ctrl+Alt+\\", other: "Ctrl+Shift+\\"},
    {id: "moveRight", group: "Splits", name: "Move Tab to Right Split", mac: "Ctrl+Shift+Alt+Right", other: "Ctrl+Shift+Alt+."},
    {id: "moveDown", group: "Splits", name: "Move Tab to Bottom Split", mac: "Ctrl+Shift+Alt+Down", other: "Ctrl+Shift+Alt+,"},
    {id: "nextSplit", group: "Splits", name: "Focus Next Split", mac: "Ctrl+Alt+Down", other: "Ctrl+Alt+."},
    {id: "previousSplit", group: "Splits", name: "Focus Previous Split", mac: "Ctrl+Alt+Up", other: "Ctrl+Alt+,"},
    {id: "tabsPanel", group: "Panels", name: "Vertical Tabs", mac: "Ctrl+Shift+B", other: "Ctrl+Shift+B"},
    {id: "filesPanel", group: "Panels", name: "Library Panel", mac: "Ctrl+Shift+E", other: "Ctrl+Shift+E"},
    {id: "documentPanel", group: "Panels", name: "Document Panel", mac: "Ctrl+Shift+O", other: "Ctrl+Shift+O"},
    {id: "annotations", group: "Panels", name: "Annotations", mac: "Ctrl+Shift+M", other: "Ctrl+Shift+M"},
    {id: "aiPanel", group: "Panels", name: "AI Chat", mac: "Ctrl+Shift+I", other: "Ctrl+Shift+I"},
    {id: "previousPage", group: "Reading", name: "Previous Page", mac: "Ctrl+[", other: "Ctrl+["},
    {id: "nextPage", group: "Reading", name: "Next Page", mac: "Ctrl+]", other: "Ctrl+]"},
    {id: "jumpBack", group: "Reading", name: "Back to Previous Spot", mac: "Alt+Left", other: "Alt+Left"},
    {id: "jumpForward", group: "Reading", name: "Forward to Next Spot", mac: "Alt+Right", other: "Alt+Right"},
    {id: "fitWidth", group: "Reading", name: "Fit Width", mac: "Ctrl+0", other: "Ctrl+0"},
    {id: "fitPage", group: "Reading", name: "Fit Page", mac: "Ctrl+Alt+0", other: "Ctrl+Alt+0"},
    {id: "highlight", group: "Reading", name: "Highlight Selection", mac: "Ctrl+Meta+H", other: "Ctrl+Alt+H"},
    {id: "comment", group: "Reading", name: "Comment", mac: "Ctrl+Meta+M", other: "Ctrl+Alt+M"},
    {id: "markRegion", group: "Reading", name: "Mark Region", mac: "Ctrl+Shift+C", other: "Ctrl+Shift+C"},
    {id: "darkPages", group: "Reading", name: "Dark Pages", mac: "Ctrl+Shift+D", other: "Ctrl+Shift+D"},
    {id: "newNote", group: "Notes and AI", name: "New Note", mac: "Ctrl+Shift+N", other: "Ctrl+Shift+N"},
    {id: "askAi", group: "Notes and AI", name: "Ask AI (the selection, or the paper)", mac: "Ctrl+Shift+A", other: "Ctrl+Shift+A"}
]

function defaultKeys(id, os) {
    const action = actions.find(function(a) { return a.id === id })
    return action ? (os === "osx" ? action.mac : action.other) : ""
}
// The shortcut in effect: the reader's choice ("" disables it), or the default.
function keys(id, overrides, os) {
    return overrides && Object.prototype.hasOwnProperty.call(overrides, id) ? overrides[id] : defaultKeys(id, os)
}
function parse(json) {
    try { const value = JSON.parse(json || "{}"); return value && typeof value === "object" ? value : {} }
    catch (e) { return {} }
}
// Actions that share a shortcut, as {keys: [names]} (only for keys used more than once).
// Ctrl+1…8 select a tab and Ctrl+9 the last one (as in browsers); they are fixed, so nothing else may take them.
function conflicts(overrides, os) {
    const used = {}
    for (let n = 1; n <= 9; ++n) used["Ctrl+" + n] = [n === 9 ? "Last Tab" : "Tab " + n]
    actions.forEach(function(a) {
        const k = keys(a.id, overrides, os)
        if (k.length) used[k] = (used[k] || []).concat([a.name])
    })
    const result = {}
    Object.keys(used).forEach(function(k) { if (used[k].length > 1) result[k] = used[k] })
    return result
}
// A key press as a shortcut text ("Ctrl+Shift+K"); empty for modifier-only presses.
function fromEvent(key, modifiers, text) {
    const names = {}
    names[Qt.Key_Left] = "Left"; names[Qt.Key_Right] = "Right"; names[Qt.Key_Up] = "Up"; names[Qt.Key_Down] = "Down"
    names[Qt.Key_PageUp] = "PgUp"; names[Qt.Key_PageDown] = "PgDown"; names[Qt.Key_Home] = "Home"; names[Qt.Key_End] = "End"
    names[Qt.Key_Tab] = "Tab"; names[Qt.Key_Space] = "Space"; names[Qt.Key_Return] = "Return"; names[Qt.Key_Enter] = "Enter"
    names[Qt.Key_Delete] = "Del"; names[Qt.Key_Backslash] = "\\"; names[Qt.Key_BracketLeft] = "["; names[Qt.Key_BracketRight] = "]"
    names[Qt.Key_Comma] = ","; names[Qt.Key_Period] = "."; names[Qt.Key_Slash] = "/"; names[Qt.Key_Semicolon] = ";"
    names[Qt.Key_Minus] = "-"; names[Qt.Key_Equal] = "="; names[Qt.Key_Apostrophe] = "'"
    if ([Qt.Key_Control, Qt.Key_Shift, Qt.Key_Alt, Qt.Key_Meta, Qt.Key_AltGr].indexOf(key) >= 0) return ""
    let name = names[key]
    if (!name && key >= Qt.Key_F1 && key <= Qt.Key_F12) name = "F" + (key - Qt.Key_F1 + 1)
    if (!name && ((key >= Qt.Key_A && key <= Qt.Key_Z) || (key >= Qt.Key_0 && key <= Qt.Key_9))) name = String.fromCharCode(key)
    if (!name) return ""
    const parts = []
    if (modifiers & Qt.ControlModifier) parts.push("Ctrl")
    if (modifiers & Qt.MetaModifier) parts.push("Meta")
    if (modifiers & Qt.ShiftModifier) parts.push("Shift")
    if (modifiers & Qt.AltModifier) parts.push("Alt")
    // A shortcut needs a modifier, except function keys.
    if (!parts.length && !/^F\d+$/.test(name)) return ""
    return parts.concat([name]).join("+")
}
