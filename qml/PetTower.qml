import QtQuick
import Owelk.Ui

// The small cat tower that stands beside the pet while it sleeps: a grey cushion on top, a board, a sisal
// post and a base, as in docs/pet/tuxedo-cat-pet.html. (Its colors are the page's, light or dark.)
Item {
    id: tower
    readonly property color cushion: Theme.dark ? "#7C8697" : "#8D97A8"
    readonly property color cushionEdge: Theme.dark ? "#66707F" : "#76808F"
    readonly property color wood: Theme.dark ? "#A88F68" : "#C9AF85"
    readonly property color sisal: Theme.dark ? "#B9A784" : "#D6C49D"
    readonly property color sisalLine: Theme.dark ? "#A08E6C" : "#C1AB80"
    readonly property real cushionHeight: Math.max(10, Math.round(width * .19))
    Rectangle {
        id: post
        x: (parent.width - width) / 2; y: tower.cushionHeight + 4
        width: Math.round(tower.width * .26); height: tower.height - y - 5
        radius: 3
        color: tower.sisal
        // Rope: bands of 5 and 2 points, as the page's repeating gradient.
        Repeater {
            model: Math.max(0, Math.floor((post.height - 2) / 7))
            Rectangle { y: index * 7 + 5; width: parent.width; height: 2; color: tower.sisalLine }
        }
    }
    Rectangle {
        x: tower.width * .04; y: tower.cushionHeight - 2; width: tower.width * .92; height: 8
        radius: 3; color: tower.wood
    }
    Rectangle { width: tower.width; height: tower.cushionHeight; radius: 8; color: tower.cushionEdge }
    Rectangle { width: tower.width; height: tower.cushionHeight - 4; radius: 8; color: tower.cushion }
    Rectangle {
        x: -tower.width * .04; y: tower.height - 6; width: tower.width * 1.08; height: 6
        radius: 3; color: tower.wood
    }
}
