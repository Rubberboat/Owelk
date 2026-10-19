import QtQuick
import Owelk.Ui
import "PetPath.js" as P

// The tuxedo cat, drawn as docs/pet/tuxedo-cat-pet.html draws it (the page's POSES, head(), leg(), leg2())
// in its 220 x 180 units, with the page's @keyframes as motion. Only the pose shown is built, and it moves
// only when it should: a sitting cat is still but for a tail flick and a blink every half minute or so,
// a sleeping one only breathes.
//
// A change of pose is not a cut: the new pose fades in over the old one (blendMs), the legs of a walker
// stride as far as it really moves and ease in and out, and crouching, jumping and running run into each
// other.
Item {
    id: cat
    width: 220; height: 180
    // sit, groom, knead, walk, stand, run, sleep, sleepBack, belly, stretch or arch. (stand is the walker
    // without its stride.)
    property string pose: "sit"
    // How long a change of pose takes to show, in milliseconds.
    property int blendMs: 450
    // Looking left; the paws keep their marks (white glove on the right front paw, toes on the left).
    property bool facingLeft: false
    // Switched on for a while by what the cat does: low with the bottom wiggling (before the dash), a jump,
    // wiping the face, meowing, ears perked.
    property bool crouch: false
    property bool leap: false
    property bool wipe: false
    property bool meow: false
    property bool perk: false
    // How much the walker strides (0 stands, 1 walks) and how far it has walked, in strides: the legs follow
    // the ground, so the feet do not slide.
    property real gait: 0
    property real stridePhase: 0
    // Nothing moves while this is false (the screen is locked, the pet is hidden).
    property bool alive: true
    // Seconds per stride of the gallop.
    property real stride: .27
    // Points of the screen the cat's 220 units take: the fade of a change of pose is drawn at that size.
    property real renderScale: 2
    // Milliseconds between idle blinks and tail flicks (a blink or a flick after somewhere in between).
    property int quietMin: 25000
    property int quietMax: 60000
    property bool blink: false
    property real earX: 1
    property real earY: 1
    // Progress of the tail flick (0..1; 1: at rest).
    property real flick: 1
    readonly property bool eyesOpen: pose === "sit" || pose === "walk" || pose === "stand" || pose === "belly" || pose === "stretch"

    // Crouching and jumping come on and off over a moment, not at once.
    property real crouchBlend: crouch ? 1 : 0
    Behavior on crouchBlend { NumberAnimation { duration: 320; easing.type: Easing.InOutQuad } }
    property real leapBlend: leap ? 1 : 0
    Behavior on leapBlend { NumberAnimation { duration: 320; easing.type: Easing.InOutQuad } }

    // Turning round takes a moment: the cat narrows to a line and widens the other way, and its marks swap
    // sides at the middle of that, when it is edge on.
    property real flip: facingLeft ? -1 : 1
    Behavior on flip { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }
    readonly property bool looksLeft: flip < 0
    // How a cat that looks left is drawn: into one picture the right way round, which is then turned over, because
    // paths drawn under a mirroring transform come out wrong with the curve renderer on the GPU (a tail cut off,
    // jerky shapes). The software renderer has no layers and mirrors the paths.
    readonly property bool mirrorByLayer: GraphicsInfo.api !== GraphicsInfo.Software
    // Where the cat looks (-1..1 across and down): the pupils follow it. It is the pet window that says.
    property real lookX: 0
    property real lookY: 0
    Behavior on lookX { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }
    Behavior on lookY { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }

    // ---- a change of pose: the new one fades in over the old one, which is built until it is gone ----
    // Two slots take turns: the one in front shows the pose, the other the pose it replaces.
    property bool aFront: true
    // Progress of the change: 0 when it starts, 1 when the old pose is gone.
    property real fade: 1
    readonly property string shownPose: aFront ? slotA.name : slotB.name
    readonly property string leavingPose: fade < 1 ? (aFront ? slotB.name : slotA.name) : ""
    // The new one is solid before the old one starts to go, so no gap shows through where both are drawn.
    readonly property real frontOpacity: P.smoothstep(0, .6, fade)
    readonly property real backOpacity: 1 - P.smoothstep(.5, 1, fade)
    // Poses that are drawn alike (a standing cat is the walker without its stride) change without a fade.
    function family(name) { return name === "stand" ? "walk" : name }
    onPoseChanged: {
        const front = aFront ? slotA : slotB, back = aFront ? slotB : slotA
        if (front.name.length && family(front.name) === family(pose)) { front.name = pose; return }
        if (!front.name.length || blendMs <= 0) { front.name = pose; back.name = ""; fade = 1; blendAnimation.stop(); return }
        back.name = pose
        aFront = !aFront
        fade = 0
        blendAnimation.duration = blendMs
        blendAnimation.restart()
    }
    Component.onCompleted: slotA.name = pose
    NumberAnimation {
        id: blendAnimation
        target: cat; property: "fade"; from: 0; to: 1
        onFinished: (cat.aFront ? slotB : slotA).name = ""
    }
    function poseComponent(name) {
        switch (name) {
        case "sit": return sitPose
        case "groom": return groomPose
        case "knead": return kneadPose
        case "walk": case "stand": return walkPose
        case "run": return runPose
        case "sleep": return sleepPose
        case "sleepBack": return sleepBackPose
        case "belly": return bellyPose
        case "stretch": return stretchPose
        case "arch": return archPose
        }
        return null
    }
    component Slot: Item {
        id: slot
        property string name: ""
        width: 220; height: 180
        // While it fades the pose is drawn as one picture and then made see-through, so what overlaps in it
        // does not show through itself.
        layer.enabled: opacity > 0 && opacity < 1
        layer.smooth: true
        // (Wider than the 220 x 180 units: a galloping cat's tail is outside them.)
        layer.sourceRect: Qt.rect(-50, -40, 320, 260)
        layer.textureSize: Qt.size(Math.max(1, Math.round(320 * cat.renderScale)), Math.max(1, Math.round(260 * cat.renderScale)))
        Loader { sourceComponent: slot.name.length ? cat.poseComponent(slot.name) : null }
    }
    // The turn itself (a flat picture turned over is drawn right on every renderer) ...
    Item {
        id: flipBox
        width: 220; height: 180
        transform: Scale { origin.x: 110; xScale: cat.flip }
        // ... of the cat drawn the right way round into a picture while it looks left.
        Item {
            id: mirrorBox
            width: 220; height: 180
            layer.enabled: cat.mirrorByLayer && cat.looksLeft
            layer.smooth: true
            layer.sourceRect: Qt.rect(-50, -40, 320, 260)
            layer.textureSize: Qt.size(Math.max(1, Math.round(320 * cat.renderScale)), Math.max(1, Math.round(260 * cat.renderScale)))
            Slot { id: slotA; z: cat.aFront ? 1 : 0; opacity: cat.aFront ? cat.frontOpacity : cat.backOpacity }
            Slot { id: slotB; z: cat.aFront ? 0 : 1; opacity: cat.aFront ? cat.backOpacity : cat.frontOpacity }
        }
    }

    onPerkChanged: {
        if (perk) perkGrow.restart()
        else { perkGrow.stop(); earX = 1; earY = 1 }
    }
    SequentialAnimation {
        id: perkGrow
        ParallelAnimation {
            NumberAnimation { target: cat; property: "earX"; to: 1.14; duration: 280; easing.type: Easing.OutQuad }
            NumberAnimation { target: cat; property: "earY"; to: 1.2; duration: 280; easing.type: Easing.OutQuad }
        }
        ParallelAnimation {
            NumberAnimation { target: cat; property: "earX"; to: 1.06; duration: 420; easing.type: Easing.OutQuad }
            NumberAnimation { target: cat; property: "earY"; to: 1.1; duration: 420; easing.type: Easing.OutQuad }
        }
    }
    // A blink and a tail flick now and then, not on a short cycle: the window is not redrawn between.
    function rest() { return quietMin + Math.random() * (quietMax - quietMin) }
    Timer {
        id: blinker
        running: cat.alive && cat.eyesOpen && !cat.blink
        interval: cat.rest()
        onTriggered: { cat.blink = true; blinkEnd.start(); interval = cat.rest() }
    }
    Timer { id: blinkEnd; interval: 180; onTriggered: cat.blink = false }
    Timer {
        id: flicker
        running: cat.alive && cat.pose === "sit" && cat.flick >= 1
        interval: cat.rest()
        onTriggered: { flickAnimation.restart(); interval = cat.rest() }
    }
    NumberAnimation { id: flickAnimation; target: cat; property: "flick"; from: 0; to: 1; duration: 2400 }
    onAliveChanged: if (!alive) { flickAnimation.stop(); flick = 1; blink = false }

    // A letter that reads the right way round whichever way the cat looks.
    component Letter: Text {
        text: "z"
        color: Theme.textSecondary
        transform: Scale { origin.x: width / 2; xScale: cat.looksLeft ? -1 : 1 }
    }
    component Pose: Item {
        // Milliseconds between the steps of its clock: 0 every frame, -1 no clock (a pose that does not move by
        // itself has nothing to count, and a running clock would wake the window every frame).
        property int tick: 0
        readonly property alias t: clock.t
        PetClock { id: clock; objectName: "clock"; running: cat.alive && parent && parent.tick >= 0; interval: parent ? Math.max(0, parent.tick) : 0 }
    }
    component Head: PetHead {
        meow: cat.meow
        blink: cat.blink
        earX: cat.earX
        earY: cat.earY
        lookX: cat.lookX
        lookY: cat.lookY
    }
    component Foot: PetLeg {
        facingLeft: cat.looksLeft
    }
    component Foot2: PetLeg2 {
        facingLeft: cat.looksLeft
    }
    // A rounded bar at (px, py) turned: a leg of a lying pose. sock, glove and toes are the white parts as
    // [x, y, width, height, radius]; front ("near" or "far") makes it a front paw with its marks.
    component Bar: Item {
        id: bar
        property real px
        property real py
        property real rot: 0
        property var base: [-7, -4, 14, 40, 7]
        property color fill: P.fur
        property var sock: null
        property var glove: null
        property var toes: null
        property string front: ""
        readonly property bool gloved: (front === "near" && cat.looksLeft) || (front === "far" && !cat.looksLeft)
        readonly property bool toed: (front === "near" && !cat.looksLeft) || (front === "far" && cat.looksLeft)
        function path(r) { return r ? P.rect(r[0], r[1], r[2], r[3], r[4]) : "M0,0" }
        x: px; y: py; rotation: rot
        PetShape {
            PetFill { d: bar.path(bar.base); color: bar.fill }
            PetFill { d: bar.path(bar.sock); color: bar.sock ? P.white : "transparent" }
            PetFill { d: bar.path(bar.glove); color: bar.glove && bar.gloved ? P.white : "transparent" }
            PetFill { d: bar.path(bar.toes); color: bar.toes && bar.toed ? P.white : "transparent" }
        }
    }

    // The sitting body that sit, groom and knead share.
    component SitBody: Item {
        property real tailAngle: 0
        Item {
            transform: Rotation { origin.x: 80; origin.y: 161.33; angle: tailAngle }
            PetShape { PetLine { d: "M80,162 C52,172 28,170 22,152 C18,141 24,133 31,135"; color: P.fur; width: 12 } }
        }
        PetShape {
            PetFill { d: P.ellipse(88, 140, 42, 33); color: P.fur }
            PetFill { d: "M86,152 C84,112 104,84 132,82 C154,82 162,104 160,128 C158,152 146,168 124,171 L96,171 Z"; color: P.fur }
            PetFill { d: "M66,160 C80,150 100,150 112,158 C100,155 80,155 66,160 Z"; color: Qt.alpha(P.white, .92) }
            PetFill { d: P.ellipse(104, 168, 16, 6); color: P.white }
            PetFill { d: "M133,90 C145,94 151,108 148,126 C146,142 140,156 136,167 C131,154 126,138 125,122 C124,106 125,96 133,90 Z"; color: P.white }
        }
    }

    Component {
        id: sitPose
        Pose {
            objectName: "pose-sit"
            tick: -1
            SitBody { tailAngle: P.keyframes([[0, 0], [.4, -5], [.55, 7], [.7, -2], [1, 0]], cat.flick, true) }
            Foot { px: 126; py: 118; len: 54; front: "far"; mark: "front"; fill: P.furLo }
            Foot { px: 146; py: 118; len: 54; w: 15; front: "near"; mark: "front" }
            Head { px: 142; py: 70 }
        }
    }

    Component {
        id: groomPose
        Pose {
            objectName: "pose-groom"
            id: groom
            SitBody {}
            Foot { px: 146; py: 118; len: 54; w: 15; front: "near"; mark: "front" }
            Head {
                px: 140; py: 70; eye: "half"
                tongue: !cat.wipe && groom.t % .46 < .23
                tilt: cat.wipe ? -14 : 9
                Behavior on tilt { NumberAnimation { duration: 450; easing.type: Easing.InOutQuad } }
            }
            // The far paw raised to the mouth: licked, then wiped over the face.
            Item {
                x: 128; y: 124; rotation: 178
                Item {
                    y: cat.wipe ? -3 * P.back(P.cycle(groom.t, .9)) : -P.back(P.cycle(groom.t, .46))
                    transform: Rotation {
                        origin.y: -4
                        angle: cat.wipe ? P.keyframes([[0, -6], [.5, -38], [1, -6]], P.cycle(groom.t, .9), true)
                                        : P.keyframes([[0, 0], [.5, -7], [1, 0]], P.cycle(groom.t, .46), true)
                    }
                    Bar {
                        base: [-7.5, -4, 15, 42, 7.5]; front: "far"
                        glove: [-7.5, 24, 15, 15, 7.5]; toes: [-7.5, 33, 15, 6, 3]
                    }
                }
            }
        }
    }

    Component {
        id: kneadPose
        Pose {
            objectName: "pose-knead"
            id: knead
            SitBody {}
            Foot { px: 126; py: 118; len: 54; front: "far"; mark: "front"; fill: P.furLo; lift: -7 * P.back(P.cycle(knead.t, .52)) }
            Foot { px: 146; py: 118; len: 54; w: 15; front: "near"; mark: "front"; lift: -7 * P.back(P.cycle(knead.t, .52, .5)) }
            Head { px: 142; py: 70; eye: "happy" }
        }
    }

    // Walking and standing: the legs stride as far as the cat has walked, as much as it walks now.
    Component {
        id: walkPose
        Pose {
            objectName: "pose-walk"
            id: walk
            property real amp: cat.pose === "stand" ? 0 : cat.gait
            Behavior on amp { NumberAnimation { duration: 450; easing.type: Easing.InOutQuad } }
            readonly property real phase: P.frac(cat.stridePhase)
            Item {
                transform: Rotation { origin.x: 60.4; origin.y: 106; angle: P.keyframes([[0, -4], [.5, 5], [1, -4]], P.cycle(walk.t, 1.8), true) }
                PetShape { PetLine { d: "M62,106 C52,78 54,50 60,34 C63,26 71,24 73,31"; color: P.fur; width: 11 } }
            }
            // The two pairs of legs (a and b, half a stride apart), in degrees.
            readonly property real legA: walk.amp * P.keyframes([[0, 20], [.5, -20], [1, 20]], walk.phase, true)
            readonly property real legB: walk.amp * P.keyframes([[0, 20], [.5, -20], [1, 20]], P.frac(walk.phase + .5), true)
            Item {
                y: -2 * walk.amp * P.back(walk.phase)
                Foot { px: 78; py: 118; len: 54; mark: "sock"; fill: P.furLo; swing: walk.legB }
                Foot { px: 140; py: 118; len: 54; front: "far"; mark: "front"; fill: P.furLo; swing: walk.legA }
                PetShape {
                    PetFill { d: P.ellipse(108, 114, 56, 26); color: P.fur }
                    PetFill { d: "M148,103 C161,108 164,124 155,136 C149,128 145,115 148,103 Z"; color: P.white }
                    PetFill { d: "M96,138 C108,141 124,141 134,137 C124,136 108,136 96,138 Z"; color: Qt.alpha(P.white, .9) }
                }
                Foot { px: 88; py: 122; len: 50; mark: "sock"; swing: walk.legA }
                Foot { px: 150; py: 122; len: 50; w: 15; front: "near"; mark: "front"; swing: walk.legB }
                Head { px: 166; py: 84; s: .95; r: 4 }
            }
        }
    }

    // Rotary gallop: extended flight, front legs land, gathered flight, hind legs push. Crouching (before
    // the dash) and the jump are poses of the same body; they run into the gallop and out of it.
    Component {
        id: runPose
        Pose {
            objectName: "pose-run"
            id: run
            readonly property real far: P.cycle(run.t, cat.stride)
            readonly property real near: P.cycle(run.t, cat.stride, .11)
            readonly property real cb: cat.crouchBlend
            readonly property real lb: Math.min(cat.leapBlend, 1 - cb)
            readonly property real gw: Math.max(0, 1 - cb - lb)
            readonly property real wig: P.back(P.cycle(run.t, .3))
            // A number for the gallop (g), crouched (c) or in a jump (l), as far as each is on.
            function mix(g, c, l) { return g * gw + c * cb + l * lb }
            readonly property real hipX: mix(P.keyframes(P.hipsX, far), -3 + 6 * wig, -10)
            readonly property real hipY: mix(P.keyframes(P.hipsY, far), -2 + wig, 0)
            Item {
                visible: run.gw > .02
                opacity: .55 * run.gw
                PetShape {
                    PetLine { d: "M34,104 h-30"; color: Qt.alpha(P.closed, run.t % (cat.stride * .66) < cat.stride * .33 ? .55 : .2); width: 2.2 }
                    PetLine { d: "M40,122 h-36"; color: Qt.alpha(P.closed, run.t % (cat.stride * .66) < cat.stride * .33 ? .2 : .55); width: 2.2 }
                    PetLine { d: "M30,140 h-22"; color: Qt.alpha(P.closed, run.t % (cat.stride * .66) < cat.stride * .33 ? .55 : .2); width: 2.2 }
                }
            }
            Item {
                y: run.mix(P.keyframes(P.allY, run.far), 9, 0)
                transform: Rotation { origin.x: 110; origin.y: 125; angle: run.gw * P.keyframes(P.allR, run.far) }
                Item {
                    x: run.hipX; y: run.hipY
                    Item {
                        transform: Rotation {
                            origin.x: 54; origin.y: 113.27
                            angle: run.mix(P.keyframes([[0, -6], [.5, 5], [1, -6]], run.far), -4 + 12 * P.back(P.cycle(run.t, .56)), 0)
                        }
                        PetShape { PetLine { d: "M54,114 C40,112 24,114 6,121"; color: P.fur; width: 10 } }
                    }
                    Foot2 {
                        px: 74; py: 122; u: 26; l: 28; fill: P.furLo; mark: "sock"
                        upper: run.mix(P.keyframes(P.hu, run.far), -42, 55); lower: run.mix(P.keyframes(P.hl, run.far), 62, 10)
                    }
                }
                Foot2 {
                    px: 148; py: 120; u: 24; l: 30; front: "far"; mark: "front"; fill: P.furLo
                    upper: run.mix(P.keyframes(P.fu, run.far), -22, -58); lower: run.mix(P.keyframes(P.fl, run.far), 70, -6)
                }
                Item {
                    x: run.gw * P.keyframes(P.midX, run.far); y: run.gw * P.keyframes(P.midY, run.far)
                    PetShape { PetFill { d: P.ellipse(102, 117, 37, 19.5); color: P.fur } }
                }
                Item {
                    x: run.hipX; y: run.hipY
                    PetShape { PetFill { d: P.ellipse(74, 118, 26, 21); color: P.fur } }
                }
                PetShape {
                    PetFill { d: P.ellipse(132, 116, 38, 20); color: P.fur }
                    PetFill { d: "M158,107 C170,111 172,125 164,133 C159,126 155,116 158,107 Z"; color: P.white }
                }
                Item {
                    x: run.hipX; y: run.hipY
                    Foot2 {
                        px: 80; py: 126; u: 24; l: 26; mark: "sock"
                        upper: run.mix(P.keyframes(P.hu, run.near), -42, 55); lower: run.mix(P.keyframes(P.hl, run.near), 62, 10)
                    }
                }
                Foot2 {
                    px: 154; py: 124; u: 22; l: 28; w: 14; front: "near"; mark: "front"
                    upper: run.mix(P.keyframes(P.fu, run.near), -22, -58); lower: run.mix(P.keyframes(P.fl, run.near), 70, -6)
                }
                Item {
                    y: run.gw * P.keyframes([[0, 1], [.5, 4], [1, 1]], run.far)
                    Head { px: 184; py: 106; s: .86; r: 6; eye: "wide"; ears: "back" }
                }
            }
        }
    }

    Component {
        id: sleepPose
        Pose {
            objectName: "pose-sleep"
            id: sleep
            // Breathing is slow, and little: thirty steps a second look smooth and keep the window quiet.
            tick: 33
            Item {
                transform: Scale { origin.x: 108; origin.y: 172; yScale: P.keyframes([[0, 1], [.5, 1.045], [1, 1]], P.cycle(sleep.t, 3.8), true) }
                PetShape {
                    PetFill { d: P.ellipse(108, 142, 60, 30); color: P.fur }
                    PetLine { d: "M62,128 C84,108 132,106 160,120"; color: Qt.alpha(P.furHi, .8); width: 2.5 }
                }
            }
            PetShape { PetFill { d: P.ellipse(68, 166, 12, 5); color: P.white } }
            Head { px: 154; py: 138; s: .82; r: 14; eye: "closed" }
            PetShape {
                PetLine { d: "M54,150 C62,172 122,177 172,163"; color: P.fur; width: 11 }
                PetFill { d: P.ellipse(164, 164, 13, 6); color: P.white }
            }
            // Sleeping z's, still: nothing else moves.
            Letter { x: 176; y: 88; font.pixelSize: 18 }
            Letter { x: 190; y: 74; font.pixelSize: 15 }
            Letter { x: 200; y: 62; font.pixelSize: 12 }
        }
    }

    // Asleep with its back turned: breathing, and now and then an ear twitch and a flick of the tail tip.
    Component {
        id: sleepBackPose
        Pose {
            id: back
            objectName: "petSleepBack"
            // Breathing is slow, and little: thirty steps a second look smooth and keep the window quiet.
            tick: 33
            // How far the ear twitch and the tail flick are (0..1; 1: at rest). Each moves once in a while,
            // not on the page's cycle (7.5 s and 11 s): that would keep the window redrawn.
            property real earMove: 1
            property real tailMove: 1
            // The ear: still for most of 7.5 s; in the last tenth -16, 5, -9, 0 degrees around its base.
            readonly property real earAngle: P.keyframes([[0, 0], [.25, -16], [.5, 5], [.75, -9], [1, 0]], earMove, true)
            // The tail tip: from 70 to 88 % of 11 s, -18, 6, 0 degrees around its left bottom.
            readonly property real tailAngle: P.keyframes([[0, 0], [.3333, -18], [.6667, 6], [1, 0]], tailMove, true)
            function twitchEar() { earAnimation.restart() }
            function flickTail() { tailAnimation.restart() }
            NumberAnimation { id: earAnimation; target: back; property: "earMove"; from: 0; to: 1; duration: 750 }
            NumberAnimation { id: tailAnimation; target: back; property: "tailMove"; from: 0; to: 1; duration: 1980 }
            Timer {
                running: cat.alive
                interval: cat.rest()
                onTriggered: { back.twitchEar(); interval = cat.rest() }
            }
            Timer {
                running: cat.alive
                interval: cat.rest()
                onTriggered: { back.flickTail(); interval = cat.rest() }
            }
            Item {
                transform: Scale { origin.x: 110; origin.y: 170; yScale: P.keyframes([[0, 1], [.5, 1.045], [1, 1]], P.cycle(back.t, 4.4), true) }
                PetShape {
                    PetFill { d: "M36,170 C28,130 58,98 98,96 C128,95 148,106 154,122 C162,138 178,148 180,170 Z"; color: P.fur }
                    PetLine { d: "M46,158 C46,128 70,108 100,106"; color: Qt.alpha(P.furHi, .9); width: 3 }
                    PetLine { d: "M98,104 C118,104 134,110 144,121"; color: Qt.alpha(P.furHi, .6); width: 2 }
                    PetLine { d: "M62,162 C68,146 82,134 98,130"; color: Qt.alpha(P.furHi, .5); width: 2 }
                }
                Item {
                    transform: Rotation { origin.x: 147.5; origin.y: 106; angle: back.earAngle }
                    PetShape {
                        PetFill { d: "M138,106 L142,79 L157,99 Z"; color: P.fur; outline: 3 }
                        PetLine { d: "M142,83 L140,103"; color: P.furHi; width: 1.6 }
                    }
                }
                PetShape {
                    PetFill { d: "M161,97 L174,77 L183,103 Z"; color: P.fur; outline: 3 }
                    PetLine { d: "M173,81 L176,100"; color: P.furHi; width: 1.6 }
                    PetFill { d: P.ellipse(160, 117, 26, 22); color: P.fur }
                    PetLine { d: "M138,110 C146,98 168,96 181,106"; color: Qt.alpha(P.furHi, .85); width: 2.5 }
                }
            }
            PetShape {
                PetLine { d: "M184,121 L201,116 M185,126 L203,126 M183,131 L200,136"; color: Qt.alpha(P.white, .75); width: .75 }
                PetFill { d: P.ellipse(42, 167, 13, 6); color: P.white }
                PetFill { d: P.ellipse(126, 171, 10, 4.5); color: P.white }
                PetLine { d: "M40,168 C66,176 128,177 164,169"; color: P.fur; width: 11 }
                PetLine { d: "M54,168 C82,172 128,173 160,166"; color: Qt.alpha(P.furHi, .75); width: 2 }
            }
            Item {
                transform: Rotation { origin.x: 162; origin.y: 170; angle: back.tailAngle }
                PetShape { PetLine { d: "M162,170 C173,167 180,161 178,154"; color: P.fur; width: 10 } }
            }
            // Sleeping z's, still: nothing else moves.
            Letter { x: 182; y: 67; font.pixelSize: 18 }
            Letter { x: 196; y: 53; font.pixelSize: 15 }
            Letter { x: 206; y: 41; font.pixelSize: 12 }
        }
    }

    Component {
        id: bellyPose
        Pose {
            objectName: "pose-belly"
            id: belly
            Item {
                transform: Rotation { origin.x: 110; origin.y: 161; angle: P.keyframes([[0, -2.5], [.5, 2.5], [1, -2.5]], P.cycle(belly.t, 2.6), true) }
                PetShape { PetLine { d: "M50,156 C32,166 16,164 8,152"; color: P.fur; width: 10 } }
                Bar { px: 66; py: 150; rot: 78; base: [-7, -4, 14, 48, 7]; sock: [-7, 33, 14, 11, 7] }
                PetShape {
                    PetFill { d: P.ellipse(106, 142, 60, 27); color: P.fur }
                    PetFill { d: "M60,140 C66,117 128,110 156,128 C150,150 96,160 60,140 Z"; color: P.white }
                    PetFill { d: P.ellipse(98, 129, 10, 6); color: P.fur }
                    PetFill { d: P.ellipse(129, 140, 7, 5); color: P.fur }
                    PetFill { d: P.ellipse(75, 139, 6, 4); color: P.fur }
                }
                Bar { px: 80; py: 132; rot: 200; base: [-7, -4, 14, 34, 7]; sock: [-7, 19, 14, 11, 7] }
                Bar { px: 144; py: 126; rot: 196; base: [-7, -4, 14, 30, 7]; front: "near"; glove: [-7, 12, 14, 14, 7]; toes: [-7, 20, 14, 6, 3] }
                Bar { px: 155; py: 133; rot: 168; base: [-7, -4, 14, 26, 7]; front: "far"; glove: [-7, 8, 14, 14, 7]; toes: [-7, 16, 14, 6, 3] }
                Head { px: 172; py: 140; s: .88; r: 100 }
            }
        }
    }

    Component {
        id: stretchPose
        Pose {
            objectName: "pose-stretch"
            tick: -1
            PetShape { PetLine { d: "M62,88 C54,62 58,42 66,30"; color: P.fur; width: 11 } }
            Foot { px: 66; py: 96; len: 76; mark: "sock"; fill: P.furLo }
            PetShape { PetFill { d: "M54,96 C54,74 84,70 104,88 C126,108 156,130 176,142 C184,150 178,162 164,162 C132,160 96,142 72,124 C60,116 54,108 54,96 Z"; color: P.fur } }
            Foot { px: 80; py: 100; len: 72; mark: "sock" }
            Bar { base: [148, 156, 60, 12, 6]; fill: P.furLo; front: "far"; glove: [193, 156, 15, 12, 6]; toes: [202, 156, 6, 12, 3] }
            PetShape { PetFill { d: "M160,140 C171,144 175,152 170,159 C164,155 159,148 160,140 Z"; color: P.white } }
            Bar { base: [142, 160, 60, 12, 6]; front: "near"; glove: [187, 160, 15, 12, 6]; toes: [196, 160, 6, 12, 3] }
            Head { px: 178; py: 130; s: .9; r: -6; eye: "half" }
        }
    }

    Component {
        id: archPose
        Pose {
            objectName: "pose-arch"
            id: arch
            Item {
                transform: Rotation { origin.x: 61.19; origin.y: 114; angle: -2 + 4 * P.back(P.cycle(arch.t, .36)) }
                PetShape { PetLine { d: "M62,114 C56,86 58,60 64,40"; color: P.fur; width: 19 } }
            }
            Foot { px: 74; py: 112; len: 60; mark: "sock"; fill: P.furLo }
            Foot { px: 150; py: 112; len: 60; front: "far"; mark: "front"; fill: P.furLo }
            PetShape {
                PetFill { d: "M54,128 C52,66 162,62 168,124 C160,114 138,104 112,104 C86,104 64,114 54,128 Z"; color: P.fur }
                PetFill { d: "M70,96 l-6,-10 l10,4 l2,-12 l7,10 l5,-12 l5,12 l7,-11 l3,13 l9,-9 l0,13 l10,-6 l-3,12 Z"; color: P.fur }
            }
            Foot { px: 82; py: 116; len: 56; mark: "sock" }
            Foot { px: 158; py: 116; len: 56; w: 15; front: "near"; mark: "front" }
            PetShape { PetFill { d: "M160,108 C170,112 172,124 166,132 C160,126 158,116 160,108 Z"; color: P.white } }
            Head { px: 176; py: 106; s: .9; r: 10; eye: "wide"; ears: "flat"; mouth: "open" }
        }
    }
}
