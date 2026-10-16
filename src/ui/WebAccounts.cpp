#include "WebAccounts.h"

#include <QDateTime>
#include <QFileInfo>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QTimeZone>
#include <QUuid>
#include <QWebEngineCookieStore>
#include <QWebEngineUrlRequestInfo>
#include <QWebEngineUrlRequestInterceptor>
#include <QtWebEngineQuick/QQuickWebEngineProfile>

// Google's sign-in pages asked for as Firefox (the rest of the web sees Chrome, as always).
class GoogleSignInAgent final : public QWebEngineUrlRequestInterceptor {
public:
    using QWebEngineUrlRequestInterceptor::QWebEngineUrlRequestInterceptor;
    bool enabled = true;
    void interceptRequest(QWebEngineUrlRequestInfo &info) override
    {
        if (enabled && WebAccounts::signInHost(info.requestUrl().host()))
            info.setHttpHeader("User-Agent", WebAccounts::firefoxAgent());
    }
};

WebAccounts::WebAccounts(QObject *parent) : QObject(parent) {}

WebAccounts::~WebAccounts() = default;

int WebAccounts::firefoxVersion(const QDate &today)
{
    // Google turns away a Firefox much older than the current one, so the version follows the calendar:
    // Firefox 158 came out on 12 October 2026, and a new one comes every four weeks.
    const auto weeks = QDate(2026, 10, 12).daysTo(today) / 28;
    return int(qMax<qint64>(158, 158 + weeks));
}

QByteArray WebAccounts::firefoxAgent()
{
    // The current Firefox, on this kind of computer.
    const auto v = QByteArray::number(firefoxVersion(QDate::currentDate())) + ".0";
#if defined(Q_OS_MACOS)
    const QByteArray system = "Macintosh; Intel Mac OS X 10.15";
#elif defined(Q_OS_WIN)
    const QByteArray system = "Windows NT 10.0; Win64; x64";
#else
    const QByteArray system = "X11; Linux x86_64";
#endif
    return "Mozilla/5.0 (" + system + "; rv:" + v + ") Gecko/20100101 Firefox/" + v;
}

QString WebAccounts::firefoxScript() const
{
#if defined(Q_OS_MACOS)
    const QString appVersion = "5.0 (Macintosh)", platform = "MacIntel", oscpu = "Intel Mac OS X 10.15";
#elif defined(Q_OS_WIN)
    const QString appVersion = "5.0 (Windows)", platform = "Win32", oscpu = "Windows NT 10.0; Win64; x64";
#else
    const QString appVersion = "5.0 (X11)", platform = "Linux x86_64", oscpu = "Linux x86_64";
#endif
    return QStringLiteral(R"((function () {
    if (location.hostname !== "accounts.google.com") return;
    var values = {userAgent: "%1", appVersion: "%2", platform: "%3", oscpu: "%4", vendor: "", productSub: "20100101",
        buildID: "20181001000000", userAgentData: undefined};
    Object.keys(values).forEach(function (key) {
        try { Object.defineProperty(Navigator.prototype, key, {get: function () { return values[key]; }, configurable: true}); } catch (e) {}
    });
    try { delete window.chrome; } catch (e) {}
})();)")
        .arg(QString::fromLatin1(firefoxAgent()), appVersion, platform, oscpu);
}

bool WebAccounts::refusedPage(const QUrl &url)
{
    return signInHost(url.host()) && url.path().contains("/signin/rejected");
}

bool WebAccounts::signInHost(const QString &host)
{
    return host.compare("accounts.google.com", Qt::CaseInsensitive) == 0;
}

bool WebAccounts::googleDomain(const QString &domain)
{
    const auto d = domain.toLower();
    const auto bare = d.startsWith('.') ? d.mid(1) : d;
    // google.com and Google's country sites (google.co.kr, google.de, …), and YouTube.
    return bare == "youtube.com" || bare.endsWith(".youtube.com") || bare.startsWith("google.")
        || bare.contains(".google.");
}

bool WebAccounts::sessionCookie(const QNetworkCookie &cookie)
{
    // Google's sign-in cookies on google.com (one of them is enough).
    static const QList<QByteArray> names{"SID", "__Secure-1PSID", "__Secure-3PSID"};
    const auto domain = cookie.domain().toLower();
    return names.contains(cookie.name()) && (domain == ".google.com" || domain == "google.com")
        && (cookie.isSessionCookie() || cookie.expirationDate() > QDateTime::currentDateTimeUtc());
}

void WebAccounts::watch(QObject *profile)
{
    auto *quick = qobject_cast<QQuickWebEngineProfile *>(profile);
    if (!quick || m_cookies) return;
    m_agent = new GoogleSignInAgent(this);
    m_agent->enabled = m_firefox;
    quick->setUrlRequestInterceptor(m_agent);
    // Kept from before (Chromium keeps the file in the profile folder, or in its Network folder).
    for (const auto &file : {quick->persistentStoragePath() + "/Network/Cookies", quick->persistentStoragePath() + "/Cookies"})
        if (QFileInfo::exists(file)) {
            m_kept = googleCookiesIn(file);
            break;
        }
    m_cookies = quick->cookieStore();
    connect(m_cookies, &QWebEngineCookieStore::cookieAdded, this, &WebAccounts::added);
    connect(m_cookies, &QWebEngineCookieStore::cookieRemoved, this, &WebAccounts::removed);
    if (signedIn(m_kept)) emit changed();
}

QList<QNetworkCookie> WebAccounts::googleCookiesIn(const QString &cookieFile)
{
    QList<QNetworkCookie> list;
    const auto name = "web-cookies-" + QUuid::createUuid().toString(QUuid::WithoutBraces);
    {
        auto db = QSqlDatabase::addDatabase("QSQLITE", name);
        db.setDatabaseName(cookieFile);
        db.setConnectOptions("QSQLITE_OPEN_READONLY;QSQLITE_BUSY_TIMEOUT=200");
        if (db.open()) {
            QSqlQuery query(db);
            // Expiry in Chromium's time: microseconds since 1601 (0 for a session cookie).
            if (query.exec("SELECT host_key,name,path,expires_utc FROM cookies"))
                while (query.next()) {
                    QNetworkCookie cookie(query.value(1).toByteArray());
                    cookie.setDomain(query.value(0).toString());
                    cookie.setPath(query.value(2).toString());
                    const auto expires = query.value(3).toLongLong();
                    if (expires > 0)
                        cookie.setExpirationDate(
                            QDateTime::fromMSecsSinceEpoch(expires / 1000 - 11644473600000LL, QTimeZone::utc()));
                    if (googleDomain(cookie.domain())) list.append(cookie);
                }
            db.close();
        }
    }
    QSqlDatabase::removeDatabase(name);
    return list;
}

bool WebAccounts::signedIn(const QList<QNetworkCookie> &cookies)
{
    for (const auto &cookie : cookies)
        if (sessionCookie(cookie)) return true;
    return false;
}

bool WebAccounts::googleSignedIn() const
{
    return signedIn(m_google) || signedIn(m_kept);
}

bool WebAccounts::firefoxForGoogle() const
{
    return m_firefox;
}

void WebAccounts::setFirefoxForGoogle(bool on)
{
    if (on == m_firefox) return;
    m_firefox = on;
    if (m_agent) m_agent->enabled = on;
    emit changed();
}

QUrl WebAccounts::googleSignInUrl() const
{
    return QUrl("https://accounts.google.com/ServiceLogin?continue=https%3A%2F%2Fscholar.google.com%2F");
}

void WebAccounts::signOutOfGoogle()
{
    if (!m_cookies) return;
    // Those kept from before go too (the engine takes the request in once a page has started it).
    const bool before = googleSignedIn();
    for (const auto &cookie : m_google + m_kept) m_cookies->deleteCookie(cookie);
    m_kept.clear();
    if (googleSignedIn() != before) emit changed();
}

void WebAccounts::added(const QNetworkCookie &cookie)
{
    if (!googleDomain(cookie.domain())) return;
    const bool before = googleSignedIn();
    for (auto &kept : m_google)
        if (kept.hasSameIdentifier(cookie)) {
            kept = cookie;
            if (googleSignedIn() != before) emit changed();
            return;
        }
    m_google.append(cookie);
    if (googleSignedIn() != before) emit changed();
}

void WebAccounts::removed(const QNetworkCookie &cookie)
{
    const bool before = googleSignedIn();
    const auto same = [&](const QNetworkCookie &kept) { return kept.hasSameIdentifier(cookie); };
    m_google.removeIf(same);
    m_kept.removeIf(same);
    if (googleSignedIn() != before) emit changed();
}
