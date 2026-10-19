import QtQuick
import "PetPath.js" as P

// The page's leg2(): a leg in two parts for running; the upper part turns around the hip, the lower
// around the knee.
Item {
    id: leg
    property real px
    property real py
    property real u
    property real l
    property real w: 13
    property string mark: ""
    property string front: ""
    property bool facingLeft: false
    property color fill: P.fur
    property real upper: 0
    property real lower: 0
    readonly property bool glove: (front === "near" && facingLeft) || (front === "far" && !facingLeft)
    readonly property bool toes: (front === "near" && !facingLeft) || (front === "far" && facingLeft)
    x: px; y: py
    Item {
        rotation: leg.upper
        PetShape { PetFill { d: P.rect(-leg.w / 2, -6, leg.w, leg.u + 6 + leg.w / 2, leg.w / 2); color: leg.fill } }
        Item {
            y: leg.u
            rotation: leg.lower
            PetShape {
                PetFill { d: P.rect(-leg.w / 2 + .5, -leg.w / 2, leg.w - 1, leg.l + leg.w / 2, (leg.w - 1) / 2); color: leg.fill }
                PetFill { d: P.rect(-leg.w / 2 + .5, leg.l - 10, leg.w - 1, 10, (leg.w - 1) / 2); color: leg.mark === "sock" ? P.white : "transparent" }
                PetFill { d: P.rect(-leg.w / 2 + .5, leg.l - 14, leg.w - 1, 14, (leg.w - 1) / 2); color: leg.mark === "front" && leg.glove ? P.white : "transparent" }
                PetFill { d: P.rect(-leg.w / 2 + .5, leg.l - 6, leg.w - 1, 6, 3); color: leg.mark === "front" && leg.toes ? P.white : "transparent" }
            }
        }
    }
}
