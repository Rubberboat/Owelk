import QtQuick
import QtQuick.Controls
import Owelk.Ui

// The cat tower: a window of its own that stands where the user puts it. Drag it anywhere (the pet that sleeps
// up on it goes along); it keeps its place. The pet window tells where it stands and when it is wanted.
Window {
    id: tower
    objectName: "petTowerWindow"
    // Set by the pet window: the tower's size, and where it stands (the middle of its base and the bottom of it,
    // in screen points).
    property int towerWidth: 157
    property int towerHeight: 99
    property real centerX: 0
    property real baseY: 0
    // Shown: always, or only while the cat is about to sleep on it or does.
    property bool wanted: true
    property bool dragging: false
    property bool canBring: true
    // The user moves it (where to), lets go, or asks for it beside the cat.
    signal dragged(real centerX, real baseY)
    signal dropped()
    signal bringRequested()
    readonly property int pad: Math.max(6, Math.round(towerWidth * .08))

    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.NoDropShadowWindowHint | Qt.WindowDoesNotAcceptFocus
    // Its own window, below the pet's (a child window would be above it).
    transientParent: null
    color: "transparent"
    title: DesktopPet.englishName + "'s tower"
    palette.window: Theme.sidebar
    palette.windowText: Theme.text
    palette.highlight: Theme.accent
    palette.highlightedText: Theme.onAccent
    palette.button: Theme.control
    palette.buttonText: Theme.text
    palette.text: Theme.text
    palette.base: Theme.content
    palette.mid: Theme.border
    width: towerWidth + 2 * pad
    height: towerHeight + 2 * pad
    visible: wanted || content.opacity > 0

    // In one step, so a drag does not move it sideways and then up.
    function place() {
        DesktopPet.move(tower, Math.round(centerX - width / 2), Math.round(baseY - towerHeight - pad))
    }
    onCenterXChanged: place()
    onBaseYChanged: place()
    onWidthChanged: place()
    onHeightChanged: place()
    onVisibleChanged: if (visible) { place(); DesktopPet.floatEverywhere(tower); fitLater.restart() }
    Component.onCompleted: DesktopPet.prepare(tower)

    // Following the pointer: from where the pointer was when the button went down.
    property point pressCursor
    property point dragCursor
    property point dragStart
    function beginDrag(cursor) {
        dragging = true
        dragCursor = cursor
        dragStart = Qt.point(centerX, baseY)
    }
    function dragTo(cursor) {
        dragged(dragStart.x + cursor.x - dragCursor.x, dragStart.y + cursor.y - dragCursor.y)
    }
    function endDrag() {
        if (!dragging) return
        dragging = false
        dropped()
    }
    // The window follows the pointer every frame, and the button coming up ends it (see the pet window).
    property bool followPointer: true
    FrameAnimation {
        running: tower.dragging && tower.followPointer
        onTriggered: {
            if (!DesktopPet.leftButtonDown()) tower.endDrag()
            else tower.dragTo(DesktopPet.cursor())
        }
    }

    // Clicks beside the tower go to whatever is behind it.
    function fitClicks() {
        if (!visible || !content.visible) return
        content.grabToImage(function(result) {
            DesktopPet.letClicksThrough(tower, result.image, Qt.size(tower.width, tower.height), 0)
        }, Qt.size(Math.max(1, Math.round(width / 2)), Math.max(1, Math.round(height / 2))))
    }
    Timer { id: fitLater; interval: 150; onTriggered: tower.fitClicks() }
    onTowerWidthChanged: fitLater.restart()
    onTowerHeightChanged: fitLater.restart()
    Connections { target: Theme; function onChanged() { fitLater.restart() } }

    Item {
        id: content
        objectName: "petTowerContent"
        anchors.fill: parent
        opacity: tower.wanted ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.InOutQuad } }
        onOpacityChanged: fitLater.restart()
        Accessible.role: Accessible.Graphic
        Accessible.name: DesktopPet.englishName + "'s cat tower"
        PetTower {
            objectName: "petTower"
            x: tower.pad; y: tower.pad
            width: tower.towerWidth; height: tower.towerHeight
        }
    }
    DragHandler {
        target: null
        onActiveChanged: {
            if (active) tower.beginDrag(tower.pressCursor)
            else tower.endDrag()
        }
    }
    TapHandler { onPressedChanged: if (pressed) tower.pressCursor = DesktopPet.cursor() }
    TapHandler { acceptedButtons: Qt.RightButton; onTapped: menu.popup() }
    Menu {
        id: menu
        objectName: "petTowerMenu"
        popupType: Popup.Window
        palette.windowText: Theme.text
        palette.text: Theme.text
        palette.buttonText: Theme.text
        palette.highlight: Theme.accent
        palette.highlightedText: Theme.onAccent
        MenuItem { objectName: "bringTower"; enabled: tower.canBring; text: "Move next to " + DesktopPet.englishName; onTriggered: tower.bringRequested() }
    }
}
