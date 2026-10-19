import QtQuick

// Time in seconds for a pose's looping motion. Every frame while the cat walks or runs; a few times a
// second when only something slow moves (a sleeper's breathing), so the window is hardly redrawn.
Item {
    id: clock
    property bool running: false
    // Milliseconds between steps; 0 steps every frame.
    property int interval: 0
    property real t: 0
    FrameAnimation { running: clock.running && clock.interval === 0; onTriggered: clock.t = elapsedTime }
    Timer {
        interval: Math.max(1, clock.interval); repeat: true
        running: clock.running && clock.interval > 0
        onTriggered: clock.t += clock.interval / 1000
    }
}
