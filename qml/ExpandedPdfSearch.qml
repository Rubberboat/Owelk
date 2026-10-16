import QtQuick
import QtQml.Models
import QtQuick.Pdf

// Union literal PDF matches for the original words and their Korean search alternatives.
// Each location and polygon comes from Qt's PDF search, so translations never invent coordinates.
Item {
    id: root
    objectName: "expandedPdfSearch"
    property var document
    property string searchString: ""
    property int currentPage: 0
    property int currentResult: -1
    property var results: []
    property var terms: []
    property var polygonCache: ({})
    readonly property var currentResultLink: results[currentResult] || ({page: 0, location: Qt.point(0, 0)})
    signal modelReset()
    signal currentPageBoundingPolygonsChanged()
    function rowCount() { return results.length }
    function updateTerms() {
        results = []; polygonCache = ({}); currentResult = -1; modelReset()
        terms = searchString.trim().length ? researchStore.searchText.variants(searchString).slice(0, 24) : []
    }
    onSearchStringChanged: { researchStore.searchText.prepare(searchString); updateTerms() }
    onDocumentChanged: updateTerms()
    onCurrentPageChanged: polygonsLater.restart()
    Connections {
        target: researchStore.searchText
        function onConfigurationChanged() { root.updateTerms() }
        function onChanged(query) { if (query === root.searchString.trim().replace(/\s+/g, " ")) root.updateTerms() }
    }
    function collect() {
        const rows = [], seen = {}
        const previous = results[currentResult]
        for (let i = 0; i < models.count; ++i) {
            const model = models.objectAt(i)
            if (!model) continue
            for (let n = 0; n < model.rowCount(); ++n) {
                const index = model.index(n, 0), page = model.data(index, 256), point = model.data(index, 258)
                if (!point) continue
                const key = page + ":" + point.x + ":" + point.y
                if (seen[key]) continue
                seen[key] = true
                rows.push({page: page, location: point, key: key})
            }
        }
        rows.sort(function(a, b) { return a.page - b.page || a.location.y - b.location.y || a.location.x - b.location.x })
        polygonCache = ({})
        results = rows
        const retained = previous ? rows.findIndex(function(r) { return r.key === previous.key }) : -1
        modelReset()
        currentResult = rows.length ? Math.max(0, retained) : -1
        polygonsLater.restart()
    }
    function boundingPolygonsOnPage(page) {
        if (polygonCache[page]) return polygonCache[page]
        const polygons = [], seen = {}
        for (let i = 0; i < models.count; ++i) {
            const model = models.objectAt(i)
            if (!model) continue
            for (const polygon of model.boundingPolygonsOnPage(page)) {
                const key = JSON.stringify(polygon)
                if (!seen[key]) { seen[key] = true; polygons.push(polygon) }
            }
        }
        polygonCache[page] = polygons
        return polygons
    }
    Timer { id: polygonsLater; interval: 16; onTriggered: root.currentPageBoundingPolygonsChanged() }
    Timer { id: collectLater; interval: 30; onTriggered: root.collect() }
    Instantiator {
        id: models
        model: root.terms
        delegate: PdfSearchModel {
            required property string modelData
            document: root.document
            currentPage: root.currentPage
            searchString: modelData
            onRowsInserted: collectLater.restart()
            onRowsRemoved: collectLater.restart()
            onModelReset: collectLater.restart()
            onCurrentPageBoundingPolygonsChanged: polygonsLater.restart()
        }
        onObjectAdded: collectLater.restart()
        onObjectRemoved: collectLater.restart()
    }
}
