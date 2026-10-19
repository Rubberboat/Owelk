import QtQuick
import Owelk.Ui
import "PetPath.js" as P

// The small cat tower: a grey cushion on top, a board, a sisal post and a base, as in
// docs/pet/tuxedo-cat-pet.html. (Its colors are the page's, light or dark.) Drawn as paths, like the cat.
Item {
    id: tower
    readonly property color cushion: Theme.dark ? "#7C8697" : "#8D97A8"
    readonly property color cushionEdge: Theme.dark ? "#66707F" : "#76808F"
    readonly property color wood: Theme.dark ? "#A88F68" : "#C9AF85"
    readonly property color sisal: Theme.dark ? "#B9A784" : "#D6C49D"
    readonly property color sisalLine: Theme.dark ? "#A08E6C" : "#C1AB80"
    readonly property real cushionHeight: Math.max(10, Math.round(width * .19))
    // The post, and its rope: bands of 5 and 2 points, as the page's repeating gradient.
    readonly property real postWidth: Math.round(width * .26)
    readonly property real postX: (width - postWidth) / 2
    readonly property real postY: cushionHeight + 4
    readonly property real postHeight: Math.max(0, height - postY - 5)
    readonly property string rope: {
        let d = ""
        for (let i = 0; i < Math.max(0, Math.floor((postHeight - 2) / 7)); ++i)
            d += P.rect(postX, postY + i * 7 + 5, postWidth, 2, 0) + " "
        return d.length ? d : "M0,0"
    }
    PetShape {
        PetFill { d: P.rect(tower.postX, tower.postY, tower.postWidth, tower.postHeight, 3); color: tower.sisal }
        PetFill { d: tower.rope; color: tower.sisalLine }
        PetFill { d: P.rect(tower.width * .04, tower.cushionHeight - 2, tower.width * .92, 8, 3); color: tower.wood }
        PetFill { d: P.rect(0, 0, tower.width, tower.cushionHeight, 8); color: tower.cushionEdge }
        PetFill { d: P.rect(0, 0, tower.width, tower.cushionHeight - 4, 8); color: tower.cushion }
        PetFill { d: P.rect(-tower.width * .04, tower.height - 6, tower.width * 1.08, 6, 3); color: tower.wood }
    }
}
