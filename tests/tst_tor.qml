import QtQuick
import QtTest
import "../qml" as App
import "../qml/WorkspaceTree.js" as Tree

// Settings › Web › Browse through Tor, with tests/fake_tor.py as Tor: it lets through only owelk.test
// (this computer), so a page there loads only when web tabs really go through it.
Item {
    width: 1440; height: 930
    App.Main { id: workspace }
    App.SettingsDialog { id: settings }
    SignalSpy { id: citations; target: researchStore; signalName: "citationsLoaded" }
    SignalSpy { id: held; signalName: "heldUrlChanged" }
    TestCase {
        name: "Tor"
        when: windowShown
        readonly property var tor: researchStore.tor
        function initTestCase() { testInput.useFakeTor(true) }
        function cleanupTestCase() { workspace.visible = false }
        function init() {
            workspace.documents.restore({})
            workspace.homeVisible = true
        }
        function cleanup() {
            settings.close()
            tor.setEnabled(false)
            tor.setExitCountry("")
            testInput.useFakeTor(true)
        }
        function visualChild(item, name) {
            if (!item) return null
            if (item.objectName === name) return item
            const children = item.children || []
            for (let i = 0; i < children.length; ++i) { const found = visualChild(children[i], name); if (found) return found }
            return null
        }
        function webPane() {
            let pane = null
            tryVerify(function() { const v = workspace.documents.groupView(workspace.documents.activeGroup); pane = v ? v.webPane : null; return pane !== null }, 5000)
            return pane
        }
        function behindTor(path) { return testInput.webFixture(path).toString().replace("127.0.0.1", "owelk.test") }
        function turnOn() {
            tor.setEnabled(true)
            tryCompare(tor, "state", "ready", 10000)
            tryCompare(tor, "routePending", false, 10000)
        }

        function test_offUntilTheReaderTurnsItOn() {
            compare(tor.enabled, false)
            compare(tor.state, "off")
            compare(testInput.webProxy(), "direct")
            compare(tor.summary, "Off. Web tabs connect directly.")
            workspace.documents.openWeb(testInput.webFixture("/page.html?direct"), true)
            const pane = webPane()
            tryCompare(pane.view, "title", "Owelk Test Page", 10000)
            verify(!findChild(pane, "webTorChip").visible)
            verify(!findChild(pane, "webTorNotice").visible)
        }
        function test_webTabsGoThroughTorAndNothingElseDoes() {
            turnOn()
            compare(researchStore.setting("web.tor"), "1")
            verify(testInput.webProxy().indexOf("socks5 127.0.0.1:") === 0)
            compare(tor.summary, "On. Web tabs go out through Tor.")
            workspace.documents.openWeb(behindTor("/page.html?tor"), true)
            const pane = webPane()
            tryCompare(pane.view, "title", "Owelk Test Page", 10000)
            verify(testInput.fakeTorLog().indexOf("connect owelk.test:") >= 0)
            const chip = findChild(pane, "webTorChip")
            verify(chip.visible)
            verify(chip.checked)
            verify(!findChild(pane, "webTorNotice").visible)
            // Everything else stays off Tor: a citations server at owelk.test (a name only Tor knows here)
            // is looked up directly and not found; Tor never hears of it.
            verify(researchStore.rememberDocument(fixtureSource))
            verify(researchStore.updateDocumentDetails(fixtureSource, {doi: "10.1/tor"}))
            const base = researchStore.setting("citations.baseUrl")
            researchStore.setSetting("citations.baseUrl", "http://owelk.test:9/graph/v1")
            citations.clear()
            researchStore.loadCitations(fixtureSource, true)
            tryCompare(citations, "count", 1, 25000)
            verify(citations.signalArguments[0][2].error)
            verify(testInput.fakeTorLog().indexOf("connect owelk.test:9 ") < 0)
            // ...while the same server answers directly.
            researchStore.setSetting("citations.baseUrl", testInput.webFixture("/graph/v1").toString())
            citations.clear()
            researchStore.loadCitations(fixtureSource, true)
            tryCompare(citations, "count", 1, 10000)
            const result = citations.signalArguments[0][2]
            verify(!result.error, result.error)
            compare(result.references.length, 1)
            researchStore.setSetting("citations.baseUrl", base)
            // Home's web row says where it goes.
            workspace.showHome()
            const home = findChild(workspace, "homeView"), field = findChild(home, "homeSearch")
            field.text = "occupancy grids"
            tryVerify(function() { return home.rows.length > 0 && home.rows[home.rows.length - 1].kind === "web" })
            const list = findChild(home, "homeResults")
            let row = null
            tryVerify(function() { list.forceLayout(); row = list.itemAtIndex(home.rows.length - 1); return row !== null })
            verify(findChild(row, "resultKind").text.indexOf("Web via Tor") === 0)
            field.text = ""
        }
        function test_turningItOffConnectsDirectlyAgain() {
            turnOn()
            workspace.documents.openWeb(testInput.webFixture("/page.html?off"), true)
            const pane = webPane()
            mouseClick(findChild(pane, "webTorChip"))
            const off = findChild(pane, "webTorMenuOff")
            tryCompare(off, "visible", true)
            mouseClick(off)
            compare(tor.enabled, false)
            compare(tor.state, "off")
            compare(researchStore.setting("web.tor"), "0")
            compare(testInput.webProxy(), "direct")
            verify(!findChild(pane, "webTorChip").visible)
        }
        function test_pagesAskedForWhileTheRouteChangesWait() {
            workspace.documents.openWeb(testInput.webFixture("/page.html?before"), true)
            const pane = webPane()
            tryCompare(pane.view, "title", "Owelk Test Page", 10000)
            // Chromium would send the first request after a change the old way: it is held instead.
            held.target = pane
            held.clear()
            tor.setEnabled(true)
            verify(tor.routePending)
            const there = behindTor("/page.html?held")
            pane.view.url = there
            tryVerify(function() { return held.count > 0 })
            tryCompare(tor, "routePending", false, 10000)
            tryCompare(held, "count", 2) // Held, then let go.
            tryCompare(pane.view, "title", "Owelk Test Page", 10000)
            compare(pane.view.url.toString(), there)
            verify(testInput.fakeTorLog().indexOf("connect owelk.test:") >= 0)
            // The same on the way back.
            held.clear()
            tor.setEnabled(false)
            const back = testInput.webFixture("/page.html?back").toString()
            pane.view.url = back
            tryCompare(held, "count", 2, 10000)
            tryCompare(pane.view, "url", back, 10000)
            tryCompare(pane.view, "title", "Owelk Test Page", 10000)
            compare(pane.heldUrl.toString(), "")
        }
        function test_withoutTorWebTabsStayOffline() {
            testInput.useFakeTor(false)
            tor.setEnabled(true)
            compare(tor.state, "missing")
            verify(tor.summary.indexOf("Tor is not installed") === 0, tor.summary)
            // Asked for Tor, so no direct connection either.
            verify(testInput.webProxy().indexOf("socks5") === 0)
            workspace.documents.openWeb(behindTor("/page.html?missing"), true)
            const pane = webPane()
            const notice = findChild(pane, "webTorNotice")
            tryCompare(notice, "visible", true)
            compare(findChild(notice, "webTorNoticeText").text, tor.summary)
            mouseClick(findChild(notice, "webTorTurnOff"))
            compare(tor.enabled, false)
            compare(testInput.webProxy(), "direct")
            tryCompare(notice, "visible", false)
        }
        function test_newIdentityUsesFreshConnections() {
            turnOn()
            workspace.documents.openWeb(behindTor("/page.html?first"), true)
            const pane = webPane()
            tryCompare(pane.view, "title", "Owelk Test Page", 10000)
            const before = testInput.webProxy(), identity = tor.identity
            mouseClick(findChild(pane, "webTorChip"))
            const item = findChild(pane, "webTorNewIdentity")
            tryCompare(item, "visible", true)
            verify(item.enabled)
            mouseClick(item)
            tryCompare(tor, "identity", identity + 1, 5000)
            verify(testInput.fakeTorLog().indexOf("newnym") >= 0)
            verify(testInput.webProxy() !== before)
            // The page in view comes again through the other port.
            const port = testInput.webProxy().split(":")[1]
            tryVerify(function() { return testInput.fakeTorLog().indexOf("via " + port) >= 0 }, 10000)
            tryCompare(pane.view, "title", "Owelk Test Page", 10000)
        }
        function test_exitCountryRestartsTor() {
            turnOn()
            tor.setExitCountry("us")
            compare(researchStore.setting("web.torExit"), "us")
            tryCompare(tor, "state", "ready", 10000)
            verify(testInput.fakeTorLog().indexOf("--ExitNodes {us}") >= 0)
            compare(tor.summary, "On. Web tabs go out through Tor (exit in United States).")
            tor.setExitCountry("xx") // Not offered: ignored.
            compare(researchStore.setting("web.torExit"), "us")
        }
        function test_settingsTurnItOnAndOff() {
            settings.openPage("web"); tryCompare(settings, "opened", true)
            const page = findChild(settings, "settingsPageLoader").item
            let toggle = null
            tryVerify(function() { toggle = visualChild(page, "torSwitch"); return toggle !== null })
            verify(!toggle.checked)
            compare(visualChild(page, "torStatus").text, "Off. Web tabs connect directly.")
            verify(!visualChild(page, "torNewIdentity").visible)
            mouseClick(toggle)
            verify(tor.enabled)
            tryCompare(tor, "state", "ready", 10000)
            tryCompare(visualChild(page, "torStatus"), "text", "On. Web tabs go out through Tor.")
            verify(visualChild(page, "torNewIdentity").visible)
            const box = visualChild(page, "torExitBox")
            compare(box.currentText, "Any country")
            box.currentIndex = 2
            box.activated(2)
            compare(tor.exitCountry, tor.countries[2].code)
            tryCompare(tor, "state", "ready", 10000)
            mouseClick(toggle)
            compare(tor.enabled, false)
            compare(visualChild(page, "torStatus").text, "Off. Web tabs connect directly.")
        }
    }
}
