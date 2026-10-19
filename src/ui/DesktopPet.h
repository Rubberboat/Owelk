#pragma once

#include <QImage>
#include <QObject>
#include <QPoint>
#include <QRect>
#include <QRegion>
#include <QSize>

class QWindow;
class ResearchStore;

// The desktop pet (QML: DesktopPet): a tuxedo cat drawn in a small window that floats above other apps
// while Owelk runs. Its switch, size and place are kept with the settings.
class DesktopPet : public QObject {
    Q_OBJECT
    // The pet's name: 알맹이, Allmeng-E in English text.
    Q_PROPERTY(QString name READ name CONSTANT)
    Q_PROPERTY(QString englishName READ englishName CONSTANT)
    // How much faster than real time the pet lives: 1, unless OWELK_PET_PACE says otherwise (to watch it all
    // in a short time).
    Q_PROPERTY(qreal pace READ pace CONSTANT)
    // What it does first when it appears: sit, unless OWELK_PET_FIRST names another (nap, groom ...).
    Q_PROPERTY(QString first READ first CONSTANT)
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY changed)
    // "small", "medium" or "large"; height is the cat's height in points for it.
    Q_PROPERTY(QString size READ size WRITE setSize NOTIFY changed)
    Q_PROPERTY(int height READ height NOTIFY changed)
    // After this many minutes of reading in Owelk the pet suggests a break: 0 (never), 25, 50 or 90.
    Q_PROPERTY(int breakMinutes READ breakMinutes WRITE setBreakMinutes NOTIFY changed)
    // Not on Wayland, where a window can neither stay above others nor say where it goes.
    Q_PROPERTY(bool supported READ supported CONSTANT)
    // The cat tower: "always" (it stands where the user put it) or "sleeping" (it comes there for a nap).
    Q_PROPERTY(QString towerMode READ towerMode WRITE setTowerMode NOTIFY changed)
    // The screen is locked or asleep, or Owelk is hidden (macOS): the pet stops whatever it does.
    Q_PROPERTY(bool dormant READ dormant WRITE setDormant NOTIFY dormantChanged)

public:
    explicit DesktopPet(ResearchStore *store = nullptr, QObject *parent = nullptr);

    static QString name() { return QString::fromUtf8("\xec\x95\x8c\xeb\xa7\xb9\xec\x9d\xb4"); }
    static QString englishName() { return QStringLiteral("Allmeng-E"); }
    static qreal pace();
    static QString first();
    bool enabled() const { return m_enabled; }
    void setEnabled(bool on);
    QString size() const { return m_size; }
    void setSize(const QString &size);
    int height() const;
    int breakMinutes() const { return m_breakMinutes; }
    void setBreakMinutes(int minutes);
    static bool supported();
    QString towerMode() const { return m_towerMode; }
    void setTowerMode(const QString &mode);
    bool dormant() const { return m_dormant; }
    void setDormant(bool dormant);

    // Where a pet window of this size goes: where it was left while that is still on a screen, else the
    // bottom right of the main screen.
    Q_INVOKABLE QPoint place(int width, int height) const;
    Q_INVOKABLE void remember(int x, int y);
    // Where the tower stands (the middle of its base): where the user left it while that is still on a
    // screen, else the place given.
    Q_INVOKABLE QPoint towerPlace(int defaultX, int defaultY) const;
    Q_INVOKABLE void rememberTower(int x, int y);
    // The pointer, in screen points; and a window moved to a place in one step (a drag follows the pointer).
    Q_INVOKABLE QPoint cursor() const;
    Q_INVOKABLE void move(QWindow *window, int x, int y) const;
    // A window in front of the other pet window, without bringing Owelk forward (raise() on macOS does).
    Q_INVOKABLE void raiseWindow(QWindow *window) const;
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
    // The smallest rectangle of the window that takes clicks (the whole window when none is set).
    Q_INVOKABLE QRect clickArea(QWindow *window) const;
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
    QString m_towerMode = "always";
    int m_breakMinutes = 50;
};
