#include "SearchText.h"
#include "ResearchStore.h"
#include "ForYou.h"
#include "PaperIndex.h"
#include "AiService.h"
#include "PdfFixture.h"
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSignalSpy>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QUrlQuery>
#include <QtTest>

class SearchServer : public QObject {
public:
    QTcpServer server;
    QList<QUrl> urls;
    QList<QByteArray> bodies;
    std::function<QByteArray(const QUrl &)> answer;
    SearchServer()
    {
        server.listen(QHostAddress::LocalHost);
        connect(&server, &QTcpServer::newConnection, this, [this] {
            auto *socket = server.nextPendingConnection();
            auto buffer = std::make_shared<QByteArray>();
            auto handled = std::make_shared<bool>(false);
            connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
            connect(socket, &QTcpSocket::readyRead, socket, [this, socket, buffer, handled] {
                *buffer += socket->readAll();
                const auto end = buffer->indexOf("\r\n\r\n");
                if (*handled || end < 0) return;
                const int length
                    = QRegularExpression("Content-Length: (\\d+)", QRegularExpression::CaseInsensitiveOption)
                          .match(QString::fromUtf8(buffer->left(end)))
                          .captured(1)
                          .toInt();
                if (buffer->size() < end + 4 + length) return;
                *handled = true;
                const auto url = QUrl::fromEncoded(buffer->split(' ').value(1));
                urls << url;
                bodies << buffer->mid(end + 4, length);
                const auto body = answer ? answer(url) : QByteArray("{}");
                socket->write(
                    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: "
                    + QByteArray::number(body.size()) + "\r\n\r\n" + body);
                socket->disconnectFromHost();
            });
        });
    }
    QString base() const { return QString("http://127.0.0.1:%1").arg(server.serverPort()); }
};

class SearchTextTest : public QObject {
    Q_OBJECT
private slots:
    void koreanNameSpellingsAndTopics()
    {
        const auto names = SearchText::localVariants("김주현");
        QCOMPARE(names.first(), QString("김주현"));
        for (const auto &name : {"Juhyun Kim", "Ju-hyun Kim", "Kim Juhyun", "Kim Juhyeon", "Kim Ju Hyun"})
            QVERIFY2(SearchText::matchesAny(name, names), name);
        QVERIFY(!SearchText::matchesAny("Minho Kim", names));
        QCOMPARE(SearchText::localVariants(QString("김주현").normalized(QString::NormalizationForm_D)), names);
        QVERIFY(SearchText::matchesAny("Juhyun Kim", SearchText::localVariants("김 주현")));
        QVERIFY(SearchText::matchesAny("Minho Lee", SearchText::localVariants("이민호")));
        QVERIFY(SearchText::matchesAny("Radar Odometry", SearchText::localVariants("레이더 오도메트리")));
        QVERIFY(SearchText::matchesAny("Machine learning", SearchText::localVariants("기계학습")));
        QVERIFY(!SearchText::matchesAny("Radar detection", SearchText::localVariants("레이더 오도메트리")));
        QCOMPARE(SearchText::localVariants("unknownterm"), QStringList{"unknownterm"});
        QVERIFY(
            ForYouParse::arxivQuery("레이더", "cs.RO", QDateTime::currentDateTimeUtc(), QDateTime::currentDateTimeUtc())
                .contains("all:radar"));
    }
    void localLibraryAndNotesKeepFiltersAndDeduplicate()
    {
        QTemporaryDir dir;
        ResearchStore store(dir.filePath("data"));
        QString error;
        QVERIFY2(store.initialize(&error), qPrintable(error));
        QList<QUrl> papers;
        const QStringList authors{"Juhyun Kim", "Ju-hyun Kim", "Minho Lee"};
        for (int i = 0; i < 3; ++i) {
            const auto file = dir.filePath(QString("paper-%1.pdf").arg(i));
            writeFixture(file);
            papers << QUrl::fromLocalFile(file);
            QVERIFY(store.rememberDocument(papers.last()));
            QVERIFY(store.updateDocumentDetails(
                papers.last(), {{"title", "Radar odometry"}, {"authors", authors[i]}, {"year", "2025"}}));
        }
        QCOMPARE(store.libraryDocuments({{"text", "김주현"}}).size(), 2);
        QCOMPARE(store.libraryDocuments({{"text", "김주현 레이더"}, {"limit", 1}}).size(), 1);
        QCOMPARE(store.libraryDocuments({{"text", "김주현"}, {"yearFrom", 2026}}).size(), 0);
        const auto note = store.createNote("Reading", "Radar odometry by Ju-hyun Kim");
        const auto rows = store.searchKnowledge("김주현 레이더");
        QSet<QString> urls;
        bool foundNote = false;
        int count = 0;
        for (const auto &value : rows) {
            const auto row = value.toMap();
            if (row["kind"] == "paper") {
                ++count;
                urls.insert(row["source"].toUrl().toString());
            }
            if (row["id"].toString() == note) foundNote = true;
        }
        QCOMPARE(count, 2);
        QCOMPARE(urls.size(), 2);
        QVERIFY(foundNote);
        const auto scoped = store.searchKnowledge("김주현", papers[1], "filename");
        QCOMPARE(scoped.size(), 1);
        QCOMPARE(scoped[0].toMap()["source"].toUrl(), papers[1]);
        QVERIFY(store.searchKnowledge("' OR 1=1 --").isEmpty());
    }
    void indexedEnglishPagesMatchKoreanWithoutDuplicates()
    {
        QTemporaryDir dir;
        const auto path = dir.filePath("names.pdf");
        writeTextFixture(path,
            {"Radar odometry by Juhyun Kim.", "Machine learning by Kim Ju-hyun.", "Unrelated optics by Alice Smith."});
        QVERIFY(QDir().mkpath(dir.filePath("index")));
        PaperIndex index(dir.filePath("index"));
        QString error;
        QVERIFY2(index.initialize(&error), qPrintable(error));
        index.enqueue(QUrl::fromLocalFile(path));
        QTRY_VERIFY_WITH_TIMEOUT(!index.busy(), 10000);
        QSignalSpy found(&index, &PaperIndex::searchFinished);
        index.search("김주현");
        QTRY_COMPARE_WITH_TIMEOUT(found.size(), 1, 10000);
        QVERIFY2(found[0][2].toString().isEmpty(), qPrintable(found[0][2].toString()));
        QCOMPARE(found[0][1].toList().size(), 2);
        index.search("레이더 오도메트리");
        QTRY_COMPARE(found.size(), 2);
        QCOMPARE(found[1][1].toList().size(), 1);
        QCOMPARE(found[1][1].toList()[0].toMap()["page"].toInt(), 0);
    }
    void peopleExpandSpellingsButKeepDifferentAuthors()
    {
        SearchServer server;
        server.answer = [](const QUrl &url) {
            const auto query = QUrlQuery(url).queryItemValue("query");
            QJsonArray people;
            if (query.contains("hyun", Qt::CaseInsensitive)) {
                people << QJsonObject{{"authorId", "77"}, {"name", "Juhyun Kim"}, {"paperCount", 12}};
                people << QJsonObject{{"authorId", "78"}, {"name", "Ju-hyun Kim"}, {"paperCount", 4}};
            }
            return QJsonDocument(QJsonObject{{"data", people}}).toJson();
        };
        QTemporaryDir dir;
        ResearchStore store(dir.filePath("data"));
        QString error;
        QVERIFY(store.initialize(&error));
        store.setSetting("forYou.graphBaseUrl", server.base());
        store.setSetting("forYou.delayMs", "10");
        auto *forYou = qobject_cast<ForYou *>(store.forYou());
        QSignalSpy found(forYou, &ForYou::peopleFound);
        forYou->findPeople("김주현");
        QTRY_COMPARE_WITH_TIMEOUT(found.size(), 1, 10000);
        QCOMPARE(found[0][0].toString(), QString("김주현"));
        QCOMPARE(found[0][1].toList().size(), 2);
        QVERIFY(found[0][2].toString().isEmpty());
        QVERIFY(server.urls.size() > 1 && server.urls.size() <= 6);
        QVERIFY(std::any_of(server.urls.begin(), server.urls.end(),
            [](const auto &url) { return QUrlQuery(url).queryItemValue("query") == "Juhyun Kim"; }));
        QCOMPARE(forYou->people().size(), 0); // Retrieval never silently follows or merges identities.
        found.clear();
        forYou->findPeople("이민호");
        forYou->findPeople("Other Person");
        QTRY_COMPARE(found.size(), 1);
        QCOMPARE(found[0][0].toString(), QString("Other Person"));
    }
    void aiTranslationIsAutomaticDebouncedAndQueryOnly()
    {
        SearchServer server;
        server.answer = [](const QUrl &) {
            const auto content
                = QString::fromUtf8(QJsonDocument(QJsonObject{{"terms", QJsonArray{"quasiperiodic crystal"}}})
                        .toJson(QJsonDocument::Compact));
            return QJsonDocument(QJsonObject{{"message", QJsonObject{{"content", content}}}, {"done", true}})
                       .toJson(QJsonDocument::Compact)
                + '\n';
        };
        QTemporaryDir dir;
        ResearchStore store(dir.filePath("data"));
        QString error;
        QVERIFY(store.initialize(&error));
        auto *ai = qobject_cast<AiService *>(store.ai());
        store.setSetting("ai.baseUrl.ollama", server.base());
        store.createNote("Private paper", "secret library content must never be sent");
        auto *search = qobject_cast<SearchText *>(store.searchText());
        search->prepare("준주기 결정");
        QTest::qWait(700);
        QCOMPARE(server.urls.size(), 0);
        // Local Ollama is ready without cloud consent or an extra search opt-in.
        ai->setProvider("ollama");
        search->prepare("준주기 결정");
        search->prepare("");
        QTest::qWait(700);
        QCOMPARE(server.urls.size(), 0);
        QSignalSpy ready(search, &SearchText::changed);
        search->prepare("준주기 결정");
        QTRY_COMPARE_WITH_TIMEOUT(ready.size(), 1, 5000);
        QCOMPARE(server.urls.size(), 1);
        QVERIFY(search->variants("준주기 결정").contains("quasiperiodic crystal"));
        QVERIFY(!server.bodies[0].contains("secret library"));
        const auto messages = QJsonDocument::fromJson(server.bodies[0]).object()["messages"].toArray();
        QCOMPARE(messages.last().toObject()["content"].toString(), QString("준주기 결정"));
        search->prepare("준주기 결정");
        QTest::qWait(700);
        QCOMPARE(server.urls.size(), 1);
        QSignalSpy configuration(search, &SearchText::configurationChanged);
        store.setSetting("search.aiTranslation", "0");
        QCOMPARE(configuration.size(), 1);
        QVERIFY(!search->variants("준주기 결정").contains("quasiperiodic crystal"));
        search->prepare("다른 검색어");
        QTest::qWait(700);
        QCOMPARE(server.urls.size(), 1);
    }
};
QTEST_MAIN(SearchTextTest)
#include "SearchTextTest.moc"
