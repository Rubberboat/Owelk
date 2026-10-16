import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Owelk.Ui

// For You: the topics, people and collections followed, and how often and how far back to look.
ColumnLayout {
    id: root
    objectName: "forYouSettings"
    spacing: 22
    readonly property var forYou: researchStore.forYou
    // Read again after a change here.
    property int revision: 0
    Connections { target: researchStore; function onSettingsChanged() { root.revision++ } }
    // Topics and followed collections live in the library (they sync).
    Connections { target: root.forYou; function onSettingsChanged() { root.revision++ } }
    readonly property var topics: (revision, forYou.topics())
    readonly property var collections: (revision, researchStore.documentsRevision, researchStore.collections())
    function saveTopics(list) { forYou.saveTopics(list) }
    function setTopic(index, change) {
        const list = topics.map(function(t) { return Object.assign({}, t) })
        Object.assign(list[index], change)
        saveTopics(list)
    }
    // People: found by name (Semantic Scholar's author records), then followed.
    readonly property var people: (revision, forYou.people())
    property var foundPeople: []
    property string peopleStatus: ""
    property bool findingPeople: false
    function findPeople() {
        const name = personName.text.trim()
        if (!name.length) return
        findingPeople = true; peopleStatus = "Looking…"; foundPeople = []
        forYou.findPeople(name)
    }
    // Followed: the search is done (its list goes after this click, whose row it holds).
    function followFound(person) {
        personName.clear(); peopleStatus = ""
        forYou.followPerson(person, true)
        Qt.callLater(function() { root.foundPeople = [] })
    }
    Connections {
        target: root.forYou
        function onPeopleFound(name, people, error) {
            root.findingPeople = false
            root.foundPeople = people
            root.peopleStatus = error.length ? error : people.length ? "" : "No one by that name on Semantic Scholar."
        }
    }
    function addTopic() {
        if (!topicWords.text.trim().length && !topicCategories.text.trim().length) return
        saveTopics(topics.concat([{words: topicWords.text, categories: topicCategories.text, on: true}]))
        topicWords.clear(); topicCategories.clear()
        topicWords.forceActiveFocus()
    }
    SettingsGroup {
        objectName: "settingsGroup-topics"
        title: "Topics"
        note: "New arXiv papers with any of the words (separate them with commas), in any of the categories, such as cs.RO or cs.CV. Either may be left empty."
        Repeater {
            model: root.topics
            delegate: SettingsRow {
                id: topicRow
                required property var modelData
                required property int index
                objectName: "forYouTopic-" + index
                label: modelData.words || modelData.categories
                detail: modelData.words ? modelData.categories : ""
                opacity: modelData.on === false ? .55 : 1
                IconButton {
                    objectName: "forYouRemoveTopic-" + topicRow.index
                    icon.name: "trash"; description: "Remove"
                    onClicked: root.saveTopics(root.topics.filter(function(_, i) { return i !== topicRow.index }))
                }
                Switch {
                    objectName: "forYouTopicSwitch-" + topicRow.index
                    checked: topicRow.modelData.on !== false
                    onToggled: root.setTopic(topicRow.index, {on: checked})
                }
            }
        }
        SettingsRow {
            objectName: "settingsRow-addTopic"
            wide: true
            TextField {
                id: topicWords
                objectName: "forYouTopicWords"
                Layout.fillWidth: true
                placeholderText: "Words: lidar odometry, SLAM"
                onAccepted: root.addTopic()
            }
            TextField {
                id: topicCategories
                objectName: "forYouTopicCategories"
                Layout.preferredWidth: 130
                placeholderText: "cs.RO, cs.CV"
                onAccepted: root.addTopic()
            }
            Button {
                objectName: "forYouAddTopic"
                text: "Add"
                enabled: topicWords.text.trim().length > 0 || topicCategories.text.trim().length > 0
                onClicked: root.addTopic()
            }
        }
    }
    SettingsGroup {
        objectName: "settingsGroup-people"
        title: "People"
        note: "New papers by researchers you follow, such as the people you follow on Google Scholar. Find one by name and choose the right person (Semantic Scholar's author records); only the name is sent to look, then their author ID."
        Repeater {
            model: root.people
            delegate: SettingsRow {
                id: personRow
                required property var modelData
                required property int index
                objectName: "forYouPerson-" + index
                label: modelData.name
                detail: modelData.detail
                IconButton {
                    objectName: "forYouRemovePerson-" + personRow.index
                    icon.name: "trash"; description: "Stop following"
                    onClicked: root.forYou.followPerson(personRow.modelData, false)
                }
            }
        }
        SettingsRow {
            objectName: "settingsRow-findPerson"
            wide: true
            TextField {
                id: personName
                objectName: "forYouPersonName"
                Layout.fillWidth: true
                placeholderText: "Name: Ada Lovelace"
                onAccepted: root.findPeople()
            }
            Button {
                objectName: "forYouFindPeople"
                text: "Find"
                enabled: personName.text.trim().length > 0 && !root.findingPeople
                onClicked: root.findPeople()
            }
        }
        SettingsRow {
            objectName: "settingsRow-peopleStatus"
            visible: root.peopleStatus.length > 0
            label: root.peopleStatus
        }
        Repeater {
            model: root.foundPeople
            delegate: SettingsRow {
                id: foundRow
                required property var modelData
                required property int index
                readonly property bool followed: (root.revision, root.forYou.followingPerson(modelData.id))
                objectName: "forYouFoundPerson-" + index
                label: modelData.name
                detail: modelData.detail || "No details"
                Button {
                    objectName: "forYouFollowPerson-" + foundRow.index
                    text: foundRow.followed ? "Following" : "Follow"
                    enabled: !foundRow.followed
                    highlighted: !foundRow.followed
                    onClicked: root.followFound(foundRow.modelData)
                }
            }
        }
    }
    SettingsGroup {
        objectName: "settingsGroup-followCollections"
        title: "Collections"
        note: root.collections.length ? "Papers like the ones in a followed collection, from Semantic Scholar. It looks at the papers that have an arXiv ID or a DOI (Paper Details)."
                                      : "Make collections in the Library to follow them here."
        Repeater {
            model: root.collections
            delegate: SettingsRow {
                id: collectionRow
                required property var modelData
                readonly property int usable: (root.revision, root.forYou.usablePapers(modelData.id))
                readonly property bool followed: (root.revision, root.forYou.following(modelData.id))
                objectName: "forYouCollection-" + modelData.name
                label: "    ".repeat(modelData.depth || 0) + modelData.name
                detail: usable ? usable + (usable === 1 ? " paper to compare with" : " papers to compare with")
                               : "Needs a paper with an arXiv ID or DOI"
                Switch {
                    objectName: "forYouFollow-" + collectionRow.modelData.name
                    checked: collectionRow.followed
                    enabled: collectionRow.usable > 0 || collectionRow.followed
                    onToggled: root.forYou.follow(collectionRow.modelData.id, checked)
                }
            }
        }
    }
    SettingsGroup {
        objectName: "settingsGroup-forYouChecking"
        title: "Checking"
        note: root.forYou.problem.length ? root.forYou.problem
            : "Papers found wait in Home and in Library › For You until you add or dismiss them. Only the words, categories, author IDs and arXiv IDs or DOIs above are sent."
        noteColor: root.forYou.problem.length ? Theme.danger : Theme.textTertiary
        SettingsRow {
            objectName: "settingsRow-forYouDaily"
            label: "Check once a day"
            detail: "A little after Owelk opens"
            Switch {
                objectName: "forYouDaily"
                checked: (root.revision, researchStore.setting("forYou.auto", "1") === "1")
                onToggled: researchStore.setSetting("forYou.auto", checked ? "1" : "0")
            }
        }
        // The AI orders new papers by how well they fit and gives each a reason. Turning it on is the OK to
        // send their titles and abstracts, with what is followed, to the AI chosen in Settings › AI.
        SettingsRow {
            id: aiRow
            objectName: "settingsRow-forYouAi"
            readonly property var ai: researchStore.ai
            readonly property var provider: (root.revision, ai.providers.find(function(p) { return p.id === ai.provider })) || ({})
            readonly property bool usable: !!provider.configured || provider.id === "ollama"
            label: "Explain with AI"
            detail: !usable ? "Set up AI in Settings › AI first."
                : "Orders new papers by how well they fit what you follow, with one sentence each. Sends their titles and abstracts and what you follow to " + (provider.sends || provider.name) + "."
            Switch {
                objectName: "forYouAi"
                enabled: aiRow.usable
                checked: (root.revision, researchStore.setting("forYou.ai", "1") === "1" && !!aiRow.provider.consented && aiRow.usable)
                onToggled: {
                    if (checked) researchStore.ai.giveConsent(researchStore.ai.provider)
                    researchStore.setSetting("forYou.ai", checked ? "1" : "0")
                }
            }
        }
        SettingsRow {
            objectName: "settingsRow-forYouDays"
            label: "Papers from the last"
            ComboBox {
                objectName: "forYouDays"
                Layout.preferredWidth: 140
                readonly property var days: [1, 7, 30]
                model: ["Day", "7 days", "30 days"]
                currentIndex: Math.max(0, days.indexOf(Number((root.revision, researchStore.setting("forYou.days", "7")))))
                onActivated: function(index) { researchStore.setSetting("forYou.days", String(days[index])) }
            }
        }
        SettingsRow {
            objectName: "settingsRow-forYouKeep"
            label: "Keep papers in the list"
            detail: "Until you add or dismiss them, for at most"
            ComboBox {
                objectName: "forYouKeep"
                Layout.preferredWidth: 140
                readonly property var days: [7, 15, 30, 60, 0]
                model: ["7 days", "15 days", "30 days", "60 days", "Always"]
                currentIndex: Math.max(0, days.indexOf(Number((root.revision, researchStore.setting("forYou.keepDays", "30")))))
                onActivated: function(index) { researchStore.setSetting("forYou.keepDays", String(days[index])) }
            }
        }
        SettingsRow {
            objectName: "settingsRow-forYouCount"
            label: "At most, per topic, person or collection"
            ComboBox {
                objectName: "forYouCount"
                Layout.preferredWidth: 140
                readonly property var counts: [5, 10, 20]
                model: counts.map(function(n) { return n + " papers" })
                currentIndex: Math.max(0, counts.indexOf(Number((root.revision, researchStore.setting("forYou.perSource", "10")))))
                onActivated: function(index) { researchStore.setSetting("forYou.perSource", String(counts[index])) }
            }
        }
        SettingsRow {
            objectName: "settingsRow-forYouCheck"
            label: root.forYou.checking ? "Looking for new papers…"
                 : root.forYou.lastChecked.getTime && !isNaN(root.forYou.lastChecked.getTime()) ? "Last checked " + root.forYou.lastChecked.toLocaleString(Qt.locale(), Locale.ShortFormat)
                 : "Not checked yet"
            Button {
                objectName: "forYouCheckNow"
                text: "Check Now"
                enabled: root.forYou.configured && !root.forYou.checking
                onClicked: root.forYou.refresh()
            }
        }
    }
}
