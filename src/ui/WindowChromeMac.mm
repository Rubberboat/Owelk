#include "WindowChrome.h"

#include <QWindow>
#import <AppKit/AppKit.h>

void WindowChrome::apply(QWindow *window, bool follow, const QColor &color, const QColor &, bool dark)
{
    if (!window) return;
    @autoreleasepool {
        NSView *view = (__bridge NSView *)reinterpret_cast<void *>(window->winId());
        NSWindow *frame = view.window;
        if (!frame) return;
        // A transparent title bar shows the window's background color: the theme's, without the line
        // under it. The window's appearance gives the buttons the matching light or dark look.
        frame.titlebarAppearsTransparent = follow;
        frame.backgroundColor = follow ? [NSColor colorWithSRGBRed:color.redF()
                                                             green:color.greenF()
                                                              blue:color.blueF()
                                                             alpha:1]
                                       : [NSColor windowBackgroundColor];
        frame.appearance = follow ? [NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua]
                                  : nil;
        if (@available(macOS 11.0, *))
            frame.titlebarSeparatorStyle = follow ? NSTitlebarSeparatorStyleNone : NSTitlebarSeparatorStyleAutomatic;
    }
}
