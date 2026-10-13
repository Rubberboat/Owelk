import Owelk.Ui
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Popup {
    id: root
    objectName: "searchPalette"
    width: Math.min(600, parent ? parent.width - 32 : 600)
    x: parent ? (parent.width - width) / 2 : 0
    y: parent ? Math.min(100, parent.height * .12) : 0
    padding: 12
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    property alias results: search.results
    property alias searchController: search
    property url currentSource: ""
    ResearchSearch { id: search; query: searchInput.text; active: root.visible; showRecent: true; onRewrite: function(text) { searchInput.text = text; searchInput.cursorPosition = text.length; searchInput.forceActiveFocus() } }
    signal resultChosen(var result)
    // The Library's results and a row for the web, as on Home: first when the text reads as an address
    // or names an engine ("arxiv: …"), last otherwise.
    readonly property var rows: {
        const web = search.webRow, found = root.results
        return !web ? found : web.first ? [web].concat(found) : found.concat([web])
    }
    function selectionIndex() {
        const web = search.webRow, at = search.selectionIndex()
        if (!web) return at
        if (web.first) return 0
        return at >= 0 ? at : root.rows.length - 1
    }
    function refresh() {
        search.refresh()
        list.currentIndex = root.selectionIndex()
    }
    // Return pressed before the saved items are known waits for them (see HomeView).
    property bool acceptWhenReady: false
    onRowsChanged: {
        list.currentIndex = root.selectionIndex()
        if (list.currentIndex >= 0) list.positionViewAtIndex(list.currentIndex, ListView.Contain)
        if (acceptWhenReady && !search.namesPending) {
            acceptWhenReady = false
            // After this change has gone round (choosing closes the palette).
            const text = searchInput.text
            Qt.callLater(function() { if (searchInput.text === text) root.choose(Math.max(0, list.currentIndex)) })
        }
    }
    function move(direction) {
        const rows = root.rows
        if (!rows.length) return
        list.currentIndex = (list.currentIndex + direction + rows.length) % rows.length
        if ((rows[list.currentIndex].kind === "paperGroup" || rows[list.currentIndex].kind === "section") && rows.length > 1)
            list.currentIndex = (list.currentIndex + direction + rows.length) % rows.length
        list.positionViewAtIndex(list.currentIndex, ListView.Contain)
    }
    function choose(index) {
        if (index < 0 || index >= rows.length) return
        const result = rows[index]
        if (result.kind !== "web" && search.choose(result)) return
        close()
        Qt.callLater(function() { root.resultChosen(result) })
    }
    onAboutToShow: { searchInput.clear(); refresh() }
    onOpened: searchInput.forceActiveFocus()
    contentItem: ColumnLayout {
        spacing: 8
        TextField {
            id: searchInput
            objectName: "searchPaletteQuery"
            Layout.fillWidth: true
            placeholderText: "Search your library or the web  ·  narrow with tag: collection: state: year:"
            selectByMouse: true
            onTextChanged: root.acceptWhenReady = false
            onAccepted: {
                if (search.delay.running) root.refresh()
                if (search.namesPending) root.acceptWhenReady = true
                else root.choose(Math.max(0, list.currentIndex))
            }
            // Ctrl/⌘+Return: the web, whatever row is chosen.
            Keys.onPressed: function(event) {
                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier) && search.webRow) {
                    root.choose(root.rows.indexOf(search.webRow))
                    event.accepted = true
                }
            }
            Keys.onDownPressed: root.move(1)
            Keys.onUpPressed: root.move(-1)
            Keys.onEscapePressed: root.close()
        }
        SearchFilters { Layout.fillWidth: true; controller: search; currentSource: root.currentSource }
        ListView {
            id: list
            objectName: "searchPaletteResults"
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(360, Math.max(44, contentHeight))
            model: root.rows
            // A new model resets the current row to 0, which can be a heading; choose again afterwards.
            onModelChanged: currentIndex = root.selectionIndex()
            clip: true
            ScrollBar.vertical: ScrollBar {}
            delegate: SearchResultDelegate {
                required property int index
                queryText: searchInput.text
                width: list.width
                highlighted: list.currentIndex === index
                onClicked: root.choose(index)
            }
            Label { visible: list.count === 0; anchors.centerIn: parent; text: search.waiting ? "Searching PDF text…" : search.error.length ? "Text search failed. Try again." : "No matching saved items"; color: Theme.textTertiary }
        }
        Label { text: search.sourceFilter.toString().length ? "Matching pages in this paper · 40 per page" : "PDF text grouped by paper · 3 previews each"; color: Theme.textTertiary; font.pixelSize: Theme.fontCaption }
        Label { Layout.fillWidth: true; visible: search.error.length > 0; text: "PDF text search failed: " + search.error; textFormat: Text.PlainText; wrapMode: Text.Wrap; font.pixelSize: Theme.fontCaption; color: Theme.textTertiary }
        IndexStatus { Layout.fillWidth: true }
    }
}
