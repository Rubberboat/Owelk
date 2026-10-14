import Owelk.Ui
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Platform.js" as Platform
import "Shortcuts.js" as Shortcuts

// Every keyboard shortcut on one sheet, the reader's own choices (Settings › Shortcuts) included. Opened
// with ?, Ctrl/⌘+/, the ? button in the status bar, Help › Keyboard Shortcuts or /shortcuts.
Popup {
    id: root
    objectName: "shortcutSheet"
    // id → keys the reader set ("" turns one off).
    property var overrides: ({})
    signal settingsRequested()
    width: Math.min(560, parent ? parent.width - 48 : 560)
    height: Math.min(680, parent ? parent.height - 80 : 680)
    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? Math.round((parent.height - height) / 2) : 0
    padding: 14
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    readonly property bool mac: Qt.platform.os === "osx"
    // A row of a customizable action, with the keys in effect.
    function action(id, name) {
        const a = Shortcuts.actions.find(function(x) { return x.id === id })
        return {name: name || a.name, keys: [Shortcuts.keys(id, overrides, Qt.platform.os)], custom: true}
    }
    function fixed(name, keys) { return {name: name, keys: keys, custom: false} }
    readonly property var groups: [
        {title: "General", rows: [
            action("search"), action("commands"),
            fixed("Keyboard Shortcuts", ["?", "Ctrl+/"]),
            fixed("Open PDF", ["Ctrl+O"]), fixed("Settings", ["Ctrl+,"]),
            action("home"), action("library"), action("openWeb")]},
        {title: "Tabs", rows: [
            action("newTab"), action("closeTab"), action("reopenTab"), action("nextTab"), action("previousTab"),
            fixed("Next / Previous Tab", ["Ctrl+Shift+]", "Ctrl+Shift+["]),
            fixed("Next or Last Used Tab (Settings › Appearance)", [mac ? "Meta+Tab" : "Ctrl+Tab"]),
            fixed("Tab 1–8 / Last Tab", ["Ctrl+1…8", "Ctrl+9"])]},
        {title: "Panels", rows: [
            action("tabsPanel"), action("filesPanel"), action("documentPanel"), action("annotations"), action("aiPanel")]},
        {title: "Reading", rows: [
            action("previousPage"), action("nextPage"),
            action("jumpBack"), action("jumpForward"),
            fixed("Find in This PDF", ["Ctrl+F"]),
            fixed("Zoom In / Out", ["Ctrl+Plus", "Ctrl+-"]),
            action("fitWidth"), action("fitPage"),
            fixed("Copy Selected Text", ["Ctrl+C"]),
            action("highlight"), action("comment"), action("markRegion"), action("darkPages"),
            fixed("Undo / Redo Annotation", ["Ctrl+Z", mac ? "Ctrl+Shift+Z" : "Ctrl+Y"]),
            fixed("Delete Selected Mark", ["Delete"]),
            fixed("Stop Drawing or Marking", ["Esc"]),
            fixed("Scroll Sideways (wide page)", ["Left", "Right"])]},
        {title: "Splits", rows: [
            action("splitRight"), action("splitDown"), action("moveRight"), action("moveDown"),
            action("nextSplit"), action("previousSplit")]},
        {title: "Notes and AI", rows: [
            action("newNote"), action("askAi"),
            fixed("Send Question", ["Return"]), fixed("New Line in a Question", ["Shift+Return"]),
            fixed("Done with a Note (saves)", ["Esc"])]}
    ]
    // Rows matching the filter, with their group's title on the first one.
    readonly property var rows: {
        const terms = filter.text.trim().toLowerCase().split(/\s+/).filter(function(t) { return t.length })
        const list = []
        groups.forEach(function(group) {
            const shown = group.rows.filter(function(row) {
                const text = (group.title + " " + row.name + " " + row.keys.map(function(k) { return k + " " + Platform.keys(k) }).join(" ")).toLowerCase()
                return terms.every(function(t) { return text.indexOf(t) >= 0 })
            })
            shown.forEach(function(row, i) { list.push(Object.assign({group: i === 0 ? group.title : ""}, row)) })
        })
        return list
    }
    onAboutToShow: filter.clear()
    onOpened: filter.forceActiveFocus()
    contentItem: ColumnLayout {
        spacing: 8
        RowLayout {
            Layout.fillWidth: true
            Label {
                Layout.fillWidth: true
                text: "Keyboard Shortcuts"
                font.pixelSize: Theme.fontBody + 2; font.weight: Font.DemiBold; color: Theme.text
            }
            IconButton { objectName: "shortcutSheetClose"; icon.name: "close"; description: "Close"; onClicked: root.close() }
        }
        TextField {
            id: filter
            objectName: "shortcutFilter"
            Layout.fillWidth: true
            implicitHeight: Theme.controlHeight + 4
            placeholderText: "Search shortcuts"
            selectByMouse: true
            Keys.onEscapePressed: root.close()
        }
        ListView {
            id: list
            objectName: "shortcutList"
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true
            model: root.rows
            ScrollBar.vertical: ScrollBar {}
            delegate: Column {
                id: entry
                required property var modelData
                required property int index
                width: ListView.view.width
                Label {
                    visible: entry.modelData.group.length > 0
                    topPadding: entry.index > 0 ? 12 : 0; bottomPadding: 4
                    text: entry.modelData.group
                    font.pixelSize: Theme.fontCaption; font.weight: Font.DemiBold; color: Theme.textTertiary
                }
                Item {
                    objectName: "shortcutRow-" + entry.index
                    readonly property string name: entry.modelData.name
                    width: parent.width; height: Theme.rowHeight
                    Label {
                        anchors.left: parent.left; anchors.right: keyRow.left; anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: entry.modelData.name
                        elide: Text.ElideRight; textFormat: Text.PlainText; color: Theme.text
                    }
                    Row {
                        id: keyRow
                        anchors.right: parent.right; anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Repeater {
                            model: entry.modelData.keys
                            delegate: Rectangle {
                                required property string modelData
                                readonly property bool off: modelData.length === 0
                                objectName: "shortcutKey"
                                width: keyText.implicitWidth + 12; height: Theme.rowHeight - 6
                                radius: Theme.radiusSmall
                                color: off ? "transparent" : Theme.window
                                border.color: off ? "transparent" : Theme.border
                                Label {
                                    id: keyText
                                    anchors.centerIn: parent
                                    text: parent.off ? "Off" : Platform.keys(parent.modelData)
                                    textFormat: Text.PlainText
                                    font.pixelSize: Theme.fontSmall
                                    color: parent.off ? Theme.textTertiary : Theme.textSecondary
                                }
                            }
                        }
                    }
                }
            }
            Label { anchors.centerIn: parent; visible: list.count === 0; text: "No matching shortcuts"; color: Theme.textTertiary }
        }
        RowLayout {
            Layout.fillWidth: true
            Label {
                Layout.fillWidth: true
                text: "Most of these can be changed."
                font.pixelSize: Theme.fontCaption; color: Theme.textTertiary
            }
            Button {
                objectName: "shortcutSettings"
                text: "Change Shortcuts…"
                onClicked: { root.close(); root.settingsRequested() }
            }
        }
    }
}
