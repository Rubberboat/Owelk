#include "WindowChrome.h"

#include <QWindow>

#ifdef Q_OS_WIN
#include <QGuiApplication>
#include <QStyleHints>
#include <windows.h>
#include <dwmapi.h>
#endif

// macOS: WindowChromeMac.mm.
#ifndef Q_OS_MACOS
void WindowChrome::apply(QWindow *window, bool follow, const QColor &color, const QColor &text, bool dark)
{
#ifdef Q_OS_WIN
    if (!window) return;
    const auto hwnd = reinterpret_cast<HWND>(window->winId());
    // dwmapi.h numbers (named constants are missing from older SDKs). Dark mode: Windows 10 2004 and
    // later; caption, text and border colors: Windows 11, earlier versions ignore them.
    constexpr DWORD darkMode = 20, borderColor = 34, captionColor = 35, textColor = 36;
    constexpr COLORREF systemColor = 0xFFFFFFFF;
    const auto colorRef = [](const QColor &c) { return COLORREF(RGB(c.red(), c.green(), c.blue())); };
    const BOOL useDark = follow ? dark : QGuiApplication::styleHints()->colorScheme() == Qt::ColorScheme::Dark;
    DwmSetWindowAttribute(hwnd, darkMode, &useDark, sizeof useDark);
    const COLORREF caption = follow ? colorRef(color) : systemColor;
    const COLORREF title = follow ? colorRef(text) : systemColor;
    DwmSetWindowAttribute(hwnd, captionColor, &caption, sizeof caption);
    DwmSetWindowAttribute(hwnd, borderColor, &caption, sizeof caption);
    DwmSetWindowAttribute(hwnd, textColor, &title, sizeof title);
#else
    Q_UNUSED(window)
    Q_UNUSED(follow)
    Q_UNUSED(color)
    Q_UNUSED(text)
    Q_UNUSED(dark)
#endif
}
#endif
