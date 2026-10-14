#pragma once

#include <QColor>

class QWindow;

// The title bar the system draws above the window (the strip with the close, minimize and zoom
// buttons). With `follow` it takes the theme's window color, with light or dark buttons and title to
// match: macOS, and Windows 11 (Windows 10 only switches between light and dark). Without it the
// system's own title bar comes back. Elsewhere it does nothing.
namespace WindowChrome {
void apply(QWindow *window, bool follow, const QColor &color, const QColor &text, bool dark);
}
