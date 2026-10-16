import QtQuick
import QtTest
import "../qml" as App

Item {
    id: scene
    width: 700; height: 800
    QtObject {
        id: mockPeople
        property var requests: []
        signal personDetailsFound(string id, var person, string error)
        function personDetails(id) { requests = requests.concat([id]) }
    }
    Component {
        id: rowComponent
        App.PersonRow { objectName: "person"; width: 400; service: mockPeople; actionName: "follow" }
    }
    Component { id: settingsComponent; App.SettingsForYou { width: 500 } }
    SignalSpy { id: links; signalName: "linkRequested" }
    SignalSpy { id: follows; signalName: "followRequested" }
    TestCase {
        name: "People"
        when: windowShown
        function init() { mockPeople.requests = []; links.clear(); follows.clear() }
        function row(person) {
            const item = createTemporaryObject(rowComponent, scene, {person: person})
            verify(item !== null)
            links.target = item; follows.target = item
            return item
        }
        function expand(item) {
            waitForPolish(item)
            mouseClick(findChild(item, "person-expand"))
            tryCompare(item, "expanded", true)
        }
        function test_expandLoadsOnceAndKeepsFollowSeparate() {
            const item = row({id: "77", name: "Grace Hopper", detail: "12 papers"})
            const collapsedHeight = item.height
            compare(mockPeople.requests.length, 0)
            verify(!findChild(item, "person-details").visible)
            expand(item)
            compare(mockPeople.requests, ["77"])
            verify(item.loading)
            mockPeople.personDetailsFound("99", {affiliation: "Wrong person"}, "")
            verify(item.loading)
            mockPeople.personDetailsFound("77", {id: "77", affiliation: "Navy", homepage: "https://example.org/hopper", profileLoaded: true}, "")
            verify(!item.loading)
            compare(findChild(item, "person-affiliation").text, "Navy")
            tryVerify(function() { return item.height > collapsedHeight })
            const toggle = findChild(item, "person-expand")
            toggle.forceActiveFocus()
            keyClick(Qt.Key_Space)
            tryCompare(item, "expanded", false)
            keyClick(Qt.Key_Space)
            tryCompare(item, "expanded", true)
            compare(mockPeople.requests.length, 1)
            compare(follows.count, 0)
            findChild(item, "follow").clicked()
            compare(follows.count, 1)
        }
        function test_knownHomepageAndExactPaperList() {
            const item = row({id: "77", name: "Grace Hopper", affiliation: "Navy", homepage: "https://example.org/hopper", profileLoaded: true})
            expand(item)
            compare(mockPeople.requests.length, 0)
            findChild(item, "person-homepage").clicked()
            compare(links.signalArguments[0][0].toString(), "https://example.org/hopper")
            findChild(item, "person-papers").clicked()
            compare(links.signalArguments[1][0].toString(), "https://www.semanticscholar.org/author/77")
            findChild(item, "person-scholar").clicked()
            verify(decodeURIComponent(links.signalArguments[2][0].toString()).indexOf('"Grace Hopper" Navy') >= 0)
            compare(findChild(item, "person-websiteSearch"), null)
            verify(item.expanded)
            compare(follows.count, 0)
        }
        function test_missingDetailsOfferClearlyNamedSearches() {
            const item = row({id: "88", name: "Kim & Lee", profileLoaded: true})
            expand(item)
            compare(findChild(item, "person-homepage"), null)
            compare(findChild(item, "person-affiliation").text, "Affiliation not listed.")
            findChild(item, "person-websiteSearch").clicked()
            verify(links.signalArguments[0][0].toString().indexOf("%26") >= 0)
            verify(decodeURIComponent(links.signalArguments[0][0].toString()).indexOf('"Kim & Lee" homepage') >= 0)
            // The same name is not the same author; a reused row must replace all links.
            item.person = {id: "99", name: "Kim & Lee", profileLoaded: true}
            findChild(item, "person-papers").clicked()
            compare(links.signalArguments[1][0].toString(), "https://www.semanticscholar.org/author/99")
            mockPeople.personDetailsFound("88", {homepage: "https://wrong.example"}, "")
            compare(findChild(item, "person-homepage"), null)
        }
        function test_failureKeepsLinksAndCanRetry() {
            const item = row({id: "77", name: "Grace Hopper"})
            expand(item)
            mockPeople.personDetailsFound("77", {}, "Semantic Scholar is busy.")
            verify(!item.loading)
            verify(findChild(item, "person-retry").visible)
            findChild(item, "person-papers").clicked()
            compare(links.count, 1)
            findChild(item, "person-retry").clicked()
            compare(mockPeople.requests.length, 2)
            verify(item.loading)
            mockPeople.personDetailsFound("77", {id: "77", profileLoaded: true}, "")
            compare(item.error, "")
        }
        function test_linksFitNarrowWidth() {
            const item = row({id: "77", name: "A very long researcher name", affiliation: "A long university affiliation for identifying a researcher", homepage: "https://example.org/a/very/long/homepage/address", profileLoaded: true})
            item.width = 280
            expand(item)
            waitForPolish(item)
            for (const key of ["homepage", "papers", "scholar"]) {
                const link = findChild(item, "person-" + key)
                verify(link.width <= item.width - 24)
                verify(link.width > 0)
            }
        }
        function test_settingsSearchFollowAndExpandExistingPerson() {
            const forYou = researchStore.forYou
            const previousBase = researchStore.setting("forYou.graphBaseUrl")
            researchStore.setSetting("forYou.graphBaseUrl", testInput.webFixture("/graph/v1").toString())
            const page = createTemporaryObject(settingsComponent, scene)
            verify(page !== null)
            try {
                findChild(page, "forYouPersonName").text = "Grace Hopper"
                findChild(page, "forYouFindPeople").clicked()
                tryVerify(function() { return page.foundPeople.length === 1 }, 10000)
                const found = findChild(page, "forYouFoundPerson-0")
                verify(found !== null)
                found.expanded = true
                compare(found.profile.homepage, "https://example.org/hopper")
                verify(!forYou.followingPerson("77"))
                findChild(page, "forYouFollowPerson-0").clicked()
                tryVerify(function() { return forYou.followingPerson("77") })
                tryCompare(page, "foundPeople", [])
                const followed = findChild(page, "forYouPerson-0")
                verify(followed !== null)
                followed.expanded = true
                tryVerify(function() { return followed.profile.profileLoaded === true })
                compare(followed.profile.homepage, "https://example.org/hopper")
                findChild(page, "forYouRemovePerson-0").clicked()
                tryVerify(function() { return !forYou.followingPerson("77") })
            } finally {
                forYou.followPerson({id: "77"}, false)
                researchStore.setSetting("forYou.graphBaseUrl", previousBase)
            }
        }
    }
}
