import QtQuick

// What the pet does, from docs/pet/tuxedo-cat-pet.html (next(), the B table, zoomies()), at the speed of real
// use: a sit lasts half a minute, a nap five to twenty minutes, a dash across the screen about once in
// forty minutes. It only decides poses and places; PetWindow draws them and moves its window.
//
// Places are in screen points. catX is the cat's left edge; lift how far its feet are above the walking line
// (the tower's top, or the arc of a jump).
Item {
    id: brain
    visible: false

    // The screen the pet is on, and the size of the pet window.
    property real screenLeft: 0
    property real screenWidth: 1440
    property real catW: 196
    property real catH: 160
    // The window's width and how far the cat is from its left edge (the tower is beside the cat, on either side).
    property real windowWidth: catW * 1.9
    property real towerRoom: catW * .9
    // 1 is real time; tests use more to see it all quickly.
    property real pace: 1

    // The state.
    property real catX: 0
    property real lift: 0
    property int facing: 1
    property string pose: "sit"
    property string status: ""
    property bool crouch: false
    property bool leap: false
    property bool wipe: false
    property bool meow: false
    property bool perk: false
    property bool onTower: false
    property bool towerShown: false
    property int towerSide: 1
    // Where the cat stood before it went up the tower, and the tower's height.
    property real floorX: 0
    readonly property real towerHeight: Math.round(catH * .62)
    // Out of the screen after a dash (the window is hidden); the side it left by (1: right, -1: left).
    property bool away: false
    property int exitSide: 1
    // From the crouch before a dash until the cat is back: no bubbles, notices are dropped.
    property bool running: false
    // Stopped by a drag, a locked screen or a hidden Owelk.
    property bool halted: false
    // Goes on with a new behaviour when one ends.
    property bool autoRun: true
    // The behaviour in progress, and when it began (tests read these).
    property string current: ""

    // What the window shows besides the cat: bubbles are the window's; these ask for them.
    signal hushRequested()
    signal meowSaid()
    signal hopRequested()
    signal shakeRequested()
    // The cat is moving or has moved; the window follows.
    signal placed()

    readonly property real walkSpeed: catW * .8 * pace
    readonly property real minX: screenLeft + screenWidth * .015
    readonly property real maxX: screenLeft + screenWidth - catW - screenWidth * .015
    readonly property real catXOnTower: floorX + towerSide * catW * .95
    function ms(n) { return n / pace }
    function rand(a, b) { return a + Math.random() * (b - a) }
    function clampX(v) { return Math.min(Math.max(v, minX), maxX) }

    // The pose (and what the cat is doing, for the status line); the extra poses switched off.
    function setPose(name, text) {
        pose = name
        crouch = false; leap = false; wipe = false; meow = false; perk = false
        status = text || ""
    }

    // ---- the sequencer: a behaviour is a list of steps run one after another ----
    property var steps: []
    property int index: 0
    // Counts the behaviours started and stopped: a step that starts another one (a signal it sends makes the
    // window react) ends the old one's run of steps.
    property int generation: 0
    function stop() {
        waitTimer.stop(); moveAnimation.stop(); jumpAnimation.stop(); dashAccel.stop(); dashRun.stop()
        steps = []; index = 0
        ++generation
    }
    function play(list) {
        stop()
        steps = list; index = 0
        advance()
    }
    function advance() {
        const run = generation
        while (index < steps.length) {
            const step = steps[index++]
            if (step.call) {
                step.call()
                if (run !== generation) return
                continue
            }
            if (step.wait !== undefined) { waitTimer.interval = Math.max(1, ms(step.wait)); waitTimer.restart(); return }
            // Places may be given as functions, worked out when the step starts.
            if (step.walk !== undefined) { walkTo(value(step.walk), step.speed || walkSpeed); return }
            if (step.jump) { jumpTo(value(step.jump.x), value(step.jump.lift)); return }
            if (step.dash !== undefined) { dashTo(value(step.dash)); return }
        }
        finished()
    }
    function value(v) { return typeof v === "function" ? v() : v }
    function finished() {
        current = ""
        if (autoRun && !halted) begin(next())
    }
    Timer { id: waitTimer; onTriggered: brain.advance() }

    NumberAnimation { id: moveAnimation; target: brain; property: "catX"; easing.type: Easing.Linear; onFinished: brain.advance() }
    function walkTo(target, speed) {
        const to = Math.min(Math.max(target, minX - catW * .2), maxX + catW * .2)
        facing = to >= catX ? 1 : -1
        moveAnimation.to = to
        moveAnimation.duration = Math.max(1, Math.abs(to - catX) / speed * 1000)
        moveAnimation.restart()
    }

    // A jump up to the tower or down to the floor: an arc, a little higher than both ends.
    property real jumpFromX: 0
    property real jumpToX: 0
    property real jumpFromLift: 0
    property real jumpToLift: 0
    property real jumpProgress: 0
    NumberAnimation { id: jumpAnimation; target: brain; property: "jumpProgress"; from: 0; to: 1; onFinished: brain.advance() }
    onJumpProgressChanged: {
        if (!jumpAnimation.running) return
        const k = jumpProgress
        catX = jumpFromX + (jumpToX - jumpFromX) * k
        const peak = Math.max(jumpFromLift, jumpToLift) + catH * .35
        const control = 2 * peak - (jumpFromLift + jumpToLift) / 2
        lift = (1 - k) * (1 - k) * jumpFromLift + 2 * (1 - k) * k * control + k * k * jumpToLift
    }
    function jumpTo(toX, toLift) {
        facing = toX >= catX ? 1 : -1
        jumpFromX = catX; jumpToX = toX; jumpFromLift = lift; jumpToLift = toLift
        // The jump is a pose of its own: legs stretched out.
        setPose("run", toLift > 0 ? "jumps up to the tower" : "jumps down")
        leap = true
        jumpAnimation.duration = Math.max(1, ms(620))
        jumpAnimation.restart()
    }

    // The dash: speeds up for 0.16 s, then runs on at a constant speed to the target.
    property real dashSpeed: 1
    NumberAnimation { id: dashAccel; target: brain; property: "catX"; easing.type: Easing.InQuad; onFinished: dashRun.restart() }
    NumberAnimation { id: dashRun; target: brain; property: "catX"; easing.type: Easing.Linear; onFinished: brain.advance() }
    function dashTo(target) {
        const dir = target >= catX ? 1 : -1
        facing = dir
        const speed = screenWidth / .7 * pace
        const accel = Math.min(Math.abs(target - catX), speed * .08)
        dashAccel.to = catX + dir * accel
        dashAccel.duration = Math.max(1, accel / speed * 2000)
        dashRun.to = target
        dashRun.duration = Math.max(1, (Math.abs(target - catX) - accel) / speed * 1000)
        dashAccel.restart()
    }

    // ---- behaviours ----
    function toFloorSteps() {
        if (!onTower) return []
        return [
            {call: function() { onTower = false }},
            {jump: {x: floorX, lift: 0}},
            {call: function() { towerShown = false; setPose("sit") }},
            {wait: 250}
        ]
    }
    function behaviour(name) {
        const edge = screenLeft + screenWidth
        switch (name) {
        case "sit":
            return [{call: function() { setPose("sit", "sitting, its tail now and then") }}, {wait: rand(20000, 60000)}]
        case "groom":
            return [
                {call: function() { setPose("groom", "licking its paw") }}, {wait: 4000},
                {call: function() { wipe = true; status = "wiping its face" }}, {wait: 3000},
                {call: function() { wipe = false; status = "licking its paw" }}, {wait: 3000},
                {call: function() { setPose("sit") }}, {wait: 1200}
            ]
        case "wander": {
            return toFloorSteps().concat([
                {call: function() { setPose("walk", "strolling") }},
                {walk: function() {
                    const to = rand(minX, maxX)
                    if (Math.abs(to - catX) >= catW) return to
                    return catX > screenLeft + screenWidth / 2 ? minX + screenWidth * .1 : screenLeft + screenWidth * .5
                }},
                {call: function() { setPose("sit") }}, {wait: 1500}
            ])
        }
        case "zoomies": return zoomies()
        case "nap": return nap()
        case "belly":
            return toFloorSteps().concat([
                {call: function() { setPose("belly", "rolling on its back") }}, {wait: rand(6000, 10000)},
                {call: function() { setPose("sit") }}, {wait: 800}
            ])
        case "stretch":
            return [
                {call: function() { setPose("stretch", "stretching") }}, {wait: 1300},
                {call: function() { meow = true; status = "yawning" }}, {wait: 900},
                {call: function() { setPose("sit", "meowed"); meow = true; meowSaid() }}, {wait: 1100},
                {call: function() { meow = false }}, {wait: 900}
            ]
        // Owelk: an AI answer is written (until it is done, ten minutes at most), ready, failed, new papers, time for a break.
        case "aiWriting":
            return [{call: function() { setPose("knead", "kneading while the AI writes") }}, {wait: 600000}]
        case "aiReady":
            return [
                {call: function() { setPose("sit", "tells the answer is ready"); meow = true; hopRequested() }}, {wait: 700},
                {call: function() { meow = false }}, {wait: 2200}
            ]
        case "aiFail":
            return [
                {call: function() { setPose("arch", "startled: the AI could not answer"); shakeRequested() }}, {wait: 2400},
                {call: function() { setPose("sit") }}, {wait: 800}
            ]
        case "forYou":
            return [{call: function() { setPose("sit", "ears up: new papers"); perk = true; hopRequested() }}, {wait: 2900}]
        case "breakTime":
            return [
                {call: function() { setPose("stretch", "stretches: time for a break") }}, {wait: 1500},
                {call: function() { meow = true }}, {wait: 900},
                {call: function() { setPose("sit") }}, {wait: 2200}
            ]
        }
        return [{wait: 1000}]
    }

    // How a nap goes: lying on its side or with its back turned, one as likely as the other. chance gives a
    // number from 0 to 1 (tests replace it).
    property var chance: Math.random
    function sleepPoseFor(roll) { return roll < .5 ? "sleep" : "sleepBack" }
    // The tower appears beside the cat, and it leaps up and sleeps.
    function nap() {
        const lying = sleepPoseFor(chance())
        const asleep = lying === "sleep" ? "asleep on the tower" : "asleep on the tower, its back turned"
        if (onTower) return [{call: function() { setPose(lying, asleep) }}, {wait: rand(300000, 1200000)}, {call: function() { setPose("sit", "opened its eyes") }}, {wait: 1400}]
        return [
            {call: function() {
                setPose("sit", "a tower appears")
                floorX = catX
                const roomRight = edgeRight() - (catX + catW), roomLeft = catX - screenLeft
                towerSide = roomRight >= towerRoom ? 1 : roomLeft >= towerRoom ? -1 : 1
                towerShown = true
            }},
            {wait: 700},
            {call: function() { onTower = true }},
            {jump: {x: function() { return catXOnTower }, lift: function() { return towerHeight }}},
            {call: function() { setPose("sit") }}, {wait: 600},
            {call: function() { setPose(lying, asleep) }}, {wait: rand(300000, 1200000)},
            {call: function() { setPose("sit", "opened its eyes") }}, {wait: 1400}
        ]
    }
    function edgeRight() { return screenLeft + screenWidth }

    // Low, bottom wiggling; then across the whole screen and out of sight; later in from the other side.
    function zoomies() {
        const edge = screenLeft + screenWidth
        // The window is out of sight when it is fully past the edge.
        const offset = towerSide < 0 ? towerRoom : 0
        return toFloorSteps().concat([
            {call: function() {
                hushRequested()
                running = true
                exitSide = catX + catW / 2 < screenLeft + screenWidth / 2 ? 1 : -1
                facing = exitSide
                setPose("run", "wiggling its bottom"); crouch = true
            }},
            {wait: 850},
            {call: function() { crouch = false; status = "zoomies across the screen" }},
            {dash: function() { return exitSide === 1 ? edge + offset : screenLeft - windowWidth + offset }},
            {call: function() { setPose("sit", "out of sight"); away = true }},
            {wait: rand(30000, 120000)}
        ]).concat(comeBack())
    }
    // In from the far side and strolls to a place on the screen.
    function comeBack() {
        return [
            {call: function() {
                const offset = towerSide < 0 ? towerRoom : 0
                catX = exitSide === 1 ? screenLeft - windowWidth + offset : screenLeft + screenWidth + offset
                lift = 0
                facing = exitSide === 1 ? 1 : -1
                away = false
                setPose("walk", "strolls back in")
                placed()
            }},
            {walk: function() {
                return exitSide === 1 ? rand(screenLeft + screenWidth * .12, screenLeft + screenWidth * .4)
                                      : rand(screenLeft + screenWidth * .5, maxX)
            }},
            {call: function() { setPose("sit"); running = false }}, {wait: 1400}
        ]
    }

    // From HTML next(): what comes after a behaviour.
    function next() {
        if (onTower) {
            const r = Math.random()
            return r < .55 ? "wander" : r < .8 ? "groom" : "sit"
        }
        const table = [["sit", 22], ["groom", 16], ["wander", 22], ["nap", 16], ["belly", 9], ["stretch", 9], ["zoomies", 6]]
        let r = Math.random() * table.reduce(function(sum, row) { return sum + row[1] }, 0)
        for (const row of table) { r -= row[1]; if (r < 0) return row[0] }
        return "sit"
    }

    // Where the cat stands when a new behaviour starts: an interrupted jump or walk leaves it anywhere.
    function settle() {
        running = false
        if (onTower) { catX = catXOnTower; lift = towerHeight }
        else { catX = clampX(catX); lift = 0; towerShown = false }
        placed()
    }
    function begin(name) {
        if (halted) return
        stop()
        settle()
        current = name
        play(behaviour(name))
    }
    // Something happened in Owelk. Nothing while it dashes, or is held, or the screen is locked.
    function react(name) {
        if (running || halted) return false
        begin(name)
        return true
    }
    // Held (dragged), or the screen is locked or Owelk hidden: nothing moves. The notices stay out.
    function halt() {
        if (halted) return
        const wasAway = away
        stop()
        halted = true
        current = ""
        if (!wasAway) { running = false; setPose("sit") }
    }
    // Let go: carries on from where it is (back in from out of sight if it was away).
    function resume() {
        if (!halted) return
        halted = false
        if (away) { current = "zoomies"; play(comeBack()); return }
        settle()
        play([{wait: 1500}])
    }
}
