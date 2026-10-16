import QtQuick
import QtTest
import "../qml" as App
import "../qml/WorkspaceTree.js" as Tree

Item {
    width: 1000; height: 760
    App.DocumentWorkspace { id: workspace; anchors.fill: parent }
    TestCase {
        name: "SourceNavigation"
        when: windowShown
        function init() {
            workspace.restore({})
            workspace.openDocument(fixtureSource, {page: 0, y: .2, x: 0, zoom: 1})
            tryVerify(function() { return workspace.currentReader && workspace.currentReader.pdfReady })
            tryCompare(canvas(), "restoring", false)
        }
        function canvas() { return findChild(workspace.currentReader, "pdfCanvas0") }
        function test_readingCheckpointSavesOnlyOnAccept() {
            const reader = workspace.currentReader
            verify(researchStore.setReadingReminder(fixtureSource, "Original reminder"))
            reader.openReadingCheckpoint()
            const dialog = findChild(reader, "readingCheckpoint")
            const field = findChild(reader, "readingReminder")
            tryCompare(dialog, "opened", true)
            compare(field.text, "Original reminder")
            field.text = "Unsaved"
            dialog.reject()
            tryCompare(dialog, "visible", false)
            compare(researchStore.readingContext(fixtureSource).reminder, "Original reminder")
            reader.openReadingCheckpoint()
            tryCompare(dialog, "opened", true)
            field.text = "Check Figure 2"
            dialog.accept()
            tryCompare(dialog, "visible", false)
            compare(researchStore.readingContext(fixtureSource).reminder, "Check Figure 2")
        }
        function test_pinnedReferenceSurvivesScrollingButNotAnotherDocument() {
            const c = canvas()
            c.pinObject({kind: "equation", label: "Equation 1", page: 0, x: 20, y: 50, width: 200, height: 100})
            const card = findChild(c, "linkPreview")
            tryCompare(card, "visible", true)
            c.jump(3, 0, 0)
            tryCompare(c, "restoring", false)
            compare(c.pinnedPreview.page, 0)
            verify(card.visible)
            c.closeLinkPreview()
            verify(card.visible)
            c.unpinPreview()
            tryCompare(card, "visible", false)
            c.pinObject({kind: "figure", page: 0, x: 20, y: 50, width: 200, height: 100})
            workspace.openDocument(testInput.uniqueFixture("pin-other.pdf"))
            tryCompare(c, "ready", true)
            compare(c.pinnedPreview, null)
        }
        function test_columnViewportKeepsPageAndSource() {
            const c = canvas(), source = c.source.toString(), page = c.currentPage
            c.fitColumn("left")
            tryCompare(c, "restoring", false)
            verify(c.zoomFactor > 1)
            const left = c.position().x
            c.fitColumn("right")
            tryCompare(c, "restoring", false)
            verify(c.position().x > left)
            compare(c.currentPage, page)
            compare(c.source.toString(), source)
            c.fitWidth()
            tryCompare(c, "restoring", false)
            compare(c.zoomFactor, 1)
        }
        function test_focusKeepsReadingPositionAndRestoresToolbar() {
            const reader = workspace.currentReader, c = canvas()
            const toolbar = findChild(reader, "readerToolbar")
            const before = c.position()
            verify(toolbar.visible)
            workspace.readingFocus = true
            tryCompare(toolbar, "visible", false)
            tryCompare(c, "restoring", false)
            compare(c.currentPage, before.page)
            workspace.readingFocus = false
            tryCompare(toolbar, "visible", true)
            tryCompare(c, "restoring", false)
            compare(c.currentPage, before.page)
        }
        function test_citationCancelConfirmAndReturn() {
            const c = canvas(), before = c.position()
            c.backStack = []
            const paper = researchStore.documentLinkId(fixtureSource)
            const link = "owelk://document/" + paper + "#page=4"
            verify(workspace.openLink(link))
            const dialog = findChild(workspace, "sourceNavigationConfirm")
            tryCompare(dialog, "opened", true)
            compare(c.currentPage, before.page)
            dialog.reject()
            tryCompare(dialog, "visible", false)
            compare(c.backStack.length, 0)
            fuzzyCompare(c.position().y, before.y, .01)
            verify(workspace.openLink(link))
            tryCompare(dialog, "opened", true)
            mouseClick(findChild(dialog, "confirmAction"))
            tryCompare(c, "currentPage", 3)
            compare(c.backTarget.page, before.page)
            verify(c.goBack())
            tryCompare(c, "restoring", false)
            compare(c.currentPage, before.page)
            fuzzyCompare(c.position().y, before.y, .01)
        }
        function test_noteRemainsUntilConfirmed() {
            const paper = researchStore.documentLinkId(fixtureSource)
            const note = researchStore.createNote("Reading", "Keep this note open.")
            workspace.openNote(note, true)
            function activeTab() {
                const group = Tree.find(workspace.tree, workspace.activeGroup)
                return group.tabs.find(function(t) { return t.id === group.activeTab })
            }
            compare(activeTab().noteId, note)
            verify(workspace.openLink("owelk://document/" + paper))
            const dialog = findChild(workspace, "sourceNavigationConfirm")
            tryCompare(dialog, "opened", true)
            dialog.reject()
            tryCompare(dialog, "visible", false)
            compare(activeTab().noteId, note)
            verify(workspace.openLink("owelk://document/" + paper))
            tryCompare(dialog, "opened", true)
            mouseClick(findChild(dialog, "confirmAction"))
            tryVerify(function() { return researchStore.sameSource(activeTab().source || "", fixtureSource) })
            verify(Tree.leaves(workspace.tree).some(function(g) { return g.tabs.some(function(t) { return t.noteId === note }) }))
        }
    }
}
