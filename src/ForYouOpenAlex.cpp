#include "ForYou.h"
#include "ResearchStore.h"
#include "SearchText.h"
#include "ai/Keychain.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMap>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QRegularExpression>
#include <QSqlQuery>
#include <QTimer>
#include <QUrlQuery>
#include <algorithm>

namespace {
constexpr auto keyAccount = "openalex-api-key";
bool validIdentity(const QString &id, const QString &kind)
{
    static const QRegularExpression identity("^[AI][0-9]+$");
    return identity.match(id).hasMatch()
        && ((kind == "person" && id.startsWith('A')) || (kind == "institution" && id.startsWith('I')));
}
QString webAddress(const QString &text)
{
    const QUrl url(text.trimmed());
    return url.isValid() && !url.host().isEmpty() && url.userInfo().isEmpty()
            && (url.scheme() == "https" || url.scheme() == "http")
        ? url.toString()
        : QString();
}
QNetworkRequest request(const QUrl &url)
{
    QNetworkRequest call(url);
    call.setHeader(QNetworkRequest::UserAgentHeader, "Owelk/0.1 (local research reader)");
    call.setTransferTimeout(20000);
    return call;
}
}

namespace ForYouParse {
// Adapted from x-or-b/Owelk's OpenAlex reader; original PDF coordinates and files are untouched.
QVariantList openAlexWorks(const QByteArray &json)
{
    static const QRegularExpression arxivPage(
        R"(arxiv\.org/(?:abs|pdf)/([^?#]+?)(?:v\d+)?(?:\.pdf)?$)", QRegularExpression::CaseInsensitiveOption);
    static const QRegularExpression arxivDoi(R"(^10\.48550/arxiv\.(.+)$)", QRegularExpression::CaseInsensitiveOption);
    static const QRegularExpression doiLink(R"(^https?://(dx\.)?doi\.org/)", QRegularExpression::CaseInsensitiveOption);
    const auto tail = [](const QString &id) { return id.mid(id.lastIndexOf('/') + 1); };
    QVariantList list;
    for (const auto &value : QJsonDocument::fromJson(json).object().value("results").toArray()) {
        const auto work = value.toObject();
        const auto title = work.value("title").toString().simplified();
        if (title.isEmpty()) continue;
        QStringList authors;
        for (const auto &authorship : work.value("authorships").toArray())
            if (const auto name
                = authorship.toObject().value("author").toObject().value("display_name").toString().simplified();
                !name.isEmpty())
                authors << name;
        auto doi = work.value("doi").toString().trimmed().remove(doiLink);
        QString arxiv;
        // arXiv's own DOI names the preprint, not a journal version: kept as the arXiv ID.
        if (const auto m = arxivDoi.match(doi); m.hasMatch()) {
            arxiv = m.captured(1);
            doi.clear();
        }
        const auto best = work.value("best_oa_location").toObject();
        QJsonArray locations{best};
        for (const auto &location : work.value("locations").toArray()) locations.append(location);
        for (const auto &location : std::as_const(locations)) {
            if (!arxiv.isEmpty()) break;
            if (const auto m = arxivPage.match(location.toObject().value("landing_page_url").toString()); m.hasMatch())
                arxiv = m.captured(1);
        }
        auto pdf = best.value("pdf_url").toString();
        if (!ForYouParse::isPdfAddress(pdf)) pdf.clear();
        if (pdf.isEmpty() && !arxiv.isEmpty()) pdf = "https://arxiv.org/pdf/" + arxiv;
        // The abstract comes as each word with its places in the text.
        QMap<int, QString> words;
        const auto index = work.value("abstract_inverted_index").toObject();
        for (auto it = index.begin(); it != index.end(); ++it)
            for (const auto &place : it.value().toArray()) words.insert(place.toInt(), it.key());
        const auto date = work.value("publication_date").toString();
        const auto year = work.value("publication_year").isDouble()
            ? QString::number(work.value("publication_year").toInt())
            : date.left(4);
        const auto landing = best.value("landing_page_url").toString();
        list.append(QVariantMap{{"title", title}, {"authors", authors.join(", ")}, {"date", date}, {"year", year},
            {"abstract", QStringList(words.values()).join(' ').simplified()}, {"arxiv", arxiv}, {"doi", doi},
            {"pdf", pdf}, {"openalex", tail(work.value("id").toString())},
            {"url",
                !arxiv.isEmpty()         ? "https://arxiv.org/abs/" + arxiv
                    : !doi.isEmpty()     ? "https://doi.org/" + doi
                    : !landing.isEmpty() ? landing
                                         : work.value("id").toString()}});
    }
    return list;
}

QVariantList openAlexEntities(const QByteArray &json, const QString &kind)
{
    QVariantList rows;
    for (const auto &value : QJsonDocument::fromJson(json).object().value("results").toArray()) {
        const auto found = value.toObject();
        const auto id = found.value("id").toString().section('/', -1);
        const auto name = found.value("display_name").toString().simplified();
        if (!validIdentity(id, kind) || name.isEmpty()) continue;
        QStringList places;
        for (const auto &place : found.value("last_known_institutions").toArray())
            if (const auto label = place.toObject().value("display_name").toString().simplified(); !label.isEmpty())
                places << label;
        if (kind == "institution") {
            const auto geo = found.value("geo").toObject();
            for (const auto &label : {geo.value("city").toString(), found.value("country_code").toString()})
                if (!label.isEmpty()) places << label;
        }
        const auto affiliation = places.join(", ");
        const int papers = found.value("works_count").toInt();
        const auto detail = QString(kind == "person" ? "Researcher" : "Institution")
            + (affiliation.isEmpty() ? QString() : " · " + affiliation) + " · " + QString::number(papers) + " papers";
        rows.append(
            QVariantMap{{"id", id}, {"kind", kind}, {"name", name}, {"detail", detail}, {"affiliation", affiliation},
                {"papers", papers}, {"homepage", webAddress(found.value("homepage_url").toString())},
                {"orcid", webAddress(found.value("orcid").toString())}, {"profileLoaded", true}});
    }
    return rows;
}
}

QVariantList ForYou::entities() const
{
    QVariantList rows;
    QSqlQuery query(m_store->m_database);
    query.exec("SELECT id,kind,name,profile FROM foryou_entities ORDER BY position,name");
    while (query.next()) {
        auto entity = QJsonDocument::fromJson(query.value(3).toByteArray()).object().toVariantMap();
        entity.insert(
            {{"id", query.value(0)}, {"kind", query.value(1)}, {"name", query.value(2)}, {"profileLoaded", true}});
        rows.append(entity);
    }
    return rows;
}
bool ForYou::followingEntity(const QString &id) const
{
    QSqlQuery query(m_store->m_database);
    query.prepare("SELECT 1 FROM foryou_entities WHERE id=?");
    query.addBindValue(id);
    return query.exec() && query.next();
}
void ForYou::followEntity(const QVariantMap &entity, bool on)
{
    const auto id = entity.value("id").toString(), kind = entity.value("kind").toString();
    if (!validIdentity(id, kind)) return;
    if (!on) {
        exec("DELETE FROM foryou_entities WHERE id=?", {id});
    } else {
        const auto name = entity.value("name").toString().simplified().left(200);
        if (name.isEmpty()) return;
        QVariantMap profile;
        for (const auto &field : {"detail", "affiliation"})
            profile.insert(field, entity.value(field).toString().left(500));
        for (const auto &field : {"homepage", "orcid"})
            profile.insert(field, webAddress(entity.value(field).toString()));
        profile.insert("papers", qMax(0, entity.value("papers").toInt()));
        const auto json
            = QString::fromUtf8(QJsonDocument(QJsonObject::fromVariantMap(profile)).toJson(QJsonDocument::Compact));
        exec("INSERT INTO foryou_entities(id,kind,name,profile,position) VALUES(?,?,?,?,"
             "(SELECT coalesce(max(position),-1)+1 FROM foryou_entities)) ON CONFLICT(id) DO UPDATE SET "
             "name=excluded.name,profile=excluded.profile WHERE name<>excluded.name OR profile<>excluded.profile",
            {id, kind, name, json});
    }
    emit settingsChanged();
}
bool ForYou::hasOpenAlexKey() const
{
    return !Keychain::read(keyAccount, m_store->dataDirectory()).isEmpty();
}
bool ForYou::setOpenAlexKey(const QString &key)
{
    const auto value = key.trimmed();
    const bool ok = value.isEmpty() ? Keychain::remove(keyAccount, m_store->dataDirectory())
                                    : Keychain::write(keyAccount, value, m_store->dataDirectory());
    if (!ok) m_store->notify("Could not store the OpenAlex key in " + Keychain::storageName() + ".");
    if (ok) {
        m_entitySearchCache.clear();
        m_entityRetryUntil = {};
        emit entitySearchStateChanged();
    }
    emit settingsChanged();
    return ok;
}
QStringList ForYou::entitySearchSuggestions(const QString &name, const QString &kind) const
{
    if (kind == "person") return peopleSearchSuggestions(name);
    // Institutions can have Korean official names. Keep that query available beside translated candidates.
    auto candidates = qobject_cast<SearchText *>(m_store->searchText())->variants(name);
    candidates.removeAll(name.simplified());
    for (const auto &spelling : SearchText::personNames(name)) candidates.removeAll(spelling);
    candidates.removeDuplicates();
    return candidates.mid(0, 5);
}
int ForYou::entityRetrySeconds() const
{
    return int(qMax<qint64>(0, (QDateTime::currentDateTimeUtc().msecsTo(m_entityRetryUntil) + 999) / 1000));
}
QString ForYou::openAlexError(QNetworkReply *reply)
{
    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    if (reply->error() == QNetworkReply::NoError && status < 400) return {};
    if (status == 429) {
        bool numeric = false;
        const auto header = QString::fromLatin1(reply->rawHeader("Retry-After")).trimmed();
        qint64 seconds = header.toLongLong(&numeric);
        if (!numeric) {
            const auto date = QDateTime::fromString(header, Qt::RFC2822Date);
            seconds = date.isValid() ? QDateTime::currentDateTimeUtc().secsTo(date) : 60;
        }
        m_entityRetryUntil = QDateTime::currentDateTimeUtc().addSecs(std::clamp<qint64>(seconds, 1, 86400));
        if (!m_entityRetryTimer) {
            m_entityRetryTimer = new QTimer(this);
            m_entityRetryTimer->setInterval(1000);
            connect(m_entityRetryTimer, &QTimer::timeout, this, [this] {
                emit entitySearchStateChanged();
                if (!entityRetrySeconds()) m_entityRetryTimer->stop();
            });
        }
        m_entityRetryTimer->start();
        emit entitySearchStateChanged();
        return "OpenAlex's request limit was reached. Wait for the countdown, or add a free OpenAlex API key. Web "
               "links still work.";
    }
    if (status == 401 || status == 403)
        return "OpenAlex could not authorize this request. Check the API key in Settings › For You.";
    return "OpenAlex did not answer. Check your connection and try again.";
}
void ForYou::findEntities(const QString &name, const QString &kind)
{
    const auto lookup = kind + ':' + name;
    if (m_entityReply && m_entityLookup == lookup) return;
    const int generation = ++m_entityRequest;
    if (m_entityReply) m_entityReply->abort();
    m_entityReply.clear();
    m_entityLookup = lookup;
    const auto words = (kind == "person" ? peopleSearchSuggestions(name).value(0, name) : name).simplified().left(128);
    const auto base = m_store->setting("forYou.openAlexBaseUrl", "https://api.openalex.org");
    const auto cacheKey = base + '/' + kind + '/' + words.toCaseFolded();
    const auto finishLater = [this, generation, name, kind](const QVariantList &rows, const QString &error) {
        QMetaObject::invokeMethod(
            this,
            [this, generation, name, kind, rows, error] {
                if (generation == m_entityRequest) emit entitiesFound(name, kind, rows, error);
            },
            Qt::QueuedConnection);
    };
    if (words.isEmpty() || (kind != "person" && kind != "institution")) {
        finishLater({}, {});
        return;
    }
    if (const auto cache = m_entitySearchCache.constFind(cacheKey);
        cache != m_entitySearchCache.cend() && cache->expires > QDateTime::currentDateTimeUtc()) {
        finishLater(cache->rows, {});
        return;
    }
    if (entityRetrySeconds()) {
        finishLater({}, "OpenAlex's request limit is active. Wait for the countdown or use the web links.");
        return;
    }
    QUrl url(base + (kind == "person" ? "/authors" : "/institutions"));
    QUrlQuery query{{"search", words}, {"per-page", kind == "person" ? "25" : "5"},
        {"select",
            kind == "person" ? "id,display_name,last_known_institutions,works_count,orcid"
                             : "id,display_name,country_code,geo,works_count,homepage_url"}};
    const auto key = Keychain::read(keyAccount, m_store->dataDirectory());
    if (!key.isEmpty()) query.addQueryItem("api_key", key);
    url.setQuery(query);
    if (!m_network) m_network = new QNetworkAccessManager(this);
    auto *reply = m_network->get(request(url));
    m_entityReply = reply;
    connect(reply, &QNetworkReply::finished, this, [this, reply, generation, name, kind, cacheKey, words] {
        reply->deleteLater();
        if (generation != m_entityRequest) return;
        m_entityReply.clear();
        auto error = openAlexError(reply);
        QVariantList rows;
        if (error.isEmpty()) {
            const auto body = reply->readAll();
            if (!QJsonDocument::fromJson(body).object().value("results").isArray())
                error = "OpenAlex returned an unreadable response. Try again.";
            else {
                rows = ForYouParse::openAlexEntities(body, kind);
                rows = kind == "person" ? ForYouParse::closestPeople(rows, words) : rows.mid(0, 5);
                if (m_entitySearchCache.size() >= 48) m_entitySearchCache.erase(m_entitySearchCache.begin());
                m_entitySearchCache.insert(cacheKey, {QDateTime::currentDateTimeUtc().addSecs(600), rows});
            }
        }
        emit entitiesFound(name, kind, rows, error);
    });
}
void ForYou::appendOpenAlexJobs(const QDateTime &from, const QDateTime &to, int limit)
{
    const auto base = m_store->setting("forYou.openAlexBaseUrl", "https://api.openalex.org");
    const auto key = Keychain::read(keyAccount, m_store->dataDirectory());
    for (const auto &value : entities()) {
        const auto entity = value.toMap();
        const auto id = entity.value("id").toString(), kind = entity.value("kind").toString();
        if (!validIdentity(id, kind)) continue;
        QUrl url(base + "/works");
        QUrlQuery query{{"filter",
                            (kind == "person" ? "authorships.author.id:" : "authorships.institutions.lineage:") + id
                                + ",from_publication_date:" + from.date().toString(Qt::ISODate)
                                + ",to_publication_date:" + to.date().toString(Qt::ISODate) + ",type:article|preprint"},
            {"sort", "publication_date:desc"}, {"per-page", QString::number(limit)},
            {"select",
                "id,doi,title,publication_date,publication_year,authorships,abstract_inverted_index,best_oa_location,"
                "locations"}};
        if (!key.isEmpty()) query.addQueryItem("api_key", key);
        url.setQuery(query);
        m_jobs.append({"openalex:" + id, entity.value("name").toString(), [this, url](Job job) {
                           if (entityRetrySeconds()) {
                               m_problems << "OpenAlex's request limit is active. Try Check Now after the countdown in "
                                             "Settings › For You.";
                               runNext();
                               return;
                           }
                           auto *reply = m_network->get(request(url));
                           connect(reply, &QNetworkReply::finished, this, [this, reply, job] {
                               reply->deleteLater();
                               const auto error = openAlexError(reply);
                               if (!error.isEmpty())
                                   m_problems << error;
                               else {
                                   const auto body = reply->readAll();
                                   if (!QJsonDocument::fromJson(body).object().value("results").isArray())
                                       m_problems
                                           << "OpenAlex returned an unreadable paper list for " + job.sourceName + ".";
                                   else
                                       found(ForYouParse::openAlexWorks(body), job.source, job.sourceName);
                               }
                               runNext();
                           });
                       }});
    }
}
