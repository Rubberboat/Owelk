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
    property bool fullScreenSession: false
    property real previousWidth: 0
    property real previousHeight: 0
    // Closing or autosaving in focus mode must not replace the normal window size with the screen size.
    readonly property real sessionWidth: active && enteredFullScreen ? previousWidth : targetWindow.width
    readonly property real sessionHeight: active && enteredFullScreen ? previousHeight : targetWindow.height
    onActiveChanged: {
        if (active) {
            previousVisibility = targetWindow.visibility
            previousWidth = targetWindow.width
            previousHeight = targetWindow.height
            fullScreenSession = useFullScreen || previousVisibility === Window.FullScreen
            enteredFullScreen = useFullScreen && previousVisibility !== Window.FullScreen
            if (enteredFullScreen) targetWindow.showFullScreen()
        } else {
            const restore = enteredFullScreen
            enteredFullScreen = false
            fullScreenSession = false
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
            if (root.active && root.fullScreenSession && target.visibility !== Window.FullScreen
                    && target.visibility !== Window.Minimized) root.active = false
        }
    }
}
