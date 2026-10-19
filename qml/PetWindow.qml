import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Owelk.Ui

// The desktop pet, 알맹이 (Allmeng-E), a tuxedo cat in a small window that floats above other apps while Owelk
// runs (Settings › Appearance › Desktop pet). It lives on the line it was left on: sits, grooms, strolls along
// it, sleeps on a small tower beside it, rolls on its back, stretches, and now and then dashes out of the screen
// and back. Drag it anywhere (it keeps still while held); a click brings Owelk forward; the right button has its
// menu. While Owelk is behind other apps it says when an AI answer is ready or failed and when For You has new
// papers, in a bubble above it; it kneads while an answer is written. PDFs dropped on it open in Owelk; text
// dropped on it is explained by the AI. After a stretch of reading it suggests a break. Nothing moves or redraws
// while nothing happens, and it stops when the screen is locked or Owelk is hidden.
Window {
    id: pet
    objectName: "petWindow"
    // Bring Owelk's window forward; with an AI conversation or For You to show.
    signal openRequested()
    signal threadRequested(string threadId)
    signal forYouRequested()
    signal pdfsDropped(var urls)
    signal explainRequested(string text)
    // Something dropped on the pet: PDFs to open, else text to explain. False if it was neither.
    function received(urls, text) {
        const pdfs = (urls || []).filter(function(url) { return /^file:.*\.pdf$/i.test(String(url)) })
        if (pdfs.length) { pdfsDropped(pdfs); return true }
        const words = String(text || "").trim()
        if (!words.length) return false
        explainRequested(words)
        return true
    }
    // Where the news comes from (researchStore.ai and researchStore.forYou in the app).
    property QtObject ai: null
    property QtObject forYou: null
    // Owelk is in front: news has nothing to add then, and goes. Behind again while an answer is being
    // written, the pet says so.
    property bool ownerActive: Qt.application.state === Qt.ApplicationActive
    onOwnerActiveChanged: {
        if (ownerActive) { if (message && !message.reminder && !message.plain) message = null }
        else if (writing && !message) sayWriting()
    }
    // What the bubble says: {text, kind, ttl} with thread (the conversation to open), writing, forYou or
    // reminder, or plain for the pet's own "meow". ttl: milliseconds it stays (0: until it is over).
    property var message: null
    // A notice is dropped while the pet dashes across the screen (from the crouch until it is back), and
    // while the screen is locked or Owelk hidden.
    function say(next) {
        if (brain.running || DesktopPet.dormant) return
        if (ownerActive && !next.reminder) return
        message = next
        // (Already kneading for the answer: no need to start over.)
        if (!(next.kind === "aiWriting" && brain.pose === "knead")) brain.react(next.kind)
    }
    function sayWriting() {
        const threads = Object.keys(answering).map(function(request) { return answering[request] })
        if (threads.length) say({text: "답변 쓰는 중…", kind: "aiWriting", thread: threads[threads.length - 1], writing: true, ttl: 0})
    }
    function act() {
        const m = message
        message = null
        if (m && (m.reminder || m.plain)) return
        if (m && m.thread) threadRequested(m.thread)
        else if (m && m.forYou) forYouRequested()
        else openRequested()
    }
    // Conversations being answered (gloss and other requests are not news).
    property var answering: ({})
    readonly property bool writing: Object.keys(answering).length > 0
    // It kneads while an answer is written, whether or not Owelk is in front.
    onWritingChanged: if (writing) brain.react("aiWriting")
    Connections {
        target: brain
        // Back from a dash while an answer is still written: kneads again, and says so if Owelk is behind.
        function onRunningChanged() {
            if (brain.running || !pet.writing) return
            if (pet.ownerActive) brain.react("aiWriting")
            else pet.sayWriting()
        }
        function onMeowSaid() { if (!pet.message) pet.message = {text: "야옹", plain: true, ttl: 1600} }
        function onHushRequested() { pet.message = null }
        function onHopRequested() { hop.restart() }
        function onShakeRequested() { shake.restart() }
    }
    Connections {
        target: pet.ai
        ignoreUnknownSignals: true
        function onStarted(request, threadId) {
            const next = Object.assign({}, pet.answering); next[request] = threadId; pet.answering = next
            pet.sayWriting()
        }
        function onFinished(request) {
            const thread = pet.answering[request]
            if (thread === undefined) return
            pet.settle(request)
            pet.say({text: "답변이 준비됐어요!", kind: "aiReady", thread: thread, ttl: 8000})
        }
        function onFailed(request, error) {
            const thread = pet.answering[request]
            if (thread === undefined) return
            pet.settle(request)
            pet.say({text: "AI가 답하지 못했어요", kind: "aiFail", thread: thread, ttl: 8000})
        }
    }
    // A finished or failed answer; a "writing" bubble for it goes (another one still written keeps it).
    function settle(request) {
        const next = Object.assign({}, answering); delete next[request]; answering = next
        if (message && message.writing) { message = null; sayWriting() }
        // Done kneading when nothing is written any more (what it says next comes after).
        else if (!writing && brain.pose === "knead") brain.react("sit")
    }
    // Break reminder: minutes of reading (Owelk in front with a document) are counted, and after
    // DesktopPet.breakMinutes the pet suggests a break, also while Owelk is in front. Five minutes away
    // from reading count as a break and start the count again.
    property bool reading: false
    // A minute, in milliseconds (tests shorten it).
    property int minuteLength: 60000
    property int readMinutes: 0
    Timer {
        objectName: "readingClock"
        interval: pet.minuteLength; repeat: true
        running: pet.reading && DesktopPet.breakMinutes > 0
        onTriggered: {
            pet.readMinutes = pet.readMinutes + 1
            if (pet.readMinutes < DesktopPet.breakMinutes) return
            pet.readMinutes = 0
            pet.say({text: DesktopPet.breakMinutes + "분 읽었어요. 잠깐 쉴까요?", kind: "breakTime", reminder: true, ttl: 6000})
        }
    }
    Timer {
        interval: pet.minuteLength * 5
        running: !pet.reading
        onTriggered: { pet.readMinutes = 0; if (pet.message && pet.message.reminder) pet.message = null }
    }
    // The bubble goes after its time.
    Timer {
        objectName: "bubbleClock"
        interval: pet.message && pet.message.ttl ? pet.message.ttl : 1
        running: pet.message !== null && !!pet.message.ttl
        onTriggered: pet.message = null
    }
    // New papers in For You: said when there are more than before (counted when the pet starts, not
    // bound: the count would follow the list before the handler below compares).
    property int knownPapers: 0
    onForYouChanged: knownPapers = forYou && forYou.items ? forYou.items.length : 0
    Connections {
        target: pet.forYou
        ignoreUnknownSignals: true
        function onChanged() {
            const count = pet.forYou.items.length
            if (count > pet.knownPapers) pet.say({text: "For You에 새 논문 " + (count - pet.knownPapers) + "편", kind: "forYou", forYou: true, ttl: 8000})
            pet.knownPapers = count
        }
    }

    // ---- the window ----
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.NoDropShadowWindowHint | Qt.WindowDoesNotAcceptFocus
    // Its own window, not one that follows Owelk's (minimised, on another desktop).
    transientParent: null
    color: "transparent"
    title: DesktopPet.name
    // The app's colors (a window of its own does not take the main window's).
    palette.window: Theme.sidebar
    palette.windowText: Theme.text
    palette.highlight: Theme.accent
    palette.highlightedText: Theme.onAccent
    palette.button: Theme.control
    palette.buttonText: Theme.text
    palette.text: Theme.text
    palette.base: Theme.content
    palette.mid: Theme.border
    palette.toolTipBase: Theme.raised
    palette.toolTipText: Theme.text

    // The cat is DesktopPet.height tall; the window has room beside it for the tower, above it for a hop
    // and a jump, and as much above the floor as the tower is high.
    readonly property int catH: DesktopPet.height
    readonly property int catW: Math.round(catH * 220 / 180)
    readonly property int towerRoom: Math.round(catW * .9)
    readonly property int headroom: Math.round(catH * .4)
    // How far the cat is from the window's left edge (the tower may be on its left).
    readonly property int catOffset: brain.towerSide < 0 ? towerRoom : 0
    readonly property real feetY: headroom + brain.towerHeight + catH * 172 / 180
    width: catW + towerRoom
    height: headroom + brain.towerHeight + catH
    property bool ready: false
    // Held (dragged by the user): the pet keeps still there, and the line it walks is where it was put.
    property bool dragging: false
    visible: ready && !brain.away

    // Follows the cat's place; its height (the line it walks along) is where the user left the window.
    function follow() {
        if (dragging) return
        x = Math.round(brain.catX - catOffset)
    }
    Connections {
        target: brain
        function onCatXChanged() { pet.follow(); rememberLater.restart() }
        function onPlaced() { pet.follow() }
    }
    onCatOffsetChanged: follow()
    property int lastHeight: 0
    onHeightChanged: {
        // A new size keeps the feet where they were.
        if (ready && lastHeight > 0) y += lastHeight - height
        lastHeight = height
        fitLater.restart()
    }
    onWidthChanged: { follow(); fitLater.restart() }
    Component.onCompleted: {
        DesktopPet.prepare(pet)
        lastHeight = height
        const at = DesktopPet.place(width, height)
        brain.catX = at.x; brain.floorX = at.x
        y = at.y
        ready = true
        follow()
        DesktopPet.floatEverywhere(pet)
        brain.begin(DesktopPet.first)
        fitLater.restart()
    }
    onVisibleChanged: if (visible) { DesktopPet.floatEverywhere(pet); fitLater.restart() }
    // Where it was left, once it stops moving; not while it is out of the screen.
    Timer {
        id: rememberLater
        interval: 500
        onTriggered: if (!brain.running && !brain.away && !pet.dragging) DesktopPet.remember(Math.round(brain.catX), pet.y)
    }
    onYChanged: rememberLater.restart()

    // Held, or the screen locked or Owelk hidden: nothing moves.
    function sync() {
        if (dragging || DesktopPet.dormant) brain.halt()
        else brain.resume()
    }
    Connections { target: DesktopPet; function onDormantChanged() { pet.sync() } }
    function dropped() {
        dragging = false
        brain.catX = x + catOffset
        // Asleep up on the tower: the tower goes along, beside the cat's floor spot.
        brain.floorX = brain.onTower ? brain.catX - brain.towerSide * catW * .95 : brain.catX
        DesktopPet.remember(Math.round(brain.catX), y)
        sync()
    }
    Timer {
        // The system moves the window while the button is down; this notices the button coming up.
        interval: 150; repeat: true
        running: pet.dragging
        onTriggered: if (!DesktopPet.leftButtonDown()) pet.dropped()
    }

    PetBehavior {
        id: brain
        objectName: "petBrain"
        screenLeft: pet.screen ? pet.screen.virtualX : 0
        screenWidth: pet.screen && pet.screen.width > 0 ? pet.screen.width : 1440
        catW: pet.catW; catH: pet.catH
        pace: DesktopPet.pace
        windowWidth: pet.width
        towerRoom: pet.towerRoom
    }

    // Clicks on the transparent parts go to whatever is behind the pet; worked out again when what is
    // drawn changes (pose, direction, tower, a jump over).
    function fitClicks() {
        if (!visible || !content.visible) return
        content.grabToImage(function(result) {
            DesktopPet.letClicksThrough(pet, result.image, Qt.size(pet.width, pet.height), 0)
        }, Qt.size(Math.max(1, Math.round(width / 2)), Math.max(1, Math.round(height / 2))))
    }
    Timer { id: fitLater; interval: 120; onTriggered: pet.fitClicks() }
    Connections {
        target: brain
        function onPoseChanged() { fitLater.restart() }
        function onFacingChanged() { fitLater.restart() }
        function onTowerShownChanged() { fitLater.restart() }
        function onLiftChanged() { fitLater.restart() }
        function onCrouchChanged() { fitLater.restart() }
        function onMeowChanged() { fitLater.restart() }
    }
    Connections { target: Theme; function onChanged() { fitLater.restart() } }

    Item {
        id: content
        objectName: "petContent"
        anchors.fill: parent
        Accessible.role: Accessible.Graphic
        Accessible.name: DesktopPet.englishName + ", a tuxedo cat"
        Accessible.description: brain.status

        PetTower {
            id: tower
            objectName: "petTower"
            // Beside the cat's floor spot, on the side it leaps from, and under it once it is up there (the
            // window goes along with the cat); its top is where the cat stands up there.
            width: Math.round(pet.catW * .8); height: brain.towerHeight + 4
            x: pet.catOffset + pet.catW / 2 + brain.towerSide * pet.catW * .95 - (brain.catX - brain.floorX) - width / 2
            y: pet.feetY - brain.towerHeight
            opacity: brain.towerShown ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 250 } }
            onOpacityChanged: fitLater.restart()
        }
        // A little larger while something is dragged over it.
        Item {
            id: bob
            x: pet.catOffset + bobX
            y: pet.headroom + brain.towerHeight - brain.lift + bobY
            width: pet.catW; height: pet.catH
            property real bobX: 0
            property real bobY: 0
            property real bobStretch: 1
            scale: drop.containsDrag ? 1.06 : 1
            transformOrigin: Item.Bottom
            Behavior on scale { NumberAnimation { duration: 120 } }
            Item {
                id: art
                anchors.fill: parent
                transform: Scale { origin.x: art.width / 2; origin.y: art.height; yScale: bob.bobStretch }
                // The dark theme's light rim, so black fur shows on a dark desktop.
                layer.enabled: Theme.dark
                layer.effect: MultiEffect {
                    shadowEnabled: true; shadowColor: "#FFFFFF"; shadowOpacity: .55
                    shadowBlur: .12; shadowHorizontalOffset: 0; shadowVerticalOffset: 0
                }
                PetCat {
                    id: cat
                    objectName: "petCat"
                    scale: pet.catW / 220
                    transformOrigin: Item.TopLeft
                    pose: brain.pose
                    facingLeft: brain.facing < 0
                    crouch: brain.crouch; leap: brain.leap; wipe: brain.wipe; meow: brain.meow; perk: brain.perk
                    alive: !DesktopPet.dormant && pet.visible
                }
            }
        }
    }
    DropArea {
        id: drop
        anchors.fill: parent
        onDropped: function(event) { if (pet.received(event.urls, event.hasText ? event.text : "")) event.acceptProposedAction() }
    }
    // A hop when it has something to say, a shake when it is startled.
    SequentialAnimation {
        id: hop
        ParallelAnimation {
            NumberAnimation { target: bob; property: "bobY"; to: -pet.catH * .34; duration: 190; easing.type: Easing.OutCubic }
            NumberAnimation { target: bob; property: "bobStretch"; to: 1.04; duration: 190 }
        }
        ParallelAnimation {
            NumberAnimation { target: bob; property: "bobY"; to: 0; duration: 190; easing.type: Easing.InQuad }
            NumberAnimation { target: bob; property: "bobStretch"; to: .94; duration: 190 }
        }
        NumberAnimation { target: bob; property: "bobStretch"; to: 1; duration: 170 }
        ScriptAction { script: fitLater.restart() }
    }
    SequentialAnimation {
        id: shake
        ParallelAnimation {
            NumberAnimation { target: bob; property: "bobX"; to: -pet.catW * .04; duration: 100 }
            NumberAnimation { target: bob; property: "bobY"; to: -pet.catH * .10; duration: 100 }
        }
        ParallelAnimation {
            NumberAnimation { target: bob; property: "bobX"; to: pet.catW * .04; duration: 100 }
            NumberAnimation { target: bob; property: "bobY"; to: -pet.catH * .12; duration: 100 }
        }
        ParallelAnimation {
            NumberAnimation { target: bob; property: "bobX"; to: -pet.catW * .03; duration: 100 }
            NumberAnimation { target: bob; property: "bobY"; to: -pet.catH * .04; duration: 100 }
        }
        ParallelAnimation {
            NumberAnimation { target: bob; property: "bobX"; to: pet.catW * .02; duration: 100 }
            NumberAnimation { target: bob; property: "bobY"; to: 0; duration: 100 }
        }
        NumberAnimation { target: bob; property: "bobX"; to: 0; duration: 100 }
        ScriptAction { script: fitLater.restart() }
    }
    DragHandler {
        target: null
        onActiveChanged: if (active) { pet.dragging = true; brain.halt(); pet.startSystemMove() }
    }
    TapHandler { objectName: "petTap"; onTapped: pet.act() }
    TapHandler { acceptedButtons: Qt.RightButton; onTapped: menu.popup() }
    Menu {
        id: menu
        objectName: "petMenu"
        // Its own window: the pet's is too small to hold it. That window takes the system's colors (white
        // text in dark mode), not the pet window's, so the menu has the app's here.
        popupType: Popup.Window
        palette.windowText: Theme.text
        palette.text: Theme.text
        palette.buttonText: Theme.text
        palette.highlight: Theme.accent
        palette.highlightedText: Theme.onAccent
        MenuItem { text: "Open Owelk"; onTriggered: pet.openRequested() }
        MenuItem { objectName: "hidePet"; text: "Hide " + DesktopPet.englishName; onTriggered: DesktopPet.enabled = false }
    }

    // The bubble: its own small window above the cat (below it near the top of the screen), so the pet's
    // window stays the size of the cat. A click does what it says; the right button dismisses it.
    Window {
        id: bubble
        objectName: "petBubble"
        flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.NoDropShadowWindowHint | Qt.WindowDoesNotAcceptFocus
        color: "transparent"
        title: DesktopPet.name
        visible: pet.message !== null && pet.visible && !brain.running
        width: card.width + 4; height: card.height + 4
        // The top of the cat's head in the window.
        readonly property real headTop: pet.headroom + brain.towerHeight - brain.lift + pet.catH * .14
        readonly property bool below: pet.y + headTop - height - 4 < (pet.screen ? pet.screen.virtualY : 0)
        readonly property real centerX: pet.x + pet.catOffset + pet.catW / 2
        x: Math.round(Math.min(Math.max(centerX - width / 2, (pet.screen ? pet.screen.virtualX : 0) + 4), (pet.screen ? pet.screen.virtualX + pet.screen.width : 4000) - width - 4))
        y: below ? pet.y + pet.height + 4 : pet.y + headTop - height + 4
        Component.onCompleted: DesktopPet.prepare(bubble)
        onVisibleChanged: if (visible) DesktopPet.floatEverywhere(bubble)
        Rectangle {
            id: card
            x: 2; y: 2
            width: Math.min(260, words.implicitWidth + 24); height: words.implicitHeight + 16
            radius: Theme.radiusLarge
            color: Theme.raised
            border.color: Theme.border
            Label {
                id: words
                objectName: "petBubbleText"
                x: 12; y: 8; width: parent.width - 24
                text: pet.message ? pet.message.text : ""
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                color: Theme.text
            }
        }
        TapHandler { onTapped: pet.act() }
        TapHandler { acceptedButtons: Qt.RightButton; onTapped: pet.message = null }
    }
}
