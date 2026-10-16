import QtQuick
import QtTest
import "../qml" as App
import "../qml/WorkspaceTree.js" as Tree

Item {
    width: 1440; height: 930
    App.Main { id: workspace }
    SignalSpy { id: downloads; signalName: "downloadStarted" }
    SignalSpy { id: fetches; signalName: "downloadStarted" }
    TestCase {
        name: "WebTabs"
        when: windowShown
        function cleanupTestCase() { workspace.visible = false }
        function init() {
            workspace.width = 1440; workspace.height = 930
            workspace.documents.restore({})
            workspace.homeVisible = true
            researchStore.setSetting("downloadFolder", testInput.temporaryFolder("web downloads"))
        }
        // A paper downloaded again is offered from the Library first; these tests read the download itself.
        function readerOpens() {
            const dialog = findChild(workspace, "duplicateDialog")
            return function() {
                if (dialog && dialog.opened) findChild(dialog, "duplicateAddAnyway").clicked()
                return activeTab().kind !== "web"
            }
        }
        function activeTab() {
            const d = workspace.documents, g = Tree.find(d.tree, d.activeGroup)
            return g.tabs.find(function(t) { return t.id === g.activeTab })
        }
        function webPane() {
            let pane = null
            tryVerify(function() { const v = workspace.documents.groupView(workspace.documents.activeGroup); pane = v ? v.webPane : null; return pane !== null }, 5000)
            return pane
        }
        function visibleChild(item, name) {
            if (!item || !item.visible) return null
            if (item.objectName === name) return item
            for (let i = 0; i < item.children.length; ++i) { const f = visibleChild(item.children[i], name); if (f) return f }
            return null
        }
        function test_googleAccountSignInAndOut() {
            const d = workspace.documents
            compare(webAccounts.googleSignedIn, false)
            compare(webAccounts.googleSignInUrl().toString().indexOf("https://accounts.google.com/"), 0)
            // Google's refusal page is told apart (Owelk then says what to try).
            verify(webAccounts.refusedPage("https://accounts.google.com/v3/signin/rejected?continue=x"))
            verify(webAccounts.refusedPage("https://accounts.google.com/signin/rejected"))
            verify(!webAccounts.refusedPage("https://accounts.google.com/ServiceLogin"))
            verify(!webAccounts.refusedPage("https://example.org/signin/rejected"))
            const settings = findChild(workspace, "settingsDialog")
            settings.openPage("web"); tryCompare(settings, "opened", true)
            tryVerify(function() { return visibleChild(settings.contentItem, "googleSignIn") !== null })
            verify(visibleChild(settings.contentItem, "googleSignOut") === null)
            // Google's sign-in pages go as Firefox unless turned off (kept as a setting).
            const firefox = visibleChild(settings.contentItem, "googleFirefoxSwitch")
            verify(firefox.checked && webAccounts.firefoxForGoogle)
            // The sign-in pages' scripts see Firefox too (only there: other pages still see Chrome).
            compare(d.webProfile.userScripts.find(d.googleScriptName).length, 1)
            verify(webAccounts.firefoxScript().indexOf("accounts.google.com") > 0)
            firefox.toggle(); firefox.toggled()
            verify(!webAccounts.firefoxForGoogle)
            compare(researchStore.setting("web.googleAsFirefox"), "0")
            compare(d.webProfile.userScripts.find(d.googleScriptName).length, 0)
            firefox.toggle(); firefox.toggled()
            verify(webAccounts.firefoxForGoogle)
            compare(d.webProfile.userScripts.find(d.googleScriptName).length, 1)
            // What was kept from before is read from the profile's cookie file (the engine tells only once a
            // page has loaded).
            verify(testInput.keptGoogleSignIn(true))
            verify(!testInput.keptGoogleSignIn(false))
            // Signed in in a web tab (Google's cookie arrives in the profile): Signed in, with Sign Out.
            verify(d.openWeb(testInput.webFixture("/page.html").toString(), true))
            tryCompare(activeTab(), "title", "Owelk Test Page", 15000)
            let agent = ""
            webPane().view.runJavaScript("navigator.userAgent", function(result) { agent = result })
            tryVerify(function() { return agent.length > 0 })
            verify(agent.indexOf("Firefox") < 0 && agent.indexOf("Chrome") > 0, agent)
            // What the script does on Google's sign-in page, tried here: Firefox all through.
            let seen = ""
            webPane().view.runJavaScript(webAccounts.firefoxScript().replace('location.hostname !== "accounts.google.com"', 'false')
                + "; [navigator.userAgent, navigator.vendor, typeof navigator.userAgentData, typeof window.chrome].join('|')",
                function(result) { seen = result })
            tryVerify(function() { return seen.length > 0 })
            const parts = seen.split("|")
            verify(parts[0].indexOf("Firefox/") > 0 && parts[0].indexOf("Chrome") < 0, parts[0])
            compare(parts.slice(1), ["", "undefined", "undefined"])
            d.closeTab(activeTab().id)
            testInput.setWebCookie(d.webProfile, "SID", ".google.com", "https://accounts.google.com/")
            testInput.setWebCookie(d.webProfile, "LOGIN_INFO", ".youtube.com", "https://www.youtube.com/")
            tryCompare(webAccounts, "googleSignedIn", true, 10000)
            let signOut = null
            tryVerify(function() { signOut = visibleChild(settings.contentItem, "googleSignOut"); return signOut !== null })
            compare(visibleChild(settings.contentItem, "settingsRow-googleAccount").label, "Signed in to Google")
            signOut.clicked()
            tryCompare(webAccounts, "googleSignedIn", false, 10000)
            tryVerify(function() { return visibleChild(settings.contentItem, "googleSignIn") !== null })
            // A page from Settings opens in a web tab of its own, and Settings closes.
            workspace.openWebPage(testInput.webFixture("/page.html"))
            tryCompare(settings, "opened", false)
            tryVerify(function() { return activeTab().kind === "web" })
            d.closeTab(activeTab().id)
        }
        function test_routerAndHelpers() {
            verify(Tree.validate({kind: "group", id: "g", activeTab: "t", tabs: [Tree.webTab("https://arxiv.org/abs/1")].map(function(t) { t.id = "t"; return t })}, {}, 0))
            verify(!Tree.validate({kind: "group", id: "g", activeTab: "t", tabs: [{id: "t", kind: "web", source: "javascript:alert(1)", position: {page: 0}}]}, {}, 0))
            compare(Tree.addressToUrl("arxiv.org/abs/1706.03762", "S=%s"), "https://arxiv.org/abs/1706.03762")
            compare(Tree.addressToUrl("occlusion mapping", "https://s/?q=%s"), "https://s/?q=occlusion%20mapping")
            compare(Tree.arxivPdf("https://arxiv.org/abs/1706.03762v7"), "https://arxiv.org/pdf/1706.03762v7")
            verify(!workspace.documents.openResource("ftp://example.com/x"))
        }
        function test_webTabTitleSessionAndPdfDownload() {
            const d = workspace.documents
            const page = testInput.webFixture("/page.html")
            verify(d.openResource(page))
            compare(activeTab().kind, "web")
            const pane = webPane()
            tryCompare(activeTab(), "title", "Owelk Test Page", 15000)
            const tabLabel = findChild(d.groupView(d.activeGroup), "tab-" + activeTab().id)
            verify(tabLabel !== null)
            // The session keeps web tabs by address and survives validation.
            const saved = d.snapshot()
            verify(Tree.validate(saved.tree, {}, 0))
            verify(JSON.stringify(saved.tree).indexOf("/page.html") >= 0)
            // A PDF link inside the page downloads into the chosen folder and opens next to the page.
            const webTabId = activeTab().id
            pane.view.runJavaScript("document.getElementById('pdf').click()")
            tryVerify(readerOpens(), 15000)
            const opened = activeTab()
            verify(opened.source.indexOf("web%20downloads") >= 0 || opened.source.indexOf("web downloads") >= 0, opened.source)
            verify(Tree.owner(d.tree, webTabId) !== undefined && Tree.owner(d.tree, webTabId) !== null) // The page stays open.
            tryVerify(function() { const r = workspace.currentReader; return r && findChild(r, "pdfCanvas0").ready }, 10000)
            // Opening a PDF address directly replaces the tab that only fetched it.
            verify(d.openWeb(testInput.webFixture("/paper.pdf").toString(), true))
            const fetching = activeTab().id
            tryVerify(readerOpens(), 15000)
            verify(!Tree.owner(d.tree, fetching))
            verify(researchStore.downloadTarget("paper.pdf").fileName !== "paper.pdf") // Never overwrites.
            // A page opened to get one paper (For You): the PDF downloaded there joins the Library unopened
            // (still unread, as Add leaves it) and the page closes.
            const before = researchStore.libraryDocuments({}).map(function(r) { return r.url.toString() })
            const tabsBefore = Tree.leaves(d.tree).reduce(function(n, g) { return n + g.tabs.length }, 0)
            verify(d.openWeb(page.toString(), true, "", true))
            const paperPage = activeTab().id
            tryCompare(activeTab(), "title", "Owelk Test Page", 15000)
            webPane().view.runJavaScript("document.getElementById('pdf').click()")
            tryVerify(function() { return !Tree.owner(d.tree, paperPage) }, 15000)
            compare(Tree.leaves(d.tree).reduce(function(n, g) { return n + g.tabs.length }, 0), tabsBefore, "nothing opened")
            let added = null
            tryVerify(function() { added = researchStore.libraryDocuments({}).find(function(r) { return before.indexOf(r.url.toString()) < 0 }); return !!added }, 10000)
            compare(added.readingState, "unread")
        }
        function test_downloadShowsProgressAndPdfsCanStayInTheTab() {
            const d = workspace.documents
            verify(d.openResource(testInput.webFixture("/page.html")))
            const pane = webPane()
            tryCompare(activeTab(), "title", "Owelk Test Page", 15000)
            // A download announces itself and shows its bar until the reader opens.
            downloads.clear(); downloads.target = pane
            pane.view.runJavaScript("document.getElementById('pdf').click()")
            tryCompare(downloads, "count", 1, 15000)
            verify(downloads.signalArguments[0][0].indexOf(".pdf") > 0)
            tryVerify(readerOpens(), 15000)
            // Shown in the tab instead: no download until Open in Reader.
            d.activateTab(Tree.leaves(d.tree)[0].tabs.find(function(t) { return t.kind === "web" }).id)
            const again = webPane()
            const fetched = fetches
            fetched.clear(); fetched.target = again
            tryVerify(function() { return again.view.url.toString().indexOf("page.html") > 0 && !again.view.loading }, 15000)
            again.browserPdf = true // Changing the viewer setting reloads the page.
            wait(300)
            tryVerify(function() { return !again.view.loading }, 15000)
            again.view.url = testInput.webFixture("/paper.pdf")
            tryVerify(function() { return again.showsPdf && !again.view.loading }, 15000)
            wait(500)
            compare(fetched.count, 0)
            compare(activeTab().kind, "web")
            const button = findChild(again, "webOpenInReader")
            tryCompare(button, "visible", true)
            const before = Tree.leaves(d.tree)[0].tabs.length
            button.clicked()
            tryCompare(fetched, "count", 1, 15000)
            tryVerify(readerOpens(), 15000)
            compare(Tree.leaves(d.tree)[0].tabs.length, before + 1) // The web tab stays.
            again.browserPdf = false
        }
        function test_aPaperDownloadedAgainOffersTheOneKept() {
            const d = workspace.documents
            const dialog = findChild(workspace, "duplicateDialog")
            // The first download is the Library's copy; the same paper again asks first.
            verify(d.openWeb(testInput.webFixture("/paper.pdf").toString(), true))
            tryVerify(readerOpens(), 15000)
            const first = activeTab().source
            verify(d.openWeb(testInput.webFixture("/paper.pdf").toString(), true))
            tryCompare(dialog, "opened", true, 15000)
            verify(dialog.download)
            compare(dialog.items[0].existingName, researchStore.fileName(first))
            const fresh = dialog.items[0].source
            // Open It: the copy already kept opens and the new download goes to the Trash.
            mouseClick(findChild(dialog, "duplicateOpenExisting"))
            tryVerify(function() { return activeTab().kind !== "web" && researchStore.sameSource(activeTab().source, first) }, 15000)
            tryVerify(function() { return !testInput.fileExists(fresh) })
        }
        function test_downloadBarFillsWithTheFileSize() {
            const d = workspace.documents
            verify(d.openResource(testInput.webFixture("/page.html")))
            const pane = webPane()
            tryCompare(activeTab(), "title", "Owelk Test Page", 15000)
            downloads.clear(); downloads.target = pane
            pane.view.url = testInput.webFixture("/slow.pdf")
            tryCompare(downloads, "count", 1, 15000)
            const bar = findChild(pane, "webDownloadBar"), track = findChild(pane, "webDownloadProgress")
            const label = findChild(pane, "webDownloadLabel")
            tryCompare(bar, "visible", true)
            // The size is known: a filling bar and the file size, no percentages or running bytes.
            tryCompare(track, "visible", true, 5000)
            tryVerify(function() { return track.progress > 0 && track.progress < 1 }, 5000)
            verify(/· 9\d\d KB$/.test(label.text), label.text)
            verify(label.text.indexOf("%") < 0 && label.text.indexOf(" of ") < 0)
            const first = track.progress
            tryVerify(function() { return track.progress > first }, 5000)
            tryVerify(readerOpens(), 15000)
        }
        function test_pageWithAFramedPdfOffersBothWays() {
            const d = workspace.documents
            verify(d.openResource(testInput.webFixture("/embed.html")))
            const pane = webPane()
            tryCompare(activeTab(), "title", "getPDF", 15000)
            const notice = findChild(pane, "webPdfNotice")
            tryCompare(notice, "visible", true, 10000)
            verify(pane.embeddedPdf.indexOf("/paper.pdf") > 0)
            compare(findChild(pane, "webShowPdfHere").visible, true)
            // Show Here keeps PDFs in the tab (the page reloads with the viewer on).
            findChild(pane, "webShowPdfHere").clicked()
            compare(pane.browserPdf, true)
            tryVerify(function() { return !pane.view.loading && pane.embeddedPdf.length > 0 }, 15000)
            compare(findChild(pane, "webShowPdfHere").visible, false)
            // Open in Reader fetches the framed PDF through the tab and opens it beside the page.
            const webTab = activeTab().id
            downloads.clear(); downloads.target = pane
            findChild(pane, "webOpenInReader").clicked()
            tryCompare(downloads, "count", 1, 15000)
            tryVerify(readerOpens(), 15000)
            verify(Tree.owner(d.tree, webTab) !== null && Tree.owner(d.tree, webTab) !== undefined)
        }
        function test_homeTabSearchesTheWeb() {
            const d = workspace.documents
            // Cmd+T opens Home in a tab; its one search field opens a web tab in place of that Home tab.
            verify(d.openResource(testInput.webFixture("/page.html")))
            tryCompare(activeTab(), "kind", "web")
            d.newHomeTab()
            tryCompare(activeTab(), "kind", "home")
            const homeTab = activeTab().id
            let home = null
            tryVerify(function() { const v = d.groupView(d.activeGroup); home = v ? findChild(v, "homeView") : null; return home !== null && home.visible })
            const field = findChild(home, "homeSearch")
            verify(field.placeholderText.indexOf("the web") > 0)
            verify(findChild(home, "homeWebSearch") === null) // One field, not two.
            // An address puts the web row first, so Return opens it.
            field.text = testInput.webFixture("/page.html").toString()
            field.forceActiveFocus()
            tryVerify(function() { return home.rows.length > 0 && home.rows[0].kind === "web" })
            testInput.keyClick(field, Qt.Key_Return)
            // Return may wait for the saved items first, so look at the active tab again each time.
            tryVerify(function() { return activeTab().kind === "web" })
            compare(activeTab().id, homeTab)
            verify(activeTab().source.indexOf("/page.html") > 0)
            // Words search with the chosen engine.
            researchStore.setSetting("searchEngine", testInput.webFixture("/page.html").toString() + "?q=%s")
            d.newHomeTab()
            tryVerify(function() { const v = d.groupView(d.activeGroup); home = v ? findChild(v, "homeView") : null; return home !== null && home.visible && activeTab().kind === "home" })
            // Words: the web row comes last (the Library's matches first); Ctrl/⌘+Return goes to the web.
            const words = findChild(home, "homeSearch")
            words.text = "lidar odometry"
            words.forceActiveFocus()
            tryVerify(function() { return home.rows.length > 0 && home.rows[home.rows.length - 1].kind === "web" })
            verify(home.rows[home.rows.length - 1].title.indexOf("lidar odometry") > 0)
            testInput.keyClick(words, Qt.Key_Return, Qt.ControlModifier)
            tryVerify(function() { return activeTab().kind === "web" && activeTab().source.indexOf("q=lidar%20odometry") > 0 })
            researchStore.setSetting("searchEngine", "")
        }
        function test_webRegionGoesToTheAi() {
            const d = workspace.documents
            const page = testInput.webFixture("/page.html?region")
            verify(d.openResource(page))
            const pane = webPane()
            tryCompare(activeTab(), "title", "Owelk Test Page", 15000)
            wait(300)
            const ai = findChild(workspace, "aiController")
            ai.images = []
            pane.captureRegion(Qt.rect(0, 0, 300, 120))
            tryVerify(function() { return ai.images.length === 1 }, 10000)
            compare(ai.images[0].name, "Web · Owelk Test Page")
            const image = testInput.imageSize(ai.images[0].url)
            verify(image.width > 50 && image.height > 20, JSON.stringify(image))
            ai.images = []
        }
        function test_shortcutOpensWebTabAndAddressNavigates() {
            const d = workspace.documents
            d.openDocument(fixtureSource, null, true)
            workspace.homeVisible = false
            researchStore.setSetting("startPage", testInput.webFixture("/page.html").toString())
            findChild(workspace, "openWebAction").trigger()
            compare(activeTab().kind, "web")
            const pane = webPane()
            const address = findChild(pane, "webAddress")
            tryVerify(function() { return address.focus }) // activeFocus needs the window to be active, which offscreen tests are not.
            tryCompare(activeTab(), "title", "Owelk Test Page", 15000) // Let the start page finish loading first.
            address.text = testInput.webFixture("/page.html?second").toString()
            address.accepted()
            tryVerify(function() { return activeTab().source.indexOf("second") >= 0 }, 15000)
            tryVerify(function() { return pane.view.canGoBack }, 15000)
            mouseClick(findChild(pane, "webBack"))
            tryVerify(function() { return activeTab().source.indexOf("second") < 0 }, 15000)
            researchStore.setSetting("startPage", "")
        }
    }
}
