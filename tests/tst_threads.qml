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
        }
        function chats() { return findChild(panel, "aiThreadList") }
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
            panel.width = 600
        }
    }
}
