import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs as Native
import Owelk.Ui
import "Platform.js" as Platform
import "WorkspaceTree.js" as Tree
import "WebSearch.js" as WebSearch

ColumnLayout {
    id: root
    spacing: 22
    // Read again after a change here (the engines are kept in the settings table).
    property int revision: 0
    readonly property var engines: (revision, WebSearch.all(researchStore))
    readonly property string defaultEngine: (revision, WebSearch.template(researchStore))
    readonly property var tor: researchStore.tor
    readonly property bool keepsPdfs: researchStore.setting("library.keepPdfs", "1") === "1"
    function folder() { const f = researchStore.setting("downloadFolder"); return f.length ? f : researchStore.downloadTarget("x").directory }
    Native.FolderDialog {
        id: folderDialog
        title: "Download folder for web PDFs"
        onAccepted: if (researchStore.setSetting("downloadFolder", researchStore.localPath(selectedFolder))) folderField.text = root.folder()
    }
    SettingsGroup {
        title: "PDFs"
        note: (root.keepsPdfs ? "Downloaded PDFs go to Owelk's own PDF folder (Settings › Data); other files go to the folder above. " : "")
            + "A downloaded PDF is named after its paper when its first page shows the title; files already in the Library keep their names. Existing files are never overwritten. In a web tab, Show Here reads a PDF in place; Open in Reader sends it to the reader, where annotations and notes work."
        SettingsRow {
            label: root.keepsPdfs ? "Other downloads to" : "Download to"
            wide: true
            TextField { id: folderField; objectName: "downloadFolderField"; Layout.fillWidth: true; readOnly: true; text: root.folder() }
            IconButton { icon.name: "open"; description: "Choose a folder…"; onClicked: folderDialog.open() }
        }
        SettingsRow {
            label: "Name PDFs"
            ComboBox {
                objectName: "webPdfNamesBox"
                Layout.preferredWidth: 260
                model: ["Paper title", "Name from the website"]
                currentIndex: researchStore.setting("web.pdfNames", "title") === "original" ? 1 : 0
                onActivated: function(index) { researchStore.setSetting("web.pdfNames", index === 1 ? "original" : "title") }
            }
        }
        SettingsRow {
            label: "PDF links"
            ComboBox {
                objectName: "webPdfModeBox"
                Layout.preferredWidth: 260
                model: ["Download and open in the reader", "Show in the web tab"]
                currentIndex: researchStore.setting("webPdfMode", "reader") === "browser" ? 1 : 0
                onActivated: function(index) { researchStore.setSetting("webPdfMode", index === 1 ? "browser" : "reader") }
            }
        }
    }
    SettingsGroup {
        title: "Browsing"
        note: "The start page opens with " + Platform.keys("Ctrl+L") + " when no web tab is in front. Home's web search can switch the engine too, and arxiv: or scholar: before the words searches there just once."
        SettingsRow {
            label: "Search with"
            ComboBox {
                objectName: "searchEngineBox"
                Layout.preferredWidth: 200
                model: root.engines.map(function(e) { return e.name })
                currentIndex: Math.max(0, root.engines.findIndex(function(e) { return e.template === root.defaultEngine }))
                onActivated: function(index) { WebSearch.setDefault(researchStore, root.engines[index].template); root.revision++ }
            }
        }
        // Engines of one's own: a name and the search address, %s standing for the words; each can be the
        // default above (and on Home's engine button) or removed.
        Repeater {
            model: root.engines.filter(function(e) { return !WebSearch.isBuiltIn(e.template) })
            delegate: SettingsRow {
                required property var modelData
                label: modelData.name
                detail: modelData.template
                IconButton {
                    objectName: "removeEngine-" + modelData.name
                    icon.name: "trash"; description: "Remove"
                    onClicked: { WebSearch.remove(researchStore, modelData.template); root.revision++ }
                }
            }
        }
        SettingsRow {
            label: "Add an engine"
            detail: "Its search address, with %s where the words go."
            wide: true
            TextField { id: engineName; objectName: "engineNameField"; Layout.preferredWidth: 120; placeholderText: "Name" }
            TextField {
                id: engineAddress
                objectName: "engineAddressField"
                Layout.fillWidth: true
                placeholderText: "https://example.org/search?q=%s"
                onAccepted: addEngine.clicked()
            }
            Button {
                id: addEngine
                objectName: "addEngine"
                text: "Add"
                enabled: engineName.text.trim().length > 0 && engineAddress.text.indexOf("%s") >= 0
                onClicked: {
                    if (WebSearch.add(researchStore, engineName.text, engineAddress.text)) { engineName.clear(); engineAddress.clear(); root.revision++ }
                    else researchStore.notify("Use a web address with %s where the words go, not one already listed.")
                }
            }
        }
        SettingsRow {
            label: "Start page"
            wide: true
            TextField {
                objectName: "startPageField"
                Layout.fillWidth: true
                text: researchStore.setting("startPage")
                placeholderText: "https://scholar.google.com/"
                onEditingFinished: researchStore.setSetting("startPage", text.trim())
            }
        }
    }
    // Off unless turned on here; each computer's reader decides (TorNetwork.h).
    SettingsGroup {
        title: "Tor"
        note: "Web tabs and Home's web search go out through Tor, so sites see an address in another country. "
            + "Paper details, citations and AI still connect directly. Google and Scholar often ask Tor users to show "
            + "they are not a robot; New Identity tries another exit. This changes where you appear to be, "
            + "not the privacy of Tor Browser."
        SettingsRow {
            label: "Browse through Tor"
            Switch {
                objectName: "torSwitch"
                checked: root.tor.enabled
                onToggled: root.tor.setEnabled(checked)
            }
        }
        SettingsRow {
            label: "Exit country"
            ComboBox {
                objectName: "torExitBox"
                Layout.preferredWidth: 200
                model: root.tor.countries.map(function(c) { return c.name })
                currentIndex: Math.max(0, root.tor.countries.findIndex(function(c) { return c.code === root.tor.exitCountry }))
                onActivated: function(index) { root.tor.setExitCountry(root.tor.countries[index].code) }
            }
        }
        SettingsRow {
            label: "Status"
            wide: true
            Label {
                objectName: "torStatus"
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: root.tor.summary
                color: root.tor.state === "missing" || root.tor.state === "failed" ? Theme.danger : Theme.textSecondary
            }
            Button {
                objectName: "torNewIdentity"
                visible: root.tor.state === "ready"
                text: "New Identity"
                onClicked: root.tor.newIdentity()
            }
        }
    }
}
