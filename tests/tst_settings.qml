import QtQuick
import QtQuick.Controls
import QtTest
import Owelk.Ui
import "../qml" as App
import "../qml/WorkspaceTree.js" as Tree

Item {
    id: scene
    width: 1100; height: 760
    App.SettingsDialog { id: settings }
    App.ReaderPane { id: reader; x: 0; y: 0; width: 500; height: 600; paneIndex: 0; isActive: true; visible: false }
    TestCase {
        name: "Settings"
        when: windowShown
        function visualChild(item, name) {
            if (!item) return null
            if (item.objectName === name) return item
            const children = item.children || []
            for (let i = 0; i < children.length; ++i) { const found = visualChild(children[i], name); if (found) return found }
            return null
        }
        function page() { return findChild(settings, "settingsPageLoader").item }
        function cleanup() {
            settings.close(); tryCompare(settings, "visible", false)
            Theme.theme = "neutral"; Theme.accentName = "blue"; Theme.textSize = 13; Theme.invertPages = false; Theme.appIcon = "paper"
            researchStore.setSetting("appearance.custom", "")
        }
        function test_titleBarAndOwnColors() {
            settings.openPage("appearance"); tryCompare(settings, "opened", true)
            tryVerify(function() { return page() !== null })
            // The system title bar follows the theme unless turned off (macOS and Windows draw one).
            compare(Theme.titleBar, true)
            verify(visualChild(settings.contentItem, "titleBarSwitch") !== null)
            Theme.titleBar = false
            compare(researchStore.setting("appearance.titleBar"), "0")
            Theme.titleBar = true
            compare(researchStore.setting("appearance.titleBar"), "1")
            Theme.styleWindow(settings) // Not a window: ignored.
            // Customize starts a custom theme from the one in use and shows its colors right below.
            Theme.theme = "nord"
            const customize = visualChild(settings.contentItem, "customizeColors")
            verify(customize.enabled)
            // It is in the first group: show the top of the page.
            let flick = customize.parent
            while (flick && flick.contentItem === undefined) flick = flick.parent
            if (flick) flick.contentY = 0
            waitForPolish(settings.contentItem); wait(50)
            mouseClick(customize)
            compare(Theme.theme, "custom")
            compare(Theme.seeds("custom").window, Theme.seeds("nord").window)
            verify(!customize.enabled)
            tryVerify(function() { const seed = visualChild(settings.contentItem, "seed-window"); return seed !== null && seed.visible })
        }
        function test_searchEnginesOfOnesOwn() {
            settings.openPage("web"); tryCompare(settings, "opened", true)
            tryVerify(function() { return page() !== null })
            const name = visualChild(settings.contentItem, "engineNameField"), address = visualChild(settings.contentItem, "engineAddressField")
            const add = visualChild(settings.contentItem, "addEngine")
            // Neither a site nor an address with %s: nothing to add.
            name.text = ""; address.text = "semantic scholar"
            verify(!add.enabled)
            // An address with %s is taken as it is, under the name typed.
            name.text = "Semantic"; address.text = "https://www.semanticscholar.org/search?q=%s"
            verify(add.enabled)
            add.clicked()
            tryVerify(function() { return visualChild(settings.contentItem, "removeEngine-Semantic") !== null })
            compare(name.text, "")
            // Chosen as the default (the small pill): searches go there, named after it.
            visualChild(settings.contentItem, "defaultEngine-Semantic").clicked()
            const template = "https://www.semanticscholar.org/search?q=%s"
            compare(researchStore.setting("searchEngine"), template)
            tryVerify(function() { return visualChild(settings.contentItem, "defaultEngine-Semantic").checked })
            compare(Tree.searchEngine(template).label, "Semantic")
            compare(Tree.webIntent("slam", template).title, "Search Semantic for \u201cslam\u201d")
            compare(Tree.webIntent("slam", template).url, "https://www.semanticscholar.org/search?q=slam")
            // The default is always shown; its eye cannot hide it.
            verify(!visualChild(settings.contentItem, "showEngine-Semantic").enabled)
            // Removed, the first built-in engine is the default again.
            visualChild(settings.contentItem, "removeEngine-Semantic").clicked()
            compare(researchStore.setting("searchEngine"), Tree.searchEngines[0].template)
            tryVerify(function() { return visualChild(settings.contentItem, "removeEngine-Semantic") === null })
            // A site is enough: its search address and name are filled in.
            address.text = "www.naver.com"
            compare(page().typedTemplate, "https://search.naver.com/search.naver?query=%s")
            compare(name.placeholderText, "Naver")
            add.clicked()
            tryVerify(function() { return visualChild(settings.contentItem, "removeEngine-Naver") !== null })
            address.text = "example.org/"
            compare(page().typedTemplate, "https://example.org/search?q=%s")
            compare(page().typedName, "Example")
            address.text = ""
            visualChild(settings.contentItem, "removeEngine-Naver").clicked()
            tryVerify(function() { return visualChild(settings.contentItem, "removeEngine-Naver") === null })
        }
        function test_hiddenEngineShowsCrossedEye() {
            settings.openPage("web"); tryCompare(settings, "opened", true)
            let eye = null
            tryVerify(function() { eye = visualChild(settings.contentItem, "showEngine-DuckDuckGo"); return eye !== null })
            const duck = Tree.searchEngines.find(function(e) { return e.name === "DuckDuckGo" }).template
            compare(eye.icon.name, "preview")
            eye.clicked()
            tryVerify(function() { return eye.icon.name === "hidden" })
            verify(visualChild(settings.contentItem, "engineRow-DuckDuckGo").opacity < 1, "dimmed")
            verify(JSON.parse(researchStore.setting("web.hiddenEngines")).indexOf(duck) >= 0)
            eye.clicked()
            tryVerify(function() { return eye.icon.name === "preview" })
            compare(visualChild(settings.contentItem, "engineRow-DuckDuckGo").opacity, 1)
            researchStore.setSetting("web.hiddenEngines", "")
        }
        function test_categoriesLoadOneAtATime() {
            settings.openPage("appearance"); tryCompare(settings, "opened", true)
            for (const id of ["appearance", "web", "search", "foryou", "ai", "shortcuts", "data"]) {
                mouseClick(visualChild(settings.contentItem, "settingsPage-" + id))
                compare(settings.page, id)
                tryVerify(function() { return page() !== null })
            }
            // Only the shown page exists.
            verify(visualChild(settings.contentItem, "themeTile-dark") === null)
            verify(visualChild(settings.contentItem, "backUpNow") !== null)
            verify(visualChild(settings.contentItem, "syncFolder") !== null)
            verify(visualChild(settings.contentItem, "renameKeptPdfs") !== null)
            // The pages scroll inside the dialog's outline (1 px in), not over it.
            const scroller = visualChild(settings.contentItem, "settingsScroller")
            compare(scroller.anchors.topMargin, 1); compare(scroller.anchors.rightMargin, 1); compare(scroller.anchors.bottomMargin, 1)
            verify(scroller.height <= scroller.parent.height - 2)
        }
        function test_paperNamePartsTurnOnAndMove() {
            researchStore.setSetting("pdfNames.parts", "")
            settings.openPage("data"); tryCompare(settings, "opened", true)
            // The rows are made again on each change: find them each time.
            const control = function(name) { let found = null; tryVerify(function() { found = visualChild(settings.contentItem, name); return found !== null }); return found }
            const flip = function(key) { const s = control("pdfNameSwitch-" + key); s.toggle(); s.toggled() }
            control("pdfNameSwitch-year")
            const p = page()
            // Author, year and title by default, as kept PDFs were named.
            compare(p.namesOn, ["author", "year", "title"])
            verify(findChild(settings, "pdfNameGroup").note.indexOf("Vaswani et al. - 2017 - Attention") >= 0)
            flip("year")
            compare(researchStore.setting("pdfNames.parts"), "author,-year,title,-arxiv")
            flip("author")
            compare(p.namesOn, ["title"])
            verify(!control("pdfNameSwitch-title").enabled, "the last part on stays on")
            // Year on and moved up, above the title.
            flip("year")
            control("pdfNameUp-year").clicked()
            compare(p.namesOn, ["year", "title"])
            compare(researchStore.setting("pdfNames.parts"), "year,-author,title,-arxiv")
            compare(researchStore.sampleFileName(p.namesOn), "2017 - Attention Is All You Need.pdf")
            verify(findChild(settings, "pdfNameGroup").note.indexOf("Example: 2017 - Attention") >= 0)
            researchStore.setSetting("pdfNames.parts", "")
        }
        function test_forYouTopicsAndCollections() {
            const forYou = researchStore.forYou
            forYou.saveTopics([])
            const collection = researchStore.createCollection("Follow Me")
            settings.openPage("foryou"); tryCompare(settings, "opened", true)
            let words = null
            tryVerify(function() { words = visualChild(settings.contentItem, "forYouTopicWords"); return words !== null })
            // A topic: words and categories, then on and off, then removed.
            words.text = "visual SLAM, loop closure"
            visualChild(settings.contentItem, "forYouTopicCategories").text = "cs.RO"
            visualChild(settings.contentItem, "forYouAddTopic").clicked()
            compare(forYou.topics().length, 1)
            compare(forYou.topics()[0].words, "visual SLAM, loop closure")
            compare(words.text, "")
            verify(forYou.configured)
            let toggle = null
            tryVerify(function() { toggle = visualChild(settings.contentItem, "forYouTopicSwitch-0"); return toggle !== null })
            toggle.toggle(); toggle.toggled()
            compare(forYou.topics()[0].on, false)
            verify(!forYou.configured)
            visualChild(settings.contentItem, "forYouRemoveTopic-0").clicked()
            compare(forYou.topics().length, 0)
            // People: found by name, then followed; and no longer.
            const graph = researchStore.setting("forYou.graphBaseUrl")
            researchStore.setSetting("forYou.graphBaseUrl", testInput.webFixture("/graph/v1").toString())
            const person = visualChild(settings.contentItem, "forYouPersonName")
            person.text = "Grace Hopper"
            visualChild(settings.contentItem, "forYouFindPeople").clicked()
            let followPerson = null
            tryVerify(function() { followPerson = visualChild(settings.contentItem, "forYouFollowPerson-0"); return followPerson !== null && followPerson.visible }, 10000)
            compare(visualChild(settings.contentItem, "forYouFoundPerson-0").label, "Grace Hopper")
            compare(visualChild(settings.contentItem, "forYouFoundPerson-0").detail, "Navy · 12 papers · h-index 5")
            followPerson.clicked()
            tryVerify(function() { return forYou.followingPerson("77") })
            tryVerify(function() { return visualChild(settings.contentItem, "forYouPerson-0") !== null })
            compare(visualChild(settings.contentItem, "forYouPerson-0").label, "Grace Hopper")
            compare(person.text, "")
            verify(forYou.configured)
            visualChild(settings.contentItem, "forYouRemovePerson-0").clicked()
            tryVerify(function() { return !forYou.followingPerson("77") })
            verify(!forYou.configured)
            researchStore.setSetting("forYou.graphBaseUrl", graph)
            // A collection with no arXiv ID or DOI cannot be followed yet.
            let follow = null
            tryVerify(function() { follow = visualChild(settings.contentItem, "forYouFollow-Follow Me"); return follow !== null })
            verify(!follow.enabled)
            researchStore.deleteCollection(collection)
            // Explain with AI waits for an AI to be set up; turning it on is the OK to send papers to it.
            researchStore.ai.provider = "claude"
            researchStore.ai.clearApiKey("claude")
            researchStore.setSetting("ai.consent.claude", "")
            let explain = null
            tryVerify(function() { explain = visualChild(settings.contentItem, "forYouAi"); return explain !== null })
            tryVerify(function() { return !explain.enabled })
            verify(researchStore.ai.setApiKey("claude", "sk-settings-test"))
            tryVerify(function() { return explain.enabled && !explain.checked })
            explain.toggle(); explain.toggled()
            verify(researchStore.ai.consented("claude"))
            compare(researchStore.setting("forYou.ai"), "1")
            tryVerify(function() { return explain.checked })
            verify(forYou.aiReady())
            researchStore.ai.clearApiKey("claude")
            researchStore.setSetting("ai.consent.claude", "")
        }
        function test_themeAccentAndTextSizeApplyAtOnce() {
            settings.openPage("appearance"); tryCompare(settings, "opened", true)
            tryVerify(function() { return visualChild(settings.contentItem, "themeTile-dark") !== null })
            waitForPolish(settings.contentItem); wait(50)
            mouseClick(visualChild(settings.contentItem, "themeTile-dark"), 40, 30)
            compare(Theme.theme, "dark")
            compare(researchStore.setting("appearance.theme"), "dark")
            mouseClick(visualChild(settings.contentItem, "accent-green"))
            compare(Theme.accentName, "green")
            const slider = visualChild(settings.contentItem, "textSizeSlider")
            slider.value = 15; slider.moved()
            compare(Theme.textSize, 15)
            compare(Theme.fontBody, 15)
        }
        function test_appIconChoice() {
            settings.openPage("appearance"); tryCompare(settings, "opened", true)
            let navy = null
            tryVerify(function() { navy = visualChild(settings.contentItem, "appIcon-navy"); return navy !== null })
            compare(Theme.appIcons.length, 3)
            // Scroll the page to the choice before clicking it.
            let flick = navy.parent
            while (flick && flick.contentItem === undefined) flick = flick.parent
            if (flick) flick.contentY = Math.max(0, navy.mapToItem(flick.contentItem, 0, 0).y - 40)
            waitForPolish(settings.contentItem); wait(50)
            mouseClick(navy)
            compare(Theme.appIcon, "navy")
            compare(researchStore.setting("appearance.appIcon"), "navy")
            Theme.appIcon = "unknown"
            compare(Theme.appIcon, "paper")
        }
        function test_customThemeStartsFromTheCurrentOne() {
            Theme.theme = "paper"
            settings.openPage("appearance"); tryCompare(settings, "opened", true)
            tryVerify(function() { return visualChild(settings.contentItem, "themeTile-custom") !== null })
            waitForPolish(settings.contentItem); wait(50)
            mouseClick(visualChild(settings.contentItem, "themeTile-custom"), 40, 30)
            compare(Theme.theme, "custom")
            compare(Theme.seeds("custom").window, Theme.seeds("paper").window)
            tryVerify(function() { return visualChild(settings.contentItem, "seed-window") !== null })
            mouseClick(visualChild(settings.contentItem, "customDarkSwitch"))
            compare(Theme.dark, true)
        }
        function test_aiPageAsksForTheAccountOnce() {
            // Reading the ChatGPT account refreshes the provider list; that must not ask again (a loop
            // that kept the CPU busy while Settings existed).
            const before = researchStore.ai.provider
            researchStore.ai.provider = "codex"
            const spy = Qt.createQmlObject('import QtTest; SignalSpy { signalName: "codexAccountChanged" }', scene)
            spy.target = researchStore.ai
            settings.openPage("ai"); tryCompare(settings, "opened", true)
            wait(1500)
            const settled = spy.count
            wait(3000)
            // Late answers to earlier requests can still arrive in a busy run; the old loop read the
            // account dozens of times a second.
            verify(spy.count - settled < 5, "the account is not read again and again: " + (spy.count - settled) + " more reads in 3 s")
            settings.close()
            researchStore.ai.provider = before
            spy.destroy()
        }
        function test_chatGptAccountIsAskedForAtStart() {
            // Codex keeps the ChatGPT sign-in when Owelk quits; an AI started with ChatGPT chosen asks for the
            // account at once, not only once Settings › AI opens (it looked signed out after every restart).
            const before = researchStore.ai.provider
            researchStore.ai.provider = "codex"
            const spy = Qt.createQmlObject('import QtTest; SignalSpy { signalName: "codexAccountChanged" }', scene)
            spy.target = researchStore.ai
            const controller = Qt.createComponent("../qml/AiController.qml").createObject(scene)
            verify(controller !== null)
            tryVerify(function() { return spy.count > 0 }, 10000, "the account was asked for")
            controller.destroy(); spy.destroy()
            researchStore.ai.provider = before
        }
        function test_aiInstructionsAndGlossModelAreKept() {
            settings.openPage("ai"); tryCompare(settings, "opened", true)
            tryVerify(function() { return findChild(settings, "aiInstructions") !== null })
            const instructions = findChild(settings, "aiInstructions")
            instructions.text = "  Put English terms in brackets.  "
            instructions.editingFinished()
            compare(researchStore.setting("ai.instructions"), "Put English terms in brackets.")
            // Models are chosen from the provider's list, as in the AI panel: the chat model and its
            // reasoning, and Gloss's own.
            const before = researchStore.ai.provider, chatModel = researchStore.ai.model("claude")
            researchStore.ai.provider = "claude"
            const models = findChild(settings, "aiModelBox")
            tryVerify(function() { return models.count > 2 })
            models.activated(1)
            compare(researchStore.ai.model("claude"), "claude-sonnet-5-5")
            const effort = findChild(settings, "aiEffortBox")
            tryCompare(effort, "visible", true)
            effort.activated(effort.model.indexOf("High"))
            compare(researchStore.setting("ai.effort.claude"), "high")
            // Other… takes a model name.
            models.activated(models.count - 1)
            tryCompare(findChild(settings, "aiModelField"), "visible", true)
            const gloss = findChild(settings, "aiGlossModelBox")
            compare(gloss.currentIndex, 0)
            compare(findChild(settings, "aiGlossEffortBox").visible, false) // Haiku has no effort levels.
            gloss.activated(2)
            compare(researchStore.ai.glossChoice("claude"), "claude-sonnet-5-5")
            tryCompare(findChild(settings, "aiGlossEffortBox"), "visible", true)
            gloss.activated(0)
            compare(researchStore.ai.glossChoice("claude"), "auto")
            researchStore.ai.setModel("claude", chatModel)
            researchStore.setSetting("ai.effort.claude", "")
            researchStore.ai.provider = before
            researchStore.setSetting("ai.instructions", "")
            settings.close()
        }
        function test_darkPagesOnlyWhileOn() {
            if (!Theme.canInvertPages) skip("built without Qt ShaderTools")
            reader.visible = true
            const canvas = findChild(reader, "pdfCanvas0")
            canvas.openFile(fixtureSource, {page: 0, zoom: 1})
            tryCompare(canvas, "ready", true, 10000)
            tryVerify(function() { return findChild(canvas, "pageImage0") !== null })
            const image = findChild(canvas, "pageImage0")
            compare(image.layer.enabled, false, "no effect costs while the option is off")
            settings.openPage("appearance"); tryCompare(settings, "opened", true)
            tryVerify(function() { return visualChild(settings.contentItem, "invertPagesSwitch") !== null })
            visualChild(settings.contentItem, "invertPagesSwitch").toggle()
            visualChild(settings.contentItem, "invertPagesSwitch").toggled()
            compare(Theme.invertPages, true)
            compare(image.layer.enabled, true)
            settings.close()
            // The software renderer used for tests cannot run shaders; with a GPU, the page turns dark.
            if (reader.GraphicsInfo.api !== GraphicsInfo.Software) {
                wait(300); waitForRendering(image)
                const pixels = grabImage(image)
                verify(pixels.red(4, 4) < 60, "page corner should be dark, got " + pixels.red(4, 4))
            }
            Theme.invertPages = false
            compare(image.layer.enabled, false)
            reader.visible = false
        }
    }
}
