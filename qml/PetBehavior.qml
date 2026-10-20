import QtQuick

// What the pet does, from docs/pet/tuxedo-cat-pet.html (next(), the B table, zoomies()), at the speed of a real
// cat: it strolls rather than hurries, a sit lasts half a minute, a nap five to twenty minutes, a dash across the
// screen about once in forty minutes, and nothing is a cut: a pose fades into the next, a walk speeds up and
// slows down, and a lazy cat does it all slower still. It only decides poses and places; PetWindow draws them
// and moves its window.
//
// Places are in screen points: catX is the cat's left edge, feetY the line under its feet now, lineY the line it
// walks along (where the user left it). The tower stands where the user put it (towerX, towerBaseY).
Item {
    id: brain
    visible: false

    // ---- what it needs to know ----
    // The screen the pet is on, the size of the pet window and how far the cat is from its left edge.
    property real screenLeft: 0
    property real screenTop: 0
    // The cat's window may not go above the top of the screen: from its feet to the top of the window.
    property real windowAbove: catH * 1.4
    property real screenWidth: 1440
    property real catW: 196
    property real catH: 160
    property real windowWidth: catW * 1.24
    property real windowOffset: catW * .12
    // Every screen, as [{x, y, width, height}] (the pet's own is the one above).
    property var screens: []
    function onScreen(x, y) {
        return screens.some(function(s) { return x >= s.x && x < s.x + s.width && y >= s.y && y <= s.y + s.height })
    }
    // 1 is real time; tests use more to see it all quickly.
    property real pace: 1
    // A number from 0 to 1 for every roll of the dice (tests replace it).
    property var chance: Math.random

    // ---- where it is and what it does ----
    property real catX: 0
    property real feetY: 0
    property real lineY: 0
    property int facing: 1
    property string pose: "sit"
    property string status: ""
    // How long the change into this pose takes to show.
    property int blendMs: 450
    property bool crouch: false
    property bool leap: false
    property bool wipe: false
    property bool meow: false
    property bool perk: false
    // Walking, and how far it has walked in strides (the legs follow the ground).
    property bool walking: false
    property real stridePhase: 0
    // Out of the screen after a dash (the window is hidden); the side it left by (1: right, -1: left).
    property bool away: false
    property int exitSide: 1
    // From the crouch before a dash until the cat is back: no bubbles, notices are dropped.
    property bool running: false
    // Stopped by a drag, a locked screen or a hidden Owelk.
    property bool halted: false
    // Goes on with a new behaviour when one ends.
    property bool autoRun: true
    // The behaviour in progress (empty between two), the last one begun, and one the next must not be (after a poke).
    property string current: ""
    property string last: ""
    property string avoid: ""

    // ---- the tower ----
    // Where it stands: the middle of its base and the bottom of it. It is where the user put it.
    property real towerX: 0
    property real towerBaseY: 0
    // What it is: "one", "two" or "three" tiers (each a half cat taller; the lower ones wider) or a "hammock".
    property string towerKind: "one"
    readonly property int towerLevels: towerKind === "two" ? 2 : towerKind === "three" ? 3 : 1
    readonly property bool hammock: towerKind === "hammock"
    readonly property real towerHeight: Math.round(catH * (hammock ? .5 : .62 + .5 * (towerLevels - 1)))
    readonly property real towerWidth: Math.round(catW * (hammock ? 1.3 : .8 + .16 * (towerLevels - 1)))
    // How far the middle of a hammock hangs below its posts: the cat lies in it.
    readonly property real towerSag: hammock ? Math.round(catH * .14) : 0
    readonly property real towerTopY: towerBaseY - towerHeight
    // The cat's feet stand a little way into the cushion (or down in the hammock).
    readonly property real towerFeetY: towerTopY + 2 + towerSag
    readonly property real towerCatX: towerX - catW / 2
    // The tower is wanted (a nap is coming or on); the cat is up on it; the side it leaps from (-1: its left).
    property bool towerNeeded: false
    property bool onTower: false
    property int leapSide: -1
    onTowerXChanged: followTower()
    onTowerBaseYChanged: followTower()
    // Another kind of tower (or size): the cat on it is put on the new one once its numbers have followed.
    onTowerKindChanged: Qt.callLater(followTower)
    onCatHChanged: Qt.callLater(followTower)
    // A cat asleep up there goes along when the tower is moved.
    function followTower() {
        if (!onTower || jumpAnimation.running) return
        // (From what the tower is, not from towerCatX and towerFeetY: those follow it a moment after this runs.)
        moveTo(towerX - catW / 2, towerBaseY - towerHeight + 2 + towerSag)
    }

    // What the window shows besides the cat: bubbles are the window's; these ask for them.
    signal hushRequested()
    signal meowSaid()
    signal hopRequested()
    signal shakeRequested()
    // Sprung up (poked): quick and sudden, not the hop of good news.
    signal springRequested()
    // The cat has come down from a leap.
    signal landed()
    // The cat is somewhere new; the window follows. (Both coordinates are set between batching and placed, so the
    // window moves once, not along one and then the other.)
    property bool batching: false
    signal placed()
    function moveTo(x, y) {
        batching = true
        catX = x
        feetY = y
        batching = false
        placed()
    }

    // ---- how fast ----
    // A lazy cat does everything slowly, a brisk one less so; every behaviour has its own.
    property real tempo: 1.25
    function tempoFor(roll) { return roll < .22 ? 2.1 : roll < .78 ? 1.25 : .9 }
    function t(n) { return n * tempo }
    function ms(n) { return n / pace }
    // Points a second: a stroll is about half a cat's length, the dash three and a half.
    readonly property real walkSpeed: catW * .5 / tempo * pace
    readonly property real dashSpeed: catW * 3.4 * pace
    // The ground a full stride covers, so the feet do not slide.
    readonly property real strideLength: catW * .34
    readonly property real minX: screenLeft + screenWidth * .015
    readonly property real maxX: screenLeft + screenWidth - catW - screenWidth * .015
    function rand(a, b) { return a + Math.random() * (b - a) }
    function clampX(v) { return Math.min(Math.max(v, minX), maxX) }

    // The pose (and what the cat is doing, for the status line); the extra poses switched off.
    function setPose(name, text, blend) {
        blendMs = Math.max(0, Math.round(ms(blend === undefined ? t(420) : blend)))
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
        waitTimer.stop(); turnTimer.stop(); travelAnimation.stop(); jumpAnimation.stop()
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
            if (step.walk !== undefined) { walkTo(value(step.walk)); return }
            if (step.jump) { jumpTo(value(step.jump.x), value(step.jump.y), !!step.jump.tower); return }
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

    // ---- moving along the line: speeding up, a steady speed, slowing down ----
    SequentialAnimation {
        id: travelAnimation
        NumberAnimation { id: speedUp; target: brain; property: "catX"; easing.type: Easing.InQuad }
        NumberAnimation { id: steady; target: brain; property: "catX"; easing.type: Easing.Linear }
        NumberAnimation { id: slowDown; target: brain; property: "catX"; easing.type: Easing.OutQuad }
        onFinished: { brain.walking = false; brain.advance() }
    }
    // To a place at a speed (points a second), taking accelMs to get there and decelMs to stop. A short way is
    // covered at a lower top speed, so it still starts and ends gently.
    // It turns to face where it goes first (turning round takes 0.3 s), then sets off: no walking backwards.
    Timer { id: turnTimer; onTriggered: travelAnimation.restart() }
    function travelTo(to, speed, accelMs, decelMs, stroll) {
        const distance = Math.abs(to - catX)
        const direction = to >= catX ? 1 : -1
        const turning = distance >= 1 && direction !== facing
        facing = direction
        if (distance < 1) { advance(); return }
        walking = stroll
        let ta = accelMs / 1000 / pace, td = decelMs / 1000 / pace, v = speed
        let da = v * ta / 2, dd = v * td / 2, k = 1
        if (da + dd > distance) k = Math.sqrt(distance / (da + dd))
        ta *= k; td *= k; v *= k; da *= k * k; dd *= k * k
        const cruise = Math.max(0, distance - da - dd), dir = facing
        plan = {distance: distance, topSpeed: v, accelMs: ta * 1000, decelMs: td * 1000, cruiseMs: cruise / v * 1000,
                accelDistance: da, decelDistance: dd}
        speedUp.to = catX + dir * da; speedUp.duration = ta * 1000
        steady.to = catX + dir * (da + cruise); steady.duration = cruise / v * 1000
        slowDown.to = to; slowDown.duration = td * 1000
        if (turning) { turnTimer.interval = Math.max(1, ms(340)); turnTimer.restart() }
        else travelAnimation.restart()
    }
    // How the last move was planned (tests read it): distances in points, times in milliseconds.
    property var plan: ({})
    function walkTo(target) {
        travelTo(Math.min(Math.max(target, minX - catW * .2), maxX + catW * .2), walkSpeed, t(700), t(900), true)
    }
    function dashTo(target) { travelTo(target, dashSpeed, 650, 0, false) }
    property real lastX: 0
    onCatXChanged: {
        if (walking) stridePhase += Math.abs(catX - lastX) / strideLength
        lastX = catX
    }

    // ---- a leap up to the tower or down from it: an arc, higher than both ends ----
    property real jumpFromX: 0
    property real jumpFromY: 0
    property real jumpToX: 0
    property real jumpToY: 0
    property real jumpRise: 0
    // Landing on the tower: where it is now (the tower may be carried while the cat is in the air).
    property bool jumpToTower: false
    property real jumpProgress: 0
    NumberAnimation { id: jumpAnimation; target: brain; property: "jumpProgress"; from: 0; to: 1; onFinished: { brain.landed(); brain.advance() } }
    onJumpProgressChanged: {
        if (!jumpAnimation.running) return
        const k = jumpProgress
        const toX = jumpToTower ? towerCatX : jumpToX, toY = jumpToTower ? towerFeetY : jumpToY
        const apex = Math.min(jumpFromY, toY) - jumpRise
        const control = 2 * apex - (jumpFromY + toY) / 2
        moveTo(jumpFromX + (toX - jumpFromX) * k,
               (1 - k) * (1 - k) * jumpFromY + 2 * (1 - k) * k * control + k * k * toY)
    }
    function jumpTo(toX, toY, tower) {
        jumpToTower = tower
        const x1 = tower ? towerCatX : toX, y1 = tower ? towerFeetY : toY
        if (Math.abs(x1 - catX) > 2) facing = x1 >= catX ? 1 : -1
        jumpFromX = catX; jumpFromY = feetY; jumpToX = x1; jumpToY = y1
        jumpRise = catH * .5 + Math.min(Math.abs(x1 - catX), catW * 4) * .12
        // (Not so high that the cat's window would be above the screen: it would be pushed back down.)
        jumpRise = Math.max(0, Math.min(jumpRise, Math.min(feetY, y1) - screenTop - windowAbove - 8))
        // The leap is a pose of its own, run into from the crouch: legs stretched out.
        setPose("run", y1 < feetY ? "leaps up" : "leaps down", t(260))
        leap = true
        const seconds = (.8 + Math.hypot(x1 - catX, y1 - feetY) / 1500) * Math.min(tempo, 1.5)
        jumpAnimation.duration = Math.max(1, ms(seconds * 1000))
        jumpAnimation.restart()
    }

    // ---- behaviours ----
    // Down from the tower first, beside it on the floor: on the line it walks along, or on the tower's own
    // floor when that line is not on the screen the tower is on (a tower carried to another screen).
    property real landingX: 0
    property real landingY: 0
    function toFloorSteps() {
        if (!onTower) return []
        return [
            {call: function() { setPose("sit", "looks down", t(450)); facing = spotX() >= catX ? 1 : -1 }},
            {wait: t(600)},
            {call: function() {
                landingX = spotX()
                landingY = onScreen(landingX + catW / 2, lineY - 1) ? lineY : towerBaseY - 4
                onTower = false
            }},
            {jump: {x: function() { return landingX }, y: function() { return landingY }}},
            {call: function() { lineY = landingY; setPose("sit", "", t(400)); towerNeeded = false }},
            {wait: t(500)}
        ]
    }
    function wanderTarget() {
        const to = rand(minX, maxX)
        if (Math.abs(to - catX) >= catW * 1.5) return to
        return catX > screenLeft + screenWidth / 2 ? minX + screenWidth * .1 : screenLeft + screenWidth * .5
    }
    function behaviour(name) {
        switch (name) {
        case "sit":
            return [{call: function() { setPose("sit", "sitting, its tail now and then") }}, {wait: rand(20000, 60000)}]
        case "groom":
            return [
                {call: function() { setPose("groom", "licking its paw", t(650)) }}, {wait: t(4200)},
                {call: function() { wipe = true; status = "wiping its face" }}, {wait: t(3200)},
                {call: function() { wipe = false; status = "licking its paw" }}, {wait: t(3200)},
                {call: function() { setPose("sit", "", t(600)) }}, {wait: t(1200)}
            ]
        case "wander":
            return toFloorSteps().concat([
                {call: function() { setPose("walk", "strolling", t(500)) }},
                {wait: t(350)},
                {walk: wanderTarget},
                {wait: t(500)},
                {call: function() { setPose("sit", "", t(650)) }}, {wait: t(1500)}
            ])
        case "zoomies": return zoomies()
        case "nap": return nap()
        case "watch": return watch()
        case "belly":
            return toFloorSteps().concat([
                {call: function() { setPose("belly", "rolling on its back", t(900)) }}, {wait: t(rand(6000, 10000))},
                {call: function() { setPose("sit", "", t(900)) }}, {wait: t(800)}
            ])
        case "stretch":
            return [
                {call: function() { setPose("stretch", "stretching", t(700)) }}, {wait: t(1800)},
                {call: function() { meow = true; status = "yawning" }}, {wait: t(1200)},
                {call: function() { setPose("sit", "meowed", t(600)); meow = true; meowSaid() }}, {wait: t(1200)},
                {call: function() { meow = false }}, {wait: t(1000)}
            ]
        // Owelk: an AI answer is written (until it is done, ten minutes at most), ready, failed, new papers, time for a break.
        case "aiWriting":
            return [{call: function() { setPose("knead", "kneading while the AI writes", 300) }}, {wait: 600000}]
        case "aiReady":
            return [
                {call: function() { setPose("sit", "tells the answer is ready", 200); meow = true; hopRequested() }}, {wait: 800},
                {call: function() { meow = false }}, {wait: 2400}
            ]
        case "aiFail":
            return [
                {call: function() { setPose("arch", "startled: the AI could not answer", 100); shakeRequested() }}, {wait: 2600},
                {call: function() { setPose("sit", "", 450) }}, {wait: 900}
            ]
        case "forYou":
            return [{call: function() { setPose("sit", "ears up: new papers", 200); perk = true; hopRequested() }}, {wait: 3000}]
        case "breakTime":
            return [
                {call: function() { setPose("stretch", "stretches: time for a break", 450) }}, {wait: 1800},
                {call: function() { meow = true }}, {wait: 1000},
                {call: function() { setPose("sit", "", 450) }}, {wait: 2400}
            ]
        }
        return [{wait: 1000}]
    }
    readonly property var events: ["aiWriting", "aiReady", "aiFail", "forYou", "breakTime"]

    // ---- the tower ----
    // The place on the line beside the tower (a cat's length from the middle of it) the cat leaps from and lands
    // on, on the side it is nearer to; the other side when that is out of the screen.
    function spotFor(side) { return towerX + side * (towerWidth / 2 + catW * .55) - catW / 2 }
    function spotX() {
        let side = catX + catW / 2 < towerX ? -1 : 1
        let spot = spotFor(side)
        if (spot < minX || spot > maxX) { side = -side; spot = spotFor(side) }
        leapSide = side
        return clampX(spot)
    }
    // How a nap goes: lying on its side or with its back turned, one as likely as the other.
    function sleepPoseFor(roll) { return roll < .5 ? "sleep" : "sleepBack" }
    // Up on the tower: it looks at it, goes to it, wiggles, leaps up and settles.
    function climbSteps() {
        if (onTower) return []
        const spot = spotX()
        const far = Math.abs(spot - catX) > 6
        let approach = [
            {call: function() { towerNeeded = true; setPose("sit", "looks at the tower", t(450)) }},
            {wait: t(900)}
        ]
        if (far) approach = approach.concat([
            {call: function() { setPose("walk", "goes to the tower", t(450)) }},
            {wait: t(350)},
            {walk: function() { return spotX() }},
            {wait: t(500)}
        ])
        return approach.concat([
            {call: function() { facing = towerX >= catX + catW / 2 ? 1 : -1; setPose("run", "gathers itself", t(450)); crouch = true }},
            {wait: t(1000)},
            {call: function() { onTower = true }},
            {jump: {tower: true}},
            {call: function() { setPose("sit", hammock ? "in the hammock" : "up on the tower", t(500)) }},
            {wait: t(1000)}
        ])
    }
    // A nap up there (in the hammock, if it is one), and waking slowly.
    function nap() {
        const lying = sleepPoseFor(chance())
        const where = hammock ? "asleep in the hammock" : "asleep on the tower"
        return climbSteps().concat([
            {call: function() { setPose(lying, lying === "sleep" ? where : where + ", its back turned", t(1100)) }}, {wait: rand(300000, 1200000)},
            {call: function() { setPose("sit", "opened its eyes", t(900)) }}, {wait: t(1400)}
        ])
    }
    // Up there it sits and looks at the user, the pupils following the pointer.
    property bool watching: false
    function watch() {
        return climbSteps().concat([
            {call: function() { setPose("sit", "watches you", t(500)); watching = true }},
            {wait: rand(30000, 90000)},
            {call: function() { watching = false }},
            {wait: t(400)}
        ])
    }

    // Low, bottom wiggling; then across the whole screen and out of sight; later in from the other side.
    property double lastZoomies: 0
    function zoomies() {
        const edge = screenLeft + screenWidth
        return toFloorSteps().concat([
            {call: function() {
                hushRequested()
                running = true
                lastZoomies = Date.now()
                exitSide = catX + catW / 2 < screenLeft + screenWidth / 2 ? 1 : -1
                facing = exitSide
                setPose("run", "wiggling its bottom", 300); crouch = true
            }},
            {wait: 850},
            {call: function() { crouch = false; status = "zoomies across the screen" }},
            // The window is out of sight when it is fully past the edge.
            {dash: function() { return exitSide === 1 ? edge + windowOffset : screenLeft - windowWidth + windowOffset }},
            {call: function() { setPose("sit", "out of sight", 0); away = true }},
            {wait: rand(30000, 120000)}
        ]).concat(comeBack())
    }
    // In from the far side and strolls to a place on the screen.
    function comeBack() {
        return [
            {call: function() {
                moveTo(exitSide === 1 ? screenLeft - windowWidth + windowOffset : screenLeft + screenWidth + windowOffset, lineY)
                facing = exitSide === 1 ? 1 : -1
                away = false
                setPose("walk", "strolls back in", 0)
            }},
            {walk: function() {
                return exitSide === 1 ? rand(screenLeft + screenWidth * .12, screenLeft + screenWidth * .4)
                                      : rand(screenLeft + screenWidth * .5, maxX)
            }},
            {wait: t(500)},
            {call: function() { setPose("sit", "", t(650)); running = false }}, {wait: t(1400)}
        ]
    }

    // From HTML next(): what comes after a behaviour. After a poke it is something else than before.
    function next() {
        const table = onTower ? [["wander", 45], ["groom", 20], ["sit", 15], ["watch", 20]]
                              : [["sit", 22], ["groom", 16], ["wander", 22], ["nap", 16], ["belly", 9], ["stretch", 9], ["zoomies", 6], ["watch", 8]]
        // A dash about once in forty minutes, never twice within ten.
        const options = table.filter(function(row) {
            return row[0] !== avoid && !(row[0] === "zoomies" && Date.now() - lastZoomies < 600000 / pace)
        })
        let r = Math.random() * options.reduce(function(sum, row) { return sum + row[1] }, 0)
        for (const row of options) { r -= row[1]; if (r < 0) return row[0] }
        return "sit"
    }

    // Where the cat stands when a new behaviour starts: an interrupted jump or walk leaves it anywhere.
    function settle() {
        running = false
        walking = false
        watching = false
        if (onTower) moveTo(towerCatX, towerFeetY)
        else { towerNeeded = false; moveTo(clampX(catX), lineY) }
    }
    function begin(name) {
        if (halted) return
        stop()
        settle()
        last = name
        current = name
        avoid = ""
        // Something that happens in Owelk is quick; a cat at its own business is not.
        tempo = events.indexOf(name) >= 0 ? 1 : tempoFor(chance())
        play(behaviour(name))
    }
    // Something happened in Owelk. Nothing while it dashes, or is held, or the screen is locked.
    function react(name) {
        if (running || halted) return false
        begin(name)
        return true
    }

    // ---- a poke: it springs up, and does something else than it did ----
    Timer { id: pokeCooldown; interval: 1200 }
    readonly property bool pokeCooling: pokeCooldown.running
    function poke() {
        if (running || halted || away || pokeCooling) return false
        // Kneading while the AI writes goes on after a start.
        if (pose === "knead") { springRequested(); pokeCooldown.start(); return true }
        const from = last
        pokeCooldown.start()
        stop()
        settle()
        tempo = 1
        current = "poke"
        play([
            {call: function() { setPose("stand", "springs up", 140); perk = true; springRequested() }},
            {wait: 800},
            {call: function() { perk = false; avoid = from }}
        ])
        return true
    }

    // Held (dragged), or the screen is locked or Owelk hidden: nothing moves. The notices stay out.
    function halt(held) {
        if (halted) return
        const wasAway = away
        stop()
        halted = true
        current = ""
        walking = false
        watching = false
        if (!wasAway) { running = false; setPose(held ? "stand" : "sit", held ? "held" : "", 160) }
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
