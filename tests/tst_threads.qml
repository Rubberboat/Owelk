import QtQuick
import QtTest
import Owelk.Ui
import "../qml" as App

// The AI panel's Threads: one per paper, General, and Threads of one's own holding chats about several
// papers. A stand-in reader is enough: the panel follows the paper in front.
Item {
    width: 1000; height: 700
    QtObject { id: reader; property url source: ""; property bool pdfReady: true; property int pageCount: 3; property int currentPage: 0; property string selectedText: "" }
    App.AiController { id: controller; reader: reader.source.toString().length ? reader : null }
    App.AiPanel { id: panel; width: 600; height: 700; controller: controller }
    TestCase {
        name: "AiThreads"
        when: windowShown
        // The data folder is shared with the other test files: these chats and Threads go at the end.
        property var made: []
        property string first: ""
        property string second: ""
        function chat(title, source) {
            const id = researchStore.createAiThread({title: title, provider: "claude", model: "m", source: source})
            made.push(id)
            return id
        }
        function initTestCase() {
            verify(researchStore.rememberDocument(outlineSource))
            verify(researchStore.rememberDocument(linkSource))
            first = researchStore.aiTopicFor(outlineSource)
            second = researchStore.aiTopicFor(linkSource)
            chat("A1", outlineSource); chat("A2", outlineSource); chat("B1", linkSource)
        }
        function cleanupTestCase() {
            for (const t of researchStore.aiTopics()) if (t.kind === "custom") researchStore.deleteAiTopic(t.key)
            researchStore.purgeAiThreads(made)
            researchStore.ai.clearApiKey("claude")
            researchStore.setSetting("ai.consent.claude", "")
        }
        function chats() { return findChild(panel, "aiThreadList") }
        // A visible item by objectName under item (findChild also finds menu items that are not shown).
        function shown(item, name) {
            if (item.objectName === name && item.visible) return item
            const children = item.children || []
            for (let i = 0; i < children.length; ++i) { const found = shown(children[i], name); if (found) return found }
            return null
        }
        function menuItem(menu, name) {
            for (let i = 0; i < menu.count; ++i) if (menu.itemAt(i) && menu.itemAt(i).objectName === name) return menu.itemAt(i)
            return null
        }
        // A chat with many turns, long enough to scroll.
        function longChat(title, turns) {
            const id = chat(title, outlineSource)
            for (let i = 0; i < turns; ++i) {
                verify(researchStore.appendAiMessage(id, {role: "user", content: "Question " + i, display: "Question " + i}))
                verify(researchStore.appendAiMessage(id, {role: "assistant", content: "Answer " + i + ". " + "Some words. ".repeat(30)}))
            }
            return id
        }
        function atEnd(view) { return view.count > 0 && Math.abs(view.contentY + view.height - view.contentHeight - view.originY) < 2 }
        function topicRow(title) {
            const list = findChild(panel, "aiTopicList")
            for (let i = 0; i < list.count; ++i) {
                list.positionViewAtIndex(i, ListView.Contain)
                const row = list.itemAtIndex(i)
                if (row && row.modelData.title === title) return row
            }
            return null
        }
        function test_1_threadsStandBesideTheChats() {
            verify(panel.wide)
            verify(findChild(panel, "aiTopics").visible)
            compare(panel.topics[0].title, "All Chats")
            compare(controller.topicKey, "")
            tryCompare(chats(), "count", Math.min(500, panel.topics[0].chats))
            const paper = panel.topics.find(function(t) { return t.key === first })
            compare(paper.title, researchStore.displayName(outlineSource))
            compare(paper.chats, 2)
            compare(paper.kind, "paper")
        }
        function test_2_thePaperInFrontShowsItsThread() {
            reader.source = outlineSource
            tryCompare(controller, "topicKey", first)
            tryCompare(chats(), "count", 2)
            compare(findChild(panel, "aiThreadTitle").text, researchStore.displayName(outlineSource))
            const row = topicRow(researchStore.displayName(outlineSource))
            verify(row.highlighted && row.here)
            reader.source = linkSource
            tryCompare(controller, "topicKey", second)
            tryCompare(chats(), "count", 1)
        }
        function test_3_aConversationAboutAnotherPaperGivesWay() {
            reader.source = outlineSource
            verify(controller.openThread(made[0]))
            reader.source = linkSource
            compare(controller.conversationOpen, false)
            compare(controller.topicKey, second)
            // About the paper in front again (after Home), it stays.
            verify(controller.openThread(made[2]))
            reader.source = ""; reader.source = linkSource
            compare(controller.conversationOpen, true)
            controller.showThreads()
        }
        function test_4_ownThreadTakesDraggedChatsAndStaysAcrossPapers() {
            reader.source = outlineSource
            panel.saveTopic("", "Radar", [])
            const radar = controller.topicKey
            verify(controller.isCustomTopic(radar))
            tryCompare(chats(), "count", 0)
            panel.chooseTopic(first)
            const list = chats()
            tryVerify(function() { return list.count === 2 && list.itemAtIndex(1) !== null })
            const chat = list.itemAtIndex(1), id = chat.modelData.id, target = topicRow("Radar")
            const from = chat.mapToItem(panel, chat.width / 2, chat.height / 2)
            const to = target.mapToItem(panel, target.width / 2, target.height / 2)
            mousePress(panel, from.x, from.y)
            for (let i = 1; i <= 12; ++i) mouseMove(panel, from.x + (to.x - from.x) * i / 12, from.y + (to.y - from.y) * i / 12)
            verify(findChild(panel, "aiChatDragProxy").visible)
            mouseRelease(panel, to.x, to.y)
            tryVerify(function() { return researchStore.aiThread(id).topic === radar })
            verify(!findChild(panel, "aiChatDragProxy").visible)
            tryCompare(list, "count", 1)
            // Inside one's own Thread another paper in front changes nothing.
            panel.chooseTopic(radar)
            reader.source = linkSource
            compare(controller.topicKey, radar)
            // Deleted, its chats go back to their papers.
            panel.deleteTopic(radar)
            compare(controller.topicKey, "")
            compare(researchStore.aiThread(id).topic, first)
            verify(topicRow("Radar") === null)
        }
        function test_5_menusMoveChatsAndNameThreads() {
            reader.source = outlineSource
            panel.saveTopic("", "Reading group", [])
            const group = controller.topicKey
            panel.chooseTopic(first)
            const list = chats()
            tryVerify(function() { return list.count > 0 && list.itemAtIndex(0) !== null })
            const id = list.itemAtIndex(0).modelData.id
            mouseClick(list.itemAtIndex(0), 10, 10, Qt.RightButton)
            const menu = findChild(panel, "aiThreadMenu")
            tryCompare(menu, "opened", true)
            const move = findChild(panel, "aiMoveMenu")
            let item = null
            for (let i = 0; i < move.count; ++i) if (move.itemAt(i).objectName === "aiMoveTo-Reading group") item = move.itemAt(i)
            verify(item !== null)
            verify(!findChild(panel, "aiRemoveFromTopic").visible)
            item.triggered()
            menu.close()
            tryVerify(function() { return researchStore.aiThread(id).topic === group })
            panel.chooseTopic(group)
            tryVerify(function() { return list.count === 1 && list.itemAtIndex(0) !== null })
            mouseClick(list.itemAtIndex(0), 10, 10, Qt.RightButton)
            tryCompare(menu, "opened", true)
            verify(findChild(panel, "aiRemoveFromTopic").visible)
            findChild(panel, "aiRemoveFromTopic").triggered()
            menu.close()
            tryVerify(function() { return researchStore.aiThread(id).topic === first })
            mouseClick(topicRow("Reading group"), 10, 10, Qt.RightButton)
            const topicMenu = findChild(panel, "aiTopicMenu")
            tryCompare(topicMenu, "opened", true)
            findChild(panel, "aiRenameTopic").triggered()
            topicMenu.close()
            const dialog = findChild(panel, "aiTopicDialog")
            tryCompare(dialog, "opened", true)
            compare(findChild(panel, "aiTopicField").text, "Reading group")
            findChild(panel, "aiTopicField").text = "Journal club"
            dialog.accept()
            tryVerify(function() { return topicRow("Journal club") !== null })
            panel.deleteTopic(group)
        }
        function test_6_narrowShowsOneListAtATime() {
            panel.width = 300
            verify(!panel.wide)
            reader.source = outlineSource
            panel.chooseTopic(first)
            const column = findChild(panel, "aiTopics"), back = findChild(panel, "aiTopicsButton")
            tryCompare(column, "visible", false)
            tryCompare(chats(), "visible", true)
            mouseClick(back)
            tryCompare(column, "visible", true)
            tryCompare(chats(), "visible", false)
            mouseClick(topicRow(researchStore.displayName(linkSource)))
            tryCompare(column, "visible", false)
            compare(controller.topicKey, second)
            tryCompare(chats(), "count", 1)
            // The question box stays below the Threads: asked there, it starts a chat in the Thread chosen.
            mouseClick(back)
            tryCompare(column, "visible", true)
            const area = findChild(panel, "aiComposerArea"), box = findChild(panel, "aiQuestion")
            verify(area.visible && box.visible)
            verify(column.y + column.height <= area.y + 1)
            compare(box.placeholderText, "Ask about the paper…")
            panel.width = 600
        }
        function test_7_everyThreadHasAMenuAndMerges() {
            reader.source = outlineSource
            const loose = chat("Loose", "")
            panel.chooseTopic("")
            // General has a menu too, from its "…" button (shown on hover) or a right-click.
            const general = topicRow("General")
            verify(general !== null)
            mouseMove(general, general.width / 2, general.height / 2)
            const more = shown(general, "aiTopicMore")
            verify(more !== null)
            mouseClick(more)
            const menu = findChild(panel, "aiTopicMenu")
            tryCompare(menu, "opened", true)
            compare(menu.row.key, "general")
            verify(!menuItem(menu, "aiRenameTopic").visible)
            verify(!menuItem(menu, "aiDeleteTopic").visible)
            verify(menuItem(menu, "aiTrashTopic").enabled)
            menu.close()
            tryCompare(menu, "opened", false)
            // Merged into a Thread of one's own, its chats move there; that one merged into a paper's,
            // they stay in the paper's Thread and the merged Thread goes.
            panel.saveTopic("", "Gathered", [])
            const gathered = controller.topicKey
            mouseClick(topicRow("General"), 10, 10, Qt.RightButton)
            tryCompare(menu, "opened", true)
            const merge = findChild(panel, "aiMergeMenu")
            const into = menuItem(merge, "aiMergeInto-Gathered")
            verify(into !== null)
            into.triggered()
            menu.close()
            tryVerify(function() { return researchStore.aiThread(loose).topic === gathered })
            verify(topicRow("General") === null)
            panel.chooseTopic(gathered)
            mouseClick(findChild(panel, "aiMoreButton"))
            tryCompare(menu, "opened", true)
            compare(menu.row.key, gathered)
            verify(menuItem(menu, "aiRenameTopic").visible)
            menuItem(merge, "aiMergeInto-" + researchStore.displayName(linkSource)).triggered()
            menu.close()
            tryVerify(function() { return researchStore.aiThread(loose).topic === second })
            compare(controller.topicKey, second)
            verify(topicRow("Gathered") === null)
            // A chat's "…" (on hover) moves it into any Thread, General too, and back out.
            const list = chats()
            tryVerify(function() { return list.count > 0 && list.itemAtIndex(0) !== null })
            let row = null
            for (let i = 0; i < list.count; ++i) if (list.itemAtIndex(i) && list.itemAtIndex(i).modelData.id === loose) row = list.itemAtIndex(i)
            verify(row !== null)
            mouseMove(row, row.width / 2, row.height / 2)
            const chatMore = shown(row, "aiChatMore")
            verify(chatMore !== null)
            mouseClick(chatMore)
            const chatMenu = findChild(panel, "aiThreadMenu")
            tryCompare(chatMenu, "opened", true)
            verify(findChild(panel, "aiRemoveFromTopic").visible)
            const toGeneral = menuItem(findChild(panel, "aiMoveMenu"), "aiMoveTo-General")
            verify(toGeneral !== null)
            toGeneral.triggered()
            chatMenu.close()
            tryVerify(function() { return researchStore.aiThread(loose).topic === "general" })
            // Deleted with its chats (a red row), a Thread's chats go to the Trash only once confirmed.
            panel.chooseTopic("general")
            const trashTopic = function() {
                mouseClick(findChild(panel, "aiThreadTitle"), 10, 5, Qt.RightButton)
                tryCompare(menu, "opened", true)
                compare(menu.row.key, "general")
                const item = menuItem(menu, "aiTrashTopic")
                verify(Qt.colorEqual(item.palette.windowText, Theme.danger))
                verify(!Qt.colorEqual(menuItem(menu, "aiTopicNewChat").palette.windowText, Theme.danger))
                item.triggered()
                menu.close()
            }
            trashTopic()
            const confirm = findChild(panel, "aiDeleteTopicDialog")
            tryCompare(confirm, "opened", true)
            compare(confirm.title, "Delete this Thread and its chats?")
            verify(confirm.message.indexOf("Are you sure?") >= 0)
            confirm.reject()
            tryCompare(confirm, "opened", false)
            compare(researchStore.aiThread(loose).trashed, false)
            trashTopic()
            tryCompare(confirm, "opened", true)
            confirm.accept()
            tryVerify(function() { return researchStore.aiThread(loose).trashed === true })
        }
        function test_8_askingInAThreadStartsAChatThere() {
            researchStore.setSetting("ai.baseUrl.claude", testInput.webFixture("/").toString())
            researchStore.ai.provider = "claude"
            verify(researchStore.ai.setApiKey("claude", "sk-ui-test-key"))
            researchStore.ai.giveConsent("claude")
            reader.source = outlineSource
            const box = findChild(panel, "aiQuestion")
            const ask = function(key, question) {
                controller.showThreads()
                panel.chooseTopic(key)
                tryCompare(controller, "conversationOpen", false)
                box.forceActiveFocus()
                box.text = question
                keyClick(Qt.Key_Return)
                compare(box.text, "")
                compare(controller.conversationOpen, true)
                tryCompare(controller, "streaming", false, 10000)
                verify(controller.threadId.length > 0)
                made.push(controller.threadId)
                compare(controller.messages.length, 2)
                return researchStore.aiThread(controller.threadId)
            }
            // General: a chat about no paper, in General, even with a paper in front.
            panel.chooseTopic("general")
            compare(box.placeholderText, "Ask in General…")
            let asked = ask("general", "Anything new?")
            compare(asked.topic, "general")
            compare(asked.source.toString(), "")
            compare(controller.topicKey, "general")
            // A paper's Thread (not the paper in front): a chat about that paper, there.
            asked = ask(second, "What is the main claim?")
            compare(asked.topic, second)
            verify(researchStore.sameSource(asked.source, linkSource))
            // One's own: it stays there; All Chats: the paper in front's Thread.
            panel.saveTopic("", "Asked here", [])
            const own = controller.topicKey
            asked = ask(own, "Compare them?")
            compare(asked.topic, own)
            asked = ask("", "And this one?")
            compare(asked.topic, first)
            compare(controller.topicKey, "")
            // + in General starts a chat about no paper.
            panel.chooseTopic("general")
            mouseClick(findChild(panel, "aiNewThread"))
            compare(controller.conversationOpen, true)
            compare(controller.spec.source, undefined)
            controller.showThreads()
        }
        function test_9_aChatOpensAtItsLatestTurn() {
            reader.source = outlineSource
            panel.chooseTopic(first)
            const many = longChat("Long", 15), other = longChat("Other", 12)
            const view = findChild(panel, "aiConversation")
            verify(controller.openThread(many, true))
            tryVerify(function() { return view.count === 30 && view.contentHeight > view.height * 2 })
            tryVerify(function() { return atEnd(view) })
            wait(200)
            verify(atEnd(view))
            // Scrolled up there, another chat still opens at its end; so does the first one again.
            view.contentY = view.originY
            verify(!view.following)
            controller.showThreads()
            verify(controller.openThread(other, true))
            tryVerify(function() { return view.count === 24 && atEnd(view) })
            controller.showThreads()
            verify(controller.openThread(many, true))
            tryVerify(function() { return view.count === 30 && atEnd(view) })
            // An answer coming in reloads the chat: it stays at the end.
            verify(researchStore.appendAiMessage(many, {role: "user", content: "One more", display: "One more"}))
            verify(researchStore.appendAiMessage(many, {role: "assistant", content: "Last answer."}))
            controller.thread = researchStore.aiThread(many)
            tryVerify(function() { return view.count === 32 && atEnd(view) })
            controller.showThreads()
        }
        function test_9z_deletingSeveralChatsOrAThreadAsksFirst() {
            reader.source = outlineSource
            panel.saveTopic("", "Pile", [])
            const pile = controller.topicKey, ids = []
            for (const title of ["P1", "P2", "P3"]) {
                ids.push(researchStore.createAiThread({title: title, provider: "claude", model: "m", source: outlineSource, topic: pile}))
                made.push(ids[ids.length - 1])
            }
            panel.chooseTopic(pile)
            const list = chats(), menu = findChild(panel, "aiThreadMenu"), ask = findChild(panel, "aiTrashChatsDialog")
            const trashed = function(id) { return researchStore.aiThread(id).trashed === true }
            tryVerify(function() { return list.count === 3 && list.itemAtIndex(2) !== null })
            // One chat goes to the Trash at once.
            const single = list.itemAtIndex(0).modelData.id
            mouseClick(list.itemAtIndex(0), 10, 10, Qt.RightButton)
            tryCompare(menu, "opened", true)
            findChild(panel, "trashThreadOption").triggered()
            menu.close()
            verify(!ask.opened)
            tryVerify(function() { return trashed(single) })
            // Several: the Delete key and the menu both ask; Cancel keeps them.
            tryVerify(function() { return list.count === 2 && list.itemAtIndex(1) !== null })
            const two = [list.itemAtIndex(0).modelData.id, list.itemAtIndex(1).modelData.id]
            panel.selectedThreads = two.slice()
            list.forceActiveFocus()
            keyClick(Qt.Key_Delete)
            tryCompare(ask, "opened", true)
            compare(ask.title, "Move 2 chats to the Trash?")
            verify(ask.message.indexOf("Are you sure?") >= 0)
            ask.reject()
            tryCompare(ask, "opened", false)
            verify(!trashed(two[0]) && !trashed(two[1]))
            panel.selectedThreads = two.slice()
            mouseClick(list.itemAtIndex(0), 10, 10, Qt.RightButton)
            tryCompare(menu, "opened", true)
            const option = findChild(panel, "trashThreadOption")
            compare(option.text, "Move 2 to Trash…")
            option.triggered()
            menu.close()
            tryCompare(ask, "opened", true)
            ask.accept()
            tryVerify(function() { return trashed(two[0]) && trashed(two[1]) })
            // A Thread of one's own deleted while keeping its chats asks too (in red).
            const kept = chat("Kept", outlineSource)
            researchStore.moveAiThreads([kept], pile)
            const topicMenu = findChild(panel, "aiTopicMenu"), confirm = findChild(panel, "aiDeleteTopicDialog")
            const deleteKeeping = function() {
                mouseClick(topicRow("Pile"), 10, 10, Qt.RightButton)
                tryCompare(topicMenu, "opened", true)
                const item = menuItem(topicMenu, "aiDeleteTopic")
                verify(item.visible)
                verify(Qt.colorEqual(item.palette.windowText, Theme.danger))
                item.triggered()
                topicMenu.close()
                tryCompare(confirm, "opened", true)
            }
            deleteKeeping()
            compare(confirm.title, "Delete this Thread?")
            confirm.reject()
            tryCompare(confirm, "opened", false)
            verify(topicRow("Pile") !== null)
            deleteKeeping()
            confirm.accept()
            tryVerify(function() { return topicRow("Pile") === null })
            compare(researchStore.aiThread(kept).topic, first)
            verify(!trashed(kept))
        }
        function rowFor(list, id) {
            for (let i = 0; i < list.count; ++i) {
                list.positionViewAtIndex(i, ListView.Contain)
                const row = list.itemAtIndex(i)
                if (row && row.modelData.id === id) return row
            }
            return null
        }
        function test_9zz_allChatsHasAMenuAndSeveralCanBeChosen() {
            reader.source = outlineSource
            panel.chooseTopic("")
            // All Chats has a "…" too: every chat to the Trash is red and asks first.
            const more = findChild(panel, "aiMoreButton")
            verify(more.visible)
            mouseClick(more)
            const allMenu = findChild(panel, "aiAllChatsMenu")
            tryCompare(allMenu, "opened", true)
            const deleteAll = menuItem(allMenu, "aiDeleteAllChats")
            verify(Qt.colorEqual(deleteAll.palette.windowText, Theme.danger))
            deleteAll.triggered()
            allMenu.close()
            const confirm = findChild(panel, "aiDeleteTopicDialog")
            tryCompare(confirm, "opened", true)
            compare(confirm.title, "Delete all chats?")
            confirm.reject()
            tryCompare(confirm, "opened", false)
            verify(researchStore.aiThreads().length > 0)
            // Several Threads, chosen after the Threads column's "…": a click marks them; deleting them
            // asks; merged, they all go into one.
            panel.saveTopic("", "Alpha", [])
            const alpha = controller.topicKey
            panel.saveTopic("", "Beta", [])
            const beta = controller.topicKey
            const a = chat("In alpha", outlineSource), b = chat("In beta", linkSource)
            researchStore.moveAiThreads([a], alpha)
            researchStore.moveAiThreads([b], beta)
            panel.chooseTopic("")
            mouseClick(findChild(panel, "aiTopicsMore"))
            const header = findChild(panel, "aiTopicsHeaderMenu")
            tryCompare(header, "opened", true)
            menuItem(header, "aiSelectThreadsOption").triggered()
            header.close()
            verify(panel.selectingTopics)
            tryVerify(function() { return topicRow("Alpha") !== null && topicRow("Beta") !== null })
            mouseClick(topicRow("Alpha"))
            mouseClick(topicRow("Beta"))
            compare(panel.selectedTopics.length, 2)
            verify(shown(topicRow("Alpha"), "aiTopicMark").checked)
            compare(findChild(panel, "aiTopicsTitle").text, "2 selected")
            compare(controller.topicKey, "")
            // The header row has made room for Delete, More and Done.
            const trashTopics = findChild(panel, "aiTrashTopics"), done = findChild(panel, "aiTopicsDone")
            tryVerify(function() { return trashTopics.x > 0 && done.x > trashTopics.x })
            mouseClick(trashTopics)
            tryCompare(confirm, "opened", true)
            compare(confirm.title, "Delete 2 Threads and their chats?")
            verify(confirm.message.indexOf("Are you sure?") >= 0)
            confirm.reject()
            tryCompare(confirm, "opened", false)
            verify(topicRow("Alpha") !== null)
            mouseClick(findChild(panel, "aiTopicsMore"))
            const chosenMenu = findChild(panel, "aiSelectedTopicsMenu")
            tryCompare(chosenMenu, "opened", true)
            menuItem(findChild(panel, "aiMergeSelectedMenu"), "aiMergeSelectedInto-General").triggered()
            chosenMenu.close()
            tryVerify(function() { return researchStore.aiThread(a).topic === "general" && researchStore.aiThread(b).topic === "general" })
            verify(!panel.selectingTopics)
            verify(topicRow("Alpha") === null && topicRow("Beta") === null)
            // Several chats, chosen from a chat's menu: clicks mark them, the header acts on them all.
            panel.chooseTopic("general")
            const list = chats()
            tryVerify(function() { return rowFor(list, a) !== null && rowFor(list, b) !== null })
            mouseClick(rowFor(list, a), 10, 10, Qt.RightButton)
            const menu = findChild(panel, "aiThreadMenu")
            tryCompare(menu, "opened", true)
            // A right-click opens the menu, not the chat.
            wait(50)
            compare(controller.conversationOpen, false)
            findChild(panel, "aiSelectChatsOption").triggered()
            menu.close()
            verify(panel.selectingChats)
            compare(panel.selectedThreads, [a])
            mouseClick(rowFor(list, b))
            compare(panel.selectedThreads.length, 2)
            verify(shown(rowFor(list, b), "aiChatMark").checked)
            compare(controller.conversationOpen, false)
            compare(findChild(panel, "aiThreadTitle").text, "2 selected")
            const trashChats = findChild(panel, "aiTrashSelected"), chatsDone = findChild(panel, "aiChatsDone")
            tryVerify(function() { return trashChats.x > 0 && chatsDone.x > trashChats.x })
            mouseClick(trashChats)
            const ask = findChild(panel, "aiTrashChatsDialog")
            tryCompare(ask, "opened", true)
            ask.accept()
            tryVerify(function() { return researchStore.aiThread(a).trashed === true && researchStore.aiThread(b).trashed === true })
            mouseClick(chatsDone)
            verify(!panel.selectingChats)
            compare(findChild(panel, "aiThreadTitle").text, "General")
        }
    }
}
