import QtQuick
import "PetPath.js" as P

// The page's head(): the cat's head at (px, py), scaled and turned. eye: "open", "half", "wide", "closed" or
// "happy"; ears: "up", "back" or "flat"; mouth: "auto" (shut, open while the cat meows) or "open".
Item {
    id: head
    property real px
    property real py
    property real s: 1
    property real r: 0
    property string eye: "open"
    property string ears: "up"
    property string mouth: "auto"
    property bool tongue: false
    // The cat meows; the eyes are blinking.
    property bool meow: false
    property bool blink: false
    // How open the eyes are (1) or shut (.08): a blink closes and opens them, not in one step.
    property real lid: blink ? .08 : 1
    Behavior on lid { NumberAnimation { duration: 80 } }
    // The head turned around its chin, in degrees (grooming), and the ears' size (perked).
    property real tilt: 0
    property real earX: 1
    property real earY: 1
    x: px; y: py; rotation: r; scale: s
    transformOrigin: Item.TopLeft
    readonly property real earAngle: ears === "back" ? 22 : ears === "flat" ? 40 : 0
    readonly property bool openEyes: eye === "open" || eye === "half" || eye === "wide"
    readonly property real eyeRy: eye === "half" ? 4.2 : 7.6
    readonly property real eyeCy: eye === "half" ? -0.2 : -2
    readonly property var pupilSize: eye === "wide" ? [4.8, 5.4] : eye === "half" ? [2, 3.2] : [2.3, 6.2]
    readonly property bool mouthOpen: mouth === "open" || meow

    Item {
        transform: Rotation { origin.y: 17; angle: head.tilt }
        // Ears.
        Item {
            transform: Scale { origin.y: -6; xScale: head.earX; yScale: head.earY }
            Item {
                transform: Rotation { origin.x: -16; origin.y: -14; angle: -head.earAngle }
                PetShape {
                    PetFill { d: "M-28,-6 L-25,-41 L-5,-23 Z"; color: P.fur; outline: 3 }
                    PetFill { d: "M-23,-13 L-22,-32 L-11,-22 Z"; color: Qt.alpha(P.pink, .45) }
                }
            }
            Item {
                transform: Rotation { origin.x: 16; origin.y: -14; angle: head.earAngle }
                PetShape {
                    PetFill { d: "M28,-6 L25,-41 L5,-23 Z"; color: P.fur; outline: 3 }
                    PetFill { d: "M23,-13 L22,-32 L11,-22 Z"; color: Qt.alpha(P.pink, .45) }
                }
            }
        }
        PetShape {
            PetFill { d: P.ellipse(0, 0, 32, 27); color: P.fur }
            PetFill { d: P.ellipse(0, 7, 29, 21); color: P.fur }
            PetFill { d: P.ellipse(0, 9, 13, 8.5); color: Qt.alpha(P.furHi, .9) }
        }
        // Eyes: open ones close for a blink; shut ones are lines.
        Item {
            visible: head.openEyes
            transform: Scale { origin.y: head.eyeCy; yScale: head.lid }
            PetShape {
                PetFill { d: P.ellipse(-12, head.eyeCy, 7, head.eyeRy); color: P.eye }
                PetFill { d: P.ellipse(12, head.eyeCy, 7, head.eyeRy); color: P.eye }
                PetFill { d: P.ellipse(-12, head.eyeCy, head.pupilSize[0], Math.min(head.pupilSize[1], head.eyeRy - .8)); color: P.pupil }
                PetFill { d: P.ellipse(12, head.eyeCy, head.pupilSize[0], Math.min(head.pupilSize[1], head.eyeRy - .8)); color: P.pupil }
                PetFill { d: P.ellipse(-14.2, head.eyeCy - 2.4, 1.5, 1.5); color: P.white }
                PetFill { d: P.ellipse(9.8, head.eyeCy - 2.4, 1.5, 1.5); color: P.white }
            }
        }
        PetShape {
            visible: head.eye === "closed" || head.eye === "happy"
            PetLine { d: head.eye === "closed" ? "M-18,-2 q6,5 12,0" : "M-18,0 q6,-6 12,0"; color: P.closed; width: 1.9 }
            PetLine { d: head.eye === "closed" ? "M6,-2 q6,5 12,0" : "M6,0 q6,-6 12,0"; color: P.closed; width: 1.9 }
        }
        PetShape {
            PetFill { d: P.ellipse(0, 17.6, 7.4, 4.8); color: P.white }
            PetLine { d: "M-5,12.6 q2.5,3 5,0 q2.5,3 5,0"; color: head.mouthOpen ? "transparent" : P.pupil; width: 1.3 }
            PetFill { d: P.ellipse(0, 16.5, 5.4, 6.8); color: head.mouthOpen ? P.pink : "transparent" }
            PetLine { d: "M-5.4,16.5 a5.4,6.8 0 1 0 10.8,0 a5.4,6.8 0 1 0 -10.8,0"; color: head.mouthOpen ? P.pupil : "transparent"; width: 1.3 }
            PetFill { d: P.ellipse(0, 18.2, 3, 3.6); color: head.tongue ? P.pink : "transparent" }
            PetFill { d: "M-3.8,4.6 h7.6 l-3.8,4.4 z"; color: P.nose }
            PetLine { d: "M8,9 L34,4 M8,11.5 L35,12 M8,14 L32,19.5 M-8,9 L-34,4 M-8,11.5 L-35,12 M-8,14 L-32,19.5"; color: Qt.alpha(P.white, .75); width: .75 }
        }
    }
}
