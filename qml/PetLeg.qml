import QtQuick
import "PetPath.js" as P

// The page's leg(): a leg hanging from (px, py) that swings around its top. mark: "sock" (white foot),
// "front" (a front paw: the white glove on the right one, only the toes on the left one, whichever way
// the cat looks) or "" (none).
Item {
    id: leg
    property real px
    property real py
    property real len
    property real w: 14
    property string mark: ""
    // "near" or "far" for a front paw.
    property string front: ""
    property bool facingLeft: false
    property color fill: P.fur
    property real rot: 0
    // The swing around the top of the leg, in degrees.
    property real swing: 0
    // Lifted, as kneading does, in drawing units.
    property real lift: 0
    readonly property bool glove: (front === "near" && facingLeft) || (front === "far" && !facingLeft)
    readonly property bool toes: (front === "near" && !facingLeft) || (front === "far" && facingLeft)
    x: px; y: py + lift; rotation: rot
    Item {
        transform: Rotation { origin.y: -4; angle: leg.swing }
        PetShape {
            PetFill { d: P.rect(-leg.w / 2, -4, leg.w, leg.len + 4, leg.w / 2); color: leg.fill }
            PetFill { d: P.rect(-leg.w / 2, leg.len - 11, leg.w, 11, leg.w / 2); color: leg.mark === "sock" ? P.white : "transparent" }
            PetFill { d: P.rect(-leg.w / 2, leg.len - 15, leg.w, 15, leg.w / 2); color: leg.mark === "front" && leg.glove ? P.white : "transparent" }
            PetFill { d: P.rect(-leg.w / 2, leg.len - 6, leg.w, 6, 3); color: leg.mark === "front" && leg.toes ? P.white : "transparent" }
        }
    }
}
