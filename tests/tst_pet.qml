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
            DesktopPet.dormant = false
            researchStore.setSetting("pet.position", "")
        }
        function asleep(brain) { return brain.pose === "sleep" || brain.pose === "sleepBack" }
        // A pet that does nothing by itself: the test says what it does.
        function quietPet(props) {
            const pet = createTemporaryObject(petComponent, null, props || {})
            const brain = findChild(pet, "petBrain")
            brain.autoRun = false
            brain.stop()
            brain.halted = false
            return pet
        }
        function test_petIsNamedAndFloatsWhereItWasLeft() {
            verify(DesktopPet.supported, "only Wayland has no pet")
            compare(DesktopPet.englishName, "Allmeng-E")
            compare(DesktopPet.name, "알맹이")
            const pet = quietPet()
            verify(pet.visible)
            compare(pet.title, "알맹이")
            compare(pet.catH, 160)
            compare(pet.height, pet.headroom + findChild(pet, "petBrain").towerHeight + 160)
            const first = DesktopPet.place(pet.width, pet.height)
            compare(pet.x, first.x); compare(pet.y, first.y)
            // Left somewhere, it comes back there.
            pet.x = first.x - 300; pet.y = first.y - 200
            const brain = findChild(pet, "petBrain")
            brain.catX = first.x - 300
            tryVerify(function() { return researchStore.setting("pet.position") === (first.x - 300) + "," + (first.y - 200) })
            const again = quietPet()
            compare(again.x, first.x - 300); compare(again.y, first.y - 200)
            // A place no screen shows any more falls back to the corner.
            researchStore.setSetting("pet.position", "-90000,-90000")
            verify(DesktopPet.place(60, 160).x > -90000)
            // A new size keeps the feet where they were.
            const feet = pet.y + pet.height
            DesktopPet.size = "small"
            compare(pet.catH, 120)
            tryCompare(pet, "height", pet.headroom + findChild(pet, "petBrain").towerHeight + 120)
            tryVerify(function() { return pet.y + pet.height === feet })
            compare(researchStore.setting("pet.size"), "small")
            openSpy.target = pet
            mouseClick(pet.contentItem)
            compare(openSpy.count, 1)
            // Its menu has the app's colors, not the system's (white text in dark mode): the menu opens in
            // a window of its own, which does not take the pet window's colors.
            const menu = findChild(pet, "petMenu")
            menu.popup()
            tryCompare(menu, "opened", true)
            const row = findChild(menu, "hidePet")
            compare(row.text, "Hide Allmeng-E")
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
            // A click dismisses it and opens nothing.
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
            threadSpy.target = pet
            waitForRendering(bubble.contentItem)
            mouseClick(bubble.contentItem)
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
            forYouSpy.target = pet
            mouseClick(pet.contentItem, pet.width / 2, pet.height - 10)
            compare(forYouSpy.count, 1)
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
            tryVerify(function() { return brain.away }, 3000)
            verify(!pet.visible)
            const out = brain.catX
            verify(out >= brain.screenLeft + brain.screenWidth || out + brain.windowWidth <= brain.screenLeft, "fully outside: " + out)
            compare(pet.message, null)
            tryVerify(function() { return !brain.away }, 30000)
            verify(pet.visible)
            tryVerify(function() { return !brain.running }, 10000)
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
            brain.catX = brain.screenLeft + brain.screenWidth * .2; brain.floorX = brain.catX
            brain.begin("zoomies")
            compare(brain.facing, 1)
            tryVerify(function() { return brain.away }, 3000)
            compare(brain.exitSide, 1)
            verify(brain.catX >= brain.screenLeft + brain.screenWidth)
            tryVerify(function() { return !brain.away && brain.pose === "walk" }, 30000)
            verify(brain.catX + brain.windowWidth <= brain.screenLeft + 50 || brain.catX < mid, "enters at the left: " + brain.catX)
            compare(brain.facing, 1)
            tryVerify(function() { return !brain.running }, 10000)
            // On the right half, the other way.
            brain.catX = brain.screenLeft + brain.screenWidth * .8; brain.floorX = brain.catX
            brain.begin("zoomies")
            compare(brain.facing, -1)
            tryVerify(function() { return brain.away }, 3000)
            compare(brain.exitSide, -1)
            verify(brain.catX + brain.windowWidth <= brain.screenLeft)
            tryVerify(function() { return !brain.running }, 30000)
            verify(brain.catX > brain.screenLeft)
        }
        function test_aSleeperHasATowerAndLeapsUp() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            const tower = findChild(pet, "petContent").children[0]
            brain.pace = 600
            brain.catX = brain.screenLeft + brain.screenWidth * .3; brain.floorX = brain.catX
            compare(brain.towerShown, false)
            brain.begin("nap")
            tryVerify(function() { return brain.towerShown }, 1000)
            tryVerify(function() { return asleep(brain) }, 3000)
            verify(brain.onTower)
            compare(brain.lift, brain.towerHeight)
            compare(brain.catX, brain.catXOnTower)
            tryCompare(tower, "opacity", 1, 1000)
            // The nap is five to twenty minutes long (at pace 600: half a second to two).
            // Then it is down again and the tower goes.
            tryVerify(function() { return !asleep(brain) }, 5000)
            brain.begin("wander")
            tryVerify(function() { return !brain.onTower }, 2000)
            tryVerify(function() { return !brain.towerShown }, 4000)
        }
        function test_theTowerIsBesideTheCatAndThenUnderIt() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            const tower = findChild(pet, "petTower")
            const art = findChild(pet, "petCat")
            brain.pace = 600
            brain.catX = brain.screenLeft + brain.screenWidth * .3; brain.floorX = brain.catX
            brain.begin("nap")
            tryVerify(function() { return brain.towerShown }, 1000)
            // Before the leap the tower stands to the right of the cat, touching its spot.
            const catCenter = function() { return pet.catOffset + pet.catW / 2 }
            verify(brain.pose === "sit" || brain.onTower)
            tryVerify(function() { return brain.onTower }, 2000)
            tryVerify(function() { return asleep(brain) }, 3000)
            // Up there it is right under the cat (the window went along with it).
            compare(Math.round(tower.x + tower.width / 2), Math.round(catCenter()))
            compare(brain.lift, brain.towerHeight)
            // The tower top is where its feet stand.
            compare(Math.round(tower.y), Math.round(pet.headroom + brain.towerHeight + pet.catH * 172 / 180 - brain.towerHeight))
            brain.stop()
            // Standing on the floor it is beside it.
            brain.onTower = false; brain.towerShown = true; brain.lift = 0; brain.catX = brain.floorX
            compare(Math.round(tower.x + tower.width / 2 - catCenter()), Math.round(brain.towerSide * pet.catW * .95))
        }
        function test_theTowerStandsOnTheSideWithRoom() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            brain.pace = 600
            brain.catX = brain.maxX; brain.floorX = brain.catX
            brain.begin("nap")
            tryVerify(function() { return brain.towerShown }, 1000)
            compare(brain.towerSide, -1)
            // The window grows to the left so the cat stays where it is.
            compare(pet.catOffset, pet.towerRoom)
            compare(pet.x, Math.round(brain.catX - pet.towerRoom))
            brain.stop()
        }
        function test_aNapperCarriedAwayStaysWhereItIsPut() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            brain.pace = 600
            brain.catX = brain.screenLeft + brain.screenWidth * .3; brain.floorX = brain.catX
            brain.begin("nap")
            tryVerify(function() { return asleep(brain) }, 3000)
            pet.dragging = true; brain.halt()
            pet.x = 300; pet.y = 250
            pet.dropped()
            compare(brain.catX, 300 + pet.catOffset)
            // The tower goes along; it does not pull the cat back to where it was.
            wait(100)
            compare(brain.catX, 300 + pet.catOffset)
            compare(brain.lift, brain.towerHeight)
            compare(brain.catXOnTower, brain.catX)
            brain.stop()
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
            tryVerify(function() { return !brain.running }, 40000)
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
                brain.setPose(pose)
                tryVerify(function() { return letters(cat, []).length === 3 })
                // The cat is turned around (mirrored); each letter is turned back.
                compare(letters(cat, []).map(function(z) { return z.transform[0].xScale }), [1, 1, 1])
                brain.facing = -1
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
            brain.catX = brain.screenLeft + brain.screenWidth * .3; brain.floorX = brain.catX
            brain.chance = function() { return .9 }
            brain.begin("nap")
            tryVerify(function() { return brain.pose === "sleepBack" }, 3000)
            verify(brain.onTower)
            brain.stop()
            const other = quietPet()
            const again = findChild(other, "petBrain")
            again.pace = 600
            again.catX = again.screenLeft + again.screenWidth * .3; again.floorX = again.catX
            again.chance = function() { return .1 }
            again.begin("nap")
            tryVerify(function() { return again.pose === "sleep" }, 3000)
            again.stop()
        }
        function test_aBackTurnedSleeperBreathesAndOnlyNowAndThenMoves() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            const cat = findChild(pet, "petCat")
            // Nothing in it is on a short cycle: the ear and the tail tip wait tens of seconds.
            cat.quietMin = 1000000; cat.quietMax = 1000000
            brain.setPose("sleepBack")
            tryVerify(function() { return findChild(cat, "petSleepBack") !== null })
            const back = findChild(cat, "petSleepBack")
            compare(back.earMove, 1); compare(back.tailMove, 1)
            compare(back.earAngle, 0); compare(back.tailAngle, 0)
            // Redrawn only as often as breathing needs.
            wait(400)
            frameSpy.target = pet; frameSpy.clear()
            wait(1500)
            verify(frameSpy.count > 0 && frameSpy.count <= 20, "back turned: " + frameSpy.count + " frames in 1.5 s")
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
            brain.catX = brain.screenLeft + brain.screenWidth * .3; brain.floorX = brain.catX
            brain.begin("wander")
            tryVerify(function() { return brain.pose === "walk" }, 1000)
            pet.dragging = true; brain.halt()
            const held = brain.catX
            wait(300)
            compare(brain.catX, held)
            compare(brain.pose, "sit")
            // Put down somewhere else: that is where its line is now.
            pet.x = 400; pet.y = 300
            pet.dropped()
            compare(brain.catX, 400 + pet.catOffset)
            compare(pet.y, 300)
            verify(!brain.halted)
        }
        function test_nothingMovesWhileTheScreenIsLockedOrOwelkHidden() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            brain.pace = 6
            brain.catX = brain.screenLeft + brain.screenWidth * .3; brain.floorX = brain.catX
            brain.begin("wander")
            tryVerify(function() { return brain.pose === "walk" }, 1000)
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
            brain.setPose("sit")
            wait(400)
            frameSpy.target = pet; frameSpy.clear()
            wait(1500)
            verify(frameSpy.count <= 2, "sitting: " + frameSpy.count + " frames in 1.5 s")
            brain.setPose("sleep")
            wait(400)
            frameSpy.clear()
            wait(1500)
            verify(frameSpy.count > 0 && frameSpy.count <= 20, "sleeping: " + frameSpy.count + " frames in 1.5 s")
        }
        function test_clicksOnTheTransparentPartsGoThrough() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            brain.setPose("sit")
            tryVerify(function() { const a = DesktopPet.clickArea(pet); return a.width > 0 && a.width < pet.width }, 3000)
            const sitting = DesktopPet.clickArea(pet)
            verify(sitting.height < pet.height, "the headroom is clear: " + sitting.height + " of " + pet.height)
            // A new pose, another place: the area is worked out again.
            brain.setPose("stretch")
            tryVerify(function() { const a = DesktopPet.clickArea(pet); return a.width !== sitting.width || a.height !== sitting.height }, 3000)
        }
        function test_thePawsKeepTheirMarksWhenItTurns() {
            const pet = quietPet()
            const brain = findChild(pet, "petBrain")
            const cat = findChild(pet, "petCat")
            brain.setPose("sit")
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
            compare(marks(), ["far:toes", "near:glove"])
        }
        function test_everyPoseDraws() {
            const shots = testInput.petShotsFolder()
            const poses = ["sit", "groom", "knead", "walk", "run", "sleep", "sleepBack", "belly", "stretch", "arch"]
            for (let i = 0; i < poses.length; ++i) {
                // A pet for each pose, so no pose leaves anything behind in the next.
                const pet = quietPet()
                const brain = findChild(pet, "petBrain")
                brain.setPose(poses[i], "")
                if (poses[i] === "sleep" || poses[i] === "sleepBack") { brain.towerShown = true; brain.onTower = true; brain.towerSide = 1; brain.lift = brain.towerHeight; brain.catX = brain.catXOnTower }
                tryVerify(function() { return findChild(pet, "petCat").children.length > 0 })
                wait(450)
                const cat = findChild(pet, "petContent")
                let saved = false
                cat.grabToImage(function(result) { saved = result.saveToFile(shots + "/" + poses[i] + ".png") })
                tryVerify(function() { return saved }, 3000)
            }
        }
    }
}
