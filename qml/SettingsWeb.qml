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
            + "A downloaded PDF is named from its paper (Settings \u203a Data \u203a Paper names) when its first page shows the title; files already in the Library keep their names. Existing files are never overwritten. In a web tab, Show Here reads a PDF in place; Open in Reader sends it to the reader, where annotations and notes work."
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
                model: ["From the paper", "Name from the website"]
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
    // Every engine: the default (a small accent pill), shown on Home's engine button or hidden there,
    // and engines of one's own (a site such as google.com is enough), which can be removed.
    SettingsGroup {
        objectName: "searchEngineGroup"
        title: "Search engines"
        note: "Home's web search starts on the default engine; its engine button offers the ones shown here. arxiv: or scholar: before the words searches there just once."
        Repeater {
            model: root.engines
            delegate: SettingsRow {
                id: engineRow
                required property var modelData
                readonly property bool isDefault: root.defaultEngine === modelData.template
                readonly property bool isHidden: (root.revision, WebSearch.hidden(researchStore).indexOf(modelData.template) >= 0) && !isDefault
                objectName: "engineRow-" + modelData.name
                label: modelData.name
                detail: modelData.template
                opacity: isHidden ? .55 : 1
                // Small and quiet; the default one is filled with the accent.
                AbstractButton {
                    objectName: "defaultEngine-" + engineRow.modelData.name
                    implicitWidth: defaultLabel.implicitWidth + 14; implicitHeight: Theme.controlHeightSmall - 4
                    checkable: true
                    checked: engineRow.isDefault
                    hoverEnabled: true
                    background: Rectangle {
                        radius: height / 2
                        color: engineRow.isDefault ? Theme.accent : parent.hovered ? Theme.hover : "transparent"
                        border.color: engineRow.isDefault ? Theme.accent : Theme.border
                    }
                    contentItem: Label {
                        id: defaultLabel
                        text: "Default"
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        font.pixelSize: Theme.fontCaption
                        color: engineRow.isDefault ? Theme.onAccent : Theme.textSecondary
                    }
                    onClicked: { WebSearch.setDefault(researchStore, engineRow.modelData.template); root.revision++ }
                }
                IconButton {
                    objectName: "showEngine-" + engineRow.modelData.name
                    enabled: !engineRow.isDefault
                    icon.name: engineRow.isHidden ? "hidden" : "preview"
                    tint: engineRow.isHidden ? Theme.textDisabled : Theme.icon
                    description: engineRow.isDefault ? "The default engine is always shown" : engineRow.isHidden ? "Show on Home's engine button" : "Hide from Home's engine button"
                    onClicked: { WebSearch.setHidden(researchStore, engineRow.modelData.template, !engineRow.isHidden); root.revision++ }
                }
                IconButton {
                    visible: !WebSearch.isBuiltIn(engineRow.modelData.template)
                    objectName: "removeEngine-" + engineRow.modelData.name
                    icon.name: "trash"; description: "Remove"
                    onClicked: { WebSearch.remove(researchStore, engineRow.modelData.template); root.revision++ }
                }
            }
        }
        // A site is enough ("google.com"); its search address and name are filled in.
        SettingsRow {
            wide: true
            detail: engineAddress.text.trim().length ? (root.typedTemplate.length ? "\u2192 " + root.typedTemplate : "Type a site such as google.com, or an address with %s for the words.") : ""
            TextField {
                id: engineAddress
                objectName: "engineAddressField"
                Layout.fillWidth: true
                placeholderText: "Add a site (google.com) or an address with %s"
                onAccepted: addEngine.clicked()
            }
            TextField { id: engineName; objectName: "engineNameField"; Layout.preferredWidth: 130; placeholderText: root.typedName.length ? root.typedName : "Name" }
            Button {
                id: addEngine
                objectName: "addEngine"
                text: "Add"
                enabled: root.typedTemplate.length > 0
                onClicked: {
                    const name = engineName.text.trim().length ? engineName.text : root.typedName
                    if (WebSearch.add(researchStore, name, root.typedTemplate)) { engineName.clear(); engineAddress.clear(); root.revision++ }
                    else researchStore.notify("That engine is already listed.")
                }
            }
        }
    }
    readonly property string typedTemplate: WebSearch.templateFor(engineAddress.text)
    readonly property string typedName: WebSearch.nameFor(engineAddress.text)
    SettingsGroup {
        title: "Browsing"
        note: "The start page opens with " + Platform.keys("Ctrl+L") + " when no web tab is in front."
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
    // One Google sign-in for every web tab (Scholar, YouTube, Google), kept like a browser keeps it (WebAccounts.h).
    SettingsGroup {
        id: googleGroup
        objectName: "googleAccountGroup"
        title: "Google account"
        readonly property bool known: typeof webAccounts !== "undefined"
        readonly property bool signedIn: known && webAccounts.googleSignedIn
        function openWeb(address) { const w = ApplicationWindow.window; if (w && w.openWebPage) w.openWebPage(address) }
        note: "Sign in once and Scholar, YouTube and Google know you in every web tab, also after Owelk restarts. "
            + "You type your password on Google's own page; Owelk never sees it."
        SettingsRow {
            objectName: "settingsRow-googleAccount"
            label: googleGroup.signedIn ? "Signed in to Google" : "Not signed in"
            detail: googleGroup.signedIn ? "Scholar shows your library, alerts and the people you follow" : "Scholar, YouTube and Google see a guest"
            Button {
                objectName: "googleSignIn"
                visible: !googleGroup.signedIn
                enabled: googleGroup.known
                highlighted: true
                text: "Sign In…"
                onClicked: googleGroup.openWeb(webAccounts.googleSignInUrl())
            }
            Button {
                objectName: "googleAccountPage"
                visible: googleGroup.signedIn
                flat: true
                text: "Account…"
                onClicked: googleGroup.openWeb("https://myaccount.google.com/")
            }
            Button {
                objectName: "googleSignOut"
                visible: googleGroup.signedIn
                text: "Sign Out"
                onClicked: webAccounts.signOutOfGoogle()
            }
        }
        SettingsRow {
            objectName: "settingsRow-googleFirefox"
            label: "Sign in as Firefox"
            detail: "Google turns away browsers it takes for embedded ones, so its sign-in pages are asked for as Firefox. If signing in still fails, try with this off."
            Switch {
                objectName: "googleFirefoxSwitch"
                checked: googleGroup.known ? webAccounts.firefoxForGoogle : true
                enabled: googleGroup.known
                onToggled: { researchStore.setSetting("web.googleAsFirefox", checked ? "1" : "0"); webAccounts.firefoxForGoogle = checked }
            }
        }
    }
}
