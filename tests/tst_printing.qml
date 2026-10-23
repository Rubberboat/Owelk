import QtQuick
import QtTest
import "../qml" as App
import "../qml/Shortcuts.js" as Shortcuts

Item {
    id: scene
    width: 1000; height: 760
    App.DocumentWorkspace { id: workspace; anchors.fill: parent }
    SignalSpy { id: messages; target: researchStore; signalName: "message" }
    SignalSpy { id: printed; signalName: "triggered" }
    TestCase {
        name: "PdfPrinting"
        when: windowShown
        property string savedShortcuts
        function ready() {
            tryVerify(function() { return workspace.currentReader && workspace.currentReader.canPrint })
            tryCompare(workspace.currentReader.pdfCanvas, "restoring", false)
            printed.target = workspace.currentReader.printAction
            printed.clear(); messages.clear()
        }
        function init() {
            savedShortcuts = researchStore.setting("shortcuts")
            researchStore.setSetting("shortcuts", "{}")
            workspace.readingFocus = false
            workspace.restore({})
            workspace.openDocument(fixtureSource, {page: 2, y: .2, x: 0, zoom: 1})
            ready()
        }
        function cleanup() {
            researchStore.setSetting("shortcuts", savedShortcuts)
            printed.target = null
        }
        function press(key, modifiers) {
            testInput.keyClick(workspace.currentReader.pdfCanvas, key, modifiers)
        }
        function verifyDispatch() {
            tryCompare(printed, "count", 1)
            // Quick Test uses QGuiApplication: the backend reports this instead of opening
            // an OS dialog or sending a physical print job. Rendering is tested in AnnotationTest.
            tryCompare(messages, "count", 1)
            verify(messages.signalArguments[0][0].indexOf("Printing needs the updated desktop app") >= 0)
        }
        function test_shortcutInReadingFocusPreservesPlace() {
            const reader = workspace.currentReader
            workspace.readingFocus = true
            tryCompare(findChild(reader, "readerToolbar"), "visible", false)
            tryCompare(reader.pdfCanvas, "restoring", false)
            const before = reader.pdfCanvas.position()
            press(Qt.Key_P, Qt.ControlModifier)
            verifyDispatch()
            compare(reader.pdfCanvas.position(), before)
            verify(workspace.readingFocus)
        }
        function test_buttonAndMenuShareAction() {
            const reader = workspace.currentReader
            const button = findChild(reader, "printButton")
            compare(button.action, reader.printAction)
            compare(findChild(reader, "printOption").action, reader.printAction)
            mouseClick(button)
            verifyDispatch()
        }
        function test_onlyActiveSplitPrints() {
            const first = workspace.currentReader
            workspace.duplicateSplit("right")
            ready()
            const second = workspace.currentReader
            verify(first !== second)
            compare(first.printAction.shortcut.toString(), "")
            press(Qt.Key_P, Qt.ControlModifier)
            verifyDispatch()
            workspace.focusGroup(-1)
            ready()
            compare(workspace.currentReader, first)
            compare(second.printAction.shortcut.toString(), "")
            press(Qt.Key_P, Qt.ControlModifier)
            verifyDispatch()
        }
        function test_customShortcutAndDisable() {
            compare(Shortcuts.defaultKeys("print", "osx"), "Ctrl+P")
            compare(Shortcuts.defaultKeys("print", "linux"), "Ctrl+P")
            compare(Shortcuts.defaultKeys("print", "windows"), "Ctrl+P")
            researchStore.setSetting("shortcuts", JSON.stringify({print: "Ctrl+Shift+9"}))
            press(Qt.Key_P, Qt.ControlModifier)
            wait(80); compare(printed.count, 0)
            press(Qt.Key_9, Qt.ControlModifier | Qt.ShiftModifier)
            verifyDispatch()
            researchStore.setSetting("shortcuts", JSON.stringify({print: ""}))
            printed.clear(); messages.clear()
            press(Qt.Key_9, Qt.ControlModifier | Qt.ShiftModifier)
            wait(80); compare(printed.count, 0)
            verify(findChild(workspace.currentReader, "printButton").enabled)
        }
        function test_unverifiedAndEmptyPdfCannotPrint() {
            const reader = workspace.currentReader
            reader.pdfCanvas.documentFingerprint = ""
            verify(!reader.canPrint)
            verify(!findChild(reader, "printButton").enabled)
            press(Qt.Key_P, Qt.ControlModifier)
            reader.printDocument()
            wait(80); compare(messages.count, 0)
            reader.restore({})
            verify(!reader.canPrint)
        }
        function test_unfinishedAnnotationCannotPrint() {
            const reader = workspace.currentReader
            const editor = findChild(reader, "annotationEditor")
            editor.begin(reader.pdfCanvas, {kind: "comment", page: 2}, null)
            tryCompare(editor, "visible", true)
            verify(!reader.canPrint)
            reader.printDocument()
            compare(messages.count, 0)
            editor.close()
            tryCompare(reader, "canPrint", true)
        }
    }
}
