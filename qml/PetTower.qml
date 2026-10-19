import QtQuick
import Owelk.Ui
import "PetPath.js" as P

// The cat tower, as in docs/pet/tuxedo-cat-pet.html (grey cushion, board, sisal post, base) with one, two or
// three tiers (the lower ones wider), or a hammock between two posts. (Its colors are the page's, light or
// dark.) Drawn as paths, like the cat. width and height are the whole of it; sag is how far the middle of a
// hammock hangs below its posts.
Item {
    id: tower
    property string kind: "one"
    property real sag: 0
    readonly property int levels: kind === "two" ? 2 : kind === "three" ? 3 : 1
    readonly property bool hammock: kind === "hammock"
    readonly property color cushion: Theme.dark ? "#7C8697" : "#8D97A8"
    readonly property color cushionEdge: Theme.dark ? "#66707F" : "#76808F"
    readonly property color wood: Theme.dark ? "#A88F68" : "#C9AF85"
    readonly property color sisal: Theme.dark ? "#B9A784" : "#D6C49D"
    readonly property color sisalLine: Theme.dark ? "#A08E6C" : "#C1AB80"
    // Tiers: the top one is as wide as one tier alone, each one down 20 % wider; a tier below is half a cat
    // taller than the one above (62 : 50 of the unit the height is made of).
    readonly property real unit: height / (.62 + .5 * (levels - 1))
    readonly property real topWidth: width / (1 + .2 * (levels - 1))
    readonly property real step: topWidth * .2
    readonly property real tierHeight: unit * .5
    readonly property real cushionHeight: Math.max(10, Math.round(topWidth * .19))
    readonly property real postWidth: Math.round(topWidth * .26)
    function rope(x, y, w, h) {
        let d = ""
        for (let i = 0; i < Math.max(0, Math.floor((h - 2) / 7)); ++i) d += P.rect(x, y + i * 7 + 5, w, 2, 0) + " "
        return d.length ? d : "M0,0"
    }
    // One path for all the tiers' cushions, boards and posts (each in its color).
    function tiers(part) {
        let d = ""
        for (let i = 0; i < levels; ++i) {
            const w = topWidth + i * step, x = (width - w) / 2, y = i * tierHeight
            const postTop = y + cushionHeight + 4
            const postBottom = i < levels - 1 ? (i + 1) * tierHeight : height - 5
            const px = (width - postWidth) / 2
            if (part === "edge") d += P.rect(x, y, w, cushionHeight, 8) + " "
            else if (part === "cushion") d += P.rect(x, y, w, cushionHeight - 4, 8) + " "
            else if (part === "board") d += P.rect(x + w * .04, y + cushionHeight - 2, w * .92, 8, 3) + " "
            else if (part === "post") d += P.rect(px, postTop, postWidth, Math.max(0, postBottom - postTop), 3) + " "
            else if (part === "rope") d += rope(px, postTop, postWidth, Math.max(0, postBottom - postTop)) + " "
        }
        return d
    }
    // The hammock: two posts and a band of cloth that hangs between them (sag below the middle of its top edge).
    readonly property real postX: width * .06
    readonly property real clothDrop: 2 + sag / .75
    function cloth() {
        const l = postX + 4, r = width - postX - 4
        const c = (r - l) * .22
        return "M" + l + ",2 C" + (l + c) + "," + clothDrop + " " + (r - c) + "," + clothDrop + " " + r + ",2 L" + r + ",10 C"
            + (r - c) + "," + (clothDrop + 8) + " " + (l + c) + "," + (clothDrop + 8) + " " + l + ",10 Z"
    }
    PetShape {
        PetFill { d: tower.hammock ? "M0,0" : tower.tiers("post"); color: tower.sisal }
        PetFill { d: tower.hammock ? "M0,0" : tower.tiers("rope"); color: tower.sisalLine }
        PetFill { d: tower.hammock ? "M0,0" : tower.tiers("board"); color: tower.wood }
        PetFill { d: tower.hammock ? "M0,0" : tower.tiers("edge"); color: tower.cushionEdge }
        PetFill { d: tower.hammock ? "M0,0" : tower.tiers("cushion"); color: tower.cushion }
        PetFill { d: tower.hammock ? "M0,0" : P.rect(-tower.width * .04, tower.height - 6, tower.width * 1.08, 6, 3); color: tower.wood }
        // the hammock
        PetFill { d: tower.hammock ? P.rect(tower.postX, 0, tower.postWidth * .5 + 4, tower.height, 3) : "M0,0"; color: tower.sisal }
        PetFill { d: tower.hammock ? P.rect(tower.width - tower.postX - tower.postWidth * .5 - 4, 0, tower.postWidth * .5 + 4, tower.height, 3) : "M0,0"; color: tower.sisal }
        PetFill { d: tower.hammock ? P.rect(tower.postX - 6, tower.height - 6, tower.postWidth * .5 + 16, 6, 3) : "M0,0"; color: tower.wood }
        PetFill { d: tower.hammock ? P.rect(tower.width - tower.postX - tower.postWidth * .5 - 10, tower.height - 6, tower.postWidth * .5 + 16, 6, 3) : "M0,0"; color: tower.wood }
        PetFill { d: tower.hammock ? tower.cloth() : "M0,0"; color: tower.cushion; outline: 2 }
    }
}
