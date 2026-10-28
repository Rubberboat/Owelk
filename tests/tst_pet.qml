import QtQuick
import QtQuick.Controls
import QtTest
import Owelk.Ui
import "../qml" as App

Item {
    width: 200; height: 100
    Component { id: petComponent; App.PetWindow {} }
    SignalSpy { id: openSpy; signalName: "openRequested" }
    SignalSpy { id: threadSpy; signalName: "threadRequested" }
    SignalSpy { id: forYouSpy; signalName: "forYouRequested" }
    SignalSpy { id: pdfSpy; signalName: "pdfsDropped" }
    SignalSpy { id: explainSpy; signalName: "explainRequested" }
    SignalSpy { id: frameSpy; signalName: "frameSwapped" }
    // Stand-ins for researchStore.ai and researchStore.forYou.
    QtObject {
        id: fakeAi
        signal started(int request, string threadId, string provider, string model, bool truncated)
        signal finished(int request, string text, var details)
        signal failed(int request, string error)
    }
    QtObject { id: fakeForYou; property var items: []; signal changed() }
    TestCase {
        name: "DesktopPet"
        when: windowShown
        function cleanup() {
            DesktopPet.enabled = false; DesktopPet.size = "medium"; DesktopPet.breakMinutes = 50
            DesktopPet.towerMode = "always"; DesktopPet.towerKind = "one"
            DesktopPet.dormant = false
            researchStore.setSetting("pet.position", "")
            researchStore.setSetting("pet.tower", "")
        }
        function asleep(brain) { return brain.pose === "sleep" || brain.pose === "sleepBack" }
        // A pet that does nothing by itself: the test says what it does.
        function quietPet(props) {
            // (A drag is made by calling beginDrag, dragTo and dropped: there is no hand on the pointer here.)
            const pet = createTemporaryObject(petComponent, null, Object.assign({followPointer: false}, props || {}))
            const brain = findChild(pet, "petBrain")
            brain.autoRun = false
            brain.stop()
            brain.halted = false
            return pet
        }
        // The cat on its line at a place across the screen.
        function stand(brain, across) {
            brain.catX = brain.screenLeft + brain.screenWidth * across
            brain.feetY = brain.lineY
        }

        function test_petIsNamedAndFloatsWhereItWasLeft() {
            verify(DesktopPet.supported, "only Wayland has no pet")
            compare(DesktopPet.englishName, "Allmeng-E")
            compare(DesktopPet.name, "알맹이")
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            verify(pet.visible)
            compare(pet.title, "알맹이")
            compare(pet.catH, 160)
            compare(pet.height, pet.headroom + 160 + Math.round(160 * .06))
            const first = DesktopPet.place(pet.width, pet.height)
            compare(pet.x, first.x); compare(pet.y, first.y)
            // Picked up and put down somewhere else, it stays there: the window, and the line it walks.
            pet.beginDrag(Qt.point(500, 400))
            verify(pet.dragging); verify(brain.halted)
            pet.dragTo(Qt.point(200, 200))
            compare(pet.x, first.x - 300); compare(pet.y, first.y - 200)
            pet.dropped()
            compare(brain.catX, first.x - 300 + pet.marginX)
            compare(brain.lineY, first.y - 200 + pet.feetOffset)
            compare(researchStore.setting("pet.position"), (first.x - 300) + "," + (first.y - 200))
            verify(!brain.halted)
            const again = quietPet()
            compare(again.x, first.x - 300); compare(again.y, first.y - 200)
            // A place no screen shows any more falls back to the corner.
            researchStore.setSetting("pet.position", "-90000,-90000")
            verify(DesktopPet.place(60, 160).x > -90000)
            // A new size keeps the feet where they were.
            DesktopPet.size = "small"
            compare(pet.catH, 120)
            tryVerify(function() { return pet.y + pet.feetOffset === Math.round(brain.lineY) })
            compare(researchStore.setting("pet.size"), "small")
            // A click makes it spring up and leaves Owelk where it is; a double click brings Owelk forward.
            openSpy.target = pet; openSpy.clear()
            mouseClick(pet.contentItem)
            compare(openSpy.count, 0)
            compare(brain.pose, "stand")
            // (A double tap, as the tap handler reports it: synthetic clicks are not timed like a hand's.)
            findChild(pet, "petTap").doubleTapped(null, Qt.LeftButton)
            compare(openSpy.count, 1)
            // Its menu has the app's colors, not the system's (white text in dark mode): the menu opens in
            // a window of its own, which does not take the pet window's colors.
            const menu = findChild(pet, "petMenu")
            menu.popup()
            tryCompare(menu, "opened", true)
            const row = findChild(menu, "hidePet")
            compare(row.text, "Hide Allmeng-E")
            compare(findChild(menu, "bringTowerHere").text, "Move the tower here")
            verify(Qt.colorEqual(row.contentItem.color, Theme.text), "menu text " + row.contentItem.color + ", theme text " + Theme.text)
            menu.close()
            DesktopPet.enabled = true
            findChild(pet, "hidePet").triggered()
            compare(DesktopPet.enabled, false)
            compare(researchStore.setting("pet.enabled"), "0")
        }
        function test_aBreakAfterAStretchOfReading() {
            DesktopPet.breakMinutes = 25
            compare(researchStore.setting("pet.breakMinutes"), "25")
            // Minutes of 20 ms; Owelk in front, a document open.
            const pet = quietPet({minuteLength: 20, ownerActive: true, reading: true})
            const words = findChild(pet, "petBubbleText")
            // Shown although Owelk is in front: that is where the reading happens.
            tryVerify(function() { return pet.message !== null }, 2000)
            compare(words.text, "25분 읽었어요. 잠깐 쉴까요?")
            // And the cat stretches.
            compare(findChild(pet, "petBrain").pose, "stretch")
            // The count starts again (test minutes are short: a few may have passed already).
            verify(pet.readMinutes < 25, "count " + pet.readMinutes)
            // A click on the cat dismisses it and opens nothing.
            openSpy.target = pet; openSpy.clear()
            mouseClick(pet.contentItem, pet.width / 2, pet.height - 10)
            compare(pet.message, null); compare(openSpy.count, 0)
            // Away for a while: the count starts again.
            tryVerify(function() { return pet.readMinutes >= 3 })
            pet.reading = false
            tryCompare(pet, "readMinutes", 0, 1000)
            // Off: no counting.
            DesktopPet.breakMinutes = 0
            pet.reading = true
            verify(!findChild(pet, "readingClock").running)
        }
        function test_droppedPdfsOpenAndTextIsExplained() {
            const pet = quietPet()
            pdfSpy.target = pet; explainSpy.target = pet
            verify(pet.received(["file:///papers/a.PDF", "file:///papers/b.png"], ""))
            compare(pdfSpy.count, 1)
            compare(pdfSpy.signalArguments[0][0].map(String), ["file:///papers/a.PDF"])
            verify(pet.received([], "  The attention weights sum to one.  "))
            compare(explainSpy.signalArguments[0][0], "The attention weights sum to one.")
            verify(!pet.received(["file:///papers/b.png"], ""), "a picture alone is neither")
            verify(!pet.received([], "   "))
            compare(pdfSpy.count, 1); compare(explainSpy.count, 1)
        }
        function test_petSaysWhatHappenedWhileOwelkIsBehind() {
            // Papers already waiting when the pet starts are not news.
            fakeForYou.items = [{id: "old"}]
            const pet = quietPet({ai: fakeAi, forYou: fakeForYou, ownerActive: false})
            const brain = findChild(pet, "petBrain")
            fakeForYou.changed()
            compare(pet.message, null)
            fakeForYou.items = []
            fakeForYou.changed()
            const bubble = findChild(pet, "petBubble"), words = findChild(pet, "petBubbleText")
            compare(bubble.visible, false)
            // While a conversation is answered it says so and kneads; other AI work is not news.
            fakeAi.started(7, "thread-1", "codex", "model", false)
            verify(pet.writing)
            compare(brain.pose, "knead")
            tryCompare(bubble, "visible", true)
            compare(words.text, "답변 쓰는 중…")
            fakeAi.finished(8, "a gloss", {})
            compare(words.text, "답변 쓰는 중…")
            // Done: it hops with a bubble.
            fakeAi.finished(7, "the answer", {})
            compare(words.text, "답변이 준비됐어요!")
            compare(brain.pose, "sit"); verify(brain.meow)
            // Only a double click opens the answer (a click on the bubble or the cat leaves Owelk be).
            threadSpy.target = pet; threadSpy.clear()
            openSpy.target = pet; openSpy.clear()
            waitForRendering(bubble.contentItem)
            mouseClick(bubble.contentItem)
            mouseClick(pet.contentItem, pet.width / 2, pet.height - 10)
            compare(threadSpy.count, 0); compare(openSpy.count, 0)
            compare(words.text, "답변이 준비됐어요!")
            findChild(bubble, "petBubbleTap").doubleTapped(null, Qt.LeftButton)
            compare(threadSpy.count, 1)
            compare(threadSpy.signalArguments[0][0], "thread-1")
            tryCompare(bubble, "visible", false)
            // Failed: the fur stands on end.
            fakeAi.started(9, "thread-2", "codex", "model", false)
            fakeAi.failed(9, "No key for this provider.\nDetails")
            compare(words.text, "AI가 답하지 못했어요")
            compare(brain.pose, "arch")
            // With Owelk in front there is nothing to say (it still kneads while an answer is written);
            // behind again mid-answer, it says it is writing.
            pet.ownerActive = true
            compare(pet.message, null)
            fakeAi.started(10, "thread-3", "codex", "model", false)
            compare(brain.pose, "knead")
            fakeAi.finished(10, "", {})
            compare(pet.message, null)
            compare(brain.pose, "sit", "no more kneading")
            fakeAi.started(11, "thread-4", "codex", "model", false)
            compare(pet.message, null)
            pet.ownerActive = false
            compare(words.text, "답변 쓰는 중…")
            compare(pet.message.thread, "thread-4")
            fakeAi.finished(11, "", {})
            compare(words.text, "답변이 준비됐어요!")
            pet.message = null
            // More papers in For You than before: ears up.
            fakeForYou.items = [{id: "a"}, {id: "b"}]
            fakeForYou.changed()
            compare(words.text, "For You에 새 논문 2편")
            compare(brain.pose, "sit"); verify(brain.perk)
            forYouSpy.target = pet; forYouSpy.clear()
            mouseClick(pet.contentItem, pet.width / 2, pet.height - 10)
            compare(forYouSpy.count, 0)
            findChild(pet, "petTap").doubleTapped(null, Qt.LeftButton)
            compare(forYouSpy.count, 1)
            compare(openSpy.count, 0)
            fakeForYou.items = [{id: "a"}]
            fakeForYou.changed()
            compare(pet.message, null, "fewer papers are not news")
        }
        function test_aDashSaysNothingAndNoticesAreDropped() {
            fakeForYou.items = []
            const pet = quietPet({ai: fakeAi, forYou: fakeForYou, ownerActive: false, minuteLength: 20, reading: false})
            const brain = findChild(pet, "petBrain")
            brain.pace = 6
            // A bubble is up when the cat crouches: it goes at once.
            pet.message = {text: "야옹", plain: true, ttl: 0}
            brain.begin("zoomies")
            verify(brain.running)
            compare(pet.message, null)
            compare(brain.pose, "run"); verify(brain.crouch)
            // Notices are dropped, not kept for later.
            fakeForYou.items = [{id: "a"}]
            fakeForYou.changed()
            compare(pet.message, null)
            fakeAi.started(1, "t", "codex", "model", false)
            fakeAi.finished(1, "", {})
            compare(pet.message, null)
            verify(!brain.react("aiFail"), "not even a startled look")
            compare(brain.pose, "run")
            // Out of the screen, window hidden, then back in.
            tryVerify(function() { return brain.away }, 5000)
            verify(!pet.visible)
            verify(pet.x >= brain.screenLeft + brain.screenWidth || pet.x + pet.width <= brain.screenLeft, "window fully outside: " + pet.x)
            compare(pet.message, null)
            tryVerify(function() { return !brain.away }, 40000)
            verify(pet.visible)
            tryVerify(function() { return !brain.running }, 20000)
            // Back to normal: news is said again.
            fakeForYou.items = [{id: "a"}, {id: "b"}]
            fakeForYou.changed()
            compare(pet.message.text, "For You에 새 논문 1편")
        }
        function test_aDashLeavesByTheFarSideAndComesBackFromTheOther() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            brain.pace = 6
            const mid = brain.screenLeft + brain.screenWidth / 2
            // On the left half it runs right, out past the right edge, and returns from the left.
            stand(brain, .2)
            brain.begin("zoomies")
            compare(brain.facing, 1)
            tryVerify(function() { return brain.away }, 5000)
            compare(brain.exitSide, 1)
            verify(pet.x >= brain.screenLeft + brain.screenWidth, "the whole window is past the right edge")
            tryVerify(function() { return !brain.away && brain.pose === "walk" }, 40000)
            verify(brain.catX + brain.windowWidth <= brain.screenLeft + 60 || brain.catX < mid, "enters at the left: " + brain.catX)
            compare(brain.facing, 1)
            tryVerify(function() { return !brain.running }, 20000)
            // On the right half, the other way.
            stand(brain, .8)
            brain.begin("zoomies")
            compare(brain.facing, -1)
            tryVerify(function() { return brain.away }, 5000)
            compare(brain.exitSide, -1)
            verify(pet.x + pet.width <= brain.screenLeft, "the whole window is past the left edge")
            tryVerify(function() { return !brain.running }, 40000)
            verify(brain.catX > brain.screenLeft)
        }
        function test_theDashIsSlowEnoughToSeeTheGallop() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            const cat = findChild(pet, "petCat")
            // A stride of the gallop is 0.27 s, and the cat covers about a body length in it, not four.
            compare(cat.stride, .27)
            const perStride = brain.dashSpeed / brain.pace * cat.stride
            verify(perStride >= brain.catW * .6 && perStride <= brain.catW * 1.3, "per stride " + perStride)
            // On a 1920 point screen that is a few seconds, not 0.7 of one.
            verify(1920 / (brain.dashSpeed / brain.pace) >= 2.5, "crossing " + 1920 / (brain.dashSpeed / brain.pace))
            // It speeds up over 0.65 s, then runs at that speed to the end: out of sight at a run.
            stand(brain, .3)
            brain.dashTo(brain.catX + 3000)
            compare(brain.plan.accelMs, 650)
            compare(brain.plan.decelMs, 0)
            compare(brain.plan.topSpeed, brain.dashSpeed)
            brain.stop()
        }
        function test_theCatWalksToTheTowerLeapsUpAndSleeps() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            const towerWin = findChild(pet, "petTowerWindow")
            verify(towerWin.visible, "the tower stands there, as the user left it")
            brain.pace = 600
            brain.chance = function() { return .1 }
            verify(!brain.onTower)
            brain.begin("nap")
            verify(brain.towerNeeded)
            tryVerify(function() { return brain.onTower }, 5000)
            tryVerify(function() { return asleep(brain) }, 8000)
            compare(brain.pose, "sleep")
            // It is right on the tower: the feet on its top, in the middle of it.
            compare(brain.catX, brain.towerCatX)
            compare(brain.feetY, brain.towerFeetY)
            verify(Math.abs(pet.x + pet.innerX + pet.marginX - brain.towerCatX) < .01)
            verify(Math.abs(pet.y + pet.innerY + pet.feetOffset - brain.towerFeetY) < .01)
            compare(Math.round(towerWin.y + towerWin.pad), Math.round(brain.towerTopY))
            verify(Math.abs(towerWin.x + towerWin.width / 2 - brain.towerX) <= 1, "the tower is where it stands")
            // The cat's window is above the tower's (the cat is not behind it): the tower's is not a child.
            verify(towerWin.transientParent === null)
            // Awake, it comes down again, beside the tower, on its line.
            tryVerify(function() { return !asleep(brain) }, 8000)
            brain.begin("wander")
            tryVerify(function() { return !brain.onTower }, 6000)
            tryVerify(function() { return brain.feetY === brain.lineY }, 8000)
            verify(towerWin.visible)
        }
        function test_theTowerCanBeMovedAnywhere() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            const towerWin = findChild(pet, "petTowerWindow")
            verify(towerWin.visible)
            const cx0 = pet.towerCenterX, base0 = pet.towerBase
            compare(researchStore.setting("pet.tower"), cx0 + "," + base0)
            compare(towerWin.x, Math.round(cx0 - towerWin.width / 2))
            compare(towerWin.y, Math.round(base0 - brain.towerHeight - towerWin.pad))
            // Drag it: it follows the pointer, from where the pointer was.
            towerWin.beginDrag(Qt.point(100, 100))
            verify(towerWin.dragging)
            towerWin.dragTo(Qt.point(160, 40))
            compare(pet.towerCenterX, cx0 + 60); compare(pet.towerBase, base0 - 60)
            compare(towerWin.x, Math.round(cx0 + 60 - towerWin.width / 2))
            compare(towerWin.y, Math.round(base0 - 60 - brain.towerHeight - towerWin.pad))
            towerWin.endDrag()
            verify(!towerWin.dragging)
            // It stays where it was put: kept for the next time too.
            compare(researchStore.setting("pet.tower"), (cx0 + 60) + "," + (base0 - 60))
            const again = quietPet()
            compare(again.towerCenterX, cx0 + 60); compare(again.towerBase, base0 - 60)
            // Not out of every screen.
            pet.moveTower(-5000, 99999)
            verify(pet.towerCenterX >= brain.screenLeft + 20)
            verify(pet.towerBase <= 900 + 4)
            pet.moveTower(99999, -5000)
            verify(pet.towerCenterX <= brain.screenLeft + brain.screenWidth - 20)
            verify(pet.towerBase >= brain.towerHeight)
            // The menu brings it back beside the cat.
            const beside = pet.towerBeside()
            findChild(towerWin, "bringTower").triggered()
            compare(pet.towerCenterX, beside.x); compare(pet.towerBase, beside.y)
            compare(researchStore.setting("pet.tower"), beside.x + "," + beside.y)
        }
        function test_aSleeperGoesAlongWhenItsTowerIsMoved() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            const towerWin = findChild(pet, "petTowerWindow")
            brain.pace = 600
            brain.chance = function() { return .1 }
            brain.begin("nap")
            tryVerify(function() { return asleep(brain) }, 8000)
            const pose = brain.pose
            towerWin.beginDrag(Qt.point(0, 0))
            towerWin.dragTo(Qt.point(-80, -50))
            towerWin.endDrag()
            verify(brain.onTower)
            compare(brain.pose, pose)
            compare(brain.catX, brain.towerCatX)
            compare(brain.feetY, brain.towerFeetY)
            verify(Math.abs(pet.x + pet.innerX + pet.marginX - brain.towerCatX) < .01)
            verify(Math.abs(pet.y + pet.innerY + pet.feetOffset - brain.towerFeetY) < .01)
            // And it is still up there when it wakes.
            brain.stop()
        }
        function test_theTowerCanComeOnlyForTheNap() {
            DesktopPet.towerMode = "sleeping"
            compare(researchStore.setting("pet.towerMode"), "sleeping")
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            const towerWin = findChild(pet, "petTowerWindow")
            verify(!towerWin.visible, "no tower on the desktop while the cat is not about to sleep")
            brain.pace = 600
            brain.chance = function() { return .1 }
            brain.begin("nap")
            tryVerify(function() { return towerWin.visible }, 2000)
            tryVerify(function() { return asleep(brain) }, 8000)
            verify(towerWin.visible)
            // Awake and down from it, the tower goes again.
            tryVerify(function() { return !asleep(brain) }, 8000)
            brain.begin("wander")
            tryVerify(function() { return !brain.onTower && !brain.towerNeeded }, 6000)
            tryVerify(function() { return !towerWin.visible }, 4000)
        }
        function test_theCatLeapsToATowerAtAnyHeight() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            // Up high, far above the line it walks.
            pet.moveTower(pet.towerCenterX, 380)
            brain.pace = 600
            brain.chance = function() { return .1 }
            brain.begin("nap")
            tryVerify(function() { return asleep(brain) }, 8000)
            compare(brain.feetY, brain.towerFeetY)
            verify(brain.feetY < brain.lineY - 100, "up at " + brain.feetY + ", line " + brain.lineY)
            verify(Math.abs(pet.y + pet.innerY + pet.feetOffset - brain.feetY) < .01, "the window went up with it")
            tryVerify(function() { return !asleep(brain) }, 8000)
            brain.begin("wander")
            tryVerify(function() { return !brain.onTower }, 6000)
            tryVerify(function() { return brain.feetY === brain.lineY }, 8000)
        }
        function test_theTowerCannotGoSoHighThatTheCatOnItIsOffTheScreen() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            pet.moveTower(pet.towerCenterX, -9999)
            const screen = pet.screenOf(pet.towerCenterX, pet.towerBase)
            // The cat's window, up on it, is below the top of the screen.
            const windowTop = brain.towerFeetY - pet.feetOffset
            verify(windowTop >= screen.virtualY + 25, "window top " + windowTop)
            // And it still finds its way up there.
            brain.pace = 600
            brain.chance = function() { return .1 }
            brain.begin("nap")
            tryVerify(function() { return asleep(brain) }, 10000)
            compare(brain.feetY, brain.towerFeetY)
            verify(pet.y >= screen.virtualY, "the window is on the screen: " + pet.y)
            brain.stop()
            // A big cat and a tall tower: still all on the screen.
            DesktopPet.size = "large"
            tryCompare(pet, "catH", 220)
            tryVerify(function() { return brain.towerFeetY - pet.feetOffset >= screen.virtualY + 25 }, 2000)
        }
        function test_aTowerOnAnotherScreenGivesTheCatAFloorThere() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            // The line the cat walks along is not on the screen the tower is on (that one ends above it).
            brain.screens = [{x: 0, y: 0, width: 800, height: 400}]
            verify(brain.onScreen(100, 300)); verify(!brain.onScreen(100, brain.lineY - 1))
            pet.moveTower(340, 380)
            brain.pace = 600
            brain.chance = function() { return .1 }
            const home = brain.lineY
            brain.begin("nap")
            tryVerify(function() { return asleep(brain) }, 10000)
            compare(brain.feetY, brain.towerFeetY)
            brain.begin("wander")
            tryVerify(function() { return !brain.onTower }, 8000)
            // Down on the tower's own floor, which is where it walks from now on.
            tryVerify(function() { return brain.feetY === brain.towerBaseY - 4 }, 8000)
            compare(brain.lineY, brain.towerBaseY - 4)
            verify(brain.lineY !== home)
            // A tower is put on the screen nearest to where it is let go.
            const near = pet.screenOf(-9000, 50)
            verify(near !== null)
        }
        function test_theTowerHasOneTwoOrThreeTiersOrIsAHammock() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            const towerWin = findChild(pet, "petTowerWindow")
            const heights = {}
            for (const kind of ["hammock", "one", "two", "three"]) {
                DesktopPet.towerKind = kind
                compare(researchStore.setting("pet.towerKind"), kind)
                tryCompare(brain, "towerKind", kind)
                heights[kind] = brain.towerHeight
                // The window is as big as the tower.
                tryCompare(towerWin, "towerHeight", brain.towerHeight)
                verify(towerWin.height > brain.towerHeight)
            }
            verify(heights.hammock < heights.one && heights.one < heights.two && heights.two < heights.three, JSON.stringify(heights))
            DesktopPet.towerKind = "hammock"
            tryCompare(brain, "towerKind", "hammock")
            verify(brain.towerSag > 0)
            compare(brain.towerFeetY, brain.towerTopY + 2 + brain.towerSag)
            DesktopPet.towerKind = "three"
            tryCompare(brain, "towerKind", "three")
            compare(brain.towerSag, 0)
            verify(brain.towerWidth > Math.round(brain.catW * .8))
            // The menu on the tower picks one.
            findChild(towerWin, "towerKind-two").triggered()
            compare(DesktopPet.towerKind, "two")
        }
        function test_aCatOnTheTowerGoesWithItWhenItsKindChanges() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            brain.pace = 600
            brain.chance = function() { return .1 }
            brain.begin("nap")
            tryVerify(function() { return asleep(brain) }, 8000)
            const before = brain.feetY
            DesktopPet.towerKind = "three"
            tryVerify(function() { return brain.feetY === brain.towerFeetY && brain.feetY < before - 50 }, 3000)
            DesktopPet.towerKind = "hammock"
            tryVerify(function() { return brain.feetY === brain.towerFeetY && brain.towerSag > 0 }, 3000)
            verify(brain.onTower)
            brain.stop()
        }
        function test_aCatSleepsInTheHammockAndUpOnEveryTier() {
            for (const kind of ["hammock", "two", "three"]) {
                DesktopPet.towerKind = kind
                const pet = quietPet()
                const brain = findChild(pet, "petBrain")
                brain.pace = 600
                brain.chance = function() { return .1 }
                brain.begin("nap")
                tryVerify(function() { return asleep(brain) }, 10000)
                compare(brain.feetY, brain.towerFeetY, kind)
                verify(brain.onTower)
                if (kind === "hammock") verify(brain.status.indexOf("hammock") >= 0, brain.status)
                brain.stop()
            }
        }
        function test_upOnTheTowerItLooksAtYouAndItsEyesFollowThePointer() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            const cat = findChild(pet, "petCat")
            brain.pace = 600
            brain.chance = function() { return .1 }
            brain.begin("watch")
            tryVerify(function() { return brain.watching }, 10000)
            brain.stop()    // (the watch itself is only a moment at this pace)
            verify(brain.onTower)
            compare(brain.pose, "sit")
            // The pupils move towards the pointer, either way it looks.
            const headX = pet.x + pet.marginX + pet.innerX + pet.catW * 142 / 220
            const headY = pet.y + pet.headroom + pet.innerY + pet.catH * .4
            pet.lookAt(Qt.point(headX + 500, headY))
            compare(pet.lookX, 1); compare(pet.lookY, 0)
            tryCompare(cat, "lookX", 1, 1000)
            pet.lookAt(Qt.point(headX, headY + 125))
            compare(pet.lookX, 0); compare(pet.lookY, .5)
            brain.facing = -1
            tryCompare(cat, "looksLeft", true, 2000)
            pet.lookAt(Qt.point(headX + 500, headY))
            compare(pet.lookX, -1, "mirrored, so across is the other way")
            // Done watching: the eyes look ahead again.
            brain.watching = false
            compare(pet.lookX, 0); compare(pet.lookY, 0)
            brain.stop()
        }
        function test_aNapperCarriedAwayStaysWhereItIsPut() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            brain.pace = 600
            brain.chance = function() { return .1 }
            brain.begin("nap")
            tryVerify(function() { return asleep(brain) }, 8000)
            pet.beginDrag(Qt.point(100, 100))
            pet.dragTo(Qt.point(160, 60))
            pet.dropped()
            // Lifted off the tower, put down on the floor: that is where its line is now.
            verify(!brain.onTower)
            compare(brain.catX, pet.x + pet.marginX)
            compare(brain.lineY, pet.y + pet.feetOffset)
            compare(brain.feetY, brain.lineY)
            wait(100)
            compare(brain.catX, pet.x + pet.marginX)
            brain.stop()
        }
        function test_aPokeMakesItSpringUpAndDoSomethingElse() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            const bob = findChild(pet, "petBob")
            brain.begin("groom")
            compare(brain.last, "groom")
            verify(brain.poke())
            compare(brain.pose, "stand"); verify(brain.perk)
            compare(brain.current, "poke")
            // It springs: up and down.
            tryVerify(function() { return bob.bobY < -pet.catH * .2 }, 1500)
            tryCompare(bob, "bobY", 0, 3000)
            // A second poke at once does nothing: it has just got up.
            verify(brain.pokeCooling)
            verify(!brain.poke())
            // What comes next is anything but what it was doing.
            tryCompare(brain, "avoid", "groom", 3000)
            for (let i = 0; i < 300; ++i) verify(brain.next() !== "groom")
            // Asleep up on the tower, it springs up there, and is done with napping.
            const other = quietPet()
            const sleeper = findChild(other, "petBrain")
            sleeper.pace = 600
            sleeper.chance = function() { return .1 }
            sleeper.begin("nap")
            tryVerify(function() { return asleep(sleeper) }, 8000)
            verify(sleeper.poke())
            compare(sleeper.pose, "stand")
            verify(sleeper.onTower)
            compare(sleeper.feetY, sleeper.towerFeetY)
            tryCompare(sleeper, "avoid", "nap", 3000)
            // Not while it dashes, is held or kneads for the AI.
            const runner = quietPet()
            const racing = findChild(runner, "petBrain")
            racing.begin("zoomies")
            verify(racing.running)
            verify(!racing.poke())
            const kneader = quietPet()
            const kneading = findChild(kneader, "petBrain")
            kneading.begin("aiWriting")
            verify(kneading.poke())
            compare(kneading.pose, "knead")
        }
        // Only a double click brings Owelk forward; a click moves only the cat (as the tap handlers report
        // them: synthetic clicks are not timed like a hand's).
        function test_onlyADoubleClickOpensOwelk() {
            fakeForYou.items = []
            const pet = quietPet({ai: fakeAi, forYou: fakeForYou, ownerActive: false})
            const brain = findChild(pet, "petBrain")
            const tap = findChild(pet, "petTap"), bubbleTap = findChild(pet, "petBubbleTap")
            openSpy.target = pet; threadSpy.target = pet; forYouSpy.target = pet
            openSpy.clear(); threadSpy.clear(); forYouSpy.clear()
            brain.begin("sit")
            tap.tapped(null, Qt.LeftButton)
            compare(openSpy.count, 0); compare(brain.current, "poke")
            tap.doubleTapped(null, Qt.LeftButton)
            compare(openSpy.count, 1)
            // An answer ready: a click on the cat or the bubble keeps the bubble; a double click opens it.
            fakeAi.started(31, "thread-31", "codex", "model", false)
            fakeAi.finished(31, "the answer", {})
            compare(pet.message.thread, "thread-31")
            tap.tapped(null, Qt.LeftButton)
            bubbleTap.tapped(null, Qt.LeftButton)
            compare(threadSpy.count, 0); verify(pet.message !== null)
            bubbleTap.doubleTapped(null, Qt.LeftButton)
            compare(threadSpy.count, 1); compare(threadSpy.signalArguments[0][0], "thread-31")
            compare(pet.message, null)
            // New papers: the cat's double click opens For You.
            fakeForYou.items = [{id: "n1"}]; fakeForYou.changed()
            verify(pet.message && pet.message.forYou)
            tap.doubleTapped(null, Qt.LeftButton)
            compare(forYouSpy.count, 1); compare(openSpy.count, 1)
            // A meow: a click takes it away; with it up a double click opens Owelk.
            pet.message = {text: "야옹", plain: true, ttl: 0}
            tap.doubleTapped(null, Qt.LeftButton)
            compare(openSpy.count, 2)
            pet.message = {text: "야옹", plain: true, ttl: 0}
            tap.tapped(null, Qt.LeftButton)
            compare(pet.message, null); compare(openSpy.count, 2)
            fakeForYou.items = []
        }
        function test_aClickOnTheCatPokesIt() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            brain.begin("sit")
            tryVerify(function() { return pet.contentItem.width > 0 })
            mouseClick(pet.contentItem)
            compare(brain.current, "poke")
            compare(brain.pose, "stand")
        }
        function test_writingGoesOnAfterADash() {
            const pet = quietPet({ai: fakeAi, ownerActive: false})
            const brain = findChild(pet, "petBrain")
            const words = findChild(pet, "petBubbleText")
            brain.pace = 6
            fakeAi.started(21, "thread-9", "codex", "model", false)
            compare(words.text, "답변 쓰는 중…")
            brain.begin("zoomies")
            compare(pet.message, null)
            tryVerify(function() { return !brain.running }, 60000)
            // The answer is still being written: the bubble and the kneading are back.
            compare(brain.pose, "knead")
            compare(words.text, "답변 쓰는 중…")
            fakeAi.finished(21, "", {})
            compare(words.text, "답변이 준비됐어요!")
        }
        function test_asleepTheLettersReadTheRightWayRound() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            function letters(item, out) {
                if (item.text === "z") out.push(item)
                for (let i = 0; i < item.children.length; ++i) letters(item.children[i], out)
                return out
            }
            const cat = findChild(pet, "petCat")
            for (const pose of ["sleep", "sleepBack"]) {
                brain.facing = 1
                tryCompare(cat, "looksLeft", false, 2000)
                brain.setPose(pose, "", 0)
                tryVerify(function() { return letters(cat, []).length === 3 })
                // The cat is turned around (mirrored); each letter is turned back.
                compare(letters(cat, []).map(function(z) { return z.transform[0].xScale }), [1, 1, 1])
                brain.facing = -1
                tryCompare(cat, "looksLeft", true, 2000)
                compare(letters(cat, []).map(function(z) { return z.transform[0].xScale }), [-1, -1, -1])
            }
        }
        function test_aNapIsOnItsSideOrWithItsBackTurnedHalfAndHalf() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            compare(brain.sleepPoseFor(0), "sleep")
            compare(brain.sleepPoseFor(.49), "sleep")
            compare(brain.sleepPoseFor(.5), "sleepBack")
            compare(brain.sleepPoseFor(.99), "sleepBack")
            // And a nap asks the dice once, and lies down as they say.
            brain.pace = 600
            brain.chance = function() { return .9 }
            brain.begin("nap")
            tryVerify(function() { return brain.pose === "sleepBack" }, 8000)
            verify(brain.onTower)
            brain.stop()
            const other = quietPet()
            const again = findChild(other, "petBrain")
            again.pace = 600
            again.chance = function() { return .1 }
            again.begin("nap")
            tryVerify(function() { return again.pose === "sleep" }, 8000)
            again.stop()
        }
        function test_aBackTurnedSleeperBreathesAndOnlyNowAndThenMoves() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            const cat = findChild(pet, "petCat")
            // Nothing in it is on a short cycle: the ear and the tail tip wait tens of seconds.
            cat.quietMin = 1000000; cat.quietMax = 1000000
            brain.setPose("sleepBack", "", 0)
            tryVerify(function() { return findChild(cat, "petSleepBack") !== null })
            const back = findChild(cat, "petSleepBack")
            compare(back.earMove, 1); compare(back.tailMove, 1)
            compare(back.earAngle, 0); compare(back.tailAngle, 0)
            // Redrawn only as often as breathing needs: thirty times a second.
            wait(400)
            frameSpy.target = pet; frameSpy.clear()
            wait(1500)
            verify(frameSpy.count > 15 && frameSpy.count <= 62, "back turned: " + frameSpy.count + " frames in 1.5 s")
            // An ear twitch: -16, 5, -9 degrees and still again (the last tenth of 7.5 seconds).
            let low = 0, high = 0
            back.twitchEar()
            for (let i = 0; i < 90; ++i) { wait(10); low = Math.min(low, back.earAngle); high = Math.max(high, back.earAngle) }
            verify(low < -13 && low >= -16.5, "ear low " + low)
            verify(high > 3 && high <= 5.5, "ear high " + high)
            tryCompare(back, "earMove", 1, 2000)
            compare(back.earAngle, 0)
            compare(back.tailAngle, 0, "the tail tip stayed")
            // A flick of the tail tip: -18, 6 degrees and still again (70 to 88 % of 11 seconds).
            low = 0; high = 0
            back.flickTail()
            for (let i = 0; i < 220; ++i) { wait(10); low = Math.min(low, back.tailAngle); high = Math.max(high, back.tailAngle) }
            verify(low < -15 && low >= -18.5, "tail low " + low)
            verify(high > 4 && high <= 6.5, "tail high " + high)
            tryCompare(back, "tailMove", 1, 2000)
            compare(back.tailAngle, 0)
            // Turned around, it keeps its look (mirrored whole).
            brain.facing = -1
            compare(cat.facingLeft, true)
        }
        function test_aHeldPetKeepsStillAndLetGoItCarriesOn() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            brain.pace = 6
            stand(brain, .3)
            brain.begin("wander")
            tryVerify(function() { return brain.pose === "walk" }, 2000)
            pet.beginDrag(Qt.point(10, 10))
            compare(brain.pose, "stand")
            const held = brain.catX
            wait(300)
            compare(brain.catX, held)
            // Put down somewhere else: that is where its line is now.
            pet.dragTo(Qt.point(110, 60))
            pet.dropped()
            compare(brain.catX, pet.x + pet.marginX)
            compare(brain.lineY, pet.y + pet.feetOffset)
            verify(!brain.halted)
        }
        function test_nothingMovesWhileTheScreenIsLockedOrOwelkHidden() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            brain.pace = 6
            stand(brain, .3)
            brain.begin("wander")
            tryVerify(function() { return brain.pose === "walk" }, 2000)
            DesktopPet.dormant = true
            verify(brain.halted)
            const at = brain.catX
            wait(300)
            compare(brain.catX, at)
            verify(!findChild(pet, "petCat").alive)
            verify(!brain.react("aiReady"), "no reactions either")
            pet.say({text: "x", kind: "aiReady", ttl: 0, reminder: true})
            compare(pet.message, null)
            DesktopPet.dormant = false
            verify(!brain.halted)
            verify(findChild(pet, "petCat").alive)
        }
        function test_aCalmPetIsHardlyRedrawn() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            brain.setPose("sit", "", 0)
            wait(700)
            frameSpy.target = pet; frameSpy.clear()
            wait(1500)
            verify(frameSpy.count <= 2, "sitting: " + frameSpy.count + " frames in 1.5 s")
            brain.setPose("sleep", "", 0)
            wait(700)
            frameSpy.clear()
            wait(1500)
            verify(frameSpy.count > 15 && frameSpy.count <= 62, "sleeping: " + frameSpy.count + " frames in 1.5 s")
        }
        function test_aPoseThatDoesNotMoveByItselfRunsNoClock() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            const cat = findChild(pet, "petCat")
            // A clock that counts frames wakes the window every frame, so a still pose has none.
            for (const pose of ["sit", "stretch"]) {
                brain.setPose(pose, "", 0)
                tryVerify(function() { return findChild(cat, "pose-" + pose) !== null })
                compare(findChild(findChild(cat, "pose-" + pose), "clock").running, false, pose + " has a clock")
            }
            // Those that move have one: every frame for a walker, thirty times a second for a sleeper.
            brain.setPose("walk", "", 0)
            tryVerify(function() { return findChild(cat, "pose-walk") !== null })
            compare(findChild(findChild(cat, "pose-walk"), "clock").running, true)
            brain.setPose("sleep", "", 0)
            tryVerify(function() { return findChild(cat, "pose-sleep") !== null })
            const sleeper = findChild(findChild(cat, "pose-sleep"), "clock")
            compare(sleeper.running, true)
            compare(sleeper.interval, 33)
        }
        function test_clicksOnTheTransparentPartsGoThrough() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            brain.setPose("sit", "", 0)
            tryVerify(function() { const a = DesktopPet.clickArea(pet); return a.width > 0 && a.width < pet.width }, 3000)
            const sitting = DesktopPet.clickArea(pet)
            verify(sitting.height < pet.height, "the headroom is clear: " + sitting.height + " of " + pet.height)
            // A new pose, another place: the area is worked out again.
            brain.setPose("stretch", "", 0)
            tryVerify(function() { const a = DesktopPet.clickArea(pet); return a.width !== sitting.width || a.height !== sitting.height }, 3000)
        }
        function test_thePawsKeepTheirMarksWhenItTurns() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            const cat = findChild(pet, "petCat")
            brain.setPose("sit", "", 0)
            // Right front paw a white glove, left front paw only its toes white; turning around keeps that.
            function marks() {
                const out = []
                function walk(item) {
                    if (item.glove !== undefined && item.toes !== undefined && item.front !== undefined && item.front !== "")
                        out.push(item.front + ":" + (item.glove ? "glove" : "toes"))
                    for (let i = 0; i < item.children.length; ++i) walk(item.children[i])
                }
                walk(cat)
                return out.sort()
            }
            tryVerify(function() { return marks().length === 2 })
            compare(marks(), ["far:glove", "near:toes"])
            brain.facing = -1
            tryCompare(cat, "looksLeft", true, 2000)
            compare(marks(), ["far:toes", "near:glove"])
        }

        // ---- smooth, not cut ----
        function test_aChangeOfPoseFadesInsteadOfCutting() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            const cat = findChild(pet, "petCat")
            brain.setPose("sit", "", 0)
            tryVerify(function() { return findChild(cat, "pose-sit") !== null })
            compare(cat.fade, 1)
            compare(cat.leavingPose, "")
            // The new pose comes in over the old one, which stays until the new one is solid.
            brain.setPose("groom", "", 900)
            compare(cat.shownPose, "groom"); compare(cat.leavingPose, "sit")
            verify(cat.fade < 1)
            tryVerify(function() { return findChild(cat, "pose-groom") !== null && findChild(cat, "pose-sit") !== null })
            verify(cat.frontOpacity < 1 && cat.backOpacity > 0)
            tryCompare(cat, "fade", 1, 4000)
            tryVerify(function() { return findChild(cat, "pose-sit") === null })
            compare(cat.leavingPose, "")
            // Changed again before it was over: no harm, the last one stays.
            brain.setPose("belly", "", 900)
            brain.setPose("stretch", "", 900)
            compare(cat.shownPose, "stretch")
            tryCompare(cat, "fade", 1, 4000)
            tryVerify(function() { return findChild(cat, "pose-belly") === null && findChild(cat, "pose-groom") === null })
            // The curves: the old one holds until the new one covers it, then goes.
            cat.fade = 0
            compare(cat.frontOpacity, 0); compare(cat.backOpacity, 1)
            cat.fade = .5
            verify(cat.backOpacity > .99, "old still there half way: " + cat.backOpacity)
            verify(cat.frontOpacity > .85, "new almost solid half way: " + cat.frontOpacity)
            cat.fade = 1
            compare(cat.frontOpacity, 1); compare(cat.backOpacity, 0)
            // Poses drawn alike (standing is walking without the stride) change without any fade.
            brain.setPose("walk", "", 0)
            tryVerify(function() { return findChild(cat, "pose-walk") !== null })
            brain.setPose("stand", "", 900)
            compare(cat.fade, 1)
            compare(cat.leavingPose, "")
            // And no time at all, when asked for none.
            brain.setPose("sit", "", 0)
            compare(cat.fade, 1)
            compare(cat.shownPose, "sit")
        }
        function test_aWalkerStridesAsFarAsItWalksAndEasesIn() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            const cat = findChild(pet, "petCat")
            brain.setPose("walk", "", 0)
            tryVerify(function() { return findChild(cat, "pose-walk") !== null })
            const walk = findChild(cat, "pose-walk")
            // Not walking: it stands, the legs straight down.
            compare(cat.gait, 0)
            tryCompare(walk, "amp", 0, 1000)
            compare(walk.legA, 0); compare(walk.legB, 0)
            // Walking: the stride comes in over a moment, not at once.
            brain.walking = true
            compare(cat.gait, 1)
            verify(walk.amp < 1)
            tryVerify(function() { return walk.amp > .98 }, 2000)
            // The legs follow the ground: half a stride apart, a whole one every strideLength.
            brain.stridePhase = 0
            compare(Math.round(walk.legA), 20); compare(Math.round(walk.legB), -20)
            brain.stridePhase = .5
            compare(Math.round(walk.legA), -20); compare(Math.round(walk.legB), 20)
            const before = brain.stridePhase
            brain.catX += brain.strideLength / 2
            verify(Math.abs(brain.stridePhase - (before + .5)) < 1e-6, "phase " + brain.stridePhase)
            // Standing still on the ground, the legs do not move.
            brain.walking = false
            const kept = brain.stridePhase
            brain.catX += 100
            compare(brain.stridePhase, kept)
            tryCompare(walk, "amp", 0, 2000)
            // The stand pose is the same walker, striding not at all even when told to walk.
            brain.walking = true
            brain.setPose("stand", "", 0)
            tryCompare(walk, "amp", 0, 2000)
            brain.walking = false
        }
        function test_movesStartAndEndGently() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            brain.tempo = 1.25
            stand(brain, .3)
            // A long walk: speeding up for a moment, a steady pace, slowing down.
            const start = brain.catX
            brain.travelTo(start + 500, brain.walkSpeed, brain.t(700), brain.t(900), true)
            const plan = brain.plan
            verify(plan.accelMs > 600 && plan.decelMs > 800 && plan.cruiseMs > 0, JSON.stringify(plan))
            compare(plan.topSpeed, brain.walkSpeed)
            verify(Math.abs(plan.accelDistance + plan.decelDistance + plan.cruiseMs / 1000 * plan.topSpeed - 500) < 1)
            verify(brain.walking)
            // It really does start slowly: after a tenth of a second it has hardly moved.
            wait(100)
            verify(brain.catX - start < 3, "moved " + (brain.catX - start) + " in 0.1 s")
            brain.stop(); brain.walking = false
            // A short way: a lower top speed, still starting and ending gently.
            brain.travelTo(brain.catX + 20, brain.walkSpeed, brain.t(700), brain.t(900), true)
            verify(brain.plan.topSpeed < brain.walkSpeed * .6, "top speed " + brain.plan.topSpeed)
            verify(Math.abs(brain.plan.accelDistance + brain.plan.decelDistance - 20) < .5)
            brain.stop(); brain.walking = false
            // A stroll is a stroll: about half a cat's length a second, less when lazy.
            verify(brain.walkSpeed <= brain.catW * .5, "stroll " + brain.walkSpeed)
            brain.tempo = 2.1
            verify(brain.walkSpeed <= brain.catW * .25, "lazy stroll " + brain.walkSpeed)
        }
        function test_itTurnsToFaceWhereItGoesBeforeItSetsOff() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            const cat = findChild(pet, "petCat")
            stand(brain, .6)
            brain.facing = 1
            tryCompare(cat, "flip", 1, 2000)
            const at = brain.catX
            brain.tempo = 1.25
            brain.travelTo(at - 300, brain.walkSpeed, 700, 900, true)
            compare(brain.facing, -1)
            // Not a step while it is still turning (a walk backwards).
            wait(150)
            compare(brain.catX, at)
            tryCompare(cat, "flip", -1, 2000)
            tryVerify(function() { return brain.catX < at - 1 }, 3000)
            brain.stop(); brain.walking = false
        }
        function test_aLazyCatIsSlowerAtEverything() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            verify(brain.tempoFor(0) > brain.tempoFor(.5) * 1.5)
            verify(brain.tempoFor(.5) > brain.tempoFor(.95) * 1.2)
            // The same change of pose takes a lazy cat much longer than a brisk one.
            brain.chance = function() { return 0 }
            brain.begin("groom")
            compare(brain.tempo, brain.tempoFor(0))
            const lazy = brain.blendMs
            brain.chance = function() { return .5 }
            brain.begin("groom")
            const usual = brain.blendMs
            brain.chance = function() { return .95 }
            brain.begin("groom")
            const brisk = brain.blendMs
            verify(lazy > usual * 1.5 && usual > brisk * 1.2 && lazy > 1000, lazy + " " + usual + " " + brisk)
            // A lazy walk is slower, a brisk one faster.
            brain.tempo = brain.tempoFor(0); const slow = brain.walkSpeed
            brain.tempo = brain.tempoFor(.5); const normal = brain.walkSpeed
            brain.tempo = brain.tempoFor(.95); const quick = brain.walkSpeed
            verify(slow < normal && normal < quick)
            // What happens in Owelk is quick, whatever the cat is like.
            brain.chance = function() { return 0 }
            brain.begin("aiReady")
            compare(brain.tempo, 1)
        }
        function test_crouchAndLeapRunIntoTheGallop() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            const cat = findChild(pet, "petCat")
            brain.setPose("run", "", 0)
            tryVerify(function() { return findChild(cat, "pose-run") !== null })
            const run = findChild(cat, "pose-run")
            compare(cat.crouchBlend, 0)
            verify(run.gw > .99)
            // Crouching comes on over a moment, not at once ...
            brain.crouch = true
            verify(cat.crouchBlend < .5)
            tryVerify(function() { return cat.crouchBlend > .98 }, 1500)
            verify(run.gw < .03)
            // ... and runs into the leap as it goes, and into the gallop after it.
            brain.crouch = false; brain.leap = true
            verify(cat.crouchBlend > .5, "still crouching a moment: " + cat.crouchBlend)
            tryVerify(function() { return cat.leapBlend > .98 && cat.crouchBlend < .02 }, 1500)
            brain.leap = false
            tryVerify(function() { return run.gw > .98 }, 1500)
        }
        function test_turningRoundTakesAMoment() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            const cat = findChild(pet, "petCat")
            brain.setPose("sit", "", 0)
            brain.facing = 1
            tryCompare(cat, "flip", 1, 2000)
            verify(!cat.looksLeft)
            // It narrows to a line and widens the other way: not a mirror image from one frame to the next.
            brain.facing = -1
            let narrow = false
            for (let i = 0; i < 80 && cat.flip > -1; ++i) { wait(8); if (Math.abs(cat.flip) < .6) narrow = true }
            verify(narrow, "it was turning for a while")
            tryCompare(cat, "flip", -1, 2000)
            verify(cat.looksLeft)
            // The drawing takes it as turned only from the middle of the turn.
            brain.facing = 1
            tryCompare(cat, "flip", 1, 2000)
        }
        function test_aDragEndsWhenTheButtonIsUp() {
            // With a hand on the pointer the window follows it each frame; the button coming up (there is none
            // here) ends it, also for the tower, whether or not the window got the release as an event.
            const pet = createTemporaryObject(petComponent, null, {followPointer: true})
            const brain = findChild(pet, "petBrain")
            brain.autoRun = false; brain.stop(); brain.halted = false
            const towerWin = findChild(pet, "petTowerWindow")
            pet.beginDrag(Qt.point(10, 10))
            verify(pet.dragging)
            tryVerify(function() { return !pet.dragging }, 2000)
            verify(!brain.halted)
            towerWin.beginDrag(Qt.point(10, 10))
            verify(towerWin.dragging)
            tryVerify(function() { return !towerWin.dragging }, 2000)
        }
        function test_everyPoseDrawsWithinItsWindow() {
            const shots = testInput.petShotsFolder()
            const poses = ["sit", "groom", "knead", "walk", "stand", "run", "sleep", "sleepBack", "belly", "stretch", "arch"]
            for (let i = 0; i < poses.length; ++i) {
                // A pet for each pose, so no pose leaves anything behind in the next.
                const pet = quietPet()
                const brain = findChild(pet, "petBrain")
                const towerWin = findChild(pet, "petTowerWindow")
                const sleeping = poses[i] === "sleep" || poses[i] === "sleepBack"
                if (sleeping) { brain.onTower = true; brain.settle() }
                brain.setPose(poses[i], "", 0)
                tryVerify(function() { return findChild(pet, "petCat").shownPose === poses[i] })
                wait(600)
                const content = findChild(pet, "petContent")
                let saved = false, clear = false
                content.grabToImage(function(result) {
                    // Nothing is cut off at the edge of the window.
                    clear = testInput.edgeIsClear(result.image, 2)
                    saved = result.saveToFile(shots + "/" + poses[i] + ".png")
                })
                tryVerify(function() { return saved }, 3000)
                verify(clear, poses[i] + " reaches the edge of its window")
                if (sleeping) {
                    // The tower it sleeps on, and where it is in relation to the cat's window.
                    let towerSaved = false
                    findChild(towerWin, "petTowerContent").grabToImage(function(result) { towerSaved = result.saveToFile(shots + "/tower.png") })
                    tryVerify(function() { return towerSaved }, 3000)
                    testInput.writeText(shots + "/" + poses[i] + ".txt", (towerWin.x - pet.x) + " " + (towerWin.y - pet.y) + "\n")
                }
            }
        }
        function test_aGallopInEitherDirectionIsNotCutOff() {
            // The tail thrown back goes furthest outside the cat's own box; look at a whole stride, both ways.
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            const cat = findChild(pet, "petCat")
            const content = findChild(pet, "petContent")
            for (const facing of [-1, 1]) {
                brain.facing = facing
                brain.setPose("run", "", 0)
                tryCompare(cat, "flip", facing, 2000)
                wait(300)
                for (let i = 0; i < 24; ++i) {
                    wait(14)
                    let clear = null
                    content.grabToImage(function(result) { clear = testInput.edgeIsClear(result.image, 1) })
                    tryVerify(function() { return clear !== null }, 3000)
                    verify(clear, "cut off at the edge, facing " + facing + ", sample " + i)
                }
            }
        }
        function test_noPoseIsCutOffFacingEitherWay() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            const cat = findChild(pet, "petCat")
            const content = findChild(pet, "petContent")
            for (const facing of [-1, 1]) {
                brain.facing = facing
                tryCompare(cat, "flip", facing, 2000)
                for (const pose of ["sit", "groom", "knead", "walk", "stand", "run", "sleep", "sleepBack", "belly", "stretch", "arch"]) {
                    brain.setPose(pose, "", 0)
                    tryCompare(cat, "shownPose", pose)
                    wait(120)
                    let clear = null
                    content.grabToImage(function(result) { clear = testInput.edgeIsClear(result.image, 1) })
                    tryVerify(function() { return clear !== null }, 3000)
                    verify(clear, pose + " is cut off at the edge facing " + facing)
                }
            }
        }
        function test_nothingTheCatDoesIsCutOffAtTheWindow() {
            const pet = quietPet()
            const bob = findChild(pet, "petBob")
            // At its widest and highest the cat stays inside: a hop, a shake, a stretch with its paws forward.
            verify(bob.x >= 0 && bob.x + pet.catW <= pet.width, "wide enough")
            verify(pet.marginX >= pet.catW * .1)
            verify(pet.headroom >= pet.catH * (.34 + .05 + .02), "room above for a hop: " + pet.headroom)
            verify(pet.height >= pet.feetOffset + pet.catH * 8 / 180, "room below the feet")
            // And the bubble above it is a window of its own, so a long one is not cut either.
            verify(findChild(pet, "petBubble") !== null)
        }
    }
}
