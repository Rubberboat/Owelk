#pragma once

#include <QImage>
#include <QObject>
#include <QPoint>
#include <QRegion>
#include <QSize>

class QWindow;
class ResearchStore;

// The desktop pet (QML: DesktopPet): a tuxedo cat drawn in a small window that floats above other apps
// while Owelk runs. Its switch, size and place are kept with the settings.
class DesktopPet : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY changed)
    // "small", "medium" or "large"; height is the cat's height in points for it.
    Q_PROPERTY(QString size READ size WRITE setSize NOTIFY changed)
    Q_PROPERTY(int height READ height NOTIFY changed)
    // After this many minutes of reading in Owelk the pet suggests a break: 0 (never), 25, 50 or 90.
    Q_PROPERTY(int breakMinutes READ breakMinutes WRITE setBreakMinutes NOTIFY changed)
    // Not on Wayland, where a window can neither stay above others nor say where it goes.
    Q_PROPERTY(bool supported READ supported CONSTANT)
    // The screen is locked or asleep, or Owelk is hidden (macOS): the pet stops whatever it does.
    Q_PROPERTY(bool dormant READ dormant WRITE setDormant NOTIFY dormantChanged)

public:
    explicit DesktopPet(ResearchStore *store = nullptr, QObject *parent = nullptr);

    bool enabled() const { return m_enabled; }
    void setEnabled(bool on);
    QString size() const { return m_size; }
    void setSize(const QString &size);
    int height() const;
    int breakMinutes() const { return m_breakMinutes; }
    void setBreakMinutes(int minutes);
    static bool supported();
    bool dormant() const { return m_dormant; }
    void setDormant(bool dormant);

    // Where a pet window of this size goes: where it was left while that is still on a screen, else the
    // bottom right of the main screen.
    Q_INVOKABLE QPoint place(int width, int height) const;
    Q_INVOKABLE void remember(int x, int y);
    // Before a pet window (or its speech bubble) is first shown: a transparent surface, and on macOS
    // kept on screen while another app is in front.
    Q_INVOKABLE void prepare(QWindow *window);
    // Once shown, on macOS: on every desktop (Space) and beside full-screen apps, left out of window
    // cycling. Elsewhere staying on top is all there is.
    Q_INVOKABLE void floatEverywhere(QWindow *window);
    // Clicks on the transparent parts of a pet window go to whatever is behind it. image is the window's
    // content as drawn (a grab of it), area its size in points; the cat may hop up to rise points.
    Q_INVOKABLE void letClicksThrough(QWindow *window, const QImage &image, const QSize &area, int rise);
    // The part that takes clicks, in window points: where something is drawn, a little around it and up
    // as far as it hops. Empty for an image with no transparency or nothing drawn (all of the window
    // takes them).
    static QRegion drawnRegion(const QImage &image, const QSize &area, int rise);
    // Whether the left mouse button is down now, also while the system moves a window (a drag).
    Q_INVOKABLE bool leftButtonDown() const;

signals:
    void changed();
    void dormantChanged();

private:
    void save(const QString &key, const QString &value);
    ResearchStore *m_store = nullptr;
    bool m_enabled = false;
    bool m_dormant = false;
    QString m_size = "medium";
    int m_breakMinutes = 50;
};
