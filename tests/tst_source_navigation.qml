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
