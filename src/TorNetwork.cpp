#include "TorNetwork.h"
#include "ResearchStore.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QNetworkAccessManager>
#include <QNetworkProxy>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTimer>

namespace {
// The proxy settings Owelk had before Tor was ever turned on (usually the system's), read once.
struct Before {
    bool system;
    QNetworkProxy proxy;
};
const Before &before()
{
    static const Before value{QNetworkProxyFactory::usesSystemConfiguration(), QNetworkProxy::applicationProxy()};
    return value;
}

class DirectProxies final : public QNetworkProxyFactory {
public:
    QList<QNetworkProxy> queryProxy(const QNetworkProxyQuery &query) override
    {
        if (before().system) return systemProxyForQuery(query);
        const auto proxy = before().proxy;
        return {proxy.type() == QNetworkProxy::DefaultProxy ? QNetworkProxy(QNetworkProxy::NoProxy) : proxy};
    }
};

quint16 freePort()
{
    QTcpServer server;
    server.listen(QHostAddress::LocalHost, 0);
    return server.serverPort();
}
}

TorNetwork::TorNetwork(ResearchStore *store, QObject *parent) : QObject(parent), m_store(store)
{
    before();
    connect(store, &ResearchStore::settingsChanged, this, [this] {
        if (m_applied) apply();
    });
    // Without a web profile to probe (the C++ tests), go on after a moment.
    m_routeTimeout.setSingleShot(true);
    m_routeTimeout.setInterval(5000);
    connect(&m_routeTimeout, &QTimer::timeout, this, &TorNetwork::routeApplied);
}

TorNetwork::~TorNetwork()
{
    stop();
    routeAsBefore(false);
}

QVariantList TorNetwork::countries() const
{
    // Countries with many exits, so circuits still come quickly.
    static const QList<std::pair<const char *, const char *>> list{{"", "Any country"}, {"us", "United States"},
        {"gb", "United Kingdom"}, {"de", "Germany"}, {"nl", "Netherlands"}, {"fr", "France"}, {"ch", "Switzerland"},
        {"se", "Sweden"}, {"ca", "Canada"}, {"jp", "Japan"}};
    QVariantList result;
    for (const auto &[code, name] : list)
        result.append(QVariantMap{{"code", QString::fromLatin1(code)}, {"name", QString::fromLatin1(name)}});
    return result;
}

QString TorNetwork::summary() const
{
    if (m_state == "starting")
        return m_progress > 0 ? QStringLiteral("Connecting to Tor… %1%").arg(m_progress) : QStringLiteral("Starting Tor…");
    if (m_state == "ready") {
        QString where;
        for (const auto &country : countries())
            if (!m_exitCountry.isEmpty() && country.toMap().value("code").toString() == m_exitCountry)
                where = " (exit in " + country.toMap().value("name").toString() + ")";
        return "On. Web tabs go out through Tor" + where + ".";
    }
    if (m_state == "missing") {
#if defined(Q_OS_MACOS)
        return QStringLiteral("Tor is not installed, so web tabs cannot connect. Install it with Homebrew "
                              "(brew install tor), or turn this off.");
#elif defined(Q_OS_WIN)
        return QStringLiteral("Tor is not installed, so web tabs cannot connect. Run the install script again "
                              "with -Tor (it downloads Tor), or turn this off.");
#else
        return QStringLiteral("Tor is not installed, so web tabs cannot connect. Install it (sudo apt install tor), "
                              "or turn this off.");
#endif
    }
    if (m_state == "failed")
        return "Tor stopped, so web tabs cannot connect" + (m_message.isEmpty() ? QString() : ": " + m_message)
            + ". Turn it off and on to try again.";
    return QStringLiteral("Off. Web tabs connect directly.");
}

void TorNetwork::setEnabled(bool on)
{
    m_store->setSetting("web.tor", on ? "1" : "0");
}

void TorNetwork::setExitCountry(const QString &code)
{
    for (const auto &country : countries())
        if (country.toMap().value("code").toString() == code) {
            m_store->setSetting("web.torExit", code);
            return;
        }
}

void TorNetwork::apply()
{
    m_applied = true;
    const bool on = m_store->setting("web.tor", "0") == "1";
    const auto country = m_store->setting("web.torExit");
    const bool different = on != m_enabled || country != m_exitCountry;
    const bool restart = on && different;
    m_enabled = on;
    m_exitCountry = country;
    if (!on) {
        if (m_process || m_routed || m_state != "off") {
            stop();
            routeAsBefore();
            m_progress = 0;
            setState("off");
        } else if (different)
            emit changed();
        return;
    }
    if (restart) start();
}

QString TorNetwork::dataDirectory() const
{
    // On this computer only (never in a synced data folder), one per library so two Owelks never share it.
    const auto key = QCryptographicHash::hash(m_store->dataDirectory().toUtf8(), QCryptographicHash::Sha1).toHex();
    return QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + "/tor-" + key.left(10);
}

QString TorNetwork::findTor()
{
    const auto override = qEnvironmentVariable("OWELK_TOR");
    if (!override.isEmpty()) return QFileInfo(override).isFile() ? override : QString();
#ifdef Q_OS_WIN
    // The Tor Expert Bundle that tools\install-local.ps1 unpacks.
    QDirIterator bundle(qEnvironmentVariable("LOCALAPPDATA") + "/Owelk/tor", {"tor.exe"}, QDir::Files,
        QDirIterator::Subdirectories);
    if (bundle.hasNext()) return bundle.next();
#endif
    auto found = QStandardPaths::findExecutable("tor");
    if (!found.isEmpty()) return found;
    // Apps started from Finder, a launcher or the Start menu often miss the shell's PATH.
    const auto home = QDir::homePath();
    return QStandardPaths::findExecutable("tor",
        {"/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/usr/sbin",
            "/Applications/Tor Browser.app/Contents/MacOS/Tor", home + "/Applications/Tor Browser.app/Contents/MacOS/Tor",
            home + "/Desktop/Tor Browser/Browser/TorBrowser/Tor"});
}

void TorNetwork::keepDirect(QNetworkAccessManager *manager)
{
    manager->setProxyFactory(new DirectProxies);
}

void TorNetwork::start()
{
    stop();
    for (auto &port : m_socks) port = freePort();
    m_control = freePort();
    m_socksInUse = 0;
    m_progress = 0;
    m_message.clear();
    m_buffer.clear();
    // From now on web tabs connect only through Tor's port, ready or not.
    routeThroughTor();
    const auto program = findTor();
    if (program.isEmpty()) {
        setState("missing");
        return;
    }
    const auto data = dataDirectory();
    QDir().mkpath(data);
    // Only the settings below: a torrc written for a system-wide Tor is not read.
    const auto torrc = data + "/owelk-torrc";
    QFile empty(torrc);
    if (empty.open(QIODevice::WriteOnly | QIODevice::Truncate)) empty.close();
    QStringList arguments{"-f", torrc, "--defaults-torrc", torrc, "--DataDirectory", data, "--SocksPort",
        QStringLiteral("127.0.0.1:%1").arg(m_socks[0]), "--SocksPort", QStringLiteral("127.0.0.1:%1").arg(m_socks[1]),
        "--ControlPort", QStringLiteral("127.0.0.1:%1").arg(m_control), "--CookieAuthentication", "1",
        // Tor quits by itself if Owelk ever ends without stopping it.
        "--__OwningControllerProcess", QString::number(QCoreApplication::applicationPid()), "--Log", "notice stdout",
        "--ClientOnly", "1"};
    // Country lists: Homebrew's and Linux's Tor know where theirs are; the Windows bundle and Tor Browser
    // keep them near the program.
    const QDir folder = QFileInfo(program).absoluteDir();
    const auto geoip = [&folder](const QString &name) {
        for (const auto &candidate : {name, "../data/" + name, "../Data/Tor/" + name})
            if (QFileInfo(folder.filePath(candidate)).isFile()) return QDir::cleanPath(folder.filePath(candidate));
        return QString();
    };
    if (const auto v4 = geoip("geoip"); !v4.isEmpty()) arguments << "--GeoIPFile" << v4;
    if (const auto v6 = geoip("geoip6"); !v6.isEmpty()) arguments << "--GeoIPv6File" << v6;
    if (!m_exitCountry.isEmpty()) arguments << "--ExitNodes" << "{" + m_exitCountry + "}";

    auto *process = new QProcess(this);
    m_process = process;
    process->setProcessChannelMode(QProcess::MergedChannels);
    connect(process, &QProcess::readyRead, this, &TorNetwork::readOutput);
    connect(process, &QProcess::finished, this, [this, process] {
        process->deleteLater();
        m_process = nullptr;
        if (m_enabled) setState("failed", m_message);
    });
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart) return;
        process->deleteLater();
        m_process = nullptr;
        setState("failed", process->errorString());
    });
    setState("starting");
    // Scripts (the tests' stand-in) run through Python.
    if (program.endsWith(".py"))
        process->start(QStandardPaths::findExecutable("python3").isEmpty() ? "python" : "python3",
            QStringList{program} + arguments);
    else
        process->start(program, arguments);
}

void TorNetwork::stop()
{
    if (!m_process) return;
    QProcess *process = m_process;
    m_process = nullptr;
    process->disconnect(this);
    process->kill();
    process->waitForFinished(2000);
    process->deleteLater();
}

void TorNetwork::routeThroughTor()
{
    QNetworkProxyFactory::setUseSystemConfiguration(false);
    QNetworkProxy::setApplicationProxy(
        QNetworkProxy(QNetworkProxy::Socks5Proxy, QStringLiteral("127.0.0.1"), m_socks[m_socksInUse]));
    m_routed = true;
    announceRoute();
}

void TorNetwork::routeAsBefore(bool announce)
{
    if (!m_routed) return;
    QNetworkProxy::setApplicationProxy(before().proxy);
    if (before().system) QNetworkProxyFactory::setUseSystemConfiguration(true);
    m_routed = false;
    if (announce) announceRoute();
}

void TorNetwork::announceRoute()
{
    if (!m_probe) {
        // Answers the probe with a tiny page; it is on this computer, so it never goes through a proxy.
        m_probe = new QTcpServer(this);
        connect(m_probe, &QTcpServer::newConnection, this, [this] {
            while (auto *socket = m_probe->nextPendingConnection()) {
                connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
                connect(socket, &QTcpSocket::readyRead, socket, [socket] {
                    socket->readAll();
                    socket->write("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 2\r\n"
                                  "Cache-Control: no-store\r\nConnection: close\r\n\r\nok");
                    socket->disconnectFromHost();
                });
            }
        });
        m_probe->listen(QHostAddress::LocalHost, 0);
    }
    ++m_route;
    const bool was = m_routePending;
    m_routePending = true;
    m_routeTimeout.start();
    emit routeChanged();
    if (!was) emit routePendingChanged();
}

QUrl TorNetwork::probeUrl() const
{
    if (!m_probe) return {};
    return QUrl(QStringLiteral("http://127.0.0.1:%1/route-%2").arg(m_probe->serverPort()).arg(m_route));
}

void TorNetwork::routeApplied()
{
    if (!m_routePending) return;
    m_routeTimeout.stop();
    // A moment for Chromium's network side to take the new settings in.
    QTimer::singleShot(150, this, [this, route = m_route] {
        if (route != m_route || !m_routePending) return;
        m_routePending = false;
        emit routePendingChanged();
        if (m_identityPending) {
            m_identityPending = false;
            ++m_identity;
            emit identityChanged();
        }
        if (m_readyPending) {
            m_readyPending = false;
            if (m_state == "ready") emit ready();
        }
    });
}

void TorNetwork::readOutput()
{
    if (!m_process) return;
    m_buffer += QString::fromUtf8(m_process->readAll());
    static const QRegularExpression bootstrap("Bootstrapped (\\d+)%"), problem("\\[(warn|err)\\] (.*)");
    for (auto end = m_buffer.indexOf('\n'); end >= 0; end = m_buffer.indexOf('\n')) {
        const auto line = m_buffer.left(end).trimmed();
        m_buffer.remove(0, end + 1);
        if (const auto match = bootstrap.match(line); match.hasMatch()) {
            m_progress = match.captured(1).toInt();
            if (m_progress >= 100 && m_state == "starting") {
                setState("ready");
                if (m_routePending) m_readyPending = true;
                else emit ready();
            } else
                emit changed();
        } else if (const auto match = problem.match(line); match.hasMatch())
            m_message = match.captured(2).trimmed();
    }
}

bool TorNetwork::newIdentity()
{
    if (m_state != "ready") return false;
    QFile file(dataDirectory() + "/control_auth_cookie");
    const auto cookie = file.open(QIODevice::ReadOnly) ? file.readAll().toHex() : QByteArray();
    auto *socket = new QTcpSocket(this);
    // Once Tor has answered (or not, within a few seconds): new connections use the other port.
    const auto finish = [this, socket] {
        if (socket->property("done").toBool()) return;
        socket->setProperty("done", true);
        socket->deleteLater();
        if (m_state != "ready") return;
        m_socksInUse = 1 - m_socksInUse;
        m_identityPending = true;
        routeThroughTor();
    };
    connect(socket, &QTcpSocket::connected, socket,
        [socket, cookie] { socket->write("AUTHENTICATE " + cookie + "\r\nSIGNAL NEWNYM\r\nQUIT\r\n"); });
    connect(socket, &QTcpSocket::readyRead, socket, [socket] { socket->readAll(); });
    connect(socket, &QTcpSocket::disconnected, this, finish);
    connect(socket, &QTcpSocket::errorOccurred, this, finish);
    QTimer::singleShot(3000, socket, finish);
    socket->connectToHost(QHostAddress::LocalHost, m_control);
    return true;
}

void TorNetwork::setState(const QString &state, const QString &message)
{
    m_state = state;
    if (!message.isEmpty()) m_message = message;
    emit changed();
}
