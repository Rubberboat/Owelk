import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Owelk.Ui

// An overlay: showing the controls never moves the PDF or changes its zoom.
Item {
    id: root
    objectName: "readingFocusBar"
    property bool active: false
    property bool revealed: false
    property var tabs: []
    property string title: "Open tabs"
    property bool canSwitchTabs: true
    property bool canGoBack: false
    property bool canGoForward: false
    property string shortcut: "F8"
    signal exitRequested()
    signal tabRequested(string id)
    signal panelRequested(string panel)
    signal backRequested()
    signal forwardRequested()
    signal searchRequested()
    visible: active
    height: revealed || tabsPopup.opened ? bar.height : 6
    onActiveChanged: {
        tabsPopup.close()
        revealed = active
        if (active) hideDelay.restart()
        else hideDelay.stop()
    }
    HoverHandler {
        id: hover
        onHoveredChanged: {
            if (hovered) { hideDelay.stop(); root.revealed = true }
            else if (!tabsPopup.opened) hideDelay.restart()
        }
    }
    Timer {
        id: hideDelay
        interval: 1600
        onTriggered: if (!hover.hovered && !tabsPopup.opened) root.revealed = false
    }
    Rectangle {
        id: bar
        objectName: "readingFocusControls"
        visible: root.revealed || tabsPopup.opened
        width: parent.width; height: 44
        color: Theme.window
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.separator }
        RowLayout {
            anchors.fill: parent; anchors.margins: 4
            spacing: 2
            IconButton { icon.name: "back"; description: "Back"; enabled: root.canGoBack; onClicked: root.backRequested() }
            IconButton { icon.name: "forward"; description: "Forward"; enabled: root.canGoForward; onClicked: root.forwardRequested() }
            IconButton { icon.name: "search"; description: "Search"; onClicked: root.searchRequested() }
            Item { Layout.fillWidth: true }
            Button {
                id: tabsButton
                objectName: "readingFocusTabs"
                Layout.maximumWidth: Math.max(120, root.width - 470)
                text: root.title
                enabled: root.canSwitchTabs && root.tabs.length > 0
                onClicked: tabsPopup.opened ? tabsPopup.close() : tabsPopup.open()
                ToolTip.visible: hovered
                ToolTip.text: "Switch tab"
            }
            Item { Layout.fillWidth: true }
            Repeater {
                model: ["files", "document", "ai"]
                StatusIcon {
                    required property string modelData
                    objectName: "focusPanel-" + modelData
                    kind: modelData
                    description: "Exit focus and open " + (modelData === "files" ? "Library" : modelData === "ai" ? "AI Chat" : "Document")
                    onTriggered: root.panelRequested(modelData)
                }
            }
            Button {
                objectName: "exitReadingFocus"
                text: "Exit Focus" + (root.shortcut.length ? " · " + root.shortcut : "")
                onClicked: root.exitRequested()
            }
        }
        Popup {
            id: tabsPopup
            objectName: "readingFocusTabsPopup"
            width: Math.min(360, root.width - 16)
            x: Math.max(8, Math.min(root.width - width - 8, tabsButton.x + tabsButton.width / 2 - width / 2))
            y: bar.height + 4
            padding: 6
            onOpened: hideDelay.stop()
            onClosed: if (!hover.hovered) hideDelay.restart()
            contentItem: ListView {
                implicitHeight: Math.min(contentHeight, 360, root.parent.height - bar.height - 30)
                clip: true
                model: root.tabs
                ScrollBar.vertical: ScrollBar {}
                delegate: ItemDelegate {
                    required property var modelData
                    objectName: "focusTab-" + modelData.id
                    width: ListView.view.width
                    text: modelData.title
                    highlighted: !!modelData.current
                    onClicked: { tabsPopup.close(); root.tabRequested(modelData.id) }
                }
            }
        }
    }
}
