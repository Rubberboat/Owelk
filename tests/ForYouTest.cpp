#include "ForYouTest.h"
#include "ForYou.h"
#include "ResearchStore.h"
#include "WorkerConnection.h"
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSignalSpy>
#include <QSqlQuery>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QUrlQuery>
#include <QtTest>

class OpenAlexServer : public QObject {
public:
    QTcpServer server;
    QList<QUrl> urls;
    int status = 200;
    QByteArray body = "{\"results\":[]}";
    OpenAlexServer()
    {
        server.listen(QHostAddress::LocalHost);
        connect(&server, &QTcpServer::newConnection, this, [this] {
            auto *socket = server.nextPendingConnection();
            auto buffer = std::make_shared<QByteArray>();
            connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
            connect(socket, &QTcpSocket::readyRead, socket, [this, socket, buffer] {
                *buffer += socket->readAll();
                if (!buffer->contains("\r\n\r\n")) return;
                urls << QUrl::fromEncoded(buffer->split(' ').value(1));
                socket->write("HTTP/1.1 " + QByteArray::number(status)
                    + " Response\r\nContent-Type: application/json\r\n"
                      "Connection: close\r\nRetry-After: 1\r\nContent-Length: "
                    + QByteArray::number(body.size()) + "\r\n\r\n" + body);
                socket->disconnectFromHost();
            });
        });
    }
    QString base() const { return QString("http://127.0.0.1:%1").arg(server.serverPort()); }
};

void ForYouTest::identityDetailsAndWorkParsing()
{
    const auto authors = ForYouParse::openAlexEntities(R"({"results":[
            {"id":"https://openalex.org/A1","display_name":"Juhyun Kim","works_count":42,"orcid":"https://orcid.org/0000-0001",
             "last_known_institutions":[{"display_name":"Seoul University"}]},
            {"id":"https://openalex.org/I2","display_name":"Not an author"},
            {"id":"A../../invalid","display_name":"Bad ID"}]})",
        "person");
    QCOMPARE(authors.size(), 1);
    const auto person = authors[0].toMap();
    QCOMPARE(person["id"].toString(), QString("A1"));
    QCOMPARE(person["affiliation"].toString(), QString("Seoul University"));
    QCOMPARE(person["papers"].toInt(), 42);
    QVERIFY(person["homepage"].toString().isEmpty());
    QVERIFY(person["orcid"].toString().startsWith("https://orcid.org/"));
    const auto institutions = ForYouParse::openAlexEntities(R"json({"results":[
            {"id":"https://openalex.org/I2","display_name":"University","country_code":"KR","geo":{"city":"Seoul"},"homepage_url":"https://university.example"},
            {"id":"I3","display_name":"Unsafe link","homepage_url":"javascript:alert(1)"}]})json",
        "institution");
    QCOMPARE(institutions.size(), 2);
    QCOMPARE(institutions[0].toMap()["affiliation"].toString(), QString("Seoul, KR"));
    QCOMPARE(institutions[0].toMap()["homepage"].toString(), QString("https://university.example"));
    QVERIFY(institutions[1].toMap()["homepage"].toString().isEmpty());
    const auto works = ForYouParse::openAlexWorks(R"({"results":[{"id":"https://openalex.org/W1","title":"A paper",
            "doi":"https://doi.org/10.48550/arXiv.2610.01234","authorships":[{"author":{"display_name":"Juhyun Kim"}}],
            "abstract_inverted_index":{"the":[1,3],"In":[0],"paper":[2]},"publication_date":"2026-10-18"}]})");
    QCOMPARE(works.size(), 1);
    const auto paper = works[0].toMap();
    QCOMPARE(paper["abstract"].toString(), QString("In the paper the"));
    QCOMPARE(paper["authors"].toString(), QString("Juhyun Kim"));
    QCOMPARE(paper["arxiv"].toString(), QString("2610.01234"));
    QCOMPARE(paper["pdf"].toString(), QString("https://arxiv.org/pdf/2610.01234"));
    QVERIFY(paper["doi"].toString().isEmpty());
}
void ForYouTest::migrationKeepsExistingPeople()
{
    QTemporaryDir dir;
    QString error;
    {
        ResearchStore old(dir.path());
        QVERIFY2(old.initialize(&error), qPrintable(error));
        auto *service = qobject_cast<ForYou *>(old.forYou());
        service->followPerson({{"id", "123"}, {"name", "Existing person"}}, true);
        WorkerConnection db(dir.filePath("owelk.sqlite3"), false);
        QSqlQuery query(db.db);
        QVERIFY(query.exec("DROP TABLE foryou_entities"));
        QVERIFY(query.exec("PRAGMA user_version=19"));
    }
    ResearchStore store(dir.path());
    QVERIFY2(store.initialize(&error), qPrintable(error));
    auto *service = qobject_cast<ForYou *>(store.forYou());
    QVERIFY(service->followingPerson("123"));
    QVERIFY(service->entities().isEmpty());
    service->followEntity({{"id", "A123"}, {"kind", "person"}, {"name", "OpenAlex person"}}, true);
    service->followEntity(
        {{"id", "I123"}, {"kind", "institution"}, {"name", "Institution"}, {"homepage", "https://example.org"}}, true);
    service->followEntity({{"id", "I123"}, {"kind", "person"}, {"name", "Wrong type"}}, true);
    QCOMPARE(service->entities().size(), 2);
    service->reload();
    QCOMPARE(service->entities()[1].toMap()["homepage"].toString(), QString("https://example.org"));
    QVERIFY(service->configured());
    service->followEntity(service->entities()[0].toMap(), false);
    QVERIFY(!service->followingEntity("A123"));
    QVERIFY(service->followingEntity("I123"));
    QVERIFY(service->followingPerson("123"));
}
void ForYouTest::searchCacheKoreanAndRetryRecovery()
{
    OpenAlexServer server;
    QVERIFY(server.server.isListening());
    server.body = R"({"results":[{"id":"https://openalex.org/A1","display_name":"Juhyun Kim"}]})";
    QTemporaryDir dir;
    ResearchStore store(dir.path());
    QString error;
    QVERIFY2(store.initialize(&error), qPrintable(error));
    store.setSetting("forYou.openAlexBaseUrl", server.base());
    auto *service = qobject_cast<ForYou *>(store.forYou());
    QSignalSpy found(service, &ForYou::entitiesFound);
    service->findEntities("김주현", "person");
    service->findEntities("김주현", "person");
    QTRY_COMPARE(found.size(), 1);
    QCOMPARE(server.urls.size(), 1);
    QCOMPARE(QUrlQuery(server.urls[0]).queryItemValue("search"), QString("Juhyun Kim"));
    QCOMPARE(found.last()[2].toList().size(), 1);
    service->findEntities("김주현", "person");
    QTRY_COMPARE(found.size(), 2);
    QCOMPARE(server.urls.size(), 1);
    server.status = 429;
    service->findEntities("Example University", "institution");
    QTRY_COMPARE(found.size(), 3);
    QVERIFY(service->entityRetrySeconds() > 0);
    QCOMPARE(server.urls.last().path(), QString("/institutions"));
    service->findEntities("Different University", "institution");
    QTRY_COMPARE(found.size(), 4);
    QCOMPARE(server.urls.size(), 2);
    QVERIFY(found.last()[3].toString().contains("limit"));
    QTRY_COMPARE_WITH_TIMEOUT(service->entityRetrySeconds(), 0, 3000);
    server.status = 200;
    server.body = R"({"results":[{"id":"https://openalex.org/I2","display_name":"Example University"}]})";
    service->findEntities("Example University", "institution");
    QTRY_COMPARE(found.size(), 5);
    QCOMPARE(found.last()[2].toList()[0].toMap()["id"].toString(), QString("I2"));
    QVERIFY(found.last()[3].toString().isEmpty());
    // A superseded lookup cannot replace the new kind/name, and failures aren't cached as zero matches.
    service->findEntities("Old request", "person");
    service->findEntities("Newest request", "institution");
    QTRY_COMPARE(found.size(), 6);
    QCOMPARE(found.last()[0].toString(), QString("Newest request"));
    server.body = "not json";
    service->findEntities("Unreadable", "institution");
    QTRY_COMPARE(found.size(), 7);
    QVERIFY(found.last()[3].toString().contains("unreadable"));
    server.body = R"({"results":[]})";
    service->findEntities("Unreadable", "institution");
    QTRY_COMPARE(found.size(), 8);
    QVERIFY(found.last()[3].toString().isEmpty());
}
void ForYouTest::collectDeduplicateAndFilterBothFollows()
{
    OpenAlexServer server;
    QVERIFY(server.server.isListening());
    const auto today = QDateTime::currentDateTimeUtc().date().toString(Qt::ISODate);
    server.body = QString(R"({"results":[
            {"id":"https://openalex.org/W1","doi":"https://doi.org/10.1234/shared","title":"Shared paper","publication_date":"%1"},
            {"id":"https://openalex.org/W2","title":"No DOI paper","publication_date":"%1"},
            {"id":"https://openalex.org/W3","title":"Old paper","publication_date":"1990-01-01"},
            {"id":"https://openalex.org/W4","title":"Future paper","publication_date":"2099-01-01"}]})")
                      .arg(today)
                      .toUtf8();
    QTemporaryDir dir;
    ResearchStore store(dir.path());
    QString error;
    QVERIFY2(store.initialize(&error), qPrintable(error));
    store.setSetting("forYou.openAlexBaseUrl", server.base());
    store.setSetting("forYou.delayMs", "0");
    store.setSetting("forYou.ai", "0");
    auto *service = qobject_cast<ForYou *>(store.forYou());
    service->followEntity({{"id", "A1"}, {"kind", "person"}, {"name", "Researcher"}}, true);
    service->followEntity({{"id", "I2"}, {"kind", "institution"}, {"name", "Institution"}}, true);
    QVERIFY(service->configured());
    service->refresh();
    QTRY_VERIFY(!service->checking());
    QCOMPARE(server.urls.size(), 2);
    QCOMPARE(service->items().size(), 2);
    QVERIFY(QUrlQuery(server.urls[0]).queryItemValue("filter").contains("authorships.author.id:A1"));
    QVERIFY(QUrlQuery(server.urls[1]).queryItemValue("filter").contains("authorships.institutions.lineage:I2"));
    QCOMPARE(service->sources().size(), 2);
    for (const auto &source : service->sources()) QCOMPARE(source.toMap()["count"].toInt(), 2);
    for (const auto &paper : service->items()) QCOMPARE(paper.toMap()["sources"].toList().size(), 2);
    service->refresh();
    QTRY_VERIFY(!service->checking());
    QCOMPARE(service->items().size(), 2);
    service->dismiss({"doi:10.1234/shared"});
    service->refresh();
    QTRY_VERIFY(!service->checking());
    QCOMPARE(service->items().size(), 1);
    QCOMPARE(service->items()[0].toMap()["id"].toString(), QString("openalex:W2"));
    service->reload();
    QCOMPARE(service->items()[0].toMap()["sources"].toList().size(), 2);
    server.status = 429;
    const int before = server.urls.size();
    service->refresh();
    QTRY_VERIFY(!service->checking());
    QCOMPARE(server.urls.size(), before + 1); // The second follow is not queried while rate limited.
    QVERIFY(service->problem().contains("limit"));
    QCOMPARE(service->items().size(), 1); // Existing papers remain available during an outage.
}
QTEST_MAIN(ForYouTest)
