#pragma once

#include <QList>
#include <QNetworkCookie>
#include <QDate>
#include <QObject>
#include <QUrl>

class QWebEngineCookieStore;
class GoogleSignInAgent;

// Accounts the web tabs are signed in to, read from their shared profile's cookies (Settings › Web). One
// sign-in to Google there serves Scholar, YouTube and Google search in every web tab, and stays across
// restarts like a browser's. Google refuses sign-in from browsers it takes for embedded ones; with
// firefoxForGoogle (on unless turned off) the sign-in pages (accounts.google.com) are asked for as Firefox,
// the workaround qutebrowser ships for the same refusal. The password goes only to Google, in a web tab.
class WebAccounts final : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool googleSignedIn READ googleSignedIn NOTIFY changed)
    Q_PROPERTY(bool firefoxForGoogle READ firefoxForGoogle WRITE setFirefoxForGoogle NOTIFY changed)
public:
    explicit WebAccounts(QObject *parent = nullptr);
    ~WebAccounts() override;
    // The web tabs' profile (a WebEngineProfile from QML): its cookies are read, and its sign-in requests
    // to Google go as Firefox.
    Q_INVOKABLE void watch(QObject *profile);
    bool googleSignedIn() const;
    bool firefoxForGoogle() const;
    void setFirefoxForGoogle(bool on);
    // Where signing in starts (Google's own page, coming back to Scholar).
    Q_INVOKABLE QUrl googleSignInUrl() const;
    // Signed out of Google in Owelk's web tabs: Google's and YouTube's cookies go.
    Q_INVOKABLE void signOutOfGoogle();
    // The Firefox the sign-in pages see (the current one on this kind of computer).
    static QByteArray firefoxAgent();
    static int firefoxVersion(const QDate &today);
    // What the sign-in pages' scripts see of the browser, as Firefox too (navigator, no window.chrome), so
    // that it agrees with what their requests say; run in those pages only.
    Q_INVOKABLE QString firefoxScript() const;
    // Google's "This browser or app may not be secure" page.
    Q_INVOKABLE static bool refusedPage(const QUrl &url);
    // Whether a request to this host goes as Firefox (Google's sign-in pages only).
    static bool signInHost(const QString &host);
    // Google's and YouTube's cookies kept in a profile's cookie file (Chromium's Cookies database), names,
    // domains and paths only; empty when it cannot be read (the web engine may hold it).
    static QList<QNetworkCookie> googleCookiesIn(const QString &cookieFile);
    // Whether these cookies say a Google account is signed in.
    static bool signedIn(const QList<QNetworkCookie> &cookies);

signals:
    void changed();

private:
    static bool googleDomain(const QString &domain);
    static bool sessionCookie(const QNetworkCookie &cookie);
    void added(const QNetworkCookie &cookie);
    void removed(const QNetworkCookie &cookie);
    QWebEngineCookieStore *m_cookies = nullptr;
    GoogleSignInAgent *m_agent = nullptr;
    // Google's and YouTube's cookies seen live (some say an account is signed in; all go when signing out),
    // and those read from the cookie file at the start: the web engine reports none it keeps until a page
    // has loaded (and loadAllCookies asked before that never answers), so the file tells what was kept.
    QList<QNetworkCookie> m_google;
    QList<QNetworkCookie> m_kept;
    bool m_firefox = true;
};
