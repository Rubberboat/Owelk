import QtQuick
import QtQuick.Window
import QtTest
import "../qml" as App

Item {
    id: scene
    width: 1000; height: 700
    QtObject {
        id: fakeWindow
        property int visibility: Window.Windowed
        property real width: 1200
        property real height: 800
        function showFullScreen() { width = 1920; height = 1080; visibility = Window.FullScreen }
        function showNormal() { width = 1200; height = 800; visibility = Window.Windowed }
        function showMaximized() { visibility = Window.Maximized }
    }
    App.ReadingFocus { id: controller; targetWindow: fakeWindow }
    App.ReadingFocusBar { id: bar; width: scene.width }
    SignalSpy { id: tabSpy; target: bar; signalName: "tabRequested" }
    SignalSpy { id: exitSpy; target: bar; signalName: "exitRequested" }
    TestCase {
        name: "ReadingFocus"
        when: windowShown
        function init() {
            controller.active = false
            controller.useFullScreen = true
            fakeWindow.visibility = Window.Windowed
            fakeWindow.width = 1200; fakeWindow.height = 800
            bar.active = false
            bar.tabs = [{id: "one", title: "First paper", current: true}, {id: "two", title: "Second paper"}]
            tabSpy.clear(); exitSpy.clear()
            mouseMove(scene, 1, 500)
        }
        function test_restorePreviousWindowState_data() {
            return [{tag: "normal", state: Window.Windowed}, {tag: "maximized", state: Window.Maximized}, {tag: "alreadyFullScreen", state: Window.FullScreen}]
        }
        function test_restorePreviousWindowState(data) {
            fakeWindow.visibility = data.state
            controller.active = true
            compare(fakeWindow.visibility, Window.FullScreen)
            controller.active = false
            compare(fakeWindow.visibility, data.state)
        }
        function test_windowedPreferenceAndNativeExit() {
            controller.useFullScreen = false
            controller.active = true
            compare(fakeWindow.visibility, Window.Windowed)
            controller.active = false
            controller.useFullScreen = true
            controller.active = true
            fakeWindow.visibility = Window.Minimized
            verify(controller.active)
            fakeWindow.visibility = Window.FullScreen
            fakeWindow.visibility = Window.Windowed
            verify(!controller.active)
        }
        function test_sessionSizeAndExistingFullscreenNativeExit() {
            controller.active = true
            compare(fakeWindow.width, 1920)
            compare(controller.sessionWidth, 1200)
            compare(controller.sessionHeight, 800)
            controller.active = false
            compare(controller.sessionWidth, fakeWindow.width)
            fakeWindow.showFullScreen()
            controller.active = true
            fakeWindow.showNormal()
            verify(!controller.active)
            compare(fakeWindow.visibility, Window.Windowed)
        }
        function test_autoHidePeekTabAndExit() {
            bar.active = true
            verify(bar.revealed)
            tryCompare(bar, "revealed", false, 3000)
            compare(bar.height, 6)
            mouseMove(bar, 10, 2)
            tryCompare(bar, "revealed", true)
            mouseClick(findChild(bar, "readingFocusTabs"))
            const popup = findChild(bar, "readingFocusTabsPopup")
            tryCompare(popup, "opened", true)
            mouseMove(scene, 10, 500)
            wait(1800)
            verify(bar.revealed)
            verify(popup.contentItem.itemAtIndex(1) !== null)
            mouseClick(popup.contentItem.itemAtIndex(1))
            compare(tabSpy.count, 1)
            compare(tabSpy.signalArguments[0][0], "two")
            tryCompare(popup, "visible", false)
            mouseMove(bar, 10, 2)
            mouseClick(findChild(bar, "exitReadingFocus"))
            compare(exitSpy.count, 1)
        }
    }
}
