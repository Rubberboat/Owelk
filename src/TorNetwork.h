#pragma once

#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QTimer>
#include <QUrl>
#include <QVariantList>

class QNetworkAccessManager;
class QTcpServer;
class ResearchStore;

// Settings › Web › Browse through Tor (off unless the reader turns it on). Owelk starts its own Tor and
// sends the web tabs (Home's web search too) through it, so sites see a Tor exit in another country
// instead of this computer. Nothing else goes that way: paper details, citations, AI and meaning
// search keep connecting as before (keepDirect).
//
// While it is on but Tor is not ready (starting, missing, stopped), web tabs get no connection rather
// than a direct one: the reader asked for Tor, so pages never quietly go out from here.
class TorNetwork : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled NOTIFY changed)
    // "off", "starting", "ready", "missing" (no tor program found) or "failed" (it stopped).
    Q_PROPERTY(QString state READ state NOTIFY changed)
    // Tor's bootstrap, 0-100, while starting.
    Q_PROPERTY(int progress READ progress NOTIFY changed)
    // One line for Settings and the web tabs, e.g. "Connecting to Tor… 45%".
    Q_PROPERTY(QString summary READ summary NOTIFY changed)
    // Where the exit should be ("us", "de", …); empty for any country.
    Q_PROPERTY(QString exitCountry READ exitCountry NOTIFY changed)
    Q_PROPERTY(QVariantList countries READ countries CONSTANT)
    // Counts New Identity requests that took effect (web tabs reload on a change).
    Q_PROPERTY(int identity READ identity NOTIFY identityChanged)
    // Chromium reads a changed proxy only when a request comes, and that request still goes the old way.
    // So after each change the web profile loads probeUrl (this computer) first and calls routeApplied().
    Q_PROPERTY(int route READ route NOTIFY routeChanged)
    Q_PROPERTY(QUrl probeUrl READ probeUrl NOTIFY routeChanged)
    // Until then web tabs hold the pages they are asked for (WebPane).
    Q_PROPERTY(bool routePending READ routePending NOTIFY routePendingChanged)
public:
    explicit TorNetwork(ResearchStore *store, QObject *parent = nullptr);
    ~TorNetwork() override;

    bool enabled() const { return m_enabled; }
    QString state() const { return m_state; }
    int progress() const { return m_progress; }
    QString summary() const;
    QString exitCountry() const { return m_exitCountry; }
    QVariantList countries() const;
    int identity() const { return m_identity; }
    int route() const { return m_route; }
    bool routePending() const { return m_routePending; }
    QUrl probeUrl() const;

    // Turning it on or off is a setting (web.tor), so it stays as the reader left it.
    Q_INVOKABLE void setEnabled(bool on);
    Q_INVOKABLE void setExitCountry(const QString &code);
    // Another exit for new connections: Tor builds fresh circuits and the web tabs move to the other
    // SOCKS port, so pages already open do not keep their old connections. False unless ready.
    Q_INVOKABLE bool newIdentity();
    // The probe for the current route has loaded: web tabs may now reload (New Identity) or retry.
    Q_INVOKABLE void routeApplied();
    // Reads the settings and starts or stops Tor to match; the store calls it once it is open.
    void apply();

    // Requests that must never go through Tor use the proxy settings Owelk started with.
    static void keepDirect(QNetworkAccessManager *manager);
    // OWELK_TOR (tests), PATH, Homebrew, the bundle the Windows install script downloads, Tor Browser.
    static QString findTor();

signals:
    void changed();
    void identityChanged();
    void routeChanged();
    void routePendingChanged();
    // Bootstrap reached 100%: web tabs that could not load meanwhile try again.
    void ready();

private:
    void start();
    void stop();
    void routeThroughTor();
    void routeAsBefore(bool announce = true);
    void announceRoute();
    void readOutput();
    void setState(const QString &state, const QString &message = QString());
    QString dataDirectory() const;

    ResearchStore *m_store;
    QPointer<QProcess> m_process;
    bool m_applied = false;
    bool m_enabled = false;
    bool m_routed = false;
    QString m_state = QStringLiteral("off");
    QString m_message;
    QString m_exitCountry;
    QString m_buffer;
    int m_progress = 0;
    int m_identity = 0;
    quint16 m_socks[2] = {0, 0};
    int m_socksInUse = 0;
    quint16 m_control = 0;
    int m_route = 0;
    bool m_routePending = false;
    bool m_readyPending = false;
    bool m_identityPending = false;
    QTimer m_routeTimeout;
    QTcpServer *m_probe = nullptr;
};
