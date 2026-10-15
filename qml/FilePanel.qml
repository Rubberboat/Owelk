import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Owelk.Ui
import "WorkspaceTree.js" as Tree
import "CollectionTree.js" as CollectionTree

// The Library panel: where papers are chosen. Each row (All Papers, Favorites, Unsorted, a reading
// state, a collection, a tag) shows its papers in the Library tab, which opens if it is not open, and
// the row stays highlighted while the tab shows it; the Library tab's own sidebar steps aside while the
// panel is open. Collections fold to their sub-collections (drop a tab or a paper on one to file it);
// then recent notes and the paper folder. Sections fold; the folder takes the rest.
Item {
    id: root
    // PDFs added here go through the window, which checks them for papers already kept.
    function addPdfs(urls, options) {
        const window = ApplicationWindow.window
        if (window && window.addPdfs) window.addPdfs(urls, options)
        else researchStore.takePdfs(urls, options)
    }
    objectName: "libraryPanel"
    property url folder
    // The document area, for tabs dropped on a collection.
    property var documents: null
    signal libraryFilterRequested(var filter)
    signal noteChosen(string id)
    signal newNoteRequested()
    property var collections: []
    property var tags: []
    property var notes: []
    property int unsortedCount: 0
    function refreshShelf() {
        collections = researchStore.collections(); tags = researchStore.tags()
        unsortedCount = researchStore.unsortedCount()
    }
    // The Library tab in front and what it shows (null when it is not in front): that row is highlighted.
    property var shownFilter: null
    function readShown() {
        if (!documents) { shownFilter = null; return }
        const g = Tree.find(documents.tree, documents.activeGroup)
        const t = g ? g.tabs.find(function(tab) { return tab.id === g.activeTab }) : null
        shownFilter = t && t.kind === "library" ? (t.filter || {}) : null
    }
    Connections {
        target: root.documents
        ignoreUnknownSignals: true
        function onRevisionChanged() { root.readShown() }
        function onActiveGroupChanged() { root.readShown() }
        function onChanged() { root.readShown() }
    }
    function shows(filter) {
        if (!shownFilter || shownFilter.view) return false
        return JSON.stringify(Object.keys(shownFilter).sort().map(function(k) { return [k, shownFilter[k]] }))
            === JSON.stringify(Object.keys(filter).sort().map(function(k) { return [k, filter[k]] }))
    }
    // A row chosen: its papers in the Library tab.
    function show(filter) { root.libraryFilterRequested(filter) }
    // Collections fold to their sub-collections (the open ones are a setting, shared with the Library tab).
    property var openCollections: CollectionTree.parse(researchStore.setting("library.openCollections"))
    readonly property var shelfRows: CollectionTree.rows(collections, openCollections, shownFilter && shownFilter.collection ? shownFilter.collection : "")
    function setCollectionOpen(id, on) {
        openCollections = CollectionTree.toggled(openCollections, id, on)
        researchStore.setSetting("library.openCollections", openCollections.join(","))
    }
    // A collection chosen: shown in the Library tab, and unfolded to its sub-collections; chosen again
    // while shown, it folds.
    function chooseCollection(row) {
        if (row.hasChildren) setCollectionOpen(row.id, !(row.open && shows({collection: row.id})))
        show({collection: row.id})
    }
    function refreshNotes() { notes = researchStore.notes(false).slice(0, 5) }
    function sectionOpen(name, fallback) { return researchStore.setting("library.section." + name, fallback ? "1" : "0") === "1" }
    property bool collectionsOpen: sectionOpen("collections", true)
    property bool tagsOpen: sectionOpen("tags", false)
    property bool notesOpen: sectionOpen("notes", true)
    property bool folderOpen: sectionOpen("folder", true)
    function setSection(name, open) { researchStore.setSetting("library.section." + name, open ? "1" : "0") }
    Connections {
        target: researchStore
        function onDocumentsChanged() { root.refreshShelf() }
        function onHomeChanged() { root.refreshShelf() }
        function onNotesChanged() { root.refreshNotes() }
        function onSettingsChanged() {
            const open = CollectionTree.parse(researchStore.setting("library.openCollections"))
            if (open.join(",") !== root.openCollections.join(",")) root.openCollections = open
        }
    }
    // Tabs dragged over a collection are filed there (PDF tabs only); the tab stays open.
    function claimDrop(id, x, y) {
        if (!visible || !documents || !collectionsOpen) return null
        const strip = Tree.owner(documents.tree, id)
        const tab = strip ? strip.tabs.find(function(t) { return t.id === id }) : null
        if (!tab || tab.kind) return null
        const p = shelf.mapFromItem(null, x, y)
        if (p.x < 0 || p.y < 0 || p.x > shelf.width || p.y > shelf.height) return null
        const i = shelf.indexAt(p.x, p.y + shelf.contentY)
        const row = i >= 0 ? shelf.model[i] : null
        if (!row) return null
        return {handler: root, collection: row.id, name: row.name, source: tab.source}
    }
    function dropTab(id, target) {
        if (researchStore.setDocumentCollection(target.source, target.collection, true)) researchStore.notify("Added to " + target.name + ".")
    }
    Component.onDestruction: if (documents) documents.removeDropHandler(root)
    // A section heading: a chevron and a name; click folds it.
    component SectionHeader: Item {
        id: heading
        property string title
        property bool open
        signal toggled()
        default property alias actions: actionRow.data
        Layout.fillWidth: true
        implicitHeight: Theme.rowHeight
        Icon { id: chevron; x: 2; anchors.verticalCenter: parent.verticalCenter; name: heading.open ? "down" : "right"; size: Theme.fontSmall; color: Theme.textTertiary }
        Label {
            anchors.left: chevron.right; anchors.leftMargin: 4; anchors.verticalCenter: parent.verticalCenter
            text: heading.title; font.pixelSize: Theme.fontCaption; font.weight: Font.DemiBold; color: Theme.textSecondary
        }
        TapHandler { onTapped: heading.toggled() }
        Row { id: actionRow; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 2 }
    }
    property var pending: ({})
    property var latestRequests: ({})
    property bool initialized: false
    property string status: ""
    signal folderChosen(url folder)
    signal documentChosen(url source)

    function load(url, parentUrl, depth) {
        const request = researchStore.listFolder(url)
        pending[request] = {parentUrl: parentUrl, depth: depth}
        latestRequests[parentUrl] = request
    }
    function refresh() {
        if (!rows) return
        rows.clear()
        pending = ({})
        latestRequests = ({})
        status = ""
        if (folder.toString().length) { status = "Loading…"; load(folder, "", 0) }
    }
    function toggle(index) {
        const row = rows.get(index)
        if (!row.directory) { documentChosen(row.url); return }
        if (row.expanded) {
            let count = 0
            while (index + count + 1 < rows.count && rows.get(index + count + 1).depth > row.depth) count++
            if (count) rows.remove(index + 1, count)
            rows.setProperty(index, "expanded", false)
        } else {
            rows.setProperty(index, "expanded", true)
            rows.setProperty(index, "loading", true)
            load(row.url, row.url, row.depth + 1)
        }
    }
    onFolderChanged: if (initialized) refresh()
    Component.onCompleted: { initialized = true; refresh(); refreshShelf(); refreshNotes(); readShown(); if (documents) documents.addDropHandler(root) }
    ListModel { id: rows }
    Connections {
        target: researchStore
        function onFolderLoaded(requestId, folder, entries, error) {
            const request = root.pending[requestId]
            if (!request) return
            delete root.pending[requestId]
            if (root.latestRequests[request.parentUrl] !== requestId) return
            let insertAt = 0
            if (request.parentUrl.length) {
                let parentIndex = -1
                for (let i = 0; i < rows.count; ++i) {
                    if (rows.get(i).url === request.parentUrl) { parentIndex = i; break }
                }
                if (parentIndex < 0) return
                rows.setProperty(parentIndex, "loading", false)
                if (!rows.get(parentIndex).expanded) return
                insertAt = parentIndex + 1
                if (error.length) rows.setProperty(parentIndex, "expanded", false)
            }
            root.status = error
            for (let i = 0; i < entries.length; ++i) {
                rows.insert(insertAt + i, {name: entries[i].name, url: entries[i].url,
                    directory: entries[i].directory, depth: request.depth, expanded: false, loading: false})
            }
            if (!rows.count && !error.length) root.status = "No PDFs or subfolders."
        }
    }
    FolderDialog { id: folderDialog; title: "Open paper folder"; onAccepted: root.folderChosen(selectedFolder) }
    Menu {
        id: shelfMenu
        objectName: "panelCollectionMenu"
        property var collection: ({})
        MenuItem { objectName: "panelAddPdfs"; text: "Add PDFs…"; onTriggered: addFiles.open() }
        MenuSeparator {}
        MenuItem { text: "New Sub-collection…"; onTriggered: nameDialog.begin("new", "", shelfMenu.collection.id) }
        MenuItem { objectName: "panelRenameCollection"; text: "Rename…"; onTriggered: nameDialog.begin("rename", shelfMenu.collection.name, shelfMenu.collection.id) }
        MenuItem {
            objectName: "panelCollectionFollow"
            checkable: true
            checked: shelfMenu.visible && researchStore.forYou.following(shelfMenu.collection.id || "")
            text: "Follow in For You"
            onTriggered: researchStore.forYou.follow(shelfMenu.collection.id, !researchStore.forYou.following(shelfMenu.collection.id))
        }
        MenuSeparator {}
        MenuItem { text: "Delete Collection…"; palette.windowText: Theme.danger; onTriggered: deleteConfirm.open() }
    }
    // A collection's name, new or changed.
    Dialog {
        id: nameDialog
        objectName: "panelCollectionName"
        property string mode: "new"
        property string target: ""
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 340
        modal: true
        title: mode === "rename" ? "Rename collection" : target.length ? "New sub-collection" : "New collection"
        standardButtons: Dialog.Save | Dialog.Cancel
        function begin(how, name, collection) { mode = how; target = collection || ""; nameField.text = name || ""; open(); nameField.forceActiveFocus() }
        TextField { id: nameField; objectName: "panelCollectionNameField"; width: parent.width; placeholderText: "Collection name"; onAccepted: nameDialog.accept() }
        onAccepted: {
            if (!nameField.text.trim().length) return
            if (mode === "rename") researchStore.renameCollection(target, nameField.text)
            else researchStore.createCollection(nameField.text, target)
            root.refreshShelf()
        }
    }
    ConfirmDialog {
        id: deleteConfirm
        title: "Delete \u201c" + (shelfMenu.collection.name || "") + "\u201d?"
        message: "Only the collection goes (and its sub-collections). The papers stay in the Library."
        actionText: "Delete"
        onConfirmed: { researchStore.deleteCollection(shelfMenu.collection.id); root.refreshShelf() }
    }
    FileDialog {
        id: addFiles
        title: "Add PDFs to " + (shelfMenu.collection.name || "the collection")
        fileMode: FileDialog.OpenFiles
        nameFilters: ["PDF documents (*.pdf)"]
        onAccepted: root.addPdfs(selectedFiles, {collection: shelfMenu.collection.id})
    }
    // A row of the navigator: an icon, a name, a count at the right.
    component NavigatorRow: ItemDelegate {
        id: navRow
        property string glyph
        property var count
        property int depth: 0
        property color glyphColor: Theme.textTertiary
        // A reading state's dot (as in the Library's list) instead of a glyph.
        property string dot: ""
        Layout.fillWidth: true
        implicitHeight: Theme.rowHeight
        leftPadding: 26 + 12 * depth
        rightPadding: 34
        Icon { visible: !navRow.dot.length; x: 6 + 12 * navRow.depth; anchors.verticalCenter: parent.verticalCenter; name: navRow.glyph; size: Theme.fontBody; color: navRow.highlighted ? Theme.selectedText : navRow.glyphColor }
        Rectangle {
            visible: navRow.dot.length > 0
            x: 9 + 12 * navRow.depth; anchors.verticalCenter: parent.verticalCenter
            width: 8; height: 8; radius: 4; border.width: 1.5
            color: navRow.dot === "read" ? Theme.textTertiary : navRow.dot === "reading" ? Theme.accent : "transparent"
            border.color: navRow.dot === "read" ? Theme.textTertiary : Theme.accent
        }
        Label {
            visible: navRow.count !== undefined
            anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
            text: navRow.count !== undefined ? navRow.count : ""; font.pixelSize: Theme.fontCaption; color: Theme.textTertiary
        }
    }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 2
        // --- The whole Library, and its built-in lists ----------------------------------------
        NavigatorRow { objectName: "panelAllPapers"; glyph: "library"; text: "All Papers"; highlighted: root.shows({}); onClicked: root.show({}) }
        NavigatorRow { objectName: "panelFavorites"; glyph: "star"; text: "Favorites"; highlighted: root.shows({favorite: true}); onClicked: root.show({favorite: true}) }
        NavigatorRow { objectName: "panelUnsorted"; glyph: "document"; text: "Unsorted"; count: root.unsortedCount; highlighted: root.shows({unsorted: true}); onClicked: root.show({unsorted: true}) }
        Repeater {
            model: [{state: "unread", label: "Unread"}, {state: "reading", label: "Reading"}, {state: "read", label: "Read"}]
            delegate: NavigatorRow {
                required property var modelData
                objectName: "panelState-" + modelData.state
                dot: modelData.state; text: modelData.label
                highlighted: root.shows({state: modelData.state})
                onClicked: root.show({state: modelData.state})
            }
        }
        Item { implicitHeight: 4 }
        // --- Collections ----------------------------------------------------------------------
        SectionHeader {
            objectName: "collectionsSection"
            title: "Collections"; open: root.collectionsOpen
            onToggled: { root.collectionsOpen = !root.collectionsOpen; root.setSection("collections", root.collectionsOpen) }
            IconButton { objectName: "panelNewCollection"; icon.name: "add"; description: "New collection"; width: 22; height: 22; glyphSize: Theme.fontBody; onClicked: nameDialog.begin("new", "", "") }
        }
        ListView {
            id: shelf
            objectName: "panelCollections"
            visible: root.collectionsOpen
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, root.height * .35)
            clip: true
            interactive: contentHeight > height
            model: root.shelfRows
            delegate: ItemDelegate {
                id: shelfRow
                required property var modelData
                readonly property string collectionId: modelData.id
                objectName: "panelCollection-" + modelData.name
                width: ListView.view.width
                height: Theme.rowHeight
                leftPadding: 38 + 12 * (modelData.depth || 0)
                rightPadding: 34
                text: modelData.name
                readonly property bool tabOver: !!root.documents && !!root.documents.dropTarget && root.documents.dropTarget.handler === root && root.documents.dropTarget.collection === collectionId
                highlighted: tabOver || drop.containsDrag || root.shows({collection: modelData.id})
                // Its papers in the Library tab; unfolded to its sub-collections (chosen again, folded).
                onClicked: root.chooseCollection(modelData)
                Icon {
                    visible: shelfRow.modelData.hasChildren
                    x: 6 + 12 * (shelfRow.modelData.depth || 0); anchors.verticalCenter: parent.verticalCenter
                    name: shelfRow.modelData.open ? "down" : "right"; size: Theme.fontSmall
                    color: shelfRow.highlighted ? Theme.selectedText : Theme.textTertiary
                }
                // The chevron alone folds and unfolds, without showing the collection.
                MouseArea {
                    objectName: "panelCollectionFold-" + shelfRow.modelData.name
                    visible: shelfRow.modelData.hasChildren
                    x: 12 * (shelfRow.modelData.depth || 0); width: 20; height: parent.height
                    onClicked: root.setCollectionOpen(shelfRow.modelData.id, !shelfRow.modelData.open)
                }
                Icon { x: 20 + 12 * (shelfRow.modelData.depth || 0); anchors.verticalCenter: parent.verticalCenter; name: "folder"; size: Theme.fontBody; color: shelfRow.highlighted ? Theme.selectedText : Theme.textTertiary }
                Label { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: shelfRow.modelData.count || 0; font.pixelSize: Theme.fontCaption; color: Theme.textTertiary }
                // Papers dragged from the Library list are filed here too.
                DropArea {
                    id: drop
                    anchors.fill: parent
                    keys: ["owelk/paper", "text/uri-list"]
                    // A Library paper is filed here; PDF files (or folders of them) from the desktop join the
                    // Library like any added PDF (moving into the PDF folder) and are filed.
                    onDropped: function(event) {
                        if (event.source && event.source.paperUrls) researchStore.setDocumentsCollection(event.source.paperUrls, shelfRow.collectionId, true)
                        else root.addPdfs(event.urls.filter(function(u) { return /\.pdf$/i.test(u.toString()) || researchStore.isFolder(u) }), {collection: shelfRow.collectionId})
                    }
                }
                TapHandler { acceptedButtons: Qt.RightButton; onTapped: { shelfMenu.collection = shelfRow.modelData; shelfMenu.popup() } }
            }
        }
        Label {
            visible: root.collectionsOpen && !shelf.count
            Layout.fillWidth: true; leftPadding: 8; wrapMode: Text.Wrap
            text: "Create collections in the Library to file papers by topic."
            font.pixelSize: Theme.fontCaption; color: Theme.textTertiary
        }
        // --- Tags -----------------------------------------------------------------------------
        SectionHeader {
            title: "Tags"; open: root.tagsOpen
            visible: root.tags.length > 0
            onToggled: { root.tagsOpen = !root.tagsOpen; root.setSection("tags", root.tagsOpen) }
        }
        Flow {
            visible: root.tagsOpen && root.tags.length > 0
            Layout.fillWidth: true; Layout.leftMargin: 6; Layout.bottomMargin: 4
            spacing: 4
            Repeater {
                model: root.tagsOpen ? root.tags : []
                delegate: Chip {
                    required property var modelData
                    objectName: "panelTag-" + modelData.name
                    text: "# " + modelData.name
                    checked: root.shows({tag: modelData.id})
                    onClicked: root.show({tag: modelData.id})
                }
            }
        }
        // --- Notes ----------------------------------------------------------------------------
        SectionHeader {
            objectName: "notesSection"
            title: "Notes"; open: root.notesOpen
            onToggled: { root.notesOpen = !root.notesOpen; root.setSection("notes", root.notesOpen) }
            IconButton { objectName: "panelNewNote"; icon.name: "add"; description: "New note"; width: 22; height: 22; glyphSize: Theme.fontBody; onClicked: root.newNoteRequested() }
        }
        Repeater {
            model: root.notesOpen ? root.notes : []
            delegate: NavigatorRow {
                required property var modelData
                required property int index
                objectName: "panelNote-" + index
                glyph: "note"; text: modelData.title
                onClicked: root.noteChosen(modelData.id)
            }
        }
        NavigatorRow {
            objectName: "panelAllNotes"
            visible: root.notesOpen
            glyph: "more"; text: root.notes.length ? "All Notes" : "No notes yet"
            enabled: root.notes.length > 0
            onClicked: root.libraryFilterRequested({view: "notes"})
        }
        // --- Folder ---------------------------------------------------------------------------
        SectionHeader {
            title: root.folder.toString().length ? "Folder · " + researchStore.fileName(root.folder) : "Recent files"
            open: root.folderOpen
            onToggled: { root.folderOpen = !root.folderOpen; root.setSection("folder", root.folderOpen) }
            IconButton { icon.name: "open"; description: "Open a folder…"; width: 22; height: 22; glyphSize: Theme.fontBody; onClicked: folderDialog.open() }
            IconButton { icon.name: "reload"; description: "Refresh folder"; width: 22; height: 22; glyphSize: Theme.fontBody; enabled: root.folder.toString().length > 0; onClicked: root.refresh() }
        }
        Label { Layout.fillWidth: true; visible: root.folderOpen && root.status.length > 0; text: root.status; wrapMode: Text.Wrap; color: Theme.textTertiary }
        Item { Layout.fillHeight: true; visible: !root.folderOpen }
        ListView {
            objectName: "folderTree"
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.folderOpen && root.folder.toString().length > 0
            model: rows
            clip: true
            ScrollBar.vertical: ScrollBar {}
            delegate: ItemDelegate {
                id: fileRow
                required property int index
                required property string name
                required property string url
                required property bool directory
                required property bool expanded
                required property bool loading
                required property int depth
                width: ListView.view.width
                height: Theme.rowHeight
                // A chevron for folders, a document glyph for PDFs.
                leftPadding: 26 + depth * 14
                text: name
                onClicked: root.toggle(index)
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.RightButton; onClicked: { fileMenu.row = {url: fileRow.url, directory: fileRow.directory, index: fileRow.index}; fileMenu.popup() } }
                Icon {
                    x: 6 + fileRow.depth * 14; anchors.verticalCenter: parent.verticalCenter
                    name: fileRow.loading ? "reload" : fileRow.directory ? (fileRow.expanded ? "down" : "right") : "document"
                    size: Theme.fontBody
                    color: Theme.textTertiary
                }
                ToolTip.visible: hovered
                ToolTip.delay: 500
                ToolTip.text: researchStore.localPath(url)
            }
        }
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.folderOpen && !root.folder.toString().length
            model: researchStore.recentDocuments
            clip: true
            ScrollBar.vertical: ScrollBar {}
            delegate: RecentPaperDelegate {
                width: ListView.view.width
                height: Theme.rowHeight
                onDocumentChosen: function(source, position) { root.documentChosen(source) }
                onMenuRequested: function(row) { recentMenu.show(row) }
            }
        }
    }
    PaperMenu {
        id: recentMenu
        recent: true
        onOpenRequested: function(source, position) { root.documentChosen(source) }
    }
    Menu {
        id: fileMenu
        objectName: "fileMenu"
        property var row: ({})
        readonly property string path: row.url ? researchStore.localPath(row.url) : ""
        MenuItem { text: fileMenu.row.directory ? "Expand or Collapse" : "Open"; onTriggered: root.toggle(fileMenu.row.index) }
        MenuSeparator {}
        MenuItem { text: "Copy Path"; onTriggered: researchStore.copyText(fileMenu.path) }
        MenuItem {
            text: Qt.platform.os === "osx" ? "Show in Finder" : "Show in Folder"
            onTriggered: Qt.openUrlExternally(fileMenu.row.directory ? fileMenu.row.url : researchStore.fileUrl(fileMenu.path.substring(0, fileMenu.path.lastIndexOf("/"))))
        }
    }
}
