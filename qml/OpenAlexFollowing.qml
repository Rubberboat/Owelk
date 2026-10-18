import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Owelk.Ui

SettingsGroup {
    id: root
    objectName: "settingsGroup-openAlexFollowing"
    title: "Researchers and institutions"
    note: "Follow OpenAlex records to find their new articles and preprints in For You. Expand a result to check its affiliation, homepage, ORCID or paper list. Only search terms and followed IDs are sent to OpenAlex."
    readonly property var service: researchStore.forYou
    property int revision: 0
    readonly property var followed: (revision, service.entities())
    property var results: []
    property string status: ""
    property bool finding: false
    property string lookup: ""
    property string inputAtLookup: ""
    property string kindAtLookup: ""
    readonly property string kind: entityKind.currentIndex === 0 ? "person" : "institution"
    readonly property var suggestions: (researchStore.searchText.revision, service.entitySearchSuggestions(entityName.text, kind))
    function find(spelling) {
        const text = typeof spelling === "string" ? spelling.trim() : entityName.text.trim()
        if (!text.length || finding || service.entityRetrySeconds > 0) return
        lookup = text; inputAtLookup = entityName.text.trim(); kindAtLookup = kind
        finding = true; status = "Looking…"; results = []
        if (kind === "institution" || !suggestions.length) researchStore.searchText.prepare(text)
        service.findEntities(text, kind)
    }
    Connections {
        target: root.service
        function onSettingsChanged() { root.revision++ }
        function onEntitiesFound(name, kind, rows, error) {
            if (name !== root.lookup || kind !== root.kindAtLookup) return
            root.finding = false
            if (entityName.text.trim() !== root.inputAtLookup || kind !== root.kind) { root.results = []; root.status = ""; return }
            root.results = rows
            root.status = error.length ? error : rows.length ? "Check the record before following. Names may belong to different people or institutions."
                : "No matches for this spelling. Try a suggestion or a web search."
        }
    }
    Repeater {
        model: root.followed
        PersonRow {
            required property var modelData
            required property int index
            objectName: "openAlexFollowed-" + index
            person: modelData
            service: root.service
            removable: true
            actionName: "openAlexUnfollow-" + index
            onFollowRequested: root.service.followEntity(modelData, false)
            onLinkRequested: function(url) { Qt.openUrlExternally(url) }
        }
    }
    SettingsRow {
        wide: true
        ComboBox {
            id: entityKind
            objectName: "openAlexKind"
            Layout.preferredWidth: 135
            model: ["Researcher", "Institution"]
            onActivated: { root.results = []; root.status = ""; root.lookup = ""; root.finding = false }
        }
        TextField {
            id: entityName
            objectName: "openAlexName"
            Layout.fillWidth: true
            placeholderText: root.kind === "person" ? "김주현 or Juhyun Kim" : "Institution name"
            onTextEdited: {
                root.results = []
                if (root.kind === "institution") researchStore.searchText.prepare(text)
            }
            onAccepted: root.find()
        }
        Button {
            objectName: "openAlexFind"
            text: root.service.entityRetrySeconds > 0 ? "Retry in " + root.service.entityRetrySeconds + "s" : "Find"
            enabled: entityName.text.trim().length > 0 && !root.finding && root.service.entityRetrySeconds === 0
            onClicked: root.find()
        }
    }
    SettingsRow {
        wide: true
        visible: root.status.length > 0
        Label {
            objectName: "openAlexStatus"
            Layout.fillWidth: true
            text: root.status
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Theme.textSecondary
        }
    }
    SettingsRow {
        wide: true
        visible: root.suggestions.length > 0 && entityName.text.trim().length > 0
        ColumnLayout {
            Layout.fillWidth: true
            Label {
                Layout.fillWidth: true
                text: "Search suggestions, not verified identities. Choose one to search."
                wrapMode: Text.Wrap; font.pixelSize: Theme.fontCaption; color: Theme.textTertiary
            }
            Repeater {
                model: root.suggestions
                Button {
                    required property string modelData
                    required property int index
                    objectName: "openAlexSuggestion-" + index
                    Layout.fillWidth: true
                    text: (index + 1) + ". " + modelData
                    enabled: !root.finding && root.service.entityRetrySeconds === 0
                    onClicked: root.find(modelData)
                }
            }
        }
    }
    Repeater {
        model: root.results
        PersonRow {
            required property var modelData
            required property int index
            objectName: "openAlexResult-" + index
            person: modelData
            service: root.service
            followed: (root.revision, root.service.followingEntity(modelData.id))
            actionName: "openAlexFollow-" + index
            onFollowRequested: root.service.followEntity(modelData, true)
            onLinkRequested: function(url) { Qt.openUrlExternally(url) }
        }
    }
    SettingsRow {
        wide: true
        visible: entityName.text.trim().length > 0
        Button {
            objectName: "openAlexWebSearch"
            text: "Search OpenAlex on the web"
            onClicked: Qt.openUrlExternally("https://openalex.org/" + (root.kind === "person" ? "authors" : "institutions") + "?search="
                + encodeURIComponent(root.kind === "person" ? root.suggestions[0] || entityName.text.trim() : entityName.text.trim()))
        }
    }
    SettingsRow {
        label: "OpenAlex API key"
        detail: root.service.hasOpenAlexKey ? "Stored securely on this computer." : "Optional. A free key raises the daily request allowance."
        Button { text: "Get a free key"; onClicked: Qt.openUrlExternally("https://openalex.org/settings/api") }
    }
    SettingsRow {
        wide: true
        TextField {
            id: apiKey
            objectName: "openAlexKey"
            Layout.fillWidth: true
            echoMode: TextInput.Password
            placeholderText: root.service.hasOpenAlexKey ? "Replace API key" : "Paste API key"
        }
        Button {
            objectName: "openAlexSaveKey"
            text: "Save"
            enabled: apiKey.text.trim().length > 0 && !root.finding
            onClicked: if (root.service.setOpenAlexKey(apiKey.text)) { apiKey.clear(); root.status = "OpenAlex key saved." }
        }
        Button {
            text: "Remove key"
            visible: root.service.hasOpenAlexKey
            enabled: !root.finding
            onClicked: if (root.service.setOpenAlexKey("")) root.status = "OpenAlex key removed."
        }
    }
}
