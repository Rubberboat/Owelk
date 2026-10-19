import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs as Native
import Owelk.Ui
import "Platform.js" as Platform
import "Shortcuts.js" as Shortcuts
import "WorkspaceTree.js" as Tree

ApplicationWindow {
    id: window
    objectName: "mainWindow"
    visible: true
    width: 1440; height: 930
    minimumWidth: 880; minimumHeight: 580
    title: ""
    color: Theme.window
    // The platform UI font (San Francisco, Segoe UI, the desktop font on Linux).
    font.pixelSize: Theme.fontBody
    palette.window: Theme.sidebar
    palette.windowText: Theme.text
    palette.highlight: Theme.accent
    palette.highlightedText: Theme.onAccent
    palette.button: Theme.control
    palette.buttonText: Theme.text
    palette.text: Theme.text
    palette.base: Theme.content
    palette.alternateBase: Theme.window
    // Rich and Markdown text links (notes, AI answers) use the accent, not default blue.
    palette.link: Theme.accent
    palette.linkVisited: Theme.accent
    palette.light: Theme.content
    palette.midlight: Theme.window
    palette.mid: Theme.border
    palette.dark: Theme.textTertiary
    palette.shadow: Theme.shadow
    palette.placeholderText: Theme.textTertiary
    palette.toolTipBase: Theme.raised
    palette.toolTipText: Theme.text
    palette.brightText: Theme.onAccent
    // Vertical tabs (Settings → Appearance): the list beside the window is open or a thin rail.
    // Hide chrome without changing the saved panel layout; toggling off restores it exactly.
    property alias readingFocus: focusController.active
    readonly property bool focusedReading: readingFocus && !homeVisible
    function toggleReadingFocus() { if (!homeVisible && !restoreFailed) readingFocus = !readingFocus }
    ReadingFocus {
        id: focusController
        targetWindow: window
        useFullScreen: researchStore.setting("reading.focusFullscreen", "1") === "1"
        Connections {
            target: researchStore
            function onSettingsChanged() { focusController.useFullScreen = researchStore.setting("reading.focusFullscreen", "1") === "1" }
        }
    }
    ReadingFocusBar {
        parent: window.contentItem
        z: 90
        width: parent.width
        active: window.focusedReading
        shortcut: Platform.keys(window.keys("readingFocus"))
        canSwitchTabs: window.canSwitchTabs
        canGoBack: window.canGoBack
        canGoForward: window.canGoForward
        tabs: {
            const revision = documents.revision
            const rows = []
            Tree.leaves(documents.tree).forEach(function(group) {
                group.tabs.forEach(function(tab) {
                    rows.push({id: tab.id, title: Tree.tabTitle(tab, function(source) { return researchStore.displayName(source) }),
                        current: group.id === documents.activeGroup && group.activeTab === tab.id})
                })
            })
            return rows
        }
        title: { const tab = tabs.find(function(t) { return t.current }); return tab ? tab.title : "Open tabs" }
        onExitRequested: window.readingFocus = false
        onTabRequested: function(id) { if (window.canSwitchTabs) documents.activateTab(id) }
        onPanelRequested: function(panel) { window.togglePanel(panel) }
        onBackRequested: window.goBack()
        onForwardRequested: window.goForward()
        onSearchRequested: { commandPalette.close(); searchPalette.open() }
    }
    // The upstream shortcut, alongside the existing customizable F8 default.
    Shortcut {
        sequence: "Ctrl+Shift+F"
        enabled: window.keys("readingFocus") === "F8" && !Object.keys(window.shortcutOverrides).some(function(k) { return window.shortcutOverrides[k] === "Ctrl+Shift+F" })
        onActivated: window.toggleReadingFocus()
    }
    property bool tabsPanelOpen: researchStore.setting("tabs.panelOpen", "1") === "1"
    function setTabsPanel(open) { tabsPanelOpen = open; researchStore.setSetting("tabs.panelOpen", open ? "1" : "0") }
    property bool filesVisible: true
    property string filesSide: "left"
    property bool documentVisible: false
    property string documentSide: "left"
    property bool aiVisible: false
    property string aiSide: "right"
    property real leftDockWidth: 224
    property real rightDockWidth: 224
    function dockWidth(value) { return Math.max(160, Math.min(value, 560, (width - 360) / 2)) }
    property int navigationMode: 0
    property url paperFolder
    property bool homeVisible: true
    readonly property var leftPanels: panelsForSide("left")
    readonly property var rightPanels: panelsForSide("right")
    property bool initialized: false
    property bool restoreFailed: false
    property string notification: ""
    property alias documents: documents
    readonly property var currentReader: documents.currentReader
    readonly property bool canPrint: !homeVisible && !restoreFailed && !!currentReader
                                    && currentReader.isActive && currentReader.canPrint
    // Shortcuts the reader changed in Settings (id → keys; "" turns one off).
    property var shortcutOverrides: Shortcuts.parse(researchStore.setting("shortcuts"))
    function keys(id) { return Shortcuts.keys(id, shortcutOverrides, Qt.platform.os) }
    Connections { target: researchStore; function onSettingsChanged() { window.shortcutOverrides = Shortcuts.parse(researchStore.setting("shortcuts")) } }

    function panelsForSide(side) {
        const panels = []
        if (filesVisible && filesSide === side) panels.push("files")
        if (documentVisible && documentSide === side) panels.push("document")
        if (aiVisible && aiSide === side) panels.push("ai")
        return panels
    }
    readonly property var dockPanels: ["files", "document", "ai"]
    function panelSide(panel) { return panel === "files" ? filesSide : panel === "ai" ? aiSide : documentSide }
    function panelShown(panel) { return panel === "files" ? filesVisible : panel === "ai" ? aiVisible : documentVisible }
    function panelName(panel) { return panel === "files" ? "Library" : panel === "ai" ? "AI threads" : "Document: contents, annotations, symbols and related papers" }
    function setPanelShown(panel, shown) {
        if (panel === "files") filesVisible = shown
        else if (panel === "ai") aiVisible = shown
        else documentVisible = shown
    }
    // One panel per dock: opening one (or moving it into a dock) closes the other there.
    function closeOthers(panel) {
        const side = panelSide(panel)
        dockPanels.forEach(function(other) { if (other !== panel && panelShown(other) && panelSide(other) === side) setPanelShown(other, false) })
    }
    // Reader actions bring the AI panel forward and start a thread there.
    function showAi() { readingFocus = false; setPanelShown("ai", true); closeOthers("ai") }
    function askAi(spec) { showAi(); aiController.begin(spec) }
    // Ask AI (shortcut): about the selection in the paper in front, or a new chat about that paper.
    function askAiNow() {
        if (!homeVisible && currentReader && currentReader.selectedText.length) { currentReader.askAboutSelection(); return }
        showAi()
        aiController.newThread()
    }
    function openAiThread(id) { if (aiController.openThread(id)) showAi() }
    // A For You paper's page (no PDF to fetch, or one that did not come), in a web tab of its own.
    // A page from Settings (signing in to Google): Settings closes and it opens in a web tab of its own.
    function openWebPage(address) {
        if (window.restoreFailed || !address || !address.toString().length) return
        settingsDialog.close()
        homeVisible = false
        documents.openWeb(address.toString(), true)
    }
    function openForYouPage(address) {
        if (window.restoreFailed || !address || !address.toString().length) return
        homeVisible = false
        documents.openWeb(address, true, "", true)
    }
    Connections { target: researchStore.forYou; function onWebRequested(address) { window.openForYouPage(address) } }
    // The Document panel's Annotations view (the reader toolbar button opens and closes it).
    function toggleAnnotations() {
        const wasFocused = focusedReading
        readingFocus = false
        if (!wasFocused && documentVisible && navigationMode === 1) { documentVisible = false; return }
        navigationMode = 1
        setPanelShown("document", true); closeOthers("document")
    }
    // The AI panel shows this thread right now (panel open and in front in its dock).
    function aiThreadInView(id) {
        const dock = aiSide === "left" ? leftDock : rightDock
        return !focusedReading && aiVisible && dock.activePanel === "ai" && aiController.conversationOpen && aiController.threadId === id
    }
    function togglePanel(panel) {
        const wasFocused = focusedReading
        readingFocus = false
        const shown = panelShown(panel)
        setPanelShown(panel, wasFocused || !shown)
        if (wasFocused || !shown) closeOthers(panel)
    }
    function movePanel(panel, side) {
        if (side !== "left" && side !== "right") return
        if (panel === "files") filesSide = side
        if (panel === "document") documentSide = side
        if (panel === "ai") aiSide = side
        if (panelShown(panel)) closeOthers(panel)
    }
    // Tab switching must not discard an annotation that is still being edited.
    readonly property bool canSwitchTabs: documents.hasTabs && !restoreFailed && !(currentReader && currentReader.annotationDirty)
    // Browser conventions alongside the menu shortcuts: Cmd+Shift+] / [, Control+Tab, Cmd+1…9 (9 = last tab).
    Shortcut {
        sequence: "Ctrl+Shift+]"
        enabled: window.canSwitchTabs
        onActivated: documents.cycleTab(1)
    }
    Shortcut {
        sequence: "Ctrl+Shift+["
        enabled: window.canSwitchTabs
        onActivated: documents.cycleTab(-1)
    }
    // Control+Tab: the next tab, or back and forth between the last two (Settings › Appearance › Tabs).
    function controlTab(step) {
        if (researchStore.setting("tabs.controlTab", "next") === "recent" && documents.switchToPreviousTab()) return
        documents.cycleTab(step)
    }
    Shortcut {
        sequence: Qt.platform.os === "osx" ? "Meta+Tab" : "Ctrl+Tab"
        enabled: window.canSwitchTabs
        onActivated: window.controlTab(1)
        onActivatedAmbiguously: window.controlTab(1)
    }
    Shortcut {
        sequence: Qt.platform.os === "osx" ? "Meta+Shift+Tab" : "Ctrl+Shift+Tab"
        enabled: window.canSwitchTabs
        onActivated: window.controlTab(-1)
        onActivatedAmbiguously: window.controlTab(-1)
    }
    Instantiator {
        model: 9
        delegate: Shortcut {
            required property int index
            sequence: "Ctrl+" + (index + 1)
            enabled: window.canSwitchTabs
            onActivated: documents.selectTabAt(index === 8 ? -1 : index)
        }
    }
    // Cmd/Ctrl+W, as in browsers: the tab in front; Home shown over open tabs goes back to them;
    // with nothing left to close, the window itself.
    function closeTabOrWindow() {
        if (!documents.hasTabs || restoreFailed) window.close()
        else if (homeVisible) homeVisible = false
        else documents.closeActiveTab()
    }
    // Owelk's window in front (from Finder, another launch, the desktop pet).
    function comeForward() {
        if (!window.visible) window.show()
        else if (window.visibility === Window.Minimized) window.showNormal()
        window.raise(); window.requestActivate()
    }
    function showHome() { persist(); homeVisible = true; Qt.callLater(function() { homeView.focusSearch() }) }
    // Cmd+L: the address bar of the current web tab, or a new web tab when a paper or Home is in front.
    function openWebAddress() {
        if (restoreFailed) return
        const view = documents.groupView(documents.activeGroup)
        if (!homeVisible && view && view.isWeb && view.webPane) { view.webPane.focusAddress(); return }
        const start = researchStore.setting("startPage")
        if (documents.openWeb(start.length ? start : "https://scholar.google.com/", true))
            Qt.callLater(function() { const next = documents.groupView(documents.activeGroup); if (next) next.focusAddress() })
    }
    function findInView() {
        if (homeVisible) homeView.focusSearch()
        else if (currentReader) currentReader.find()
        else { const view = documents.groupView(documents.activeGroup); if (view) view.focusHome() }
    }
    // Where one has been, as a browser keeps it: Home, or a tab (Library, a paper, a note, a web page).
    // Back and forward step through these places once the tab in front has none of its own to go through.
    property var places: []
    property int placeIndex: -1
    property bool replaying: false
    function placeKey() { return homeVisible || !documents.currentTab.length ? "home" : "tab:" + documents.currentTab }
    function recordPlace() {
        if (!initialized || replaying || restoreFailed) return
        const key = placeKey()
        if (places[placeIndex] === key) return
        places = places.slice(0, placeIndex + 1).concat([key]).slice(-60)
        placeIndex = places.length - 1
    }
    onHomeVisibleChanged: { if (homeVisible) readingFocus = false; Qt.callLater(recordPlace) }
    Connections { target: documents; function onCurrentTabChanged() { Qt.callLater(window.recordPlace) } }
    function placeExists(key) { return key === "home" || Tree.leaves(documents.tree).some(function(g) { return g.tabs.some(function(t) { return "tab:" + t.id === key }) }) }
    function placeStep(step) {
        let at = placeIndex + step
        while (at >= 0 && at < places.length && (!placeExists(places[at]) || places[at] === placeKey())) at += step
        return at >= 0 && at < places.length ? at : -1
    }
    readonly property bool canGoBackPlace: (places, placeIndex, documents.tree, documents.currentTab, homeVisible, placeStep(-1) >= 0)
    readonly property bool canGoForwardPlace: (places, placeIndex, documents.tree, documents.currentTab, homeVisible, placeStep(1) >= 0)
    function goToPlace(step) {
        const at = placeStep(step)
        if (at < 0) return false
        replaying = true
        placeIndex = at
        const key = places[at]
        if (key === "home") showHome()
        else { homeVisible = false; documents.activateTab(key.slice(4)) }
        Qt.callLater(function() { window.replaying = false })
        return true
    }
    // Back and forward in what is in front first: a web tab's pages, or the reader's jumps (links, citations).
    readonly property var frontWeb: {
        const view = (documents.tree, documents.activeGroup, documents.revision, documents.groupView(documents.activeGroup))
        return !homeVisible && view && view.isWeb ? view.webPane : null
    }
    readonly property bool tabCanGoBack: frontWeb ? frontWeb.view.canGoBack : !homeVisible && !!currentReader && currentReader.canGoBack
    readonly property bool tabCanGoForward: frontWeb ? frontWeb.view.canGoForward : !homeVisible && !!currentReader && currentReader.canGoForward
    readonly property bool canGoBack: tabCanGoBack || canGoBackPlace
    readonly property bool canGoForward: tabCanGoForward || canGoForwardPlace
    function goBack() {
        if (frontWeb && frontWeb.view.canGoBack) frontWeb.view.goBack()
        else if (!frontWeb && !homeVisible && currentReader && currentReader.canGoBack) currentReader.goBack()
        else goToPlace(-1)
    }
    function goForward() {
        if (frontWeb && frontWeb.view.canGoForward) frontWeb.view.goForward()
        else if (!frontWeb && !homeVisible && currentReader && currentReader.canGoForward) currentReader.goForward()
        else goToPlace(1)
    }
    function openDocument(source, position) { if (!restoreFailed) documents.openDocument(researchStore.resolvedSource(source), position) }
    // Files dropped on the window where no panel takes them (from Finder, the Downloads folder or a
    // browser's download list): PDFs, and the PDFs in a dropped folder, move into the PDF folder and
    // join the Library (addPdfs), and up to dropOpenLimit of them open in tabs; web addresses open in
    // web tabs. False when the drop held none of these.
    readonly property int dropOpenLimit: 6
    function dropFiles(urls) {
        if (restoreFailed) return false
        const drop = Tree.droppedFiles(urls, function(url) { return researchStore.isFolder(url) })
        if (drop.pdfs.length || drop.folders.length) addPdfs(drop.pdfs.concat(drop.folders), {open: true})
        else if (drop.web.length) {
            drop.web.slice(0, dropOpenLimit).forEach(function(url) { documents.openWeb(url) })
            homeVisible = false
        }
        return drop.pdfs.length + drop.folders.length + drop.web.length > 0
    }
    // Adding PDFs, however they come (dropped anywhere, + › Add PDFs… or Add Folder…): each is looked at
    // first, and a paper the Library already has is offered (DuplicateDialog) instead of a second copy.
    // options: collection, foldersAsCollections, open (open what was added, up to dropOpenLimit).
    property var intakes: ({})
    function addPdfs(urls, options) {
        if (restoreFailed || !urls.length) return -1
        const request = researchStore.inspectPdfs(urls)
        intakes[request] = {kind: "add", options: options || {}}
        return request
    }
    // A finished PDF download, before it opens: done(file) with the file to read, the download itself
    // or, when the reader prefers it, the copy of that paper already kept.
    function checkDownload(file, done) {
        const request = researchStore.inspectPdfs([file])
        intakes[request] = {kind: "download", file: file, done: done}
        return request
    }
    function openPapers(urls) {
        urls.slice(0, dropOpenLimit).forEach(function(url) { window.openDocument(url) })
        if (urls.length) homeVisible = false
    }
    function quoted(items) {
        const names = items.slice(0, 3).map(function(item) { return "\u201c" + item.existingName + "\u201d" })
        return names.join(", ") + (items.length > 3 ? " and " + (items.length - 3) + " more" : "")
    }
    function pdfsInspected(request, items) {
        const intake = intakes[request]
        if (!intake) return
        delete intakes[request]
        const duplicates = items.filter(function(item) { return item.duplicate })
        if (intake.kind === "download") {
            if (!duplicates.length) { intake.done(intake.file); return }
            duplicateDialog.show(duplicates, true, function() {
                researchStore.discardDownload(intake.file)
                intake.done(duplicates[0].existing)
                notify("Opened " + quoted(duplicates) + ", which you already had. The new download went to the Trash.")
            }, function() {
                researchStore.takePdfs([Object.assign({}, duplicates[0], {source: intake.file, separate: true})])
                intake.done(intake.file)
            }, null)
            return
        }
        const options = intake.options
        const fresh = items.filter(function(item) { return !item.duplicate })
        const take = function(list) {
            if (!list.length) return []
            const added = researchStore.takePdfs(list, {collection: options.collection || "",
                                                       foldersAsCollections: !!options.foldersAsCollections})
            if (options.open && added.length <= dropOpenLimit) openPapers(added)
            return added
        }
        if (!items.length) { notify("No PDFs there."); return }
        if (!duplicates.length) { take(fresh); return }
        duplicateDialog.show(duplicates, false, function() {
            take(fresh)
            openPapers(duplicates.map(function(item) { return item.existing }))
            notify("Opened " + quoted(duplicates) + " from your Library; " + (duplicates.length === 1 ? "that file stays" : "those files stay") + " where " + (duplicates.length === 1 ? "it was." : "they were."))
        }, function() {
            take(fresh.concat(duplicates.map(function(item) { return Object.assign({}, item, {separate: true}) })))
        }, function() { take(fresh) })
    }
    Connections { target: researchStore; function onPdfsInspected(request, items) { window.pdfsInspected(request, items) } }
    DuplicateDialog { id: duplicateDialog }
    function droppable(urls) {
        const drop = Tree.droppedFiles(urls, function(url) { return researchStore.isFolder(url) })
        return drop.pdfs.length + drop.folders.length + drop.web.length > 0
    }
    function openSearchResult(result) {
        if (result.kind === "paper") openDocument(result.source, result.position)
        else if (result.kind === "highlight") researchStore.openHighlight(result.id)
        else if (result.kind === "note" && !restoreFailed) documents.openNote(result.id)
        else if (result.kind === "ai") openAiThread(result.id)
        else if (result.kind === "web" && !restoreFailed) { documents.openWeb(result.url, true); homeVisible = false }
        else if (result.kind === "collection" && !restoreFailed) documents.openLibrary({collection: result.id})
        else if (result.kind === "tag" && !restoreFailed) documents.openLibrary({tag: result.id})
        else if (result.kind === "text" && !restoreFailed) { notify("Checking PDF source…"); researchStore.paperIndex.openResult(result.documentId, Number(result.page), result.sha256) }
    }
    function persist() {
        if (!initialized || restoreFailed) return false
        const state = documents.snapshot()
        Object.assign(state, {width: focusController.sessionWidth, height: focusController.sessionHeight, panels: {filesVisible: filesVisible, filesSide: filesSide,
                documentVisible: documentVisible, documentSide: documentSide, aiVisible: aiVisible, aiSide: aiSide, navigationMode: navigationMode,
                folder: paperFolder.toString(), leftActive: leftDock.activePanel, rightActive: rightDock.activePanel,
                leftWidth: leftDockWidth, rightWidth: rightDockWidth}})
        return researchStore.saveSession(state)
    }
    // Long work in progress, for the status bar: the store's tasks (looking at and copying PDFs, downloads) and
    // what reports its own progress (text and meaning indexing, sync, backup). total 0: no measure.
    readonly property var activities: {
        const list = researchStore.tasks.slice()
        const counted = function(id, label) {
            const m = /(\d+)\s*\/\s*(\d+)/.exec(label || "")
            return {id: id, label: label, done: m ? Number(m[1]) : 0, total: m ? Number(m[2]) : 0}
        }
        const index = researchStore.paperIndex, meaning = researchStore.semantic, sync = researchStore.sync
        if (index.busy && !index.paused && index.progress.length) list.push(counted("index", index.progress))
        if (meaning.busy && meaning.progress.length) list.push(counted("meaning", meaning.progress))
        if (sync.running) list.push({id: "sync", label: "Syncing…", done: 0, total: 0})
        if (researchStore.backingUp) list.push({id: "backup", label: "Backing up…", done: 0, total: 0})
        return list
    }
    function scheduleSave() { if (initialized && !restoreFailed) saveTimer.restart() }
    function notify(text) { notification = text; notificationTimer.restart() }
    function chooseFile() { if (!restoreFailed && !(currentReader && currentReader.annotationDirty)) fileDialog.open() }

    Component.onCompleted: {
        // The system title bar follows the theme (Settings › Appearance).
        Theme.styleWindow(window)
        const state = researchStore.session
        if (state.width) width = Math.max(minimumWidth, Math.min(Screen.width, state.width))
        if (state.height) height = Math.max(minimumHeight, Math.min(Screen.height, state.height))
        const panels = state.panels || {}
        leftDockWidth = Number(panels.leftWidth) || 224
        rightDockWidth = Number(panels.rightWidth) || 224
        filesVisible = panels.filesVisible === undefined ? true : panels.filesVisible
        filesSide = panels.filesSide === "right" ? "right" : "left"
        documentVisible = !!panels.documentVisible
        documentSide = panels.documentSide === "right" ? "right" : "left"
        aiVisible = !!panels.aiVisible
        aiSide = panels.aiSide === "left" ? "left" : "right"
        navigationMode = [0, 1, 2, 3].indexOf(panels.navigationMode) >= 0 ? panels.navigationMode : 0
        paperFolder = panels.folder || ""
        // Sessions from when a dock held several panels keep the one in front.
        for (const side of ["left", "right"]) {
            const list = panelsForSide(side), front = side === "left" ? panels.leftActive : panels.rightActive
            if (list.length > 1) closeOthers(list.indexOf(front) >= 0 ? front : list[0])
        }
        // Tabs that cannot be reopened are left out and the rest open; when none can be read, Owelk starts
        // with no tabs. Either way the saved tabs are kept as they were (one copy) and a notice says so. Only
        // tabs saved by a newer Owelk stop it: they must not be overwritten.
        try {
            const dropped = documents.restore(state)
            if (dropped > 0) {
                researchStore.keepUnrestoredSession()
                restoreNotice.show(dropped === 1 ? "1 saved tab could not be reopened and was left out." : dropped + " saved tabs could not be reopened and were left out.")
            }
        } catch (error) {
            if (error.newer) {
                restoreFailed = true; notification = error.message
                restoreNotice.show(error.message)
            } else {
                researchStore.keepUnrestoredSession()
                documents.restore({})
                restoreNotice.show("The saved tabs could not be reopened, so Owelk started without them.")
            }
        }
        initialized = true
        Qt.callLater(recordPlace)
        // Files from the command line, Finder or a second launch made before the window was ready.
        const external = initialFiles.concat(typeof appInstance !== "undefined" ? appInstance.takePending() : [])
        if (!restoreFailed) for (let i = 0; i < external.length; ++i) documents.openDocument(external[i])
        // Home, unless the reader chose to come back to the last tabs (Settings › Appearance) and there are some.
        homeVisible = restoreFailed || (external.length === 0 && !(researchStore.setting("startup.view", "home") === "tabs" && documents.hasTabs))
        if (!restoreFailed) persist()
        // After a restore or an unexpected exit, say what happened.
        if (!restoreFailed && researchStore.startupMessage.length) notify(researchStore.startupMessage)
        else if (!restoreFailed && researchStore.recoveredFromCrash) notify("Owelk closed unexpectedly last time. Your tabs are back; unsaved notes are offered when you reopen them.")
    }
    // The desktop pet (Settings › Appearance › Desktop pet), only while it is on.
    Loader {
        objectName: "petLoader"
        active: DesktopPet.enabled && DesktopPet.supported
        sourceComponent: PetWindow {
            ai: researchStore.ai
            forYou: researchStore.forYou
            reading: Qt.application.state === Qt.ApplicationActive && !window.homeVisible
            onOpenRequested: window.comeForward()
            onThreadRequested: function(threadId) { window.comeForward(); window.openAiThread(threadId) }
            onForYouRequested: { window.comeForward(); window.showHome() }
            onPdfsDropped: function(urls) {
                window.comeForward()
                if (window.restoreFailed) return
                urls.forEach(function(url) { window.openDocument(url) })
                window.homeVisible = false
            }
            // Data for the AI, not interface text: the label is kept with the conversation like "Ask".
            onExplainRequested: function(text) { window.comeForward(); window.askAi({action: "explain", selection: text, label: "Explain"}) }
        }
    }
    // PDFs opened from Finder or handed over by another launch while this window is open.
    Connections {
        target: typeof appInstance !== "undefined" ? appInstance : null
        function onFilesRequested(urls) {
            window.comeForward()
            if (window.restoreFailed || !urls.length) return
            urls.forEach(function(url) { window.openDocument(url) })
            window.homeVisible = false
        }
    }
    // Logging out or quitting from the dock can skip the window's close handler.
    Connections { target: Qt.application; function onAboutToQuit() { window.persist() } }
    onClosing: function(close) {
        if (researchStore.printing) { close.accepted = false; notify("Finish or cancel printing before closing the window."); return }
        if (window.currentReader && window.currentReader.annotationDirty) { close.accepted = false; notify("Save or discard annotation edits before closing the window."); return }
        if (researchStore.busy) { close.accepted = false; notify("Saving. Please close the window after saving finishes.") }
        else if (initialized && !restoreFailed && !persist()) { close.accepted = false; notify("Cannot save the session. Check storage and try again.") }
        // Closing Owelk's window ends Owelk, desktop pet and all (the pet's own windows would keep it running).
        if (close.accepted) Qt.callLater(Qt.quit)
    }
    onWidthChanged: scheduleSave()
    onHeightChanged: scheduleSave()
    onFilesVisibleChanged: scheduleSave()
    onFilesSideChanged: scheduleSave()
    onDocumentSideChanged: scheduleSave()
    onDocumentVisibleChanged: scheduleSave()
    onNavigationModeChanged: scheduleSave()
    onPaperFolderChanged: scheduleSave()
    onLeftDockWidthChanged: scheduleSave()
    onRightDockWidthChanged: scheduleSave()
    Timer { id: saveTimer; interval: 500; onTriggered: window.persist() }
    Timer { id: notificationTimer; interval: 6500; onTriggered: if (!window.restoreFailed) window.notification = "" }
    Native.FileDialog { id: fileDialog; title: "Open PDF"; nameFilters: ["PDF documents (*.pdf)"]; onAccepted: window.openDocument(selectedFile) }
    Connections {
        target: researchStore
        function onMessage(text) { window.notify(text) }
        function onDuplicateFound(source, existing, title) { duplicateBar.show(source, existing, title) }
        function onRelinkRequested(source) { if (!window.restoreFailed && !researchStore.relinking && window.persist()) relinkDialog.begin(source) }
        function onSourceRelinked(source, candidate) { documents.relinkSource(source, candidate) }
        function onPapersDeleted(sources) { documents.closeSources(sources) }
        function onRelinkFinished(success, detail) { if (success) window.notify(detail) }
        function onSourceReady(url, page, region) { if (!window.restoreFailed) { documents.reveal(url, page, region); window.homeVisible = false } }
        function onPassageReady(url, page, region) { if (!window.restoreFailed) { documents.reveal(url, page, region, true); window.homeVisible = false } }
    }
    Connections {
        target: researchStore.paperIndex
        function onResultReady(source, page) { if (!window.restoreFailed) documents.openAtPage(source, page) }
    }
    RelinkDialog { id: relinkDialog; parent: Overlay.overlay }
    CommandPalette {
        id: commandPalette
        parent: Overlay.overlay
        hasDocument: !window.homeVisible && !!window.currentReader && window.currentReader.pdfReady
        hasSelection: hasDocument && window.currentReader.selectedText.length > 0
        canReopenTab: documents.closedTabs.length > 0
        canCloseTab: !window.homeVisible && documents.hasTabs
        canPrint: window.canPrint
        onCommandChosen: function(command) {
            if (window.currentReader && window.currentReader.annotationDirty) { window.notify("Finish annotation editing first."); return }
            switch (command) {
            case "/home": window.showHome(); break
            case "/open paper": window.chooseFile(); break
            case "/find": window.findInView(); break
            case "/print": if (window.canPrint) window.currentReader.printAction.trigger(); break
            case "/split right": documents.duplicateSplit("right"); break
            case "/split down": documents.duplicateSplit("bottom"); break
            case "/split off": documents.joinAll(); break
            case "/web": window.openWebAddress(); break
            case "/library": documents.openLibrary({}); break
            case "/new note": documents.newNote(); break
            case "/settings": settingsDialog.open(); break
            case "/organize tabs": window.organizeTabsIn(""); break
            case "/ask library": window.askAi({action: "ask", scope: "library"}); break
            case "/move right": documents.moveActiveTabToSplit("right"); break
            case "/move down": documents.moveActiveTabToSplit("bottom"); break
            case "/next split": documents.focusGroup(1); break
            case "/previous split": documents.focusGroup(-1); break
            case "/mark region": if (!window.homeVisible && window.currentReader) window.currentReader.setTool("area"); break
            case "/highlight": if (!window.homeVisible && window.currentReader) window.currentReader.highlightSelection(); break
            case "/files": window.togglePanel("files"); break
            case "/document": window.togglePanel("document"); break
            case "/annotations": window.toggleAnnotations(); break
            case "/paper note": if (window.currentReader) documents.newNoteFor(window.currentReader.source); break
            case "/close tab": documents.closeActiveTab(); break
            case "/new tab": if (!window.restoreFailed) documents.newHomeTab(); break
            case "/reopen tab": documents.reopenClosedTab(); break
            case "/fit width": if (window.currentReader) window.currentReader.fitWidth(); break
            case "/fit page": if (window.currentReader) window.currentReader.fitPage(); break
            case "/shortcuts": window.showShortcuts(); break
            }
        }
    }
    // Every keyboard shortcut on one sheet: ?, Ctrl/⌘+/, the ? in the status bar, Help, or /shortcuts.
    // Made the first time it is asked for.
    Loader {
        id: shortcutSheet
        objectName: "shortcutSheetLoader"
        active: false
        sourceComponent: ShortcutSheet {
            parent: Overlay.overlay
            overrides: window.shortcutOverrides
            onSettingsRequested: settingsDialog.openPage("shortcuts")
        }
    }
    function showShortcuts() { commandPalette.close(); searchPalette.close(); shortcutSheet.active = true; shortcutSheet.item.open() }
    // ? on its own (a text field being typed in keeps it).
    Shortcut { objectName: "shortcutSheetKey"; sequences: ["?", "Shift+?"]; onActivated: window.showShortcuts() }
    SearchPalette {
        currentSource: !window.homeVisible && window.currentReader ? window.currentReader.source : ""
        id: searchPalette
        parent: Overlay.overlay
        onResultChosen: function(result) { window.openSearchResult(result) }
    }
    menuBar: MenuBar {
        visible: Qt.platform.os === "osx" || !window.focusedReading
        Menu {
            title: "File"
            Action { text: "Open PDF…"; shortcut: StandardKey.Open; onTriggered: window.chooseFile() }
            MenuItem {
                objectName: "printMenuItem"
                text: "Print PDF…"
                action: window.canPrint ? window.currentReader.printAction : null
                enabled: window.canPrint
            }
            Action { objectName: "newNoteAction"; text: "New Note"; shortcut: window.keys("newNote"); enabled: !window.restoreFailed; onTriggered: documents.newNote() }
            Action { objectName: "openWebAction"; text: "Open Web Page…"; shortcut: window.keys("openWeb"); enabled: !window.restoreFailed; onTriggered: window.openWebAddress() }
            Action { objectName: "settingsAction"; text: "Settings…"; shortcut: Qt.platform.os === "osx" ? StandardKey.Preferences : "Ctrl+,"; onTriggered: settingsDialog.open() }
            Action { objectName: "newTabAction"; text: "New Tab"; shortcut: window.keys("newTab"); enabled: !window.restoreFailed && !(window.currentReader && window.currentReader.annotationDirty); onTriggered: documents.newHomeTab() }
            Action { objectName: "closeTabAction"; text: documents.hasTabs ? "Close Tab" : "Close Window"; shortcut: window.keys("closeTab"); enabled: !(!window.homeVisible && window.currentReader && window.currentReader.annotationDirty); onTriggered: window.closeTabOrWindow() }
            Action { text: "Reopen Closed Tab"; shortcut: window.keys("reopenTab"); enabled: documents.closedTabs.length > 0 && !window.restoreFailed; onTriggered: documents.reopenClosedTab() }
            Action { objectName: "nextTabAction"; text: "Next Tab"; shortcut: window.keys("nextTab"); enabled: window.canSwitchTabs; onTriggered: documents.cycleTab(1) }
            Action { objectName: "previousTabAction"; text: "Previous Tab"; shortcut: window.keys("previousTab"); enabled: window.canSwitchTabs; onTriggered: documents.cycleTab(-1) }
            MenuSeparator {}
            Action { text: "Quit"; shortcut: StandardKey.Quit; onTriggered: window.close() }
        }
        Menu {
            title: "View"
            Action { objectName: "readingFocusAction"; enabled: !window.homeVisible && !window.restoreFailed; text: window.readingFocus ? "Exit Reading Focus" : "Reading Focus"; shortcut: window.keys("readingFocus"); checkable: true; checked: window.readingFocus; onTriggered: window.toggleReadingFocus() }
            Action { text: "Home"; shortcut: window.keys("home"); onTriggered: window.showHome() }
            Action { objectName: "libraryAction"; text: "Library"; shortcut: window.keys("library"); enabled: !window.restoreFailed; onTriggered: documents.openLibrary({}) }
            Action { objectName: "tabsPanelAction"; text: window.tabsPanelOpen ? "Hide Vertical Tabs" : "Show Vertical Tabs"; shortcut: window.keys("tabsPanel"); enabled: Theme.verticalTabs; onTriggered: window.setTabsPanel(!window.tabsPanelOpen) }
            Action { text: "Search Research"; shortcut: window.keys("search"); onTriggered: { commandPalette.close(); searchPalette.open() } }
            Action { text: "Command Palette"; shortcut: window.keys("commands"); onTriggered: { searchPalette.close(); commandPalette.open() } }
            Action { text: "Find"; shortcut: StandardKey.Find; onTriggered: window.findInView() }
            Action { text: "Zoom in"; shortcut: StandardKey.ZoomIn; enabled: !window.homeVisible; onTriggered: if (window.currentReader) window.currentReader.zoom(1.2) }
            Action { text: "Zoom out"; shortcut: StandardKey.ZoomOut; enabled: !window.homeVisible; onTriggered: if (window.currentReader) window.currentReader.zoom(1 / 1.2) }
            // The same as the status bar's arrows: within the tab first (pages, jumps), then between places.
            Action { objectName: "jumpBackAction"; text: "Back"; shortcut: window.keys("jumpBack"); enabled: window.canGoBack; onTriggered: window.goBack() }
            Action { objectName: "jumpForwardAction"; text: "Forward"; shortcut: window.keys("jumpForward"); enabled: window.canGoForward; onTriggered: window.goForward() }
            Action { objectName: "fitWidthAction"; text: "Fit Width"; shortcut: window.keys("fitWidth"); enabled: !window.homeVisible; onTriggered: if (window.currentReader) window.currentReader.fitWidth() }
            Action { objectName: "fitPageAction"; text: "Fit Page"; shortcut: window.keys("fitPage"); enabled: !window.homeVisible; onTriggered: if (window.currentReader) window.currentReader.fitPage() }
            Action { objectName: "markRegionAction"; text: "Mark Region"; shortcut: window.keys("markRegion"); enabled: !window.homeVisible; onTriggered: if (window.currentReader) window.currentReader.setTool("area") }
            Action { objectName: "highlightAction"; text: "Highlight Selection"; shortcut: window.keys("highlight"); enabled: !window.homeVisible && !!window.currentReader; onTriggered: window.currentReader.useHighlight() }
            Action { objectName: "commentAction"; text: "Comment"; shortcut: window.keys("comment"); enabled: !window.homeVisible && !!window.currentReader; onTriggered: window.currentReader.setTool("comment") }
            Action { objectName: "darkPagesAction"; text: "Dark Pages"; shortcut: window.keys("darkPages"); checkable: true; checked: Theme.invertPages; enabled: Theme.canInvertPages; onTriggered: Theme.invertPages = checked }
            Action { objectName: "askAiAction"; text: "Ask AI"; shortcut: window.keys("askAi"); enabled: !window.restoreFailed; onTriggered: window.askAiNow() }
            MenuSeparator {}
            Action { objectName: "filesPanelAction"; text: "Library Panel"; shortcut: window.keys("filesPanel"); onTriggered: window.togglePanel("files") }
            Action { objectName: "documentPanelAction"; text: "Document Panel"; shortcut: window.keys("documentPanel"); onTriggered: window.togglePanel("document") }
            Action { objectName: "annotationsAction"; text: "Annotations"; shortcut: window.keys("annotations"); enabled: !window.homeVisible; onTriggered: window.toggleAnnotations() }
            Action { objectName: "aiPanelAction"; text: "AI Chat"; shortcut: window.keys("aiPanel"); onTriggered: window.togglePanel("ai") }
            MenuSeparator {}
            Action { objectName: "splitRightAction"; text: "Duplicate to Right Split"; shortcut: window.keys("splitRight"); enabled: !window.homeVisible && window.canSwitchTabs; onTriggered: documents.duplicateSplit("right") }
            Action { objectName: "splitDownAction"; text: "Duplicate to Bottom Split"; shortcut: window.keys("splitDown"); enabled: !window.homeVisible && window.canSwitchTabs; onTriggered: documents.duplicateSplit("bottom") }
            Action { objectName: "moveRightAction"; text: "Move Tab to Right Split"; shortcut: window.keys("moveRight"); enabled: !window.homeVisible && window.canSwitchTabs; onTriggered: documents.moveActiveTabToSplit("right") }
            Action { objectName: "moveDownAction"; text: "Move Tab to Bottom Split"; shortcut: window.keys("moveDown"); enabled: !window.homeVisible && window.canSwitchTabs; onTriggered: documents.moveActiveTabToSplit("bottom") }
            Action { objectName: "nextSplitAction"; text: "Focus Next Split"; shortcut: window.keys("nextSplit"); enabled: !window.homeVisible && window.canSwitchTabs; onTriggered: documents.focusGroup(1) }
            Action { objectName: "previousSplitAction"; text: "Focus Previous Split"; shortcut: window.keys("previousSplit"); enabled: !window.homeVisible && window.canSwitchTabs; onTriggered: documents.focusGroup(-1) }
            Action { text: "Join All Groups"; enabled: !window.homeVisible; onTriggered: documents.joinAll() }
        }
        Menu {
            title: "Help"
            Action { objectName: "shortcutsAction"; text: "Keyboard Shortcuts"; shortcut: "Ctrl+/"; onTriggered: window.showShortcuts() }
        }
    }
    // An answer arrived while its thread is not in view: a card at the bottom right (Open / Dismiss),
    // and while another app is in front, the Dock icon bounces once (the taskbar flashes on Linux).
    AiNotice {
        id: aiNotice
        parent: window.contentItem
        anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.rightMargin: 16; anchors.bottomMargin: 40
        onOpenRequested: function(id) { window.requestActivate(); window.openAiThread(id) }
    }
    Connections {
        target: aiController
        function onAnswered(id, title, preview) {
            if (!window.active) window.alert(0)
            if (!window.active || !window.aiThreadInView(id)) aiNotice.show(id, title, preview)
        }
    }
    SettingsDialog { id: settingsDialog }
    // A press anywhere else takes the cursor out of a text box that asks for it (releaseFocusOnOutsidePress: Home's
    // search field, the AI question box); presses inside its keepFocusWithin items keep it. The layer only watches
    // (a passive point handler), so every press still reaches what is under it.
    function releaseFocusAt(at) {
        const focus = window.activeFocusItem
        if (!focus || !focus.releaseFocusOnOutsidePress) return
        const inside = function(item) { return !!item && item.visible && item.contains(item.mapFromItem(null, at.x, at.y)) }
        if (inside(focus) || (focus.keepFocusWithin || []).some(inside)) return
        focusSink.forceActiveFocus()
    }
    // Where the cursor goes when it leaves a text box: an item that takes no keys of its own (the window's
    // content would hand the focus straight back to the box).
    Item { id: focusSink; objectName: "focusSink" }
    Item {
        objectName: "focusReleaseLayer"
        parent: window.contentItem.parent
        anchors.fill: parent
        z: 100000
        PointHandler {
            acceptedButtons: Qt.AllButtons
            onActiveChanged: if (active) window.releaseFocusAt(point.scenePosition)
        }
    }
    // Created on first use: the AI tab organizer.
    Loader { id: organizeTabs; active: false; sourceComponent: OrganizeTabsDialog { controller: documents } }
    // Created on first use: the AI paper comparison, for the PDFs open in a tab strip.
    Loader { id: comparePapers; active: false; sourceComponent: ComparePapersDialog { onNoteCreated: function(id) { documents.openNote(id) } } }
    function comparePapersIn(groupId) {
        if (window.restoreFailed) return
        const strip = Tree.find(documents.tree, groupId || documents.activeGroup)
        const seen = {}
        const urls = (strip ? strip.tabs : []).filter(function(t) {
            if (t.kind || seen[t.source]) return false
            seen[t.source] = true
            return true
        }).map(function(t) { return t.source })
        comparePapers.active = true
        comparePapers.item.begin(urls)
    }
    function organizeTabsIn(groupId) {
        if (restoreFailed || homeVisible) return
        organizeTabs.active = true
        organizeTabs.item.begin(groupId || documents.activeGroup)
    }
    AiController { id: aiController; reader: window.homeVisible ? null : window.currentReader; workspace: documents }
    // Same bytes as another library entry: offer the existing copy without merging anything silently.
    // A notice, not a dialog: it never takes keyboard focus from the reader.
    Rectangle {
        id: duplicateBar
        objectName: "duplicateBar"
        parent: window.contentItem
        z: 50
        property url source: ""
        property url existing: ""
        property string existingTitle: ""
        readonly property bool opened: visible
        function show(url, other, title) { source = url; existing = other; existingTitle = title; visible = true }
        function close() { visible = false }
        visible: false
        x: (parent.width - width) / 2; y: 8
        width: Math.min(620, parent.width - 32); height: duplicateRow.implicitHeight + 16
        color: Theme.raised; border.color: Theme.border; radius: Theme.radiusLarge
        RowLayout {
            id: duplicateRow
            anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 12; anchors.rightMargin: 6
            spacing: 6
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Label { Layout.fillWidth: true; text: "This PDF is already in your Library"; font.weight: Font.DemiBold; color: Theme.text; wrapMode: Text.Wrap }
                // The title wraps to two lines; anything longer shows in full on hover.
                Label {
                    Layout.fillWidth: true
                    text: "\u201c" + duplicateBar.existingTitle + "\u201d"
                    wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; textFormat: Text.PlainText
                    font.pixelSize: Theme.fontSmall; color: Theme.textSecondary
                }
            }
            Button {
                objectName: "openExistingCopy"; text: "Use Existing"; focusPolicy: Qt.NoFocus
                ToolTip.visible: hovered; ToolTip.delay: 450
                ToolTip.text: "Read the paper already in your Library (with its notes). This extra entry is set aside; no file is deleted."
                onClicked: {
                    if (researchStore.useExistingCopy(duplicateBar.source, duplicateBar.existing))
                        documents.relinkSource(duplicateBar.source, duplicateBar.existing)
                    duplicateBar.close()
                }
            }
            Button {
                objectName: "keepBothCopies"; text: "Keep Both"; focusPolicy: Qt.NoFocus
                ToolTip.visible: hovered; ToolTip.delay: 450
                ToolTip.text: "Keep two separate papers, each with its own notes. Owelk won't ask again about this file."
                onClicked: { researchStore.keepDuplicate(duplicateBar.source); duplicateBar.close() }
            }
            IconButton { icon.name: "close"; description: "Dismiss"; focusPolicy: Qt.NoFocus; onClicked: duplicateBar.close() }
        }
    }
    // Saved tabs that could not be reopened: what happened, above the window's content. A notice, not a
    // dialog; it stays until dismissed.
    Rectangle {
        id: restoreNotice
        objectName: "restoreNotice"
        parent: window.contentItem
        z: 50
        property string text: ""
        function show(message) { text = message; visible = true }
        visible: false
        x: (parent.width - width) / 2; y: 8
        width: Math.min(560, parent.width - 32); height: restoreRow.implicitHeight + 16
        color: Theme.raised; border.color: Theme.border; radius: Theme.radiusLarge
        RowLayout {
            id: restoreRow
            anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 12; anchors.rightMargin: 6
            spacing: 6
            Icon { name: "alert"; size: Theme.fontBody + 2; color: Theme.textSecondary }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Label { objectName: "restoreNoticeText"; Layout.fillWidth: true; text: restoreNotice.text; font.weight: Font.DemiBold; color: Theme.text; wrapMode: Text.Wrap; textFormat: Text.PlainText }
                Label {
                    Layout.fillWidth: true
                    visible: !window.restoreFailed
                    text: "The tabs as they were saved are kept in Owelk's data folder."
                    wrapMode: Text.Wrap; font.pixelSize: Theme.fontSmall; color: Theme.textSecondary
                }
            }
            IconButton { objectName: "restoreNoticeClose"; icon.name: "close"; description: "Dismiss"; focusPolicy: Qt.NoFocus; onClicked: restoreNotice.visible = false }
        }
    }
    // Beneath everything: a drop that no panel takes (the Library list, a collection, the AI panel) lands here.
    DropArea {
        id: windowDrop
        objectName: "windowDrop"
        anchors.fill: parent
        z: -1
        keys: ["text/uri-list"]
        onEntered: function(drag) { drag.accepted = !window.restoreFailed && window.droppable(drag.urls) }
        onDropped: function(drop) { if (window.dropFiles(drop.urls)) drop.acceptProposedAction() }
    }
    Rectangle {
        objectName: "windowDropHint"
        parent: window.contentItem
        anchors.fill: parent
        z: 60
        visible: windowDrop.containsDrag
        color: Theme.overlay
        border.color: Theme.overlayBorder; border.width: 2
        Rectangle {
            anchors.centerIn: parent
            width: dropHintText.implicitWidth + 32; height: dropHintText.implicitHeight + 20
            radius: Theme.radiusLarge
            color: Theme.raised; border.color: Theme.border
            Label {
                id: dropHintText
                anchors.centerIn: parent
                font.pixelSize: Theme.fontBody; color: Theme.text
                text: !windowDrop.containsDrag ? ""
                    : researchStore.setting("library.keepPdfs", "1") === "1" && researchStore.setting("library.dropMoves", "1") === "1"
                    ? "Drop to move PDFs into \u201c" + researchStore.fileName(researchStore.papersFolderUrl()) + "\u201d and open them"
                    : "Drop to add PDFs to the Library and open them"
            }
        }
    }
    // Areas are slices separated by 1px edges; an edge darkens under the pointer and drags to resize.
    component ResizeEdge: Rectangle {
        id: edge
        property alias area: grip
        signal moved(real delta)
        property real initialWidth
        Layout.preferredWidth: 1; Layout.fillHeight: true
        z: 2
        color: grip.containsMouse || grip.pressed ? Theme.border : Theme.separator
        MouseArea {
            id: grip
            anchors.fill: parent; anchors.leftMargin: -3; anchors.rightMargin: -3
            hoverEnabled: true; cursorShape: Qt.SplitHCursor
            preventStealing: true
            property real origin
            onPressed: function(mouse) { origin = mapToItem(window.contentItem, mouse.x, mouse.y).x; edge.moved(0) }
            onPositionChanged: function(mouse) { if (pressed) edge.moved(mapToItem(window.contentItem, mouse.x, mouse.y).x - origin) }
        }
    }
    RowLayout {
        anchors.fill: parent
        spacing: 0
        TabsPanel {
            id: tabsPanel
            visible: Theme.verticalTabs && !window.restoreFailed && !window.focusedReading
            controller: documents
            open: window.tabsPanelOpen
            openWidth: Number(researchStore.setting("tabs.panelWidth", "240")) || 240
            onWidthChosen: function(width) { researchStore.setSetting("tabs.panelWidth", String(Math.round(width))) }
            onToggleRequested: window.setTabsPanel(!window.tabsPanelOpen)
            onTabChosen: window.homeVisible = false
            Layout.preferredWidth: implicitWidth; Layout.fillHeight: true
        }
        DockSidebar {
            id: leftDock
            objectName: "leftDock"
            side: "left"; panels: window.leftPanels; folder: window.paperFolder
            reader: window.homeVisible ? null : window.currentReader
            aiController: aiController
            onSettingsRequested: settingsDialog.openPage("ai")
            navigationMode: window.navigationMode
            onNavigationModeChosen: function(mode) { window.navigationMode = mode }
            onLinkActivated: function(link) { if (!window.restoreFailed) documents.openLink(link) }
            onNewNoteRequested: function(source) { if (!window.restoreFailed) { if (source.toString().length) documents.newNoteFor(source); else documents.newNote() } }
            onAiRequested: function(spec) { window.askAi(spec) }
            visible: panels.length > 0 && !window.focusedReading
            Layout.preferredWidth: window.dockWidth(window.leftDockWidth); Layout.fillHeight: true
            Layout.minimumWidth: Layout.preferredWidth; Layout.maximumWidth: Layout.preferredWidth
            onFolderChosen: function(folder) { window.paperFolder = folder }
            onDocumentChosen: function(source) { window.openDocument(source) }
            documents: documents
            onLibraryFilterRequested: function(filter) { if (!window.restoreFailed) { window.homeVisible = false; documents.openLibrary(filter) } }
            onActivePanelChanged: window.scheduleSave()
        }
        ResizeEdge {
            visible: leftDock.visible
            area.objectName: "leftDockResize"
            onMoved: function(delta) {
                if (delta === 0) initialWidth = leftDock.width
                window.leftDockWidth = window.dockWidth(initialWidth + delta)
            }
        }
        HomeView {
            id: homeView
            onFocusLeft: focusSink.forceActiveFocus()
            visible: window.homeVisible
            Layout.fillWidth: true; Layout.fillHeight: true
            onOpenRequested: window.chooseFile()
            onDocumentChosen: function(source, position) { window.openDocument(source, position) }
            onResultChosen: function(result) { window.openSearchResult(result) }
            onLibraryRequested: if (!window.restoreFailed) documents.openLibrary({})
            onLibraryFilterRequested: function(filter) { if (!window.restoreFailed) documents.openLibrary(filter) }
            onWebRequested: function(url) { if (!window.restoreFailed) documents.openWeb(url, true) }
            onForYouPageRequested: function(url) { window.openForYouPage(url) }
            onNewNoteRequested: if (!window.restoreFailed) documents.newNote()
            onSettingsRequested: function(page) { settingsDialog.openPage(page) }
        }
        DocumentWorkspace {
            id: documents
            readingFocus: window.focusedReading
            visible: !window.homeVisible
            suspended: window.homeVisible
            enabled: !window.restoreFailed
            Layout.fillWidth: true; Layout.fillHeight: true
            onBeforeChange: window.persist()
            onChanged: window.scheduleSave()
            onEmpty: window.showHome()
            onAiRequested: function(spec) { window.askAi(spec) }
            onSettingsRequested: function(page) { settingsDialog.openPage(page) }
            onAnnotationsToggled: window.toggleAnnotations()
            onAiResponseRequested: function(id) { window.openAiThread(id) }
            onOpened: window.homeVisible = false
            onHomeOpenRequested: window.chooseFile()
            onHomeResultChosen: function(result) { window.openSearchResult(result) }
            onOrganizeRequested: function(groupId) { window.organizeTabsIn(groupId) }
            onCompareRequested: function(groupId) { window.comparePapersIn(groupId) }
        }
        ResizeEdge {
            visible: rightDock.visible
            area.objectName: "rightDockResize"
            onMoved: function(delta) {
                if (delta === 0) initialWidth = rightDock.width
                window.rightDockWidth = window.dockWidth(initialWidth - delta)
            }
        }
        DockSidebar {
            id: rightDock
            objectName: "rightDock"
            side: "right"; panels: window.rightPanels; folder: window.paperFolder
            reader: window.homeVisible ? null : window.currentReader
            aiController: aiController
            onSettingsRequested: settingsDialog.openPage("ai")
            navigationMode: window.navigationMode
            onNavigationModeChosen: function(mode) { window.navigationMode = mode }
            onLinkActivated: function(link) { if (!window.restoreFailed) documents.openLink(link) }
            onNewNoteRequested: function(source) { if (!window.restoreFailed) { if (source.toString().length) documents.newNoteFor(source); else documents.newNote() } }
            onAiRequested: function(spec) { window.askAi(spec) }
            visible: panels.length > 0 && !window.focusedReading
            Layout.preferredWidth: window.dockWidth(window.rightDockWidth); Layout.fillHeight: true
            Layout.minimumWidth: Layout.preferredWidth; Layout.maximumWidth: Layout.preferredWidth
            onFolderChosen: function(folder) { window.paperFolder = folder }
            onDocumentChosen: function(source) { window.openDocument(source) }
            documents: documents
            onLibraryFilterRequested: function(filter) { if (!window.restoreFailed) { window.homeVisible = false; documents.openLibrary(filter) } }
            onActivePanelChanged: window.scheduleSave()
        }
    }
    footer: Rectangle {
        id: statusBar
        visible: !window.focusedReading
        objectName: "statusBar"
        height: 29
        color: Theme.sidebar
        Rectangle { width: parent.width; height: 1; color: Theme.separator } // The edge above it.
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 4; anchors.rightMargin: 4
            spacing: 2
            ToolButton {
                objectName: "readingFocusButton"
                enabled: !window.homeVisible && !window.restoreFailed
                text: window.readingFocus ? "Exit Focus" : "Focus"
                checkable: true; checked: window.readingFocus
                onClicked: window.toggleReadingFocus()
                ToolTip.visible: hovered
                ToolTip.text: "Reading Focus · " + window.keys("readingFocus")
            }
            // Back and forward, as in a browser: a web tab's pages and the reader's jumps, then Home and tabs.
            IconButton {
                objectName: "statusBack"; icon.name: "back"
                description: "Back" + (window.keys("jumpBack").length ? " · " + Platform.keys(window.keys("jumpBack")) : "")
                enabled: window.canGoBack; onClicked: window.goBack()
            }
            IconButton {
                objectName: "statusForward"; icon.name: "forward"
                description: "Forward" + (window.keys("jumpForward").length ? " · " + Platform.keys(window.keys("jumpForward")) : "")
                enabled: window.canGoForward; onClicked: window.goForward()
            }
            Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 14; Layout.leftMargin: 3; Layout.rightMargin: 3; color: Theme.separator }
            Repeater {
                model: window.dockPanels.filter(function(p) { return window.panelSide(p) === "left" })
                delegate: StatusIcon {
                    required property string modelData
                    objectName: "dockIcon-" + modelData
                    kind: modelData; dockSide: "left"
                    description: window.panelName(kind)
                    selected: window.panelShown(kind) && !window.focusedReading
                    onTriggered: window.togglePanel(kind)
                    onDockSideChosen: function(side) { const panel = kind; Qt.callLater(function() { window.movePanel(panel, side) }) }
                }
            }
            // Long work: what it is, with a thin bar (filling, or sliding when there is no measure); +N when
            // more is running, all of it on hover.
            RowLayout {
                id: activity
                objectName: "statusActivity"
                visible: window.activities.length > 0
                Layout.leftMargin: 6
                spacing: 6
                readonly property var first: window.activities.length ? window.activities[0] : ({label: "", done: 0, total: 0})
                readonly property bool measured: first.total > 0
                Label {
                    objectName: "statusActivityLabel"
                    Layout.maximumWidth: 300
                    text: activity.first.label + (window.activities.length > 1 ? "  +" + (window.activities.length - 1) : "")
                    elide: Text.ElideMiddle; textFormat: Text.PlainText
                    font.pixelSize: Theme.fontCaption; color: Theme.textSecondary
                }
                Item {
                    objectName: "statusActivityBar"
                    implicitWidth: 90; implicitHeight: 4
                    clip: true
                    Rectangle { anchors.fill: parent; radius: 2; color: Theme.separator }
                    Rectangle {
                        objectName: "statusActivityFill"
                        visible: activity.measured
                        height: parent.height; radius: 2; color: Theme.accent
                        width: parent.width * Math.min(1, activity.first.done / Math.max(1, activity.first.total))
                        Behavior on width { NumberAnimation { duration: 150 } }
                    }
                    Rectangle {
                        id: slider
                        visible: !activity.measured
                        width: parent.width * .35; height: parent.height; radius: 2; color: Theme.accent
                        NumberAnimation on x {
                            running: activity.visible && !activity.measured
                            from: -slider.width; to: 90; duration: 1100; loops: Animation.Infinite
                        }
                    }
                }
                HoverHandler { id: activityHover }
                ToolTip.visible: activityHover.hovered && window.activities.length > 1
                ToolTip.text: window.activities.map(function(a) { return a.label }).join("\n")
            }
            Label {
                Layout.fillWidth: true
                // A notice while there is one.
                text: window.notification.length ? window.notification : researchStore.busy ? "Saving…" : ""
                elide: Text.ElideRight; font.pixelSize: Theme.fontCaption; color: Theme.textTertiary
            }
            StatusIcon { objectName: "shortcutsButton"; kind: "help"; description: "Keyboard Shortcuts · ?"; onTriggered: window.showShortcuts() }
            StatusIcon { kind: "search"; description: "Search · " + Platform.keys("Ctrl+K"); onTriggered: { commandPalette.close(); searchPalette.open() } }
            StatusIcon { kind: "split"; description: "Duplicate to right split · " + Platform.keys("Ctrl+\\"); visible: !window.homeVisible; selected: documents.groupCount > 1; onTriggered: documents.duplicateSplit("right") }
            Repeater {
                model: window.dockPanels.filter(function(p) { return window.panelSide(p) === "right" })
                delegate: StatusIcon {
                    required property string modelData
                    objectName: "dockIcon-" + modelData
                    kind: modelData; dockSide: "right"
                    description: window.panelName(kind)
                    selected: window.panelShown(kind) && !window.focusedReading
                    onTriggered: window.togglePanel(kind)
                    onDockSideChosen: function(side) { const panel = kind; Qt.callLater(function() { window.movePanel(panel, side) }) }
                }
            }
        }
    }
}
