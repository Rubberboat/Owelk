#include "DesktopPet.h"
#include <QCursor>
#include <QGuiApplication>
#include <QHash>
#include <QPointer>
#include <QRegion>
#include <QWindow>
#import <AppKit/AppKit.h>

void desktopPetFloatEverywhere(QWindow *window)
{
    // Only real Cocoa windows (not the offscreen platform tests use).
    if (!window || QGuiApplication::platformName() != QLatin1String("cocoa")) return;
    @autoreleasepool {
        NSWindow *native = reinterpret_cast<NSView *>(window->winId()).window;
        if (!native) return;
        native.collectionBehavior = (native.collectionBehavior & ~NSWindowCollectionBehaviorMoveToActiveSpace)
            | NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary
            | NSWindowCollectionBehaviorIgnoresCycle;
        native.hidesOnDeactivate = NO;
    }
}

void desktopPetOrderFront(QWindow *window)
{
    if (!window || QGuiApplication::platformName() != QLatin1String("cocoa")) return;
    @autoreleasepool {
        NSWindow *native = reinterpret_cast<NSView *>(window->winId()).window;
        [native orderFront:nil];
    }
}

bool desktopPetLeftButtonDown()
{
    return ([NSEvent pressedMouseButtons] & 1) != 0;
}

namespace {
// Why the pet is dormant; the notifications below set these, and the pet is told.
QPointer<DesktopPet> dormancyTarget;
bool appHidden = false, screenLocked = false, screensAsleep = false;
void tellDormancy()
{
    if (dormancyTarget) dormancyTarget->setDormant(appHidden || screenLocked || screensAsleep);
}
// Told of the lock at once (the plain observer API lets the system hold distributed notices back while the
// application is in the background, which is where the pet lives).
}
@interface PetLockObserver : NSObject
@end
@implementation PetLockObserver
- (void)locked:(NSNotification *)note { screenLocked = true; tellDormancy(); }
- (void)unlocked:(NSNotification *)note { screenLocked = false; tellDormancy(); }
@end
namespace {
void watchDormancy(NSNotificationCenter *center, NSString *name, bool *flag, bool value)
{
    // Built without ARC: the observers live as long as the program, so they are kept.
    [[center addObserverForName:name
                         object:nil
                          queue:[NSOperationQueue mainQueue]
                     usingBlock:^(NSNotification *) {
                         *flag = value;
                         tellDormancy();
                     }] retain];
}
}

// The screen locked or asleep, or Owelk hidden (Command+H): told once when that starts or ends, not polled.
void desktopPetWatchDormancy(DesktopPet *pet)
{
    if (!pet || QGuiApplication::platformName() != QLatin1String("cocoa")) return;
    const bool first = dormancyTarget.isNull();
    dormancyTarget = pet;
    if (!first) return;
    NSNotificationCenter *app = [NSNotificationCenter defaultCenter];
    NSNotificationCenter *workspace = [[NSWorkspace sharedWorkspace] notificationCenter];
    NSDistributedNotificationCenter *distributed = [NSDistributedNotificationCenter defaultCenter];
    watchDormancy(app, NSApplicationDidHideNotification, &appHidden, true);
    watchDormancy(app, NSApplicationDidUnhideNotification, &appHidden, false);
    watchDormancy(workspace, NSWorkspaceScreensDidSleepNotification, &screensAsleep, true);
    watchDormancy(workspace, NSWorkspaceScreensDidWakeNotification, &screensAsleep, false);
    PetLockObserver *lock = [[PetLockObserver alloc] init];
    [distributed addObserver:lock selector:@selector(locked:) name:@"com.apple.screenIsLocked" object:nil
          suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    [distributed addObserver:lock selector:@selector(unlocked:) name:@"com.apple.screenIsUnlocked" object:nil
          suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
}

namespace {
// Event monitors that let clicks through a pet window, and the part of it that takes them.
struct PassThrough {
    id global = nil, local = nil;
    QRegion region;
};
QHash<QWindow *, PassThrough> &passThroughs()
{
    static QHash<QWindow *, PassThrough> map;
    return map;
}
void stopPassingThrough(QWindow *window)
{
    const auto it = passThroughs().find(window);
    if (it == passThroughs().end()) return;
    // Built without ARC: the monitors were retained when added.
    for (id monitor : {it->global, it->local})
        if (monitor) {
            [NSEvent removeMonitor:monitor];
            [monitor release];
        }
    passThroughs().erase(it);
}
}

// Qt makes a window take every click in its frame, transparent or not, and a shape only clips its
// drawing. So the window ignores the mouse while the pointer is over a transparent part, and takes it
// again over the picture: decided on each mouse move (here or in another app), not by polling. False
// when this is not a Cocoa window (the caller shapes it instead).
bool desktopPetPassThrough(QWindow *window, const QRegion &region)
{
    if (!window || QGuiApplication::platformName() != QLatin1String("cocoa")) return false;
    @autoreleasepool {
        NSWindow *native = reinterpret_cast<NSView *>(window->winId()).window;
        if (!native) return false;
        const bool watched = passThroughs().contains(window);
        stopPassingThrough(window);
        native.ignoresMouseEvents = NO;
        if (region.isEmpty()) return true;
        if (!watched) QObject::connect(window, &QObject::destroyed, [window] { stopPassingThrough(window); });
        auto &entry = passThroughs()[window];
        entry.region = region;
        const QPointer<QWindow> guard(window);
        void (^update)(void) = ^{
            if (!guard) return;
            const auto it = passThroughs().constFind(guard.data());
            if (it == passThroughs().constEnd()) return;
            const bool over = it->region.contains(QCursor::pos() - guard->geometry().topLeft());
            NSWindow *shown = reinterpret_cast<NSView *>(guard->winId()).window;
            if (shown && shown.ignoresMouseEvents == over) shown.ignoresMouseEvents = !over;
        };
        const NSEventMask moves = NSEventMaskMouseMoved | NSEventMaskLeftMouseDragged | NSEventMaskRightMouseDragged;
        entry.global = [[NSEvent addGlobalMonitorForEventsMatchingMask:moves
                                                               handler:^(NSEvent *) {
                                                                   update();
                                                               }] retain];
        entry.local = [[NSEvent addLocalMonitorForEventsMatchingMask:moves
                                                             handler:^NSEvent *(NSEvent *event) {
                                                                 update();
                                                                 return event;
                                                             }] retain];
        update();
    }
    return true;
}
