import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Owelk.Ui

// Papers the Library already has, met while adding PDFs or after a download: open the copy the reader
// already keeps (named, so it is easy to find in the PDF folder), or add this one as well.
Dialog {
    id: root
    objectName: "duplicateDialog"
    // Inspected items: {name, existingName, existingTitle, reason}.
    property var items: []
    property bool download: false
    property var onOpen: null
    property var onAdd: null
    property var onSkip: null
    property bool answered: false
    function show(list, isDownload, open, add, skip) {
        items = list; download = isDownload
        onOpen = open; onAdd = add; onSkip = skip
        answered = false
        root.open()
    }
    function answer(callback) {
        if (answered) return
        answered = true
        close()
        if (callback) callback()
    }
    function why(reason) {
        return reason === "file" ? "the same file" : reason === "doi" ? "the same DOI"
             : reason === "arxiv" ? "the same arXiv paper" : "the same title"
    }
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(540, parent ? parent.width - 48 : 540)
    modal: true
    title: download ? "You already have this paper"
         : items.length === 1 ? "This paper is already in your Library"
         : items.length + " papers are already in your Library"
    ColumnLayout {
        width: parent.width
        spacing: 10
        Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Theme.textSecondary
            text: root.download ? "The PDF you just downloaded is a paper your Library already has:"
                : root.items.length === 1 ? "Your Library already has it. Adding it again would make a second copy:"
                : "Your Library already has these. Adding them again would make second copies:"
        }
        ListView {
            id: list
            objectName: "duplicateList"
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 240)
            clip: true
            interactive: contentHeight > height
            spacing: 10
            model: root.items
            ScrollBar.vertical: ScrollBar {}
            delegate: ColumnLayout {
                required property var modelData
                width: list.width
                spacing: 1
                Label {
                    Layout.fillWidth: true
                    text: "“" + modelData.existingName + "”"
                    elide: Text.ElideMiddle; textFormat: Text.PlainText
                    font.weight: Font.DemiBold; color: Theme.text
                }
                Label {
                    Layout.fillWidth: true
                    visible: text.length > 0 && text !== modelData.existingName
                    text: modelData.existingTitle || ""
                    elide: Text.ElideRight; textFormat: Text.PlainText
                    font.pixelSize: Theme.fontSmall; color: Theme.textSecondary
                }
                Label {
                    Layout.fillWidth: true
                    text: (root.download ? "Downloaded" : "Adding") + " “" + modelData.name + "” · " + root.why(modelData.reason)
                    elide: Text.ElideMiddle; textFormat: Text.PlainText
                    font.pixelSize: Theme.fontCaption; color: Theme.textTertiary
                }
            }
        }
    }
    footer: DialogButtonBox {
        Button {
            objectName: "duplicateAddAnyway"
            text: root.download ? "Keep the Download" : root.items.length > 1 ? "Add Them Anyway" : "Add Anyway"
            DialogButtonBox.buttonRole: DialogButtonBox.ActionRole
            onClicked: root.answer(root.onAdd)
        }
        Button {
            objectName: "duplicateOpenExisting"
            text: root.items.length > 1 ? "Open What I Have" : "Open It"
            highlighted: true
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
        }
    }
    onAccepted: answer(onOpen)
    // Escape: nothing moves. After a download that means reading the copy already kept.
    onRejected: answer(download ? onOpen : onSkip)
}
