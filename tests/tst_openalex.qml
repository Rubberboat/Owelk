import QtQuick
import QtTest
import "../qml" as App

Item {
    id: scene
    width: 900; height: 1000
    Component { id: settingsComponent; App.OpenAlexFollowing { width: 700 } }
    Component { id: personComponent; App.PersonRow { width: 450; service: researchStore.forYou } }
    SignalSpy { id: links; signalName: "linkRequested" }
    TestCase {
        name: "OpenAlexFollowing"
        when: windowShown
        function init() {
            for (const row of researchStore.forYou.entities()) researchStore.forYou.followEntity(row, false)
            researchStore.setSetting("forYou.openAlexBaseUrl", testInput.webFixture("/openalex").toString())
            links.clear()
        }
        function test_researcherSearchAndFollow() {
            const settings = createTemporaryObject(settingsComponent, scene)
            verify(settings !== null)
            findChild(settings, "openAlexName").text = "김주현"
            tryVerify(function() { return settings.suggestions.length > 0 })
            compare(settings.suggestions[0], "Juhyun Kim")
            findChild(settings, "openAlexFind").clicked()
            tryCompare(settings, "finding", false)
            tryVerify(function() { return settings.results.length === 1 })
            compare(settings.results[0].id, "A77")
            const follow = findChild(settings, "openAlexFollow-0")
            verify(follow !== null)
            follow.clicked()
            tryVerify(function() { return researchStore.forYou.followingEntity("A77") })
            tryCompare(follow, "enabled", false)
            compare(settings.followed[0].kind, "person")
            const existing = findChild(settings, "openAlexFollowed-0")
            existing.expanded = true
            verify(existing.links.some(function(link) { return link.key === "orcid" }))
            findChild(settings, "openAlexUnfollow-0").clicked()
            tryVerify(function() { return !researchStore.forYou.followingEntity("A77") })
        }
        function test_institutionSearchHomepageAndPaperList() {
            const settings = createTemporaryObject(settingsComponent, scene)
            const kind = findChild(settings, "openAlexKind")
            kind.currentIndex = 1; kind.activated(1)
            findChild(settings, "openAlexName").text = "Example University"
            findChild(settings, "openAlexFind").clicked()
            tryVerify(function() { return settings.results.length === 1 })
            const row = findChild(settings, "openAlexResult-0")
            verify(row !== null)
            links.target = row
            row.expanded = true
            findChild(row, "openAlexResult-0-homepage").clicked()
            compare(links.signalArguments[0][0].toString(), "https://example.org/university")
            findChild(row, "openAlexResult-0-papers").clicked()
            verify(decodeURIComponent(links.signalArguments[1][0].toString()).indexOf("authorships.institutions.lineage:I88") >= 0)
            findChild(settings, "openAlexFollow-0").clicked()
            tryVerify(function() { return researchStore.forYou.followingEntity("I88") })
            compare(settings.followed[0].kind, "institution")
        }
        function test_openAlexLinksNeverUseSemanticScholarIds() {
            const row = createTemporaryObject(personComponent, scene, {person: {id: "A77", kind: "person", name: "Juhyun Kim", orcid: "https://orcid.org/0000-0001"}})
            row.expanded = true
            verify(!row.loading)
            verify(!row.links.some(function(link) { return link.url.indexOf("semanticscholar.org") >= 0 }))
            verify(row.links.some(function(link) { return link.key === "orcid" }))
            verify(row.links.some(function(link) { return link.key === "websiteSearch" }))
        }
    }
}
