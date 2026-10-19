#include "DesktopPet.h"
#include "ResearchStore.h"
#include <QGuiApplication>
#include <QtMath>
#include <QRect>
#include <QScreen>
#include <QSurfaceFormat>
#include <QWindow>

#ifdef Q_OS_MACOS
// DesktopPetMac.mm
void desktopPetFloatEverywhere(QWindow *window);
bool desktopPetPassThrough(QWindow *window, const QRegion &region);
bool desktopPetLeftButtonDown();
void desktopPetWatchDormancy(DesktopPet *pet);
#endif

DesktopPet::DesktopPet(ResearchStore *store, QObject *parent) : QObject(parent), m_store(store)
{
#ifdef Q_OS_MACOS
    desktopPetWatchDormancy(this);
#endif
    if (!m_store) return;
    m_enabled = m_store->setting("pet.enabled") == "1";
    if (const auto size = m_store->setting("pet.size"); size == "small" || size == "large") m_size = size;
    const auto minutes = m_store->setting("pet.breakMinutes", "50").toInt();
    if (minutes == 0 || minutes == 25 || minutes == 90) m_breakMinutes = minutes;
}

void DesktopPet::save(const QString &key, const QString &value)
{
    if (m_store) m_store->setSetting(key, value);
}

void DesktopPet::setEnabled(bool on)
{
    if (on == m_enabled) return;
    m_enabled = on;
    save("pet.enabled", on ? "1" : "0");
    emit changed();
}

void DesktopPet::setSize(const QString &size)
{
    if ((size != "small" && size != "medium" && size != "large") || size == m_size) return;
    m_size = size;
    save("pet.size", size);
    emit changed();
}

void DesktopPet::setBreakMinutes(int minutes)
{
    if ((minutes != 0 && minutes != 25 && minutes != 50 && minutes != 90) || minutes == m_breakMinutes) return;
    m_breakMinutes = minutes;
    save("pet.breakMinutes", QString::number(minutes));
    emit changed();
}

void DesktopPet::setDormant(bool dormant)
{
    if (dormant == m_dormant) return;
    m_dormant = dormant;
    emit dormantChanged();
}

qreal DesktopPet::pace()
{
    bool ok = false;
    const auto value = qEnvironmentVariable("OWELK_PET_PACE").toDouble(&ok);
    return ok && value >= 1 && value <= 1000 ? value : 1;
}

QString DesktopPet::first()
{
    const auto name = qEnvironmentVariable("OWELK_PET_FIRST");
    static const QStringList known{"sit", "groom", "wander", "zoomies", "nap", "belly", "stretch"};
    return known.contains(name) ? name : QStringLiteral("sit");
}

int DesktopPet::height() const
{
    return m_size == "small" ? 120 : m_size == "large" ? 220 : 160;
}

bool DesktopPet::supported()
{
    return !QGuiApplication::platformName().startsWith(QLatin1String("wayland"));
}

QPoint DesktopPet::place(int width, int height) const
{
    const auto saved = m_store ? m_store->setting("pet.position").split(',') : QStringList();
    if (saved.size() == 2) {
        const QRect rect(saved[0].toInt(), saved[1].toInt(), width, height);
        // Still on a screen (one may have been unplugged since).
        for (const auto *screen : QGuiApplication::screens())
            if (screen->availableGeometry().contains(rect.center())) return rect.topLeft();
    }
    const auto *screen = QGuiApplication::primaryScreen();
    const QRect area = screen ? screen->availableGeometry() : QRect(0, 0, 1280, 800);
    return {area.x() + area.width() - width - 24, area.y() + area.height() - height - 24};
}

void DesktopPet::remember(int x, int y)
{
    save("pet.position", QString("%1,%2").arg(x).arg(y));
}

void DesktopPet::prepare(QWindow *window)
{
    if (!window) return;
    auto format = window->requestedFormat();
    format.setAlphaBufferSize(8);
    window->setFormat(format);
    // Qt::Tool windows hide while another app is active on macOS unless asked not to.
    window->setProperty("_q_macAlwaysShowToolWindow", true);
}

void DesktopPet::floatEverywhere(QWindow *window)
{
#ifdef Q_OS_MACOS
    desktopPetFloatEverywhere(window);
#else
    Q_UNUSED(window)
#endif
}

QRect DesktopPet::clickArea(QWindow *window) const
{
    if (!window) return {};
    return window->mask().isEmpty() ? QRect(QPoint(), window->size()) : window->mask().boundingRect();
}

bool DesktopPet::leftButtonDown() const
{
#ifdef Q_OS_MACOS
    return desktopPetLeftButtonDown();
#else
    return QGuiApplication::mouseButtons().testFlag(Qt::LeftButton);
#endif
}

QRegion DesktopPet::drawnRegion(const QImage &grabbed, const QSize &area, int rise)
{
    if (grabbed.isNull() || !grabbed.hasAlphaChannel() || area.isEmpty()) return {};
    const auto image = grabbed.convertToFormat(QImage::Format_ARGB32);
    // The grab may have more pixels than the window has points.
    const qreal sx = qreal(area.width()) / image.width(), sy = qreal(area.height()) / image.height();
    // A few points around what is drawn, so its soft edge always takes the click.
    constexpr int margin = 3;
    QRegion region;
    for (int y = 0; y < image.height(); ++y) {
        const auto *line = reinterpret_cast<const QRgb *>(image.constScanLine(y));
        for (int x = 0; x < image.width();) {
            if (qAlpha(line[x]) < 16) {
                ++x;
                continue;
            }
            int end = x;
            while (end < image.width() && qAlpha(line[end]) >= 16) ++end;
            const int left = qFloor(x * sx), right = qCeil(end * sx), top = qFloor(y * sy), rows = qCeil(sy);
            region += QRect(left - margin, top - margin - rise, right - left + 2 * margin, rows + 2 * margin + rise);
            x = end;
        }
    }
    return region;
}

void DesktopPet::letClicksThrough(QWindow *window, const QImage &image, const QSize &area, int rise)
{
    if (!window) return;
    const auto region = drawnRegion(image, area, rise);
#ifdef Q_OS_MACOS
    // A shape (mask) on macOS clips the drawing but still takes every click in the window's frame.
    if (desktopPetPassThrough(window, region)) return;
#endif
    window->setMask(region);
}
