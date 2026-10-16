import QtQuick
import QtTest
import "../qml" as App
import "../qml/WebSearch.js" as WebSearch
import "../qml/WorkspaceTree.js" as Tree

Item {
    id: scene
    width: 850; height: 750
    App.ReaderPane { id: reader; width: 700; height: 700; paneIndex: 0; isActive: true }
    App.ResearchSearch { id: search; active: false; withWeb: false }
    App.CommandPalette { id: commands; hasDocument: true }
    Component { id: settingsComponent; App.SettingsSearch { width: 500 } }
    Component { id: libraryComponent; App.LibraryView { width: 800; height: 700 } }
    TestCase {
        name: "KoreanSearch"
        when: windowShown
        function init() {
            search.active = false
            reader.source = testInput.koreanSearchFixture()
            tryVerify(function() { return reader.pdfReady })
            tryCompare(findChild(reader, "pdfCanvas0"), "restoring", false)
        }
        function cleanup() {
            search.active = false
            findChild(reader, "pdfCanvas0").searchString = ""
            commands.close()
        }
        function test_koreanNameFindsBothPdfSpellingsAtRealLocations() {
            const canvas = findChild(reader, "pdfCanvas0")
            canvas.searchString = "김주현"
            tryCompare(canvas, "matchCount", 2, 10000)
            compare(canvas.searchString, "김주현")
            const model = findChild(canvas, "expandedPdfSearch")
            compare(model.results[0].page, 0)
            compare(model.results[1].page, 1)
            verify(model.boundingPolygonsOnPage(0).length > 0)
            verify(model.boundingPolygonsOnPage(1).length > 0)
            canvas.nextMatch(1)
            tryCompare(canvas, "currentPage", 1)
            canvas.nextMatch(-1)
            tryCompare(canvas, "currentPage", 0)
            canvas.searchString = "레이더 오도메트리"
            tryCompare(canvas, "matchCount", 1, 10000)
            compare(model.results[0].page, 0)
            canvas.searchString = ""
            tryCompare(canvas, "matchCount", 0)
        }
        function test_homeAndUnifiedSearchUseKoreanAuthorAndTopic() {
            verify(researchStore.updateDocumentDetails(reader.source, {title: "Radar Odometry", authors: "Juhyun Kim", year: "2025"}))
            search.query = "김주현 레이더"
            search.active = true
            tryVerify(function() { return !search.waiting && search.results.some(function(r) { return r.kind === "paper" && r.authors === "Juhyun Kim" }) }, 10000)
            compare(search.results.filter(function(r) { return r.kind === "paper" && r.authors === "Juhyun Kim" }).length, 1)
            compare(search.query, "김주현 레이더")
            search.query = "김주현 year:2026"
            tryVerify(function() { return !search.waiting && search.results.length === 0 }, 10000)
        }
        function test_commandSearchUsesKoreanWithoutChangingCommand() {
            commands.open()
            tryCompare(commands, "opened", true)
            findChild(commands, "paletteQuery").text = "설정"
            verify(commands.results.some(function(r) { return r.title.indexOf("Settings") >= 0 }))
        }
        function test_librarySearchDoesNotFilterViewsWithoutASearchBox() {
            verify(researchStore.updateDocumentDetails(reader.source, {title: "Radar Odometry", authors: "Juhyun Kim", year: "2025"}))
            const library = createTemporaryObject(libraryComponent, scene)
            verify(library !== null)
            const field = findChild(library, "libraryQuery")
            field.text = "김주현"
            tryVerify(function() { return library.rows.some(function(r) { return r.authors === "Juhyun Kim" }) })
            const note = researchStore.createNote("Unrelated note", "A note remains visible when switching views")
            field.text = "아무것도찾을수없음"
            library.setView("notes")
            verify(!field.visible)
            verify(library.noteRows.some(function(r) { return r.id === note }))
            researchStore.deleteNote(note)
        }
        function test_aiTranslationSettingIsOnByDefaultAndCanBeDisabled() {
            const before = researchStore.ai.provider
            const consent = researchStore.setting("ai.consent.claude", "")
            const page = createTemporaryObject(settingsComponent, scene)
            verify(page !== null)
            const toggle = findChild(page, "searchAiTranslation")
            verify(toggle.checked)
            researchStore.ai.provider = "ollama"
            researchStore.ai.giveConsent("ollama")
            tryCompare(toggle, "enabled", true)
            researchStore.ai.provider = "claude"
            researchStore.setSetting("ai.consent.claude", "")
            verify(!researchStore.ai.canSend())
            verify(toggle.enabled) // An unavailable provider must not prevent turning this off.
            toggle.toggle(); toggle.toggled()
            compare(researchStore.setting("search.aiTranslation"), "0")
            researchStore.setSetting("ai.consent.claude", consent)
            researchStore.ai.provider = before
            researchStore.setSetting("search.aiTranslation", "1")
        }
        function test_webQueriesExpandButAddressesStayExact() {
            const query = WebSearch.input(researchStore, "김주현")
            verify(query.indexOf("김주현") >= 0)
            verify(query.indexOf("Juhyun Kim") >= 0)
            compare(WebSearch.input(researchStore, "https://example.org/김주현"), "https://example.org/김주현")
            compare(WebSearch.input(researchStore, "arxiv: 2601.01234"), "arxiv: 2601.01234")
            compare(WebSearch.words(researchStore, "https://example.org/김주현"), "")
            compare(WebSearch.words(researchStore, "scholar: 레이더"), "레이더")
            const scholar = WebSearch.input(researchStore, "scholar: 레이더")
            verify(scholar.indexOf("scholar:") === 0)
            verify(decodeURIComponent(Tree.addressToUrl(scholar, "https://example.org/?q=%s")).indexOf("radar") >= 0)
        }
    }
}
