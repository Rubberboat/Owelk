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

bool desktopPetLeftButtonDown()
{
    return ([NSEvent pressedMouseButtons] & 1) != 0;
}

// The screen locked or asleep, or Owelk hidden (Command+H): told once when that starts or ends, not polled.
void desktopPetWatchDormancy(DesktopPet *pet)
{
    if (!pet || QGuiApplication::platformName() != QLatin1String("cocoa")) return;
    static bool hidden = false, locked = false, asleep = false;
    const QPointer<DesktopPet> guard(pet);
    auto tell = [guard] {
        if (guard) guard->setDormant(hidden || locked || asleep);
    };
    // Built without ARC: the observers live as long as the program, so they are kept.
    auto watch = [&](NSNotificationCenter *center, NSString *name, bool *flag, bool value) {
        [[center addObserverForName:name
                             object:nil
                              queue:[NSOperationQueue mainQueue]
                         usingBlock:^(NSNotification *) {
                             *flag = value;
                             tell();
                         }] retain];
    };
    NSNotificationCenter *app = [NSNotificationCenter defaultCenter];
    NSNotificationCenter *workspace = [[NSWorkspace sharedWorkspace] notificationCenter];
    NSNotificationCenter *distributed = [NSDistributedNotificationCenter defaultCenter];
    watch(app, NSApplicationDidHideNotification, &hidden, true);
    watch(app, NSApplicationDidUnhideNotification, &hidden, false);
    watch(workspace, NSWorkspaceScreensDidSleepNotification, &asleep, true);
    watch(workspace, NSWorkspaceScreensDidWakeNotification, &asleep, false);
    watch(distributed, @"com.apple.screenIsLocked", &locked, true);
    watch(distributed, @"com.apple.screenIsUnlocked", &locked, false);
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
