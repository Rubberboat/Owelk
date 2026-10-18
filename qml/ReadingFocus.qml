import QtQuick
import QtQuick.Window

// Window state belongs to this visit to focus mode, never to the saved panel layout.
Item {
    id: root
    visible: false
    required property var targetWindow
    property bool active: false
    property bool useFullScreen: true
    property int previousVisibility: Window.Windowed
    property bool enteredFullScreen: false
    onActiveChanged: {
        if (active) {
            previousVisibility = targetWindow.visibility
            enteredFullScreen = useFullScreen && previousVisibility !== Window.FullScreen
            if (enteredFullScreen) targetWindow.showFullScreen()
        } else {
            const restore = enteredFullScreen
            enteredFullScreen = false
            if (restore) {
                if (previousVisibility === Window.Maximized) targetWindow.showMaximized()
                else targetWindow.showNormal()
            }
        }
    }
    Connections {
        target: root.targetWindow
        // Native full-screen controls (including macOS Escape) must also restore the reading chrome.
        function onVisibilityChanged() {
            if (root.active && root.enteredFullScreen && target.visibility !== Window.FullScreen
                    && target.visibility !== Window.Minimized) root.active = false
        }
    }
}
