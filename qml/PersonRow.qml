import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Owelk.Ui

// The same identity check before following someone and in the list of existing follows.
Item {
    id: root
    required property var person
    required property var service
    property bool followed: false
    property bool removable: false
    property string actionName: ""
    property bool expanded: false
    property var profile: person
    property bool loading: false
    property string error: ""
    readonly property bool openAlex: person.kind === "person" || person.kind === "institution"
    readonly property bool institution: person.kind === "institution"
    readonly property string label: person.name || ""
    readonly property string detail: profile.detail || person.detail || "No details"
    signal followRequested()
    signal linkRequested(url address)
    width: parent ? parent.width : 0
    implicitHeight: content.implicitHeight

    function loadDetails() {
        if (!person || !profile || !service || loading || openAlex || profile.profileLoaded) return
        loading = true; error = ""
        service.personDetails(person.id)
    }
    onExpandedChanged: { if (expanded) loadDetails() }
    Component.onCompleted: { if (expanded) loadDetails() }
    onPersonChanged: {
        profile = person; loading = false; error = ""
        if (expanded) loadDetails()
    }
    Connections {
        target: root.service
        function onPersonDetailsFound(id, person, error) {
            if (id !== root.person.id) return
            root.loading = false
            root.error = error
            if (!error.length) root.profile = person
        }
    }
    readonly property var links: {
        const affiliation = profile.affiliation || ""
        const query = '"' + label + '"' + (affiliation ? " " + affiliation : "")
        const result = []
        if (profile.homepage) result.push({key: "homepage", title: "Homepage", detail: profile.homepage, url: profile.homepage})
        if (openAlex) {
            result.push({key: "papers", title: "Paper List", detail: "OpenAlex · publications for this record",
                url: "https://openalex.org/works?filter=" + encodeURIComponent((institution ? "authorships.institutions.lineage:" : "authorships.author.id:") + person.id)})
            result.push({key: "profile", title: "OpenAlex Profile", detail: "Check this " + (institution ? "institution" : "researcher") + " record",
                url: "https://openalex.org/" + encodeURIComponent(person.id)})
            if (profile.orcid) result.push({key: "orcid", title: "ORCID", detail: profile.orcid, url: profile.orcid})
        } else {
            result.push({key: "papers", title: "Paper List", detail: "Semantic Scholar · this author's publications",
                url: "https://www.semanticscholar.org/author/" + encodeURIComponent(person.id)})
        }
        result.push({key: "scholar", title: "Search Google Scholar", detail: institution ? "Find publications mentioning this institution" : "Find matching researcher profiles",
            url: (institution ? "https://scholar.google.com/scholar?q=" : "https://scholar.google.com/citations?view_op=search_authors&mauthors=") + encodeURIComponent(query)})
        if (!profile.homepage) result.push({key: "websiteSearch", title: "Search for Homepage", detail: "Search by name and available affiliation",
                        url: "https://www.google.com/search?q=" + encodeURIComponent(query + " homepage")})
        return result
    }
    Rectangle {
        visible: root.Positioner.index > 0
        x: 10; width: parent.width - 20; height: 1
        color: Theme.separator
    }
    Column {
        id: content
        width: parent.width
        SettingsRow {
            label: root.label
            detail: root.detail
            IconButton {
                objectName: root.objectName + "-expand"
                icon.name: root.expanded ? "up" : "down"
                description: (root.expanded ? "Hide details for " : "Show details for ") + root.label
                checkable: true
                checked: root.expanded
                onToggled: root.expanded = checked
            }
            IconButton {
                objectName: root.removable ? root.actionName : ""
                visible: root.removable
                icon.name: "trash"; description: "Stop following"
                onClicked: root.followRequested()
            }
            Button {
                objectName: root.removable ? "" : root.actionName
                visible: !root.removable
                text: root.followed ? "Following" : "Follow"
                enabled: !root.followed
                highlighted: !root.followed
                onClicked: root.followRequested()
            }
        }
        ColumnLayout {
            objectName: root.objectName + "-details"
            visible: root.expanded
            width: parent.width - 24
            x: 12
            spacing: 4
            Label {
                objectName: root.objectName + "-affiliation"
                Layout.fillWidth: true
                text: root.loading ? "Loading details…" : root.profile.affiliation || (root.institution ? "Location not listed." : "Affiliation not listed.")
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSmall
            }
            RowLayout {
                visible: root.error.length > 0
                Layout.fillWidth: true
                Label {
                    Layout.fillWidth: true
                    text: root.error
                    wrapMode: Text.Wrap
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontCaption
                }
                Button {
                    objectName: root.objectName + "-retry"
                    text: "Retry"
                    enabled: !root.loading
                    onClicked: root.loadDetails()
                }
            }
            Label {
                visible: !root.loading && !root.error.length && !root.profile.homepage
                Layout.fillWidth: true
                text: "Homepage not listed. Use the links below to identify this " + (root.institution ? "institution." : "person.")
                wrapMode: Text.Wrap
                color: Theme.textTertiary
                font.pixelSize: Theme.fontCaption
            }
            Repeater {
                model: root.links
                delegate: ItemDelegate {
                    required property var modelData
                    objectName: root.objectName + "-" + modelData.key
                    Layout.fillWidth: true
                    Accessible.name: modelData.title + ". " + modelData.detail
                    onClicked: root.linkRequested(modelData.url)
                    contentItem: RowLayout {
                        spacing: 8
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Label { text: modelData.title; color: Theme.accent; font.pixelSize: Theme.fontSmall }
                            Label {
                                Layout.fillWidth: true
                                text: modelData.detail
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: Theme.textTertiary
                                font.pixelSize: Theme.fontCaption
                            }
                        }
                        Icon { name: "external"; color: Theme.textTertiary }
                    }
                }
            }
            Label {
                Layout.fillWidth: true
                Layout.bottomMargin: 12
                text: "Details from " + (root.openAlex ? "OpenAlex" : "Semantic Scholar") + ". Links open in your browser."
                wrapMode: Text.Wrap
                color: Theme.textTertiary
                font.pixelSize: Theme.fontCaption
            }
        }
    }
}
