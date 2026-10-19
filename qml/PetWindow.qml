import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Owelk.Ui

// The desktop pet, 알맹이 (Allmeng-E), a tuxedo cat in a small window that floats above other apps while Owelk
// runs (Settings › Appearance › Desktop pet). It lives on the line it was left on: sits, grooms, strolls along
// it, sleeps up on a cat tower that stands where the user put it (drag the tower anywhere), rolls on its back,
// stretches, and now and then dashes out of the screen and back. Drag it anywhere (it keeps still while held);
// a click makes it spring up and do something else, a double click brings Owelk forward; the right button has
// its menu. While Owelk is behind other apps it says when an AI answer is ready or failed and when For You has
// new papers, in a bubble above it; it kneads while an answer is written. PDFs dropped on it open in Owelk; text
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
    // A click on the bubble does what it says.
    function act() {
        const m = message
        message = null
        if (!m || m.reminder || m.plain) return
        if (m.thread) threadRequested(m.thread)
        else if (m.forYou) forYouRequested()
        else openRequested()
    }
    // A click on the cat: with a bubble up it does what the bubble says; else the cat springs up and goes on
    // to something else.
    function tapped() {
        if (message) act()
        else brain.poke()
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
        function onSpringRequested() { spring.restart() }
        function onShakeRequested() { shake.restart() }
        function onLanded() { land.restart() }
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

    // The cat is DesktopPet.height tall. The window has room around it for whiskers, a tail and a shake, and
    // above it for a hop or a stretch: nothing the cat does is cut off at the edge.
    readonly property int catH: DesktopPet.height
    readonly property int catW: Math.round(catH * 220 / 180)
    readonly property int marginX: Math.round(catW * .12)
    readonly property int headroom: Math.round(catH * .42)
    // Where the line under its feet is in the window.
    readonly property int feetOffset: headroom + Math.round(catH * 172 / 180)
    width: catW + 2 * marginX
    height: headroom + catH + Math.round(catH * .06)
    property bool ready: false
    // Held (dragged by the user): the pet keeps still there, and the line it walks is where it was put.
    property bool dragging: false
    // Where the cat is in the window beyond whole points (the window moves in whole points, the cat to a
    // fraction of one, so a slow walk is not a stutter).
    property real innerX: 0
    property real innerY: 0
    visible: ready && !brain.away

    // Follows the cat's place.
    function follow() {
        if (dragging) return
        const wx = brain.catX - marginX, wy = brain.feetY - feetOffset
        const ix = Math.floor(wx), iy = Math.floor(wy)
        innerX = wx - ix
        innerY = wy - iy
        DesktopPet.move(pet, ix, iy)
    }
    Connections {
        target: brain
        function onCatXChanged() { if (!brain.batching) { pet.follow(); rememberLater.restart() } }
        function onFeetYChanged() { if (!brain.batching) pet.follow() }
        function onPlaced() { pet.follow(); rememberLater.restart() }
    }
    onWidthChanged: { follow(); fitLater.restart() }
    onHeightChanged: { follow(); fitLater.restart() }
    Component.onCompleted: {
        DesktopPet.prepare(pet)
        const at = DesktopPet.place(width, height)
        brain.catX = at.x + marginX
        brain.lineY = at.y + feetOffset
        brain.feetY = brain.lineY
        // The tower where the user left it; the first time beside the cat.
        const beside = towerBeside()
        const spot = DesktopPet.towerPlace(beside.x, beside.y)
        towerCenterX = spot.x; towerBase = spot.y
        DesktopPet.rememberTower(spot.x, spot.y)
        ready = true
        follow()
        DesktopPet.floatEverywhere(pet)
        brain.begin(DesktopPet.first)
        fitLater.restart()
        Qt.callLater(pet.raise)
    }
    onVisibleChanged: if (visible) { DesktopPet.floatEverywhere(pet); fitLater.restart() }
    // Where it was left, once it stops moving; not while it is out of the screen or up on the tower.
    Timer {
        id: rememberLater
        interval: 500
        onTriggered: if (!brain.running && !brain.away && !pet.dragging && !brain.onTower && brain.feetY === brain.lineY)
            DesktopPet.remember(Math.round(brain.catX - pet.marginX), Math.round(brain.lineY - pet.feetOffset))
    }

    // ---- held by the user: the system moves the window; where there is no such move, it follows the pointer
    // (from where the pointer was when the button went down) ----
    property point pressCursor
    property point dragCursor
    property point dragWindow
    property bool followByHand: false
    function beginDrag(cursor) {
        dragging = true
        dragCursor = cursor
        dragWindow = Qt.point(x, y)
        brain.halt(true)
    }
    function dragTo(cursor) {
        innerX = 0
        innerY = 0
        DesktopPet.move(pet, dragWindow.x + cursor.x - dragCursor.x, dragWindow.y + cursor.y - dragCursor.y)
    }
    // Let go: the line it walks is where it was put (and it is off the tower, if it was up on it).
    function dropped() {
        if (!dragging) return
        // (Held still: the window does not follow the cat while these are set one by one.)
        brain.onTower = false
        brain.lineY = y + feetOffset
        brain.feetY = brain.lineY
        brain.catX = x + marginX
        dragging = false
        follow()
        DesktopPet.remember(Math.round(brain.catX - marginX), Math.round(brain.lineY - feetOffset))
        sync()
    }
    // The button coming up ends it (the system moves the window itself, and a window that lags behind the pointer
    // may ignore the mouse, so the release may not reach it as an event). Tests turn this off.
    property bool followPointer: true
    Timer {
        interval: 100; repeat: true
        running: pet.dragging && pet.followPointer
        onTriggered: if (!DesktopPet.leftButtonDown()) pet.dropped()
    }
    FrameAnimation {
        running: pet.dragging && pet.followPointer && pet.followByHand
        onTriggered: pet.dragTo(DesktopPet.cursor())
    }

    // Held, or the screen locked or Owelk hidden: nothing moves.
    function sync() {
        if (dragging || DesktopPet.dormant) brain.halt(dragging)
        else brain.resume()
    }
    Connections { target: DesktopPet; function onDormantChanged() { pet.sync() } }

    // ---- the tower: where the user put it (the middle of its base, the bottom of it) ----
    property real towerCenterX: 0
    property real towerBase: 0
    function towerBeside() {
        const side = brain.catX + catW * 2.7 < brain.screenLeft + brain.screenWidth ? 1 : -1
        return Qt.point(Math.round(brain.catX + catW / 2 + side * catW * 1.6), Math.round(brain.lineY + 4))
    }
    // The screen a point is on, else the nearest one.
    function screenOf(x, y) {
        let best = null, nearest = Infinity
        for (const screen of Qt.application.screens) {
            const dx = Math.max(screen.virtualX - x, 0, x - (screen.virtualX + screen.width))
            const dy = Math.max(screen.virtualY - y, 0, y - (screen.virtualY + screen.height))
            if (dx * dx + dy * dy < nearest) { best = screen; nearest = dx * dx + dy * dy }
        }
        return best
    }
    function moveTower(centerX, base) {
        // Anywhere on any screen: at least its middle and its top stay on the one it is nearest.
        const screen = screenOf(centerX, base - 1)
        const left = screen ? screen.virtualX : 0, top = screen ? screen.virtualY : 0
        const right = left + (screen ? screen.width : 1440), bottom = top + (screen ? screen.height : 900)
        towerCenterX = Math.min(Math.max(centerX, left + 20), right - 20)
        towerBase = Math.min(Math.max(base, top + brain.towerHeight + 10), bottom + 4)
        // A cat asleep up there stays in front of it, though the tower is the window being moved.
        if (brain.onTower) pet.raise()
    }
    function towerDropped() {
        DesktopPet.rememberTower(Math.round(towerCenterX), Math.round(towerBase))
        pet.raise()
    }
    // The tower back beside the cat (not while the cat sleeps up on it).
    function bringTower() {
        if (brain.onTower) return
        const beside = towerBeside()
        moveTower(beside.x, beside.y)
        towerDropped()
    }

    PetBehavior {
        id: brain
        objectName: "petBrain"
        screenLeft: pet.screen ? pet.screen.virtualX : 0
        screenWidth: pet.screen && pet.screen.width > 0 ? pet.screen.width : 1440
        catW: pet.catW; catH: pet.catH
        pace: DesktopPet.pace
        windowWidth: pet.width
        windowOffset: pet.marginX
        screens: Qt.application.screens.map(function(screen) { return {x: screen.virtualX, y: screen.virtualY, width: screen.width, height: screen.height} })
        towerX: pet.towerCenterX
        towerBaseY: pet.towerBase
    }
    PetTowerWindow {
        id: towerWin
        followPointer: pet.followPointer
        towerWidth: brain.towerWidth; towerHeight: brain.towerHeight
        centerX: pet.towerCenterX; baseY: pet.towerBase
        // Always, or only for a nap (the cat is about to go up or is up there).
        wanted: pet.ready && (DesktopPet.towerMode === "always" || brain.towerNeeded || brain.onTower)
        onDragged: function(centerX, baseY) { pet.moveTower(centerX, baseY) }
        onDropped: pet.towerDropped()
        onBringRequested: pet.bringTower()
        // The cat is above the tower, not behind it.
        onVisibleChanged: if (visible) Qt.callLater(pet.raise)
    }

    // Clicks on the transparent parts go to whatever is behind the pet; worked out again when what is
    // drawn changes (pose, direction, a jump over).
    function fitClicks() {
        if (!visible || !content.visible) return
        content.grabToImage(function(result) {
            DesktopPet.letClicksThrough(pet, result.image, Qt.size(pet.width, pet.height), 0)
        }, Qt.size(Math.max(1, Math.round(width / 2)), Math.max(1, Math.round(height / 2))))
    }
    Timer { id: fitLater; interval: 150; onTriggered: pet.fitClicks() }
    Connections {
        target: brain
        function onPoseChanged() { fitLater.restart() }
        function onFacingChanged() { fitLater.restart() }
        function onFeetYChanged() { fitLater.restart() }
        function onCrouchChanged() { fitLater.restart() }
        function onMeowChanged() { fitLater.restart() }
    }
    Connections { target: Theme; function onChanged() { fitLater.restart() } }
    // The fade between two poses is over: the shape to click on is the new one.
    Connections { target: cat; function onFadeChanged() { if (cat.fade >= 1) fitLater.restart() } }
    // Turning round, and appearing: the shape to click on is worked out when they are over.
    Connections { target: cat; function onFlipChanged() { fitLater.restart() } }

    Item {
        id: content
        objectName: "petContent"
        anchors.fill: parent
        // It appears, not pops up.
        opacity: pet.ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutQuad } }
        onOpacityChanged: fitLater.restart()
        Accessible.role: Accessible.Graphic
        Accessible.name: DesktopPet.englishName + ", a tuxedo cat"
        Accessible.description: brain.status
        // The cat: a little larger while something is dragged over it.
        Item {
            id: bob
            objectName: "petBob"
            x: pet.marginX + pet.innerX + bobX
            y: pet.headroom + pet.innerY + bobY
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
                    renderScale: pet.catW / 220 * (pet.screen ? pet.screen.devicePixelRatio : 1)
                    blendMs: brain.blendMs
                    pose: brain.pose
                    facingLeft: brain.facing < 0
                    crouch: brain.crouch; leap: brain.leap; wipe: brain.wipe; meow: brain.meow; perk: brain.perk
                    gait: brain.walking ? 1 : 0
                    stridePhase: brain.stridePhase
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
    // A hop when it has something to say or is startled up, a shake when it is startled, a squash when it lands.
    SequentialAnimation {
        id: hop
        ParallelAnimation {
            NumberAnimation { target: bob; property: "bobY"; to: -pet.catH * .34; duration: 300; easing.type: Easing.OutQuad }
            NumberAnimation { target: bob; property: "bobStretch"; to: 1.05; duration: 300; easing.type: Easing.OutQuad }
        }
        ParallelAnimation {
            NumberAnimation { target: bob; property: "bobY"; to: 0; duration: 300; easing.type: Easing.InQuad }
            NumberAnimation { target: bob; property: "bobStretch"; to: .93; duration: 300; easing.type: Easing.InQuad }
        }
        NumberAnimation { target: bob; property: "bobStretch"; to: 1; duration: 260; easing.type: Easing.OutQuad }
        ScriptAction { script: fitLater.restart() }
    }
    // Sprung up by a poke: sudden, up in a moment and down a little slower, squashed as it lands.
    SequentialAnimation {
        id: spring
        ParallelAnimation {
            NumberAnimation { target: bob; property: "bobY"; to: -pet.catH * .28; duration: 150; easing.type: Easing.OutCubic }
            NumberAnimation { target: bob; property: "bobStretch"; to: 1.08; duration: 150; easing.type: Easing.OutQuad }
        }
        ParallelAnimation {
            NumberAnimation { target: bob; property: "bobY"; to: 0; duration: 220; easing.type: Easing.InQuad }
            NumberAnimation { target: bob; property: "bobStretch"; to: .9; duration: 220; easing.type: Easing.InQuad }
        }
        NumberAnimation { target: bob; property: "bobStretch"; to: 1; duration: 260; easing.type: Easing.OutBack }
        ScriptAction { script: fitLater.restart() }
    }
    SequentialAnimation {
        id: land
        NumberAnimation { target: bob; property: "bobStretch"; to: .92; duration: 140; easing.type: Easing.OutQuad }
        NumberAnimation { target: bob; property: "bobStretch"; to: 1; duration: 420; easing.type: Easing.OutQuad }
    }
    SequentialAnimation {
        id: shake
        ParallelAnimation {
            NumberAnimation { target: bob; property: "bobX"; to: -pet.catW * .04; duration: 130; easing.type: Easing.InOutQuad }
            NumberAnimation { target: bob; property: "bobY"; to: -pet.catH * .10; duration: 130; easing.type: Easing.InOutQuad }
        }
        ParallelAnimation {
            NumberAnimation { target: bob; property: "bobX"; to: pet.catW * .04; duration: 130; easing.type: Easing.InOutQuad }
            NumberAnimation { target: bob; property: "bobY"; to: -pet.catH * .12; duration: 130; easing.type: Easing.InOutQuad }
        }
        ParallelAnimation {
            NumberAnimation { target: bob; property: "bobX"; to: -pet.catW * .03; duration: 130; easing.type: Easing.InOutQuad }
            NumberAnimation { target: bob; property: "bobY"; to: -pet.catH * .04; duration: 130; easing.type: Easing.InOutQuad }
        }
        ParallelAnimation {
            NumberAnimation { target: bob; property: "bobX"; to: pet.catW * .02; duration: 130; easing.type: Easing.InOutQuad }
            NumberAnimation { target: bob; property: "bobY"; to: 0; duration: 130; easing.type: Easing.InOutQuad }
        }
        NumberAnimation { target: bob; property: "bobX"; to: 0; duration: 130; easing.type: Easing.InOutQuad }
        ScriptAction { script: fitLater.restart() }
    }
    DragHandler {
        target: null
        onActiveChanged: {
            if (active) {
                pet.beginDrag(pet.pressCursor)
                // The system's own move is the smoothest; by hand where there is none.
                pet.followByHand = pet.startSystemMove() === false
            } else pet.dropped()
        }
    }
    TapHandler {
        objectName: "petTap"
        onPressedChanged: if (pressed) pet.pressCursor = DesktopPet.cursor()
        onTapped: pet.tapped()
        onDoubleTapped: pet.openRequested()
    }
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
        MenuItem { objectName: "bringTowerHere"; text: "Move the tower here"; enabled: !brain.onTower; onTriggered: pet.bringTower() }
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
        // Up while there is something to say; it fades in and out.
        readonly property bool wanted: pet.message !== null && pet.visible && !brain.running
        property string said: ""
        visible: wanted || card.opacity > 0
        width: card.width + 4; height: card.height + 4
        // The top of the cat's head in the window.
        readonly property real headTop: pet.headroom + pet.innerY + pet.catH * .14
        readonly property bool below: pet.y + headTop - height - 4 < (pet.screen ? pet.screen.virtualY : 0)
        readonly property real centerX: pet.x + pet.marginX + pet.innerX + pet.catW / 2
        x: Math.round(Math.min(Math.max(centerX - width / 2, (pet.screen ? pet.screen.virtualX : 0) + 4), (pet.screen ? pet.screen.virtualX + pet.screen.width : 4000) - width - 4))
        y: below ? pet.y + pet.height + 4 : pet.y + headTop - height + 4
        Component.onCompleted: DesktopPet.prepare(bubble)
        onVisibleChanged: if (visible) DesktopPet.floatEverywhere(bubble)
        Connections { target: pet; function onMessageChanged() { if (pet.message) bubble.said = pet.message.text } }
        Rectangle {
            id: card
            x: 2; y: 2
            width: Math.min(260, words.implicitWidth + 24); height: words.implicitHeight + 16
            radius: Theme.radiusLarge
            color: Theme.raised
            border.color: Theme.border
            opacity: bubble.wanted ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }
            Label {
                id: words
                objectName: "petBubbleText"
                x: 12; y: 8; width: parent.width - 24
                text: pet.message ? pet.message.text : bubble.said
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
