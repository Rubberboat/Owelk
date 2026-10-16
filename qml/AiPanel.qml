import Owelk.Ui
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs as Native
import "Platform.js" as Platform

// Dock panel for the AI: saved threads, the open conversation, and the composer with the model menu.
Item {
    id: root
    objectName: "aiPanel"
    property var controller: null
    readonly property var c: controller
    readonly property bool showingThreads: !c || !c.conversationOpen
    // Threads chosen in the list (Cmd/Ctrl-click, Shift-click), and where a Shift range starts.
    property var selectedThreads: []
    property int selectionAnchor: -1
    function toggleThread(id, index) {
        selectedThreads = selectedThreads.indexOf(id) >= 0 ? selectedThreads.filter(function(t) { return t !== id }) : selectedThreads.concat([id])
        selectionAnchor = index
    }
    function selectThreadRange(index) {
        const from = selectionAnchor < 0 ? index : selectionAnchor
        const rows = threadList.model.slice(Math.min(from, index), Math.max(from, index) + 1)
        selectedThreads = rows.map(function(t) { return t.id })
    }
    function trashThreads(ids) {
        if (!ids.length) return
        if (ids.indexOf(c.threadId) >= 0) c.showThreads()
        selectedThreads = []
        emptying(function() { researchStore.trashAiThreads(ids) })
    }
    // One chat goes to the Trash at once; several (a selection) only after asking.
    function askTrashThreads(ids) {
        if (ids.length < 2) { trashThreads(ids); return }
        trashChatsDialog.ids = ids.slice()
        trashChatsDialog.open()
    }
    // Threads hold the chats: All Chats, one per paper (made as its chats are), General, and Threads of the
    // reader's own, which may hold chats about several papers. Wide, the Threads stand in a column beside
    // the chats (and the conversation); narrow, one list at a time.
    readonly property bool wide: width >= 440
    readonly property real topicWidth: Math.round(Math.min(200, Math.max(140, width * .3)))
    property bool topicsOpen: false
    property int topicRevision: 0
    Connections { target: researchStore; function onAiThreadsChanged() { root.reviveHiddenPapers(); root.topicRevision++ } }
    Connections { target: root.c; function onTopicKeyChanged() { root.topicsOpen = false } }
    // The paper in front has its Thread at the top even before its first chat.
    readonly property string readerTopic: c && c.reader && c.reader.source && c.reader.source.toString().length ? researchStore.aiTopicFor(c.reader.source) : ""
    // A paper's Thread lasts while it has chats. One left empty (its chats deleted, moved or merged away)
    // or deleted itself is gone for the paper in front too, until a new chat about the paper; kept across
    // starts (ai.hiddenPaperThreads).
    property var hiddenPapers: {
        try {
            const keys = JSON.parse(researchStore.setting("ai.hiddenPaperThreads", "") || "[]")
            return Array.isArray(keys) ? keys : []
        } catch (e) { return [] }
    }
    function setHiddenPapers(keys) {
        hiddenPapers = keys.slice(-500)
        researchStore.setSetting("ai.hiddenPaperThreads", hiddenPapers.length ? JSON.stringify(hiddenPapers) : "")
    }
    function hidePapers(keys) {
        const add = keys.filter(function(k) { return k.indexOf("paper:") === 0 && root.hiddenPapers.indexOf(k) < 0 })
        if (!add.length) return
        setHiddenPapers(hiddenPapers.concat(add))
        if (add.indexOf(c.topicKey) >= 0) c.chooseTopic("")
    }
    // Runs a change to the chats; papers' Threads it leaves empty go.
    function emptying(change) {
        const before = researchStore.aiTopics().filter(function(t) { return t.kind === "paper" }).map(function(t) { return t.key })
        change()
        const after = researchStore.aiTopics().map(function(t) { return t.key })
        hidePapers(before.filter(function(k) { return after.indexOf(k) < 0 }))
    }
    readonly property var topics: {
        const revision = topicRevision
        const list = researchStore.aiTopics()
        const rows = [{key: "", kind: "all", title: "All Chats", chats: list.reduce(function(n, t) { return n + t.chats }, 0)}]
        if (readerTopic.length && hiddenPapers.indexOf(readerTopic) < 0 && !list.some(function(t) { return t.key === readerTopic }))
            rows.push({key: readerTopic, kind: "paper", title: researchStore.displayName(c.reader.source), chats: 0})
        return rows.concat(list)
    }
    // A paper's Thread with chats again (a new one, or back from the Trash) is no longer kept hidden.
    function reviveHiddenPapers() {
        if (!hiddenPapers.length) return
        const live = researchStore.aiTopics().map(function(t) { return t.key })
        const back = hiddenPapers.filter(function(k) { return live.indexOf(k) >= 0 })
        if (back.length) setHiddenPapers(hiddenPapers.filter(function(k) { return back.indexOf(k) < 0 }))
    }
    // The Thread shown; General before its first chat; All Chats when the one chosen is not there (a
    // paper's Thread that went).
    readonly property var currentTopic: (c && topics.find(function(t) { return t.key === c.topicKey }))
                                        || (c && c.topicKey === "general" ? {key: "general", kind: "general", title: "General", chats: 0} : topics[0])
    // Where a question typed below the lists goes: the Thread shown; from All Chats, the paper in front's,
    // else General.
    readonly property string askKey: c ? c.topicKey || readerTopic || "general" : "general"
    readonly property string askKind: askKey === "general" ? "general" : askKey.indexOf("paper:") === 0 ? "paper" : "custom"
    function ask(text) {
        if (!c || c.streaming) return false
        return showingThreads ? c.askIn(askKey, text) : c.send(text)
    }
    // Threads a chat can move into, or a Thread can merge into: one's own first, then General, then papers.
    // General is offered even while it holds no chats.
    function otherTopics(key) {
        const rank = function(t) { return t.kind === "custom" ? 0 : t.kind === "general" ? 1 : 2 }
        const list = topics.filter(function(t) { return t.key.length > 0 && t.key !== key })
        if (key !== "general" && !list.some(function(t) { return t.key === "general" }))
            list.push({key: "general", kind: "general", title: "General", chats: 0})
        return list.sort(function(a, b) { return rank(a) - rank(b) })
    }
    function topicChats(key) {
        return researchStore.aiThreads().filter(function(t) { return t.topic === key }).map(function(t) { return t.id })
    }
    // A chat kept in a Thread its paper would not put it in.
    function keptAside(chat) {
        return !!chat && chat.topic !== undefined && chat.topic !== researchStore.aiTopicFor(chat.source || "")
    }
    function newChatIn(key) {
        selectedThreads = []
        c.chooseTopic(key)
        c.startIn(key)
        focusQuestion()
    }
    // Threads opened in the list to show their chats right under them.
    property var expandedTopics: []
    function toggleTopic(key) {
        expandedTopics = expandedTopics.indexOf(key) >= 0 ? expandedTopics.filter(function(k) { return k !== key }) : expandedTopics.concat([key])
    }
    // A chat chosen under its Thread in the list: that Thread is shown behind it.
    function openChatIn(key, id) {
        selectedThreads = []
        c.chooseTopic(key)
        if (c.openThread(id, true)) topicsOpen = false
    }
    function chooseTopic(key) {
        c.showThreads()
        selectedThreads = []
        c.chooseTopic(key)
        topicsOpen = false
    }
    function moveChats(ids, key) {
        if (!ids.length) return
        emptying(function() { researchStore.moveAiThreads(ids, key) })
        selectedThreads = []
    }
    // A name for a new Thread (the chats given move into it) or a new name for one.
    function askTopicName(id, chats) {
        topicDialog.topicId = id
        topicDialog.chats = chats
        topicField.text = id.length ? (topics.find(function(t) { return t.key === id }) || {}).title || "" : ""
        topicDialog.open()
    }
    function saveTopic(id, name, chats) {
        if (id.length) { researchStore.renameAiTopic(id, name); return }
        const made = researchStore.createAiTopic(name)
        if (!made.length) return
        if (chats.length) researchStore.moveAiThreads(chats, made)
        chooseTopic(made)
    }
    // Its chats go back to their papers' Threads.
    function deleteTopic(key) {
        if (c.topicKey === key) c.chooseTopic("")
        researchStore.deleteAiTopic(key)
    }
    // One Thread into another: its chats move there and stay; a Thread of one's own then goes.
    function mergeTopic(from, into) {
        const ids = topicChats(from.key)
        if (ids.length) researchStore.moveAiThreads(ids, into.key)
        if (from.kind === "custom") researchStore.deleteAiTopic(from.key)
        else hidePapers([from.key])
        if (c.topicKey === from.key) c.chooseTopic(into.key)
        researchStore.notify("Merged \u201c" + from.title + "\u201d into \u201c" + into.title + "\u201d.")
    }
    // A Thread without its chats: one's own goes and its chats go back to their papers' Threads (or General);
    // a paper's goes and its chats move to General, where they stay.
    function deleteTopicKeepingChats(row) {
        if (row.kind === "custom") { deleteTopic(row.key); return }
        if (row.kind !== "paper") return
        const ids = topicChats(row.key)
        if (c.topicKey === row.key) c.chooseTopic("general")
        if (ids.length) researchStore.moveAiThreads(ids, "general")
        hidePapers([row.key])
    }
    // A Thread with its chats: they go to the Trash in the Library, where they can be restored.
    // A paper's Thread goes even with no chats (the paper in front's before its first).
    function trashTopic(row) {
        trashThreads(topicChats(row.key))
        if (row.kind === "custom") deleteTopic(row.key)
        else hidePapers([row.key])
    }
    // Deleting a Thread asks first: with its chats, or (one's own) leaving them to their papers.
    function askDeleteTopic(row, keepChats) {
        deleteTopicDialog.row = row
        deleteTopicDialog.keepChats = keepChats
        deleteTopicDialog.open()
    }
    function openTopicMenu(row, item, x, y) {
        if (!row || !row.key) return
        topicMenu.row = row
        topicMenu.paper = row.kind === "paper" ? c.topicSource(row.key) : ""
        topicMenu.place = paperPlace(topicMenu.paper)
        topicMenu.popup(item, x, y)
    }
    function openChatMenu(ids, row, item, x, y) {
        threadMenu.ids = ids
        threadMenu.row = row
        threadMenu.paper = ids.length === 1 && row.source ? row.source : ""
        threadMenu.place = paperPlace(threadMenu.paper)
        threadMenu.popup(item, x, y)
    }
    // The document area (Main.qml): a paper's tab brought to the front, or the paper opened again.
    property var documents: null
    // Where a paper's Thread (or a chat about one paper) can take the reader: "open" (its tab, wherever
    // it is), "closed" (opened again), "missing" (its file is gone: Locate PDF…), or "" (no paper, or it
    // is the one in front).
    function paperPlace(source) {
        if (!documents || !source || !source.toString().length) return ""
        if (!researchStore.paperFileExists(source)) return "missing"
        if (c.readerPaper.length && researchStore.sameSource(c.reader.source, source)) return ""
        return documents.paperTab(source) ? "open" : "closed"
    }
    readonly property var placeLabels: ({open: "Go to Paper", closed: "Open Paper", missing: "Locate PDF\u2026"})
    function goToPaper(source, place) {
        if (place === "missing") researchStore.requestRelink(source)
        else documents.showPaper(source)
    }
    // The header's menu: the Thread shown, or the open chat.
    function openHeaderMenu(item, x, y) {
        if (showingThreads) openTopicMenu(currentTopic, item, x, y)
        else if (c.threadId.length) openChatMenu([c.threadId], c.thread, item, x, y)
    }
    // The chats being dragged onto a Thread. The drop moves them once the drag is over: the row that
    // started it leaves the list then.
    property var draggedChats: []
    function startChatDrag(ids, title, scene) {
        draggedChats = ids
        dragProxy.label = title + (ids.length > 1 ? "  +" + (ids.length - 1) : "")
        dragProxy.moveTo(scene)
        dragProxy.dragging = true
    }
    function moveChatDrag(scene) { if (dragProxy.dragging) dragProxy.moveTo(scene) }
    function finishChatDrag() {
        if (!dragProxy.dragging) return
        dragProxy.Drag.drop()
        dragProxy.dragging = false
        draggedChats = []
    }
    signal linkActivated(string link)
    signal settingsRequested()
    // Conversations moved to the Trash are in the Library's Trash, with papers and notes.
    signal trashRequested()
    function focusQuestion() { question.forceActiveFocus() }
    Connections { target: root.c; function onFocusRequested() { root.focusQuestion() } }
    // Opened to ask about something just attached (or a new thread): the question box is ready.
    Component.onCompleted: if (c && c.conversationOpen && !c.streaming) question.forceActiveFocus()
    // The reader's turn: an accent bubble that hugs its text, with room on the left like a messenger.
    component Bubble: Rectangle {
        property alias text: bubbleText.text
        readonly property real room: conversation.width - Math.min(40, conversation.width * 0.12)
        Layout.alignment: Qt.AlignRight
        Layout.preferredWidth: Math.min(room, bubbleText.implicitWidth + 18)
        implicitHeight: bubbleText.contentHeight + 14
        radius: Theme.radiusLarge; color: Theme.accent
        TextEdit {
            id: bubbleText
            anchors.fill: parent; anchors.leftMargin: 9; anchors.rightMargin: 9; anchors.topMargin: 7; anchors.bottomMargin: 7
            readOnly: true; selectByMouse: true
            textFormat: TextEdit.PlainText; wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
            color: Theme.onAccent; font.pixelSize: Theme.fontSmall
            selectionColor: Theme.onAccent; selectedTextColor: Theme.accent
            TapHandler { acceptedButtons: Qt.RightButton; onTapped: function(point) { root.openTextMenu(bubbleText, point.position) } }
        }
    }
    // An attachment: what goes with a question (× removes it) or went with an earlier one. Images show a
    // thumbnail.
    component AttachmentChip: Rectangle {
        id: chipBox
        required property var modelData
        property bool removable: false
        signal removed()
        readonly property bool thumbnail: modelData.kind === "image" && !!modelData.url
        readonly property real lead: thumbnail ? 26 : 6
        height: 22; width: Math.min(chipLabel.implicitWidth + lead + (removable ? 22 : 6), root.width - 16)
        radius: Theme.radius; color: Theme.window; border.color: Theme.separator
        Image {
            visible: chipBox.thumbnail && status !== Image.Error
            x: 3; anchors.verticalCenter: parent.verticalCenter
            width: 18; height: 16; fillMode: Image.PreserveAspectCrop
            source: chipBox.thumbnail ? chipBox.modelData.url : ""
            sourceSize.width: 36; sourceSize.height: 32; asynchronous: true
        }
        // Plain text: the hover preview below shows the whole attachment instead of the cut label.
        Text {
            id: chipLabel
            x: chipBox.lead; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - chipBox.lead - (chipBox.removable ? 20 : 6)
            text: chipBox.modelData.label || ""
            elide: Text.ElideRight; maximumLineCount: 1; textFormat: Text.PlainText
            font.pixelSize: Theme.fontCaption; color: Theme.textSecondary
        }
        // Hover: the attachment itself, larger (an image) or in full (a selection or quote).
        readonly property string detail: modelData.detail || ""
        HoverHandler { id: chipHover }
        ToolTip {
            objectName: "aiChipPreview"
            visible: chipHover.hovered && (chipBox.thumbnail || chipBox.detail.length > 0)
            delay: 300
            contentItem: Item {
                implicitWidth: chipBox.thumbnail ? large.width : fullText.width
                implicitHeight: chipBox.thumbnail ? large.height : fullText.height
                Image {
                    id: large
                    visible: chipBox.thumbnail
                    source: visible && chipHover.hovered ? chipBox.modelData.url : ""
                    asynchronous: true
                    sourceSize.width: 640
                    width: Math.min(320, implicitWidth); height: implicitWidth > 0 ? width * implicitHeight / implicitWidth : 0
                    fillMode: Image.PreserveAspectFit
                }
                Text {
                    id: fullText
                    visible: !chipBox.thumbnail
                    width: Math.min(340, implicitWidth)
                    text: chipBox.detail
                    wrapMode: Text.Wrap; textFormat: Text.PlainText; maximumLineCount: 16; elide: Text.ElideRight
                    font.pixelSize: Theme.fontSmall; color: Theme.text
                }
            }
        }
        IconButton {
            visible: chipBox.removable
            objectName: "aiChipRemove"
            anchors.right: parent.right; anchors.rightMargin: 2; anchors.verticalCenter: parent.verticalCenter
            width: 18; height: 18; glyphSize: Theme.fontSmall
            icon.name: "close"; description: "Remove"
            onClicked: chipBox.removed()
        }
    }
    // What went with an earlier question, as chips: from the attachments kept with it.
    function sentAttachments(message) {
        const context = message.context || {}, list = []
        const flat = function(text) { const t = (text || "").replace(/\s+/g, " ").trim(); return t.slice(0, 60) + (t.length > 60 ? "…" : "") }
        const paper = root.c && root.c.thread.source && root.c.thread.source.toString().length ? researchStore.displayName(root.c.thread.source) : ""
        ;(context.attachments || []).forEach(function(kind) {
            if (kind === "paper") list.push({kind: kind, label: "Paper" + (paper.length ? " · " + paper : "")})
            else if (kind.indexOf("page ") === 0) list.push({kind: "page", label: "Page " + kind.slice(5) + " text"})
            else if (kind === "selection") list.push({kind: kind, label: "Selection · " + flat(context.selection), detail: context.selection || ""})
            else if (kind === "quote") list.push({kind: kind, label: "Quote · " + flat(context.quote), detail: context.quote || ""})
            else if (kind === "papers") (context.papers || []).forEach(function(name) { list.push({kind: "paper", label: "Paper · " + name}) })
            else if (kind === "library")
                list.push({kind: kind, label: context.collectionName ? "Collection · " + context.collectionName
                                             : !context.wholeLibrary && (context.searched || []).length > 1 ? "Passages from " + context.searched.length + " papers"
                                             : "Library passages"})
            else if (kind === "image") {
                const names = context.images || [], files = context.imageFiles || []
                for (let i = 0; i < Math.max(1, names.length, files.length); ++i)
                    list.push({kind: "image", label: names[i] || "Image", url: files[i] || ""})
            }
        })
        return list
    }
    // The model's reasoning summary above an answer. While it thinks: "Thinking · <latest step>" in a
    // lighter colour; once the answer starts: "Thought for 12s ›", which unfolds the whole summary.
    component ThinkingFold: ColumnLayout {
        id: fold
        property string summary: ""
        property int seconds: 0
        property bool live: false
        property bool expanded: false
        readonly property bool shown: root.c && root.c.showThinking && summary.length > 0
        visible: live || shown
        spacing: 4
        Label {
            objectName: "aiThinkingNow"
            visible: fold.live
            Layout.fillWidth: true
            text: fold.shown ? "Thinking · " + root.c.thinkingHeadline(fold.summary) : "Thinking…"
            elide: Text.ElideRight; textFormat: Text.PlainText
            color: Theme.textSecondary; font.pixelSize: Theme.fontSmall
        }
        Label {
            objectName: "aiThoughtToggle"
            visible: !fold.live && fold.shown
            text: "Thought for " + fold.seconds + "s " + (fold.expanded ? "\u2304" : "\u203a")
            textFormat: Text.PlainText
            color: toggleHover.hovered ? Theme.text : Theme.textSecondary; font.pixelSize: Theme.fontSmall
            HoverHandler { id: toggleHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: fold.expanded = !fold.expanded }
        }
        Item {
            visible: !fold.live && fold.shown && fold.expanded
            Layout.fillWidth: true
            implicitHeight: summaryText.implicitHeight
            Rectangle { width: 2; height: parent.height; radius: 1; color: Theme.separator }
            AnswerText {
                id: summaryText
                objectName: "aiThoughtText"
                x: 10; width: parent.width - 10
                text: parent.visible ? researchStore.markdownHtml(fold.summary, Theme.accent, Theme.textSecondary, Theme.fontSmall) : ""
                color: Theme.textSecondary; font.pixelSize: Theme.fontSmall
            }
        }
    }
    // An answer: Markdown as rich text that can be selected and copied; links open in Owelk.
    component AnswerText: TextEdit {
        readOnly: true; selectByMouse: true
        textFormat: TextEdit.RichText; wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
        color: Theme.text; font.pixelSize: Theme.fontBody
        selectionColor: Theme.mix(Theme.accent, Theme.field, .65); selectedTextColor: Theme.text
        onLinkActivated: function(link) { root.linkActivated(link) }
        HoverHandler { cursorShape: parent.hoveredLink.length > 0 ? Qt.PointingHandCursor : Qt.IBeamCursor }
        TapHandler { acceptedButtons: Qt.RightButton; onTapped: function(point) { root.openTextMenu(parent, point.position) } }
        Keys.onPressed: function(event) {
            if (event.matches(StandardKey.Copy) && selectedText.length) { researchStore.copyText(root.selectionText(this)); event.accepted = true }
        }
    }
    // The selected text of a message; formulas come back as their LaTeX rather than vanishing.
    function selectionText(target) {
        if (target.textFormat !== TextEdit.RichText) return target.selectedText
        return researchStore.plainTextWithMath(target.getFormattedText(target.selectionStart, target.selectionEnd))
    }
    // Right-click on a question or an answer: Copy, Select All, and Ask About This, which quotes the
    // selection at the top of the question box. One menu serves every message.
    function openTextMenu(target, at) {
        textMenu.target = target
        textMenu.kept = target.persistentSelection
        target.persistentSelection = true // The menu takes focus; the selection stays.
        textMenu.popup(target, at.x, at.y)
    }
    // Ask About This: the passage joins the next question as an attachment chip above the box.
    function quote(text) {
        textMenu.target = null // The question box keeps the focus once the menu closes.
        root.c.quote(text)
        question.forceActiveFocus()
    }
    Menu {
        id: textMenu
        objectName: "aiTextMenu"
        property Item target: null
        property bool kept: false
        readonly property bool selected: target !== null && target.selectedText.length > 0
        onClosed: if (target) { target.persistentSelection = kept; if (selected) target.forceActiveFocus() }
        MenuItem { objectName: "aiTextCopy"; text: "Copy"; enabled: textMenu.selected; onTriggered: researchStore.copyText(root.selectionText(textMenu.target)) }
        MenuItem {
            objectName: "aiTextSelectAll"; text: "Select All"
            enabled: textMenu.target !== null && textMenu.target.length > 0
            onTriggered: textMenu.target.selectAll()
        }
        MenuSeparator {}
        MenuItem {
            objectName: "aiTextAsk"; text: "Ask About This"; enabled: textMenu.selected
            onTriggered: { const target = textMenu.target; target.persistentSelection = textMenu.kept; root.quote(root.selectionText(target)) }
        }
    }
    // The Threads: wide, a column on the left; narrow, in place of the chats until one is chosen.
    Item {
        id: topicColumn
        objectName: "aiTopics"
        visible: root.wide || (root.showingThreads && root.topicsOpen)
        anchors.left: parent.left; anchors.top: parent.top
        // Narrow, the question box stays below the Threads too.
        anchors.bottom: root.wide ? parent.bottom : composerArea.top
        width: root.wide ? root.topicWidth : parent.width
        Rectangle { visible: root.wide; anchors.right: parent.right; width: 1; height: parent.height; color: Theme.separator }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            anchors.rightMargin: root.wide ? 7 : 8
            spacing: 6
            RowLayout {
                Layout.fillWidth: true; Layout.minimumWidth: 0
                spacing: 2
                Label {
                    Layout.fillWidth: true; Layout.minimumWidth: 0
                    text: "Threads"
                    elide: Text.ElideRight; textFormat: Text.PlainText
                    font.pixelSize: Theme.fontBody; font.weight: Font.DemiBold; color: Theme.text
                }
                IconButton { objectName: "aiNewTopic"; icon.name: "add"; description: "New Thread"; onClicked: root.askTopicName("", []) }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.separator }
            ListView {
                id: topicList
                objectName: "aiTopicList"
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumWidth: 0
                clip: true
                model: root.topics
                ScrollBar.vertical: ScrollBar {}
                // A Thread, and (opened with the arrow) its chats right under it: what is in it, at a glance.
                delegate: Column {
                    id: topicEntry
                    required property var modelData
                    required property int index
                    readonly property bool here: topicRow.here
                    readonly property bool highlighted: topicRow.highlighted
                    readonly property bool expandable: modelData.key.length > 0 && modelData.chats > 0
                    readonly property bool expanded: expandable && root.expandedTopics.indexOf(modelData.key) >= 0
                    readonly property var chats: expanded ? (root.topicRevision, researchStore.aiThreads().filter(function(t) { return t.topic === topicEntry.modelData.key })) : []
                    objectName: "aiTopic-" + index
                    width: ListView.view.width
                    ItemDelegate {
                        id: topicRow
                        readonly property var modelData: topicEntry.modelData
                        readonly property bool here: modelData.key.length > 0 && modelData.key === root.readerTopic
                        objectName: "aiTopicRow-" + topicEntry.index
                        width: parent.width
                        height: Theme.rowHeightTall
                        leftPadding: 2
                        // The Thread shown, and the one a dragged chat would go into.
                        highlighted: root.currentTopic.key === modelData.key || chatDrop.containsDrag
                        onClicked: root.chooseTopic(modelData.key)
                        HoverHandler { id: topicHover }
                        contentItem: RowLayout {
                            spacing: 2
                            // Opens the Thread in place, its chats listed under it.
                            IconButton {
                                objectName: "aiTopicExpand"
                                Layout.preferredWidth: 18
                                implicitWidth: 18; implicitHeight: 22; glyphSize: Theme.fontSmall
                                opacity: topicEntry.expandable ? 1 : 0
                                enabled: topicEntry.expandable
                                icon.name: topicEntry.expanded ? "down" : "right"
                                description: topicEntry.expanded ? "Hide its chats" : "Show its chats"
                                onClicked: root.toggleTopic(topicEntry.modelData.key)
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; Layout.minimumWidth: 0
                                spacing: 1
                                Label {
                                    Layout.fillWidth: true
                                    text: topicRow.modelData.title
                                    elide: Text.ElideRight; textFormat: Text.PlainText
                                    color: topicRow.highlighted ? Theme.selectedText : Theme.text
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: (topicRow.here ? "This paper · " : "") + topicRow.modelData.chats + (topicRow.modelData.chats === 1 ? " chat" : " chats")
                                    elide: Text.ElideRight; textFormat: Text.PlainText
                                    color: Theme.textTertiary; font.pixelSize: Theme.fontCaption
                                }
                            }
                            // The Thread's menu (also on right-click): new chat, rename, merge, delete.
                            IconButton {
                                id: topicMore
                                objectName: "aiTopicMore"
                                visible: topicRow.modelData.key.length > 0 && (topicHover.hovered || topicRow.highlighted)
                                implicitWidth: 24; implicitHeight: 24; glyphSize: Theme.fontBody
                                icon.name: "more"; description: "Thread actions"
                                onClicked: root.openTopicMenu(topicRow.modelData, topicMore, 0, topicMore.height)
                            }
                        }
                        // Chats dropped here move into this Thread and stay there.
                        DropArea {
                            id: chatDrop
                            anchors.fill: parent
                            keys: ["owelk-ai-chats"]
                            enabled: topicRow.modelData.key.length > 0
                            onDropped: function(drop) {
                                const ids = root.draggedChats.slice(), key = topicRow.modelData.key
                                drop.accept()
                                Qt.callLater(function() { root.moveChats(ids, key) })
                            }
                        }
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            enabled: topicRow.modelData.key.length > 0
                            onTapped: function(point) { root.openTopicMenu(topicRow.modelData, topicRow, point.position.x, point.position.y) }
                        }
                    }
                    // Its chats, newest first: a click opens one (in its Thread), a right-click its menu.
                    Repeater {
                        model: topicEntry.chats
                        delegate: ItemDelegate {
                            id: chatEntry
                            required property var modelData
                            required property int index
                            readonly property bool open: !root.showingThreads && !!root.c && root.c.threadId === modelData.id
                            objectName: "aiTopicChat-" + index
                            width: topicEntry.width
                            height: Theme.rowHeight
                            // Set in under its Thread's title, a faint line joining it to the Thread.
                            leftPadding: 36
                            highlighted: open
                            Rectangle { x: 26; width: 1; height: parent.height; color: Theme.separator }
                            onClicked: root.openChatIn(topicEntry.modelData.key, modelData.id)
                            ToolTip.visible: hovered && chatTitle.truncated; ToolTip.delay: 500
                            ToolTip.text: modelData.title
                            contentItem: RowLayout {
                                spacing: 6
                                Label {
                                    id: chatTitle
                                    Layout.fillWidth: true; Layout.minimumWidth: 0
                                    text: chatEntry.modelData.title
                                    elide: Text.ElideRight; textFormat: Text.PlainText
                                    font.pixelSize: Theme.fontSmall
                                    color: chatEntry.open ? Theme.selectedText : Theme.textSecondary
                                }
                                Label {
                                    visible: !!root.c && root.c.answering.indexOf(chatEntry.modelData.id) >= 0
                                    text: "\u2026"
                                    font.pixelSize: Theme.fontSmall; color: Theme.textTertiary
                                }
                            }
                            TapHandler {
                                acceptedButtons: Qt.RightButton
                                onTapped: function(point) { root.openChatMenu([chatEntry.modelData.id], chatEntry.modelData, chatEntry, point.position.x, point.position.y) }
                            }
                        }
                    }
                }
            }
        }
    }
    ColumnLayout {
        anchors.top: parent.top; anchors.bottom: composerArea.top; anchors.right: parent.right
        anchors.left: root.wide ? topicColumn.right : parent.left
        anchors.margins: 8; anchors.bottomMargin: 6
        visible: root.wide || !topicColumn.visible
        spacing: 6
        RowLayout {
            Layout.fillWidth: true; Layout.minimumWidth: 0
            spacing: 2
            // Narrow: from the chats back to the Threads.
            IconButton {
                objectName: "aiTopicsButton"
                icon.name: "back"; description: "Threads"
                visible: root.showingThreads && !root.wide
                onClicked: { root.selectedThreads = []; root.topicsOpen = true }
            }
            IconButton {
                objectName: "aiThreadsButton"
                icon.name: "back"; description: "Chats"
                visible: !root.showingThreads
                onClicked: root.c.showThreads()
            }
            Label {
                id: headerTitle
                objectName: "aiThreadTitle"
                Layout.fillWidth: true; Layout.minimumWidth: 0
                text: root.showingThreads ? root.currentTopic.title : (root.c.thread.title || "New chat")
                elide: Text.ElideRight; textFormat: Text.PlainText
                font.pixelSize: Theme.fontBody; font.weight: Font.DemiBold; color: Theme.text
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: function(point) { root.openHeaderMenu(headerTitle, point.position.x, point.position.y) }
                }
            }
            IconButton {
                objectName: "aiTrashButton"
                visible: root.showingThreads
                icon.name: "trash"; description: "Trash (in the Library)"
                onClicked: root.trashRequested()
            }
            // A new chat in the Thread shown (from All Chats: the paper in front's, else General).
            IconButton { objectName: "aiNewThread"; icon.name: "add"; description: "New chat"; onClicked: { root.c.startIn(root.askKey); root.focusQuestion() } }
            // The Thread's menu, or the open chat's.
            IconButton {
                id: headerMore
                objectName: "aiMoreButton"
                visible: root.showingThreads ? root.currentTopic.key.length > 0 : !!root.c && root.c.threadId.length > 0
                icon.name: "more"; description: root.showingThreads ? "Thread actions" : "Chat actions"
                onClicked: root.openHeaderMenu(headerMore, 0, headerMore.height)
            }
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.separator }
        // The Thread's chats, newest first. Click opens; Cmd/Ctrl-click and Shift-click select
        // several; Delete or the right-click menu moves them to the Trash; dragged onto a Thread of one's
        // own (wide), they move there.
        ListView {
            id: threadList
            objectName: "aiThreadList"
            Layout.minimumWidth: 0
            visible: root.showingThreads
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true
            spacing: 0
            focus: visible
            // Read again when threads change.
            property int revision: 0
            model: (revision, researchStore.aiThreads().filter(function(t) { return !root.currentTopic.key.length || t.topic === root.currentTopic.key }))
            Connections {
                target: researchStore
                function onAiThreadsChanged() { threadList.revision++ }
            }
            onModelChanged: {
                const ids = model.map(function(t) { return t.id })
                root.selectedThreads = root.selectedThreads.filter(function(id) { return ids.indexOf(id) >= 0 })
            }
            Keys.onDeletePressed: if (root.selectedThreads.length) root.askTrashThreads(root.selectedThreads)
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Backspace && root.selectedThreads.length) { root.askTrashThreads(root.selectedThreads); event.accepted = true }
            }
            delegate: ItemDelegate {
                id: row
                required property var modelData
                required property int index
                readonly property bool chosen: root.selectedThreads.indexOf(modelData.id) >= 0
                objectName: "aiThread-" + index
                width: ListView.view.width
                height: Theme.rowHeightTall
                highlighted: chosen
                separator: index < threadList.count - 1
                onClicked: {
                    threadList.forceActiveFocus()
                    const mods = threadList.clickModifiers
                    if (mods & (Qt.ControlModifier | Qt.MetaModifier)) root.toggleThread(row.modelData.id, row.index)
                    else if (mods & Qt.ShiftModifier) root.selectThreadRange(row.index)
                    else { root.selectedThreads = []; const id = row.modelData.id, controller = root.c; Qt.callLater(function() { controller.openThread(id, true) }) }
                }
                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    acceptedModifiers: Qt.KeyboardModifierMask
                    // Only notes the keys held; the click itself goes to the row.
                    onPressedChanged: if (pressed) threadList.clickModifiers = point.modifiers
                }
                DragHandler {
                    id: chatDrag
                    objectName: "aiChatDrag"
                    target: null
                    enabled: root.wide
                    onActiveChanged: {
                        if (active) root.startChatDrag(row.chosen ? root.selectedThreads.slice() : [row.modelData.id], row.modelData.title, centroid.scenePosition)
                        else root.finishChatDrag()
                    }
                    onCentroidChanged: if (active) root.moveChatDrag(centroid.scenePosition)
                }
                function openMenu(item, x, y) {
                    if (!row.chosen) root.selectedThreads = [row.modelData.id]
                    root.openChatMenu(root.selectedThreads.slice(), row.modelData, item, x, y)
                }
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: function(point) { row.openMenu(row, point.position.x, point.position.y) }
                }
                HoverHandler { id: chatHover }
                contentItem: RowLayout {
                    spacing: 2
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.minimumWidth: 0
                        spacing: 1
                        Label { Layout.fillWidth: true; text: row.modelData.title; elide: Text.ElideRight; textFormat: Text.PlainText; color: row.chosen ? Theme.selectedText : Theme.text }
                        Label {
                            Layout.fillWidth: true
                            // "Answering…" while its answer is coming, also when another chat is shown.
                            text: root.c && root.c.answering.indexOf(row.modelData.id) >= 0 ? "Answering…"
                                  : Math.ceil(row.modelData.messages / 2) + (row.modelData.messages > 2 ? " turns" : " turn") + " · " + row.modelData.model
                            elide: Text.ElideRight; textFormat: Text.PlainText; color: Theme.textTertiary; font.pixelSize: Theme.fontCaption
                        }
                    }
                    IconButton {
                        id: chatMore
                        objectName: "aiChatMore"
                        visible: chatHover.hovered
                        implicitWidth: 24; implicitHeight: 24; glyphSize: Theme.fontBody
                        icon.name: "more"; description: "Chat actions"
                        onClicked: row.openMenu(chatMore, 0, chatMore.height)
                    }
                }
            }
            property int clickModifiers: 0
            Label {
                anchors.centerIn: parent
                width: parent.width - 16
                visible: threadList.count === 0
                text: "Ask below to start a chat here, or ask about a selection, page or figure."
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere; horizontalAlignment: Text.AlignHCenter
                color: Theme.textTertiary; font.pixelSize: Theme.fontSmall
            }
        }
        // A conversation opened from a note while it is in the Trash: readable, continued once restored.
        RowLayout {
            objectName: "aiTrashedBanner"
            visible: !root.showingThreads && !!root.c && !!root.c.thread.trashed
            Layout.fillWidth: true
            Layout.leftMargin: 10; Layout.rightMargin: 6; Layout.topMargin: 6
            Label {
                Layout.fillWidth: true
                text: "This conversation is in the Trash."
                wrapMode: Text.Wrap; font.pixelSize: Theme.fontSmall; color: Theme.textSecondary
            }
            Button {
                objectName: "aiRestoreThread"
                text: "Restore"
                implicitHeight: Theme.controlHeightSmall; font.pixelSize: Theme.fontSmall
                onClicked: root.c.restoreThread()
            }
        }
        // The conversation: earlier turns, then the streaming answer. Mouse drags select text (the
        // wheel and trackpad scroll); the view follows a streaming answer only while at the bottom.
        ListView {
            id: conversation
            objectName: "aiConversation"
            Layout.minimumWidth: 0
            visible: !root.showingThreads
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true
            spacing: 10
            acceptedButtons: Qt.NoButton
            ScrollBar.vertical: ScrollBar {}
            property bool following: true
            property bool settling: false
            // A chat read again (an answer came in) keeps its place: the end while following, else where
            // it was. Another chat opens at its latest turn.
            property string shown: ""
            function load() {
                const id = root.c ? root.c.threadId : "", stay = following || id !== shown, at = contentY
                settling = true
                model = root.c ? root.c.messages : []
                settling = false
                shown = id
                if (stay) Qt.callLater(toEnd)
                else Qt.callLater(function() { conversation.settling = true; conversation.contentY = at; conversation.settling = false })
            }
            Connections { target: root.c; function onMessagesChanged() { conversation.load() } }
            Component.onCompleted: load()
            readonly property bool nearEnd: contentHeight <= height || contentY + height >= contentHeight + originY - 24
            function toEnd() { following = true; settling = true; positionViewAtEnd(); settling = false }
            function follow() { if (following) Qt.callLater(toEnd) }
            // The question an answer replies to: the nearest user turn above it.
            function toQuestion(index) {
                const list = root.c ? root.c.messages : []
                let at = index
                while (at > 0 && list[at].role !== "user") --at
                following = false
                positionViewAtIndex(at, ListView.Beginning)
            }
            onContentYChanged: if (!settling) following = nearEnd
            onCountChanged: follow()
            // Turns above are laid out after the view moves; it keeps to the end while following.
            onContentHeightChanged: follow()
            delegate: ColumnLayout {
                id: message
                required property var modelData
                required property int index
                width: ListView.view.width
                spacing: 4
                // What went with the question, above it.
                Flow {
                    readonly property var sent: message.modelData.role === "user" ? root.sentAttachments(message.modelData) : []
                    objectName: "aiSent-" + message.index
                    visible: sent.length > 0
                    Layout.fillWidth: true
                    Layout.leftMargin: Math.min(40, conversation.width * 0.12)
                    // Right-aligned like the question; filled from the right, so the list is reversed.
                    layoutDirection: Qt.RightToLeft
                    spacing: 4
                    Repeater {
                        model: parent.sent.slice().reverse()
                        delegate: AttachmentChip {
                            required property int index
                            objectName: "aiSentChip-" + message.index + "-" + index
                        }
                    }
                }
                Bubble {
                    visible: message.modelData.role === "user"
                    objectName: "aiQuestion-" + message.index
                    text: message.modelData.display || ""
                }
                ThinkingFold {
                    readonly property var context: message.modelData.context || ({})
                    objectName: "aiThought-" + message.index
                    Layout.fillWidth: true
                    summary: message.modelData.role === "assistant" ? (context.thinking || "") : ""
                    seconds: context.thinkingSeconds || 0
                }
                AnswerText {
                    visible: message.modelData.role === "assistant"
                    objectName: "aiMessage-" + message.index
                    Layout.fillWidth: true
                    text: visible ? researchStore.markdownHtml(message.modelData.content, Theme.accent, Theme.text, Theme.fontBody) : ""
                }
                Label {
                    objectName: "aiCutOff-" + message.index
                    readonly property var context: message.modelData.context || ({})
                    // A question with no answer keeps why: stopped before any text, or what went wrong.
                    visible: message.modelData.role === "assistant" && !!(context.cutOff || context.stopped || context.failed)
                    text: context.failed ? "No answer: " + context.failed : context.stopped ? "Stopped." : "Stopped at the length limit."
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere; Layout.fillWidth: true
                    textFormat: Text.PlainText; color: context.failed ? Theme.danger : Theme.textTertiary; font.pixelSize: Theme.fontSmall
                }
                RowLayout {
                    visible: message.modelData.role === "assistant" && message.modelData.content.length > 0
                    spacing: 0
                    IconButton { icon.name: "copy"; description: "Copy answer"; glyphSize: Theme.fontBody; onClicked: researchStore.copyText(message.modelData.content) }
                    // A new note, or one of the notes about this paper (a menu when there are some).
                    IconButton {
                        id: saveNoteButton
                        objectName: "aiSaveNote-" + message.index
                        icon.name: "note"; description: "Save as note"; glyphSize: Theme.fontBody
                        onClicked: {
                            const notes = root.c.paperNotes()
                            if (!notes.length) { root.c.saveAsNote(message.index); return }
                            saveNoteMenu.notes = notes
                            saveNoteMenu.popup(saveNoteButton, 0, saveNoteButton.height)
                        }
                        Menu {
                            id: saveNoteMenu
                            objectName: "aiSaveNoteMenu"
                            property var notes: []
                            MenuItem { objectName: "aiSaveNewNote"; text: "New Note"; onTriggered: root.c.saveAsNote(message.index) }
                            MenuSeparator {}
                            Instantiator {
                                model: saveNoteMenu.notes
                                delegate: MenuItem {
                                    required property var modelData
                                    text: "Add to \u201c" + modelData.title + "\u201d"
                                    onTriggered: root.c.saveAsNote(message.index, modelData.id)
                                }
                                onObjectAdded: function(index, item) { saveNoteMenu.insertItem(index + 2, item) }
                                onObjectRemoved: function(index, item) { saveNoteMenu.removeItem(item) }
                            }
                        }
                    }
                    IconButton {
                        objectName: "aiToQuestion-" + message.index
                        icon.name: "toQuestion"; description: "Back to the question"; glyphSize: Theme.fontBody
                        onClicked: conversation.toQuestion(message.index)
                    }
                }
            }
            footer: ColumnLayout {
                width: conversation.width
                spacing: 4
                Bubble {
                    visible: root.c && root.c.pendingQuestion.length > 0
                    objectName: "aiPendingQuestion"
                    Layout.topMargin: 10
                    text: root.c ? root.c.pendingQuestion : ""
                }
                ThinkingFold {
                    objectName: "aiThinking"
                    Layout.fillWidth: true
                    live: root.c && root.c.streaming && root.c.answer.length === 0
                    visible: root.c && root.c.streaming && (live || shown)
                    summary: root.c ? root.c.thinkingText : ""
                    seconds: root.c ? root.c.thinkingSeconds : 0
                    onSummaryChanged: conversation.follow()
                }
                AnswerText {
                    objectName: "aiAnswer"
                    visible: root.c && root.c.answer.length > 0
                    Layout.fillWidth: true
                    text: root.c && root.c.answer.length ? researchStore.markdownHtml(root.c.answer, Theme.accent, Theme.text, Theme.fontBody) : ""
                    onTextChanged: conversation.follow()
                }
                Label {
                    objectName: "aiError"
                    visible: root.c && root.c.error.length > 0
                    Layout.fillWidth: true; Layout.topMargin: 6
                    text: root.c ? root.c.error : ""; wrapMode: Text.WrapAtWordBoundaryOrAnywhere; textFormat: Text.PlainText
                    color: Theme.danger; font.pixelSize: Theme.fontSmall
                }
                // A paper translated a page at a time: the next page, in the same thread.
                Button {
                    objectName: "aiTranslateNext"
                    visible: root.c && root.c.canTranslateNext
                    Layout.topMargin: 4
                    text: root.c ? "Translate Page " + (root.c.translatePage + 2) : ""
                    icon.name: "forward"
                    onClicked: root.c.translateNext()
                }
                Button {
                    objectName: "aiOpenSettings"
                    visible: root.c && root.c.error.indexOf("Settings") >= 0
                    text: "Open Settings…"; implicitHeight: Theme.rowHeight - 2
                    onClicked: root.settingsRequested()
                }
            }
            // Scrolled up while newer text sits below: one click back to the latest.
            IconButton {
                id: toLatest
                objectName: "aiToLatest"
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                z: 2
                visible: !conversation.nearEnd && conversation.count > 0
                icon.name: "toLatest"; description: "Go to the latest"
                background: Rectangle {
                    implicitWidth: Theme.controlHeight; implicitHeight: Theme.controlHeight
                    radius: height / 2
                    color: toLatest.hovered ? Theme.hover : Theme.raised
                    border.color: Theme.border
                }
                onClicked: conversation.toEnd()
            }
        }
    }
    // Below the chats and the conversation (narrow, below the Threads too): attachments, the question
    // box and the composer bar. Asked from a list, the question starts a chat in that Thread.
    ColumnLayout {
        id: composerArea
        objectName: "aiComposerArea"
        anchors.bottom: parent.bottom; anchors.right: parent.right
        anchors.left: root.wide ? topicColumn.right : parent.left
        anchors.margins: 8
        spacing: 6
        // Attachments for the next turn; × removes one. Images show a thumbnail.
        Flow {
            id: attachmentRow
            Layout.fillWidth: true; Layout.minimumWidth: 0
            spacing: 4
            visible: root.c && root.c.attachments.length > 0
            Repeater {
                model: root.c ? root.c.attachments : []
                delegate: AttachmentChip {
                    required property int index
                    objectName: "aiChip-" + modelData.kind + (modelData.kind === "image" || modelData.kind === "extra" ? "-" + modelData.index : "")
                    removable: !modelData.fixed
                    onRemoved: { const kind = modelData.kind, at = modelData.index; Qt.callLater(function() { root.c.detach(kind, at) }) }
                }
            }
        }
        // The question box grows with its text up to a limit, then scrolls (the scroll bar shows only
        // while scrolling). From three lines on, the corner button makes it taller or back.
        Item {
            id: composer
            objectName: "aiComposer"
            property bool expanded: false
            readonly property bool tall: question.lineCount >= 3
            readonly property real limit: expanded ? Math.max(140, root.height * 0.5) : 140
            Layout.minimumWidth: 0
            Layout.fillWidth: true
            // Expanded, the box keeps its larger height (like Zed or ChatGPT) until collapsed or sent.
            Layout.preferredHeight: expanded ? limit : Math.min(limit, Math.max(56, question.implicitHeight))
            onTallChanged: if (!tall) expanded = false
            ScrollView {
                id: questionScroll
                objectName: "aiQuestionScroll"
                anchors.fill: parent
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                TextArea {
                    id: question
                    objectName: "aiQuestion"
                    // A click elsewhere in the window takes the cursor out (Main.qml); the box, its attachments
                    // and the bar under it (send, model, attach) keep it.
                    property bool releaseFocusOnOutsidePress: true
                    property var keepFocusWithin: [composer, attachmentRow, bar]
                    placeholderText: root.showingThreads ? (root.askKind === "paper" ? "Ask about the paper…" : root.askKind === "general" ? "Ask in General…" : "Ask in this Thread…")
                                     : root.c && root.c.spec.scope === "library" ? (root.c.spec.collection ? "Ask this collection…" : "Ask your library…") : root.c && root.c.threadId.length ? "Ask a follow-up…" : "Ask about the paper…"
                    wrapMode: TextEdit.Wrap
                    font.pixelSize: Theme.fontSmall
                    rightPadding: composer.tall ? 28 : 8
                    // Return sends, Shift+Return adds a line; pasting an image attaches it.
                    Keys.onPressed: function(event) {
                        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                            if (root.ask(text)) { text = ""; composer.expanded = false }
                            event.accepted = true
                        } else if (event.matches(StandardKey.Paste) && root.c.pasteImage()) {
                            event.accepted = true
                        }
                    }
                }
            }
            IconButton {
                objectName: "aiComposerSize"
                visible: composer.tall
                anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 3
                implicitWidth: 22; implicitHeight: 22; glyphSize: Theme.fontSmall
                icon.name: composer.expanded ? "collapse" : "expand"
                description: composer.expanded ? "Smaller question box" : "Larger question box"
                onClicked: { composer.expanded = !composer.expanded; question.forceActiveFocus() }
            }
        }
        // Composer bar, one row: context, model, reasoning effort, fast mode, Send. When the panel is
        // narrow the model name is shortened first; every control stays visible.
        RowLayout {
            id: bar
            Layout.fillWidth: true; Layout.minimumWidth: 0
            spacing: width < Theme.fontBody * 16 ? 2 : 4
            IconButton {
                id: attachButton
                objectName: "aiAttachButton"
                icon.name: "attach"
                description: "Add context"
                onClicked: attachMenu.popup(attachButton, 0, -attachMenu.implicitHeight)
                Menu {
                    id: attachMenu
                    MenuItem { objectName: "aiAttachPaper"; text: "This Paper"; enabled: root.c && root.c.reader !== null && root.c.reader.source.toString().length > 0; onTriggered: root.c.attachPaper() }
                    MenuItem { objectName: "aiAttachPapers"; text: "Papers…"; onTriggered: picker.begin("papers") }
                    MenuItem { objectName: "aiAttachCollection"; text: "Collection…"; onTriggered: picker.begin("collection") }
                    MenuItem { objectName: "aiAttachLibrary"; text: "Whole Library"; onTriggered: root.c.attachCollection("", "") }
                    MenuSeparator {}
                    MenuItem { objectName: "aiAttachRegion"; text: "Region of the PDF…"; enabled: root.c && root.c.reader !== null; onTriggered: root.c.captureRegion() }
                    MenuItem { objectName: "aiAttachImage"; text: "Image…"; onTriggered: imageDialog.open() }
                }
            }
            Chip {
                id: modelButton
                trailingIcon: "down"
                Layout.fillWidth: true
                Layout.minimumWidth: Theme.iconButton
                Layout.maximumWidth: implicitWidth
                objectName: "aiModelButton"
                text: root.c ? root.c.modelLabel : ""
                ToolTip.text: "Model"
                onClicked: { root.c.loadModels(); modelFilter.text = ""; modelMenu.open() }
            }
            Chip {
                id: effortButton
                trailingIcon: "down"
                objectName: "aiEffortButton"
                Layout.maximumWidth: Theme.fontBody * 7
                visible: root.c && root.c.efforts.length > 0
                // A narrow panel shows a gauge instead of the effort's name.
                compact: bar.width < Theme.fontBody * 22
                icon.name: "effort"
                text: root.c ? root.c.effortName(root.c.effectiveEffort) : ""
                ToolTip.text: "Reasoning effort"
                onClicked: effortMenu.popup(effortButton, 0, -effortMenu.implicitHeight)
                Menu {
                    id: effortMenu
                    objectName: "aiEffortMenu"
                    Instantiator {
                        model: root.c ? root.c.efforts : []
                        delegate: MenuItem {
                            required property string modelData
                            objectName: "aiEffort-" + modelData
                            text: root.c.effortName(modelData)
                            checkable: true; checked: root.c.effectiveEffort === modelData
                            onTriggered: root.c.setEffort(modelData)
                        }
                        onObjectAdded: function(index, item) { effortMenu.insertItem(index, item) }
                        onObjectRemoved: function(index, item) { effortMenu.removeItem(item) }
                    }
                }
            }
            IconButton {
                objectName: "aiFastButton"
                visible: root.c && root.c.fastAvailable
                icon.name: "fast"
                checkable: true
                checked: root.c && root.c.effectiveFast
                description: "Fast mode"
                onClicked: root.c.setFast(checked)
            }
            Item { Layout.fillWidth: true; Layout.minimumWidth: 0 }
            IconButton {
                id: sendButton
                objectName: "aiSend"
                Layout.alignment: Qt.AlignBottom
                primary: true
                readonly property bool stopping: root.c && root.c.streaming
                icon.name: stopping ? "stop" : "send"
                glyphSize: stopping ? Theme.fontSmall : Theme.iconSize
                description: stopping ? "Stop" : "Send · " + Platform.keys("Return")
                enabled: stopping || question.text.trim().length > 0 || (root.c && root.c.attachments.length > 0)
                onClicked: {
                    if (root.c.streaming) { root.c.stop(); return }
                    Qt.inputMethod.commit() // the last Korean character may still be composing
                    if (root.ask(question.text)) question.text = ""
                }
            }
        }
    }
    // Images, PDFs and papers dragged from the Library are attached to the next question.
    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list", "owelk/paper"]
        onDropped: function(drop) {
            if (drop.source && drop.source.paperUrls) root.c.attachPapers(drop.source.paperUrls)
            else {
                const pdfs = drop.urls.filter(function(url) { return /\.pdf$/i.test(url.toString()) })
                if (pdfs.length) root.c.attachPapers(pdfs)
                for (const url of drop.urls) root.c.attachImage(url)
            }
            drop.accept()
        }
    }
    // Papers (open tabs first, then the Library; several can be chosen) or a collection, to ask about.
    Popup {
        id: picker
        objectName: "aiPicker"
        property string mode: "papers"
        property var chosen: []
        function begin(what) { mode = what; chosen = []; pickerFilter.text = ""; open() }
        function toggle(url) { chosen = chosen.indexOf(url) >= 0 ? chosen.filter(function(u) { return u !== url }) : chosen.concat([url]) }
        function attach() {
            if (!chosen.length) return
            const urls = chosen.slice()
            close()
            root.c.attachPapers(urls)
        }
        function choose(row) {
            if (mode === "papers") toggle(row.url)
            else { close(); root.c.attachCollection(row.id, row.name) }
        }
        parent: attachButton
        y: -height - 4
        margins: 6
        width: Math.max(240, Math.min(320, root.width))
        padding: 8
        onOpened: pickerFilter.forceActiveFocus()
        readonly property string needle: pickerFilter.text.trim()
        readonly property var rows: {
            researchStore.searchText.revision
            if (!visible || !root.c) return []
            const words = needle.toLowerCase()
            const match = function(name) { return researchStore.searchText.matches(name, words) }
            if (mode === "collection")
                return researchStore.collections().filter(function(c) { return match(c.name) })
                    .map(function(c) { return {type: "collection", id: c.id, name: c.name, count: c.count} })
            const current = root.c.spec, list = [], seen = {}
            const taken = function(url) {
                return (!!current.source && researchStore.sameSource(current.source, url)) || (current.papers || []).some(function(p) { return researchStore.sameSource(p, url) })
            }
            const tabs = root.c.openTabPapers().filter(function(url) { return !taken(url) })
                .map(function(url) { return {type: "paper", url: url, name: researchStore.displayName(url)} }).filter(function(r) { return match(r.name) })
            if (tabs.length) list.push({type: "section", name: "Open Tabs"})
            tabs.forEach(function(r) { seen[r.url] = true; list.push(r) })
            const library = researchStore.libraryDocuments({text: needle, limit: 40})
                .map(function(d) { return {type: "paper", url: d.url.toString(), name: d.name} })
                .filter(function(r) { return !seen[r.url] && !taken(r.url) })
            if (library.length) list.push({type: "section", name: "Library"})
            library.forEach(function(r) { list.push(r) })
            return list
        }
        contentItem: ColumnLayout {
            spacing: 4
            TextField {
                id: pickerFilter
                objectName: "aiPickerFilter"
                Layout.fillWidth: true
                implicitHeight: Theme.controlHeight
                font.pixelSize: Theme.fontSmall
                placeholderText: picker.mode === "papers" ? "Search papers" : "Search collections"
                onTextChanged: if (picker.visible) researchStore.searchText.prepare(text)
                Keys.onEscapePressed: picker.close()
                Keys.onReturnPressed: {
                    if (picker.mode === "papers") picker.attach()
                    else { const first = picker.rows.find(function(r) { return r.type === "collection" }); if (first) picker.choose(first) }
                }
            }
            ListView {
                id: pickerList
                objectName: "aiPickerList"
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(300, Math.max(contentHeight, Theme.rowHeight))
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: picker.rows
                delegate: ItemDelegate {
                    id: pick
                    required property var modelData
                    required property int index
                    readonly property bool section: modelData.type === "section"
                    readonly property bool picked: modelData.type === "paper" && picker.chosen.indexOf(modelData.url) >= 0
                    objectName: "aiPick-" + index
                    width: ListView.view.width
                    implicitHeight: Theme.rowHeight - 2
                    enabled: !section
                    highlighted: picked
                    leftPadding: section ? 4 : 26
                    contentItem: Label {
                        text: pick.modelData.name
                        elide: Text.ElideRight; textFormat: Text.PlainText
                        font.pixelSize: pick.section ? Theme.fontCaption : Theme.fontSmall
                        font.weight: pick.section ? Font.DemiBold : Font.Normal
                        color: pick.section ? Theme.textTertiary : pick.picked ? Theme.selectedText : Theme.text
                    }
                    Icon {
                        visible: !pick.section
                        x: 6; anchors.verticalCenter: parent.verticalCenter
                        name: pick.modelData.type === "collection" ? "folder" : pick.picked ? "check" : "document"
                        size: Theme.fontBody; color: pick.picked ? Theme.selectedText : Theme.textTertiary
                    }
                    onClicked: picker.choose(modelData)
                }
                Label {
                    anchors.centerIn: parent
                    visible: pickerList.count === 0
                    text: picker.mode === "papers" ? "No paper found." : "No collection found."
                    color: Theme.textTertiary; font.pixelSize: Theme.fontSmall
                }
            }
            RowLayout {
                visible: picker.mode === "papers"
                Layout.fillWidth: true
                Label {
                    Layout.fillWidth: true
                    text: picker.chosen.length ? picker.chosen.length + " chosen" : "Up to 3 are read whole; more are searched."
                    elide: Text.ElideRight; font.pixelSize: Theme.fontCaption; color: Theme.textTertiary
                }
                Button {
                    objectName: "aiPickerAttach"
                    text: "Attach"
                    primary: true
                    enabled: picker.chosen.length > 0
                    implicitHeight: Theme.controlHeightSmall; font.pixelSize: Theme.fontSmall
                    onClicked: picker.attach()
                }
            }
        }
    }
    Native.FileDialog {
        id: imageDialog
        title: "Attach images"
        fileMode: Native.FileDialog.OpenFiles
        nameFilters: ["Images (*.png *.jpg *.jpeg *.gif *.webp *.heic)"]
        onAccepted: { for (const url of selectedFiles) root.c.attachImage(url) }
    }
    // Model picker: every set-up provider's models, grouped by company, with a filter.
    Popup {
        id: modelMenu
        objectName: "aiModelMenu"
        parent: modelButton
        y: -height - 4
        // Stays inside the window, however narrow the panel.
        margins: 6
        width: Math.max(220, Math.min(300, root.width))
        height: Math.min(440, pickerColumn.implicitHeight + 16)
        padding: 8
        onOpened: modelFilter.forceActiveFocus()
        contentItem: ColumnLayout {
            id: pickerColumn
            spacing: 4
            TextField {
                id: modelFilter
                objectName: "aiModelFilter"
                Layout.fillWidth: true
                implicitHeight: Theme.controlHeight
                font.pixelSize: Theme.fontSmall
                placeholderText: "Search models"
                onTextChanged: if (modelMenu.visible) researchStore.searchText.prepare(text)
                Keys.onEscapePressed: modelMenu.close()
            }
            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(360, modelColumn.implicitHeight)
                clip: true
                contentHeight: modelColumn.implicitHeight
                ColumnLayout {
                    id: modelColumn
                    width: parent.width
                    spacing: 1
                    Repeater {
                        model: root.c ? root.c.ai.providers.filter(function(p) { return p.configured || p.id === "ollama" }) : []
                        delegate: ColumnLayout {
                            id: providerSection
                            required property var modelData
                            readonly property string needle: modelFilter.text.trim().toLowerCase()
                            readonly property var list: (researchStore.searchText.revision, (root.c.models[modelData.id] || []).filter(function(m) {
                                return researchStore.searchText.matches(m.name + " " + m.id + " " + providerSection.modelData.name, needle)
                            }))
                            visible: !needle.length || list.length > 0
                            Layout.fillWidth: true
                            spacing: 1
                            Label { text: root.c.companyName(providerSection.modelData.id); font.pixelSize: Theme.fontCaption; font.weight: Font.DemiBold; color: Theme.textTertiary; Layout.topMargin: 4; Layout.leftMargin: 4 }
                            readonly property bool loaded: root.c.models[modelData.id] !== undefined
                            Label {
                                visible: !providerSection.loaded && !providerSection.needle.length
                                text: "Loading…"
                                font.pixelSize: Theme.fontCaption; color: Theme.textTertiary; Layout.leftMargin: 10
                            }
                            // A provider that lists no models (or is signed out) still runs its own default.
                            ItemDelegate {
                                objectName: "aiModel-" + providerSection.modelData.id + "-default"
                                visible: providerSection.loaded && (root.c.models[providerSection.modelData.id] || []).length === 0 && !providerSection.needle.length
                                Layout.fillWidth: true
                                implicitHeight: Theme.rowHeight - 2
                                highlighted: root.c.ai.provider === providerSection.modelData.id && !root.c.model
                                contentItem: Label { text: "Default model"; font.pixelSize: Theme.fontSmall; color: Theme.text }
                                onClicked: {
                                    const provider = providerSection.modelData.id, controller = root.c
                                    modelMenu.close()
                                    Qt.callLater(function() { controller.chooseModel(provider, "") })
                                }
                            }
                            Repeater {
                                model: providerSection.list
                                delegate: ItemDelegate {
                                    id: modelRow
                                    required property var modelData
                                    readonly property bool current: root.c.ai.provider === providerSection.modelData.id && root.c.model === modelData.id
                                    objectName: "aiModel-" + providerSection.modelData.id + "-" + modelData.id
                                    Layout.fillWidth: true
                                    implicitHeight: Theme.rowHeight - 2
                                    highlighted: current
                                    // The name, then a small bolt when the model has a fast mode; a check marks the one in use.
                                    contentItem: RowLayout {
                                        spacing: 4
                                        Label { Layout.maximumWidth: modelRow.availableWidth - 40; text: modelRow.modelData.name; elide: Text.ElideRight; font.pixelSize: Theme.fontSmall; color: modelRow.current ? Theme.selectedText : Theme.text }
                                        Icon { visible: !!modelRow.modelData.fast; name: "fast"; size: Theme.fontCaption; color: Theme.textTertiary }
                                        Item { Layout.fillWidth: true }
                                        Icon { visible: modelRow.current; name: "check"; size: Theme.fontBody; color: Theme.selectedText }
                                    }
                                    // Choosing rebuilds this list (the provider list changes), so act after the handler returns.
                                    onClicked: {
                                        const provider = providerSection.modelData.id, model = modelData.id, controller = root.c
                                        modelMenu.close()
                                        Qt.callLater(function() { controller.chooseModel(provider, model) })
                                    }
                                }
                            }
                        }
                    }
                    // Providers that are not set up yet, in one line.
                    ItemDelegate {
                        objectName: "aiModelSetup"
                        readonly property var missing: root.c ? root.c.ai.providers.filter(function(p) { return !p.configured && p.id !== "ollama" }) : []
                        visible: missing.length > 0 && !modelFilter.text.length
                        Layout.fillWidth: true; Layout.topMargin: 4
                        implicitHeight: Theme.rowHeight - 2
                        contentItem: Label {
                            text: "Set up " + parent.missing.map(function(p) { return root.c.companyName(p.id) }).join(", ") + "…"
                            elide: Text.ElideRight; font.pixelSize: Theme.fontCaption; color: Theme.textTertiary
                        }
                        onClicked: { modelMenu.close(); root.settingsRequested() }
                    }
                }
            }
        }
    }
    // One menu for the thread list: what it offers depends on how many are selected.
    Menu {
        id: threadMenu
        objectName: "aiThreadMenu"
        property var ids: []
        property var row: ({})
        property var paper: ""
        property string place: ""
        // A chat about a paper: back to that paper.
        MenuItem {
            objectName: "aiChatPaper"
            visible: threadMenu.place.length > 0; height: visible ? implicitHeight : 0
            text: root.placeLabels[threadMenu.place] || ""
            onTriggered: root.goToPaper(threadMenu.paper, threadMenu.place)
        }
        MenuSeparator { visible: threadMenu.place.length > 0; height: visible ? implicitHeight : 0 }
        MenuItem {
            visible: threadMenu.ids.length === 1
            height: visible ? implicitHeight : 0
            text: "Rename…"
            onTriggered: { renameDialog.threadId = threadMenu.row.id; renameField.text = threadMenu.row.title; renameDialog.open() }
        }
        Menu {
            id: moveMenu
            objectName: "aiMoveMenu"
            title: "Move to Thread"
            Instantiator {
                model: root.otherTopics(threadMenu.row.topic || "")
                delegate: MenuItem {
                    required property var modelData
                    objectName: "aiMoveTo-" + modelData.title
                    text: modelData.title
                    onTriggered: root.moveChats(threadMenu.ids, modelData.key)
                }
                onObjectAdded: function(index, item) { moveMenu.insertItem(index, item) }
                onObjectRemoved: function(index, item) { moveMenu.removeItem(item) }
            }
            MenuSeparator {}
            MenuItem { objectName: "aiMoveToNewTopic"; text: "New Thread…"; onTriggered: root.askTopicName("", threadMenu.ids) }
        }
        MenuItem {
            objectName: "aiRemoveFromTopic"
            visible: root.keptAside(threadMenu.row)
            height: visible ? implicitHeight : 0
            text: threadMenu.ids.length > 1 ? "Move " + threadMenu.ids.length + " Out of the Thread" : "Move Out of the Thread"
            onTriggered: root.moveChats(threadMenu.ids, "")
        }
        MenuItem {
            objectName: "trashThreadOption"
            text: threadMenu.ids.length > 1 ? "Move " + threadMenu.ids.length + " to Trash…" : "Move to Trash"
            palette.windowText: Theme.danger
            onTriggered: root.askTrashThreads(threadMenu.ids)
        }
    }
    Dialog {
        id: renameDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 360
        modal: true
        title: "Rename Chat"
        property string threadId: ""
        standardButtons: Dialog.Ok | Dialog.Cancel
        TextField { id: renameField; objectName: "aiRenameField"; width: parent.width; onAccepted: renameDialog.accept() }
        onAccepted: root.c.renameThread(threadId, renameField.text)
    }
    // A Thread's menu (its "…" button or a right-click): a new chat in it, a new name (one's own), merged
    // into another, or deleted: with its chats (to the Trash), or, one's own, leaving them to their papers.
    Menu {
        id: topicMenu
        objectName: "aiTopicMenu"
        property var row: ({})
        property var paper: ""
        property string place: ""
        readonly property bool own: row.kind === "custom"
        // A paper's Thread: back to its paper, wherever its tab is, opened again when closed, or its file
        // found when it moved.
        MenuItem {
            objectName: "aiTopicPaper"
            visible: topicMenu.place.length > 0; height: visible ? implicitHeight : 0
            text: root.placeLabels[topicMenu.place] || ""
            onTriggered: root.goToPaper(topicMenu.paper, topicMenu.place)
        }
        MenuSeparator { visible: topicMenu.place.length > 0; height: visible ? implicitHeight : 0 }
        MenuItem { objectName: "aiTopicNewChat"; text: "New Chat"; onTriggered: root.newChatIn(topicMenu.row.key) }
        MenuItem {
            objectName: "aiRenameTopic"
            visible: topicMenu.own; height: visible ? implicitHeight : 0
            text: "Rename…"
            onTriggered: root.askTopicName(topicMenu.row.key, [])
        }
        Menu {
            id: mergeMenu
            objectName: "aiMergeMenu"
            title: "Merge Into"
            Instantiator {
                model: root.otherTopics(topicMenu.row.key || "")
                delegate: MenuItem {
                    required property var modelData
                    objectName: "aiMergeInto-" + modelData.title
                    text: modelData.title
                    onTriggered: root.mergeTopic(topicMenu.row, modelData)
                }
                onObjectAdded: function(index, item) { mergeMenu.insertItem(index, item) }
                onObjectRemoved: function(index, item) { mergeMenu.removeItem(item) }
            }
        }
        MenuSeparator {}
        // Deleting a Thread is red, apart from the rest: one Delete, which opens to its two ways, each asking
        // first (deleteTopicDialog).
        Menu {
            id: deleteMenu
            objectName: "aiDeleteMenu"
            title: "Delete"
            // Read by the menu row that opens it (style/MenuItem.qml): red.
            readonly property bool danger: true
            // (Not from its rows' enabled: they follow the menu's, which would make a loop.)
            enabled: topicMenu.row.chats > 0 || topicMenu.row.kind === "paper" || topicMenu.own
            MenuItem {
                id: deleteTrash
                objectName: "aiTrashTopic"
                enabled: topicMenu.row.chats > 0 || topicMenu.row.kind === "paper"
                text: "Delete Thread and Chats…"
                palette.windowText: Theme.danger
                onTriggered: root.askDeleteTopic(topicMenu.row, false)
            }
            // One's own: its chats go back to their papers' Threads (or General). A paper's: they move to
            // General. General itself has nowhere else to keep them.
            MenuItem {
                id: deleteKeep
                objectName: "aiDeleteTopic"
                enabled: topicMenu.own || (topicMenu.row.kind === "paper" && topicMenu.row.chats > 0)
                text: "Delete Thread, Keep Chats…"
                palette.windowText: Theme.danger
                onTriggered: root.askDeleteTopic(topicMenu.row, true)
            }
        }
    }
    // Asked once before a Thread goes: with its chats (to the Trash), or leaving them to their papers.
    ConfirmDialog {
        id: deleteTopicDialog
        objectName: "aiDeleteTopicDialog"
        property var row: ({})
        property bool keepChats: false
        readonly property int chats: row.chats || 0
        readonly property string name: "\u201c" + (row.title || "") + "\u201d"
        title: keepChats || chats === 0 ? "Delete this Thread?" : "Delete this Thread and its chats?"
        message: keepChats
                 ? "The Thread " + name + " will be deleted. Are you sure?\n\n" + (chats === 1 ? "Its chat is kept and goes" : "Its " + chats + " chats are kept and go")
                   + (row.kind === "paper" ? " to General." : " back to their papers' Threads (or General).")
                 : chats === 0 ? "The Thread " + name + " will be deleted. Are you sure?\n\nIt has no chats; asking about the paper again makes it anew."
                 : name + " and " + (chats === 1 ? "its chat" : "all " + chats + " of its chats")
                   + " will be deleted. Are you sure?\n\nThe chats go to the Trash in the Library: until it is emptied, "
                   + (chats === 1 ? "it" : "they") + " can be restored there."
        actionText: keepChats || chats === 0 ? "Delete Thread" : "Delete Thread and Chats"
        onConfirmed: keepChats ? root.deleteTopicKeepingChats(row) : root.trashTopic(row)
    }
    // Asked once before several chats (a selection) go to the Trash.
    ConfirmDialog {
        id: trashChatsDialog
        objectName: "aiTrashChatsDialog"
        property var ids: []
        title: "Move " + ids.length + " chats to the Trash?"
        message: "These " + ids.length + " chats, with all their questions and answers, will be deleted. Are you sure?"
                 + "\n\nThey go to the Trash in the Library: until it is emptied, they can be restored there."
        actionText: "Move to Trash"
        onConfirmed: root.trashThreads(ids)
    }
    Dialog {
        id: topicDialog
        objectName: "aiTopicDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 360
        modal: true
        title: topicId.length ? "Rename Thread" : "New Thread"
        property string topicId: ""
        property var chats: []
        standardButtons: Dialog.Ok | Dialog.Cancel
        TextField { id: topicField; objectName: "aiTopicField"; width: parent.width; placeholderText: "Name"; onAccepted: topicDialog.accept() }
        onOpened: topicField.forceActiveFocus()
        onAccepted: root.saveTopic(topicId, topicField.text, chats)
    }
    // A chat on its way to a Thread: its title follows the pointer.
    Rectangle {
        id: dragProxy
        objectName: "aiChatDragProxy"
        property bool dragging: false
        property alias label: dragLabel.text
        function moveTo(scene) { const at = root.mapFromItem(null, scene.x, scene.y); x = at.x - 10; y = at.y - height / 2 }
        visible: dragging
        z: 10
        width: Math.min(220, dragLabel.implicitWidth + 16); height: 24
        radius: Theme.radius; color: Theme.raised; border.color: Theme.border
        Drag.active: dragging
        Drag.keys: ["owelk-ai-chats"]
        Drag.hotSpot.x: 10; Drag.hotSpot.y: 12
        Label {
            id: dragLabel
            anchors.verticalCenter: parent.verticalCenter
            x: 8; width: parent.width - 16
            elide: Text.ElideRight; textFormat: Text.PlainText
            font.pixelSize: Theme.fontSmall; color: Theme.text
        }
    }
}
