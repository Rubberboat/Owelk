import QtQuick
import QtTest
import "../qml/WorkspaceTree.js" as Tree
import "../qml/Platform.js" as Platform
import "../qml/Shortcuts.js" as Shortcuts

TestCase {
    name: "WorkspaceTree"
    function test_shortcutRegistry() {
        // Linux/Windows defaults avoid desktop and AltGr combinations.
        compare(Shortcuts.defaultKeys("nextTab", "osx"), "Ctrl+Alt+Right")
        compare(Shortcuts.defaultKeys("nextTab", "linux"), "Ctrl+PgDown")
        compare(Shortcuts.defaultKeys("splitDown", "windows"), "Ctrl+Shift+\\")
        verify(Shortcuts.actions.every(function(a) { return a.other.indexOf("Ctrl+Alt+Left") < 0 && a.other.indexOf("Ctrl+Alt+Right") < 0 && a.other.indexOf("Ctrl+Alt+\\") < 0 }))
        // No clashes among the defaults on any platform.
        compare(Object.keys(Shortcuts.conflicts({}, "osx")).length, 0)
        compare(Object.keys(Shortcuts.conflicts({}, "linux")).length, 0)
        // Ctrl+1…9 belong to tab switching.
        compare(Shortcuts.conflicts({library: "Ctrl+9"}, "osx")["Ctrl+9"].length, 2)
        const mine = {newTab: "Ctrl+K", closeTab: ""}
        compare(Shortcuts.keys("newTab", mine, "linux"), "Ctrl+K")
        compare(Shortcuts.keys("closeTab", mine, "linux"), "")
        compare(Shortcuts.conflicts(mine, "linux")["Ctrl+K"].length, 2)
        compare(Shortcuts.parse("not json"), {})
        compare(Shortcuts.fromEvent(Qt.Key_Y, Qt.ControlModifier | Qt.ShiftModifier, "Y"), "Ctrl+Shift+Y")
        compare(Shortcuts.fromEvent(Qt.Key_Shift, Qt.ShiftModifier, ""), "")
        compare(Shortcuts.fromEvent(Qt.Key_Y, 0, "y"), "") // A plain letter is typing, not a shortcut.
        compare(Shortcuts.fromEvent(Qt.Key_F5, 0, ""), "F5")
        // Every action sits in a section, and every section has some.
        verify(Shortcuts.actions.every(function(a) { return Shortcuts.groups.indexOf(a.group) >= 0 }))
        verify(Shortcuts.groups.every(function(g) { return Shortcuts.actions.some(function(a) { return a.group === g }) }))
        compare(Shortcuts.defaultKeys("previousPage", "linux"), "Ctrl+[")
        compare(Shortcuts.defaultKeys("highlight", "osx"), "Ctrl+Meta+H")
        compare(Shortcuts.defaultKeys("highlight", "windows"), "Ctrl+Alt+H")
    }
    function test_shortcutHintsFollowThePlatform() {
        if (Qt.platform.os === "osx") {
            compare(Platform.keys("Ctrl+Shift+L"), "⇧⌘L")
            compare(Platform.keys("Ctrl+Alt+\\"), "⌥⌘\\")
            compare(Platform.keys("Ctrl+["), "⌘[")
            compare(Platform.keys("Alt+Left"), "⌥←")
            compare(Platform.keys("Ctrl+Plus"), "⌘+")
        } else {
            compare(Platform.keys("Ctrl+Shift+L"), "Ctrl+Shift+L")
        }
    }
    function test_referenceUrl() {
        const scholar = "https://scholar.google.com/scholar?q=%s"
        compare(Tree.referenceUrl("[4] A. B. Paper. IEEE T-RO, 2020, doi: 10.1109/TRO.2020.123456.", scholar), "https://doi.org/10.1109/TRO.2020.123456")
        compare(Tree.referenceUrl("[7] J. Ba. Layer norm. arXiv preprint arXiv:1607.06450, 2016.", scholar), "https://arxiv.org/abs/1607.06450")
        compare(Tree.referenceUrl("[2] A. Vaswani et al. Attention is all you need. 2017.", scholar),
                "https://scholar.google.com/scholar?q=" + encodeURIComponent("A. Vaswani et al. Attention is all you need. 2017."))
        compare(Tree.referenceUrl("", scholar), "")
    }
    function test_tidyTabs() {
        // Home tabs not in view go; one in view, or alone in its strip, stays.
        const paper = Tree.tab("file:///a.pdf"), idle = Tree.homeTab(), shownHome = Tree.homeTab()
        const left = Tree.group([idle, paper]); left.activeTab = paper.id
        const right = Tree.group([shownHome])
        let tree = Tree.split(left, left.id, right, "right")
        verify(Tree.tidyTabs(tree, left.id))
        compare(Tree.find(tree, left.id).tabs.map(function(t) { return t.id }), [paper.id])
        compare(Tree.find(tree, right.id).tabs.length, 1)
        verify(!Tree.tidyTabs(tree, left.id))
        // One Library: the one in view in the active strip is kept.
        const libA = Tree.libraryTab({}), libB = Tree.libraryTab({tag: "x"})
        Tree.find(tree, left.id).tabs.push(libA)
        const r = Tree.find(tree, right.id); r.tabs.push(libB); r.activeTab = libB.id
        verify(Tree.tidyTabs(tree, right.id))
        verify(!Tree.find(tree, left.id).tabs.some(function(t) { return t.id === libA.id }))
        compare(Tree.find(tree, right.id).tabs.map(function(t) { return t.id }), [libB.id]) // its idle Home went too
    }
    function test_namedTabGroups() {
        const strip = Tree.group([Tree.tab("file:///a.pdf"), Tree.webTab("https://x.org"), Tree.tab("file:///b.pdf")])
        const [a, web, b] = strip.tabs
        const label = Tree.addLabel(strip, "  Radar  ")
        compare(label.name, "Radar")
        Tree.setTabLabel(strip, a.id, label.id)
        Tree.setTabLabel(strip, b.id, label.id)
        // Members sit next to each other.
        compare(strip.tabs.map(function(t) { return t.id }), [a.id, b.id, web.id])
        verify(Tree.validate(strip, {}, 0))
        label.collapsed = true
        strip.activeTab = web.id
        compare(Tree.visibleTabs(strip).map(function(t) { return t.id }), [web.id])
        strip.activeTab = b.id // The active tab shows even in a collapsed group.
        compare(Tree.visibleTabs(strip).map(function(t) { return t.id }), [b.id, web.id])
        // A label the strip does not know is invalid in saved data and dropped by tidyLabels.
        const other = Tree.group([Tree.clone(a)])
        verify(!Tree.validate(other, {}, 0))
        Tree.tidyLabels(other)
        verify(other.tabs[0].label === undefined && other.labels === undefined)
        verify(Tree.validate(other, {}, 0))
        // Leaving the last member removes the group.
        Tree.setTabLabel(strip, a.id, "")
        Tree.setTabLabel(strip, b.id, "")
        verify(strip.labels === undefined)
        verify(Tree.validate(strip, {}, 0))
        // Bad label data is rejected rather than half-restored.
        verify(!Tree.validate({kind: "group", id: "g", activeTab: "", tabs: [], labels: [{id: "", name: "x"}]}, {}, 0))
    }
    function test_groupsStayTogether() {
        const strip = Tree.group([Tree.tab("file:///a.pdf"), Tree.tab("file:///b.pdf"), Tree.tab("file:///c.pdf"), Tree.tab("file:///d.pdf")])
        const [a, b, c, d] = strip.tabs.map(function(t) { return t.id })
        const g = Tree.addLabel(strip, "G")
        Tree.setTabLabel(strip, a, g.id); Tree.setTabLabel(strip, b, g.id)
        const order = function() { return strip.tabs.map(function(t) { return t.id }) }
        compare(order(), [a, b, c, d])
        // An outside tab dropped between a and b goes after the group.
        const moved = strip.tabs.splice(2, 1)[0]; strip.tabs.splice(1, 0, moved)
        Tree.keepGroupsTogether(strip, c)
        compare(order(), [a, b, c, d])
        verify(strip.tabs[2].label === undefined)
        // A grouped tab moved away from its group leaves it.
        const away = strip.tabs.splice(0, 1)[0]; strip.tabs.push(away)
        Tree.keepGroupsTogether(strip, a)
        compare(order(), [b, c, d, a])
        verify(strip.tabs[3].label === undefined)
        compare(strip.tabs[0].label, g.id)
        verify(Tree.validate(strip, {}, 0))
    }
    function test_migrateLegacy() {
        const state = {version: 1, left: {source: "file:///a.pdf", position: {page: 3, zoom: 1.4}},
            right: {source: "file:///a.pdf", position: {page: 7, zoom: 1}}, split: true, active: 1}
        const migrated = Tree.restore(state)
        const groups = Tree.leaves(migrated.tree)
        compare(groups.length, 2)
        compare(groups[0].tabs[0].position.page, 3)
        compare(groups[1].tabs[0].position.page, 7)
        verify(groups[0].tabs[0].id !== groups[1].tabs[0].id)
        compare(migrated.activeGroup, groups[1].id)
        verify(Tree.validate(migrated.tree, {}, 0))
        state.split = false
        const hidden = Tree.restore(state)
        compare(Tree.leaves(hidden.tree).length, 1)
        compare(hidden.tree.tabs.length, 2)
    }
    function test_invalidRestoreDoesNotMutateInput() {
        const input = {version: 2, tree: {kind: "group", id: "g", activeTab: "missing", tabs: []}}
        const before = JSON.stringify(input)
        let failed = false
        try { Tree.restore(input) } catch (error) { failed = true }
        verify(failed)
        compare(JSON.stringify(input), before)
        failed = false
        try { Tree.restore({version: 99}) } catch (error) { failed = true }
        verify(failed)
    }
    function test_webSearchGoesWhereItIsAsked() {
        const scholar = Tree.searchEngines[0].template, arxiv = Tree.searchEngine("https://arxiv.org/search/?query=%s&searchtype=all")
        compare(arxiv.label, "arXiv")
        // An engine set some other way is named by its site; one of the reader's own by its name.
        compare(Tree.searchEngine("https://example.org/?q=%s").name, "example.org")
        compare(Tree.searchEngine("").name, "Google Scholar")
        Tree.setCustomEngines([{name: "Semantic", label: "Semantic", template: "https://www.semanticscholar.org/search?q=%s"}])
        compare(Tree.searchEngine("https://www.semanticscholar.org/search?q=%s").label, "Semantic")
        compare(Tree.allEngines().length, Tree.searchEngines.length + 1)
        Tree.setCustomEngines([])
        compare(Tree.addressToUrl("lidar odometry", scholar), "https://scholar.google.com/scholar?q=lidar%20odometry")
        compare(Tree.addressToUrl("lidar odometry", arxiv.template), "https://arxiv.org/search/?query=lidar%20odometry&searchtype=all")
        // A prefix searches there once, whatever engine is chosen.
        compare(Tree.addressToUrl("arxiv: lidar odometry", scholar), "https://arxiv.org/search/?query=lidar%20odometry&searchtype=all")
        compare(Tree.addressToUrl("Scholar:lidar", arxiv.template), "https://scholar.google.com/scholar?q=lidar")
        compare(Tree.addressToUrl("arxiv:2305.01234", scholar), "https://arxiv.org/abs/2305.01234")
        compare(Tree.addressToUrl("arxiv: 2305.01234v2", scholar), "https://arxiv.org/abs/2305.01234v2")
        compare(Tree.addressToUrl("example.org/paper", scholar), "https://example.org/paper")
        compare(Tree.addressToUrl("note: lidar", scholar), "https://scholar.google.com/scholar?q=note%3A%20lidar")
    }
    function test_webRowOfTheOneSearchField() {
        const scholar = Tree.searchEngines[0].template
        compare(Tree.webIntent("  ", scholar), null)
        const words = Tree.webIntent("lidar odometry", scholar)
        compare(words.title, "Search Google Scholar for \u201clidar odometry\u201d")
        compare(words.url, "https://scholar.google.com/scholar?q=lidar%20odometry")
        verify(!words.first)
        const named = Tree.webIntent("arxiv: lidar", scholar)
        compare(named.title, "Search arXiv for \u201clidar\u201d")
        verify(named.first)
        compare(Tree.webIntent("arxiv:2305.01234", scholar).title, "Open arXiv 2305.01234")
        const address = Tree.webIntent("example.org/paper", scholar)
        compare(address.title, "Open example.org/paper")
        compare(address.url, "https://example.org/paper")
        verify(address.first)
        verify(Tree.webIntent("https://doi.org/10.1/x", scholar).first)
    }
    function test_droppedFilesAreSorted() {
        const drop = Tree.droppedFiles(["file:///Users/me/Downloads/Paper%20One.PDF", "file:///Users/me/Downloads/Papers",
                                        "file:///Users/me/notes.txt", "https://arxiv.org/abs/2305.01234"],
                                       function(url) { return String(url).endsWith("/Papers") })
        compare(drop.pdfs.length, 1)
        compare(drop.folders.length, 1)
        compare(drop.web, ["https://arxiv.org/abs/2305.01234"])
    }
    function test_tabsThatCannotOpenAreLeftOut() {
        const pdf = function(id, page) { return {id: id, source: "file:///" + id + ".pdf", position: {page: page || 0, x: 0, y: 0, zoom: 1}} }
        const saved = {version: 2, activeGroup: "right", tree: {kind: "split", id: "s", axis: "horizontal", ratio: .5,
            first: {kind: "group", id: "left", activeTab: "bad", labels: [{id: "L", name: "Reading"}, {id: 5}],
                    tabs: [pdf("a"), {id: "bad", source: "", position: {page: 0}}, Object.assign(pdf("b"), {label: "L"}),
                           Object.assign(pdf("c"), {label: "gone"}), pdf("a")]},
            second: {kind: "group", id: "right", activeTab: "x", tabs: [{id: "x", kind: "web", source: "not a page", position: {page: 0}}]}}}
        const before = JSON.stringify(saved)
        const restored = Tree.restore(saved)
        compare(JSON.stringify(saved), before) // The saved data itself is left as it was.
        // Only the left group is left (its split goes with the empty right one): three tabs, bad and repeated ones out.
        compare(restored.dropped, 3)
        compare(restored.tree.kind, "group")
        compare(restored.tree.tabs.map(function(t) { return t.id }), ["a", "b", "c"])
        compare(restored.tree.activeTab, "a")
        compare(restored.tree.labels.length, 1)
        compare(restored.tree.tabs[1].label, "L")
        compare(restored.tree.tabs[2].label, undefined)
        compare(restored.activeGroup, "left")
        verify(Tree.validate(restored.tree, {}, 0))
        // A layout that reads as it is: nothing left out.
        compare(Tree.restore({version: 2, tree: restored.tree, activeGroup: "left"}).dropped, 0)
        // Nothing left that opens: it throws, and the caller starts without tabs.
        let failed = false
        try { Tree.restore({version: 2, tree: {kind: "group", id: "g", activeTab: "x", tabs: [{id: "x", source: 7}]}}) } catch (error) { failed = !error.newer }
        verify(failed)
        // Saved by a newer Owelk: refused as such, never repaired.
        let newer = false
        try { Tree.restore({version: 3, tree: restored.tree}) } catch (error) { newer = !!error.newer }
        verify(newer)
    }
    function test_webAddressesWithSpaces() {
        // url.toString() decodes %20 to a space; such an address still makes a tab, kept encoded.
        const t = Tree.webTab("https://scholar.google.com/scholar?q=radar inertial odometry")
        compare(t.source, "https://scholar.google.com/scholar?q=radar%20inertial%20odometry")
        verify(Tree.isWebAddress("https://example.com/?q=a b"))
        verify(!Tree.isWebAddress("not a url"))
        // A layout saved with the decoded address (as earlier versions did) loads, with the address encoded.
        const saved = {kind: "group", id: "g", activeTab: "w", tabs: [{id: "w", kind: "web", source: "https://example.com/?q=a b",
            title: "", position: {page: 0, x: 0, y: 0, zoom: 1}}]}
        const restored = Tree.restore({version: 2, tree: saved, activeGroup: "g"})
        compare(restored.tree.tabs[0].source, "https://example.com/?q=a%20b")
        compare(saved.tabs[0].source, "https://example.com/?q=a b") // The input is left as it was.
    }
    function test_splitGeometryAndRoundTrip() {
        let tree = Tree.group([Tree.tab("file:///a.pdf")])
        for (let i = 0; i < 8; ++i) tree = Tree.split(tree, Tree.leaves(tree)[0].id, Tree.group([Tree.tab("file:///b.pdf")]), i % 2 ? "bottom" : "right")
        const size = Tree.minimum(tree), groups = [], handles = []
        Tree.geometry(tree, 0, 0, size.width, size.height, groups, handles)
        compare(groups.length, 9); compare(handles.length, 8)
        for (let i = 0; i < groups.length; ++i) { verify(groups[i].width >= 440); verify(groups[i].height >= 280) }
        const restored = Tree.restore({version: 2, tree: tree, activeGroup: groups[5].node.id})
        compare(JSON.stringify(restored.tree), JSON.stringify(tree))
        compare(restored.activeGroup, groups[5].node.id)
    }
}
