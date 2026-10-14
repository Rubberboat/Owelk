#include "ResearchStore.h"

#include <QDateTime>
#include <QHash>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSqlQuery>
#include <QUuid>

#include <algorithm>

namespace {
QString now()
{
    return QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
}
QString text(const QString &value)
{
    return value.isNull() ? QStringLiteral("") : value;
}
}

QString ResearchStore::createAiThread(const QVariantMap &thread)
{
    const auto id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    const auto source = thread.value("source").toUrl();
    auto title = thread.value("title").toString().simplified().left(160);
    if (title.isEmpty())
        title = source.isValid() && !source.isEmpty() ? displayName(source) : QStringLiteral("New thread");
    // Started in a Thread (one of the reader's own, General, a paper's), it stays there; otherwise it
    // follows its paper.
    auto topic = thread.value("topic").toString();
    if (!isAiTopicKey(topic, aiTopicIds())) topic.clear();
    topic = aiKeptTopic(topic, source.isValid() ? source.toString() : QString());
    QSqlQuery query(m_database);
    query.prepare("INSERT INTO ai_threads(id,title,provider,model,source,created_at,updated_at,topic_id) "
                  "VALUES(?,?,?,?,?,?,?,?)");
    for (const QString &value : {id, title, thread.value("provider").toString(), thread.value("model").toString(),
             source.isValid() ? source.toString() : QString(), now(), now(), topic})
        query.addBindValue(text(value));
    if (!query.exec()) {
        emit message("Cannot start an AI thread.");
        return {};
    }
    if (!topic.isEmpty()) {
        QSqlQuery touch(m_database);
        touch.prepare("UPDATE ai_topics SET updated_at=? WHERE id=?");
        touch.addBindValue(now());
        touch.addBindValue(topic);
        touch.exec();
    }
    // A thread about a paper links to it, so the paper's Links tab finds the conversation.
    const auto document = findDocument(source);
    if (!document.isEmpty()) addLink("ai", id, "document", document);
    emit aiThreadsChanged();
    return id;
}

bool ResearchStore::appendAiMessage(const QString &threadId, const QVariantMap &message)
{
    const auto role = message.value("role").toString();
    if (role != "user" && role != "assistant") return false;
    QSqlQuery query(m_database);
    query.prepare("INSERT INTO ai_messages SELECT ?,id,?,?,?,?,?,? FROM ai_threads WHERE id=?");
    query.addBindValue(QUuid::createUuid().toString(QUuid::WithoutBraces));
    query.addBindValue(role);
    query.addBindValue(text(message.value("content").toString()));
    query.addBindValue(text(message.value("display").toString()));
    query.addBindValue(QString::fromUtf8(
        QJsonDocument(QJsonObject::fromVariantMap(message.value("context").toMap())).toJson(QJsonDocument::Compact)));
    query.addBindValue(text(message.value("model").toString()));
    query.addBindValue(now());
    query.addBindValue(threadId);
    if (!query.exec() || query.numRowsAffected() != 1) return false;
    QSqlQuery touch(m_database);
    touch.prepare(
        "UPDATE ai_threads SET "
        "updated_at=?,provider=coalesce(nullif(?,''),provider),model=coalesce(nullif(?,''),model) WHERE id=?");
    touch.addBindValue(now());
    touch.addBindValue(text(message.value("provider").toString()));
    touch.addBindValue(text(message.value("model").toString()));
    touch.addBindValue(threadId);
    touch.exec();
    emit aiThreadsChanged();
    return true;
}

QVariantList ResearchStore::aiThreads() const
{
    QVariantList rows;
    const auto topics = aiTopicIds();
    QHash<QString, QString> papers;
    QSqlQuery query(m_database);
    query.exec("SELECT t.id,t.title,t.provider,t.model,t.source,t.updated_at,(SELECT count(*) FROM ai_messages m "
               "WHERE m.thread_id=t.id),t.topic_id FROM ai_threads t WHERE t.trashed_at IS NULL "
               "ORDER BY t.updated_at DESC LIMIT 500");
    while (query.next())
        rows.append(QVariantMap{{"id", query.value(0)}, {"title", query.value(1)}, {"provider", query.value(2)},
            {"model", query.value(3)}, {"source", QUrl(query.value(4).toString())}, {"updatedAt", query.value(5)},
            {"messages", query.value(6)},
            {"topic", aiChatTopic(query.value(7).toString(), query.value(4).toString(), topics, &papers)}});
    return rows;
}

QSet<QString> ResearchStore::aiTopicIds() const
{
    QSet<QString> ids;
    QSqlQuery query(m_database);
    query.exec("SELECT id FROM ai_topics");
    while (query.next()) ids.insert(query.value(0).toString());
    return ids;
}

bool ResearchStore::isAiTopicKey(const QString &key, const QSet<QString> &topics)
{
    return topics.contains(key) || key == QStringLiteral("general")
        || (key.startsWith(QStringLiteral("paper:")) && key.size() > 6);
}

QString ResearchStore::aiKeptTopic(const QString &key, const QString &source) const
{
    if (key.isEmpty() || aiTopicIds().contains(key)) return key;
    return key == aiTopicFor(QUrl(source)) ? QString() : key;
}

QUrl ResearchStore::aiTopicSource(const QString &key) const
{
    if (!key.startsWith(QStringLiteral("paper:"))) return {};
    const auto rest = key.mid(6);
    QSqlQuery query(m_database);
    query.prepare("SELECT url FROM documents WHERE id=?");
    query.addBindValue(rest);
    if (query.exec() && query.next()) return QUrl(query.value(0).toString());
    // A paper outside the Library: its address.
    const QUrl address(rest);
    return address.scheme().isEmpty() ? QUrl() : address;
}

QString ResearchStore::aiChatTopic(
    const QString &topicId, const QString &source, const QSet<QString> &topics, QHash<QString, QString> *papers) const
{
    if (!topicId.isEmpty() && isAiTopicKey(topicId, topics)) return topicId;
    if (source.isEmpty()) return QStringLiteral("general");
    if (!papers->contains(source)) papers->insert(source, aiTopicFor(QUrl(source)));
    return papers->value(source);
}

QString ResearchStore::aiTopicFor(const QUrl &source) const
{
    if (!source.isValid() || source.isEmpty()) return QStringLiteral("general");
    // The paper's ID, so copies and relinked paths share one Thread (the address while it has none).
    const auto document = findDocument(source);
    return QStringLiteral("paper:") + (document.isEmpty() ? resolvedSource(source).toString() : document);
}

QVariantList ResearchStore::aiTopics() const
{
    QHash<QString, QVariantMap> rows;
    QSqlQuery own(m_database);
    own.exec("SELECT id,title,updated_at FROM ai_topics");
    while (own.next())
        rows.insert(own.value(0).toString(),
            {{"key", own.value(0)}, {"kind", "custom"}, {"title", own.value(1)}, {"chats", 0},
                {"updatedAt", own.value(2)}});
    const auto topics = aiTopicIds();
    QHash<QString, QString> papers;
    QSqlQuery chats(m_database);
    chats.exec("SELECT topic_id,source,updated_at FROM ai_threads WHERE trashed_at IS NULL");
    while (chats.next()) {
        const auto kept = chats.value(0).toString(), source = chats.value(1).toString();
        const auto updated = chats.value(2).toString();
        const auto key = aiChatTopic(kept, source, topics, &papers);
        auto &row = rows[key];
        if (row.isEmpty()) {
            const bool general = key == QStringLiteral("general");
            row = {{"key", key}, {"kind", general ? "general" : "paper"}, {"title", QStringLiteral("General")},
                {"chats", 0}, {"updatedAt", QString()}};
            if (!general) {
                // A chat put in another paper's Thread names that paper, not its own.
                const auto paper = kept == key ? aiTopicSource(key) : resolvedSource(QUrl(source));
                row.insert("source", paper);
                row.insert("title", paper.isEmpty() ? QStringLiteral("Paper") : displayName(paper));
            }
        }
        row["chats"] = row.value("chats").toInt() + 1;
        if (updated > row.value("updatedAt").toString()) row["updatedAt"] = updated;
    }
    QVariantList list;
    for (const auto &row : std::as_const(rows)) list.append(row);
    std::sort(list.begin(), list.end(), [](const QVariant &a, const QVariant &b) {
        const auto x = a.toMap(), y = b.toMap();
        const auto first = x.value("updatedAt").toString(), second = y.value("updatedAt").toString();
        return first != second ? first > second
                               : x.value("title").toString().localeAwareCompare(y.value("title").toString()) < 0;
    });
    return list;
}

QString ResearchStore::createAiTopic(const QString &title)
{
    const auto id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    auto name = title.simplified().left(160);
    if (name.isEmpty()) name = QStringLiteral("New Thread");
    QSqlQuery query(m_database);
    query.prepare("INSERT INTO ai_topics(id,title,created_at,updated_at) VALUES(?,?,?,?)");
    for (const QString &value : {id, name, now(), now()}) query.addBindValue(value);
    if (!query.exec()) {
        emit message("Cannot make the Thread.");
        return {};
    }
    emit aiThreadsChanged();
    return id;
}

bool ResearchStore::renameAiTopic(const QString &id, const QString &title)
{
    const auto name = title.simplified().left(160);
    if (name.isEmpty()) return false;
    QSqlQuery query(m_database);
    query.prepare("UPDATE ai_topics SET title=?,updated_at=? WHERE id=?");
    query.addBindValue(name);
    query.addBindValue(now());
    query.addBindValue(id);
    if (!query.exec() || query.numRowsAffected() != 1) return false;
    emit aiThreadsChanged();
    return true;
}

bool ResearchStore::deleteAiTopic(const QString &id)
{
    if (id.isEmpty() || !m_database.transaction()) return false;
    QSqlQuery chats(m_database), topic(m_database);
    chats.prepare("UPDATE ai_threads SET topic_id='' WHERE topic_id=?");
    chats.addBindValue(id);
    topic.prepare("DELETE FROM ai_topics WHERE id=?");
    topic.addBindValue(id);
    if (!chats.exec() || !topic.exec() || topic.numRowsAffected() != 1 || !m_database.commit()) {
        m_database.rollback();
        return false;
    }
    emit aiThreadsChanged();
    return true;
}

int ResearchStore::moveAiThreads(const QStringList &ids, const QString &topicId)
{
    // An empty ID from QML may arrive as a null string, which SQLite would store as NULL.
    const auto topic = text(topicId);
    if (!topic.isEmpty() && !isAiTopicKey(topic, aiTopicIds())) return 0;
    int moved = 0;
    for (const auto &id : ids) {
        QSqlQuery source(m_database);
        source.prepare("SELECT source FROM ai_threads WHERE id=?");
        source.addBindValue(id);
        if (!source.exec() || !source.next()) continue;
        const auto kept = text(aiKeptTopic(topic, source.value(0).toString()));
        QSqlQuery query(m_database);
        query.prepare("UPDATE ai_threads SET topic_id=? WHERE id=? AND topic_id<>?");
        query.addBindValue(kept);
        query.addBindValue(id);
        query.addBindValue(kept);
        if (query.exec()) moved += query.numRowsAffected();
    }
    if (!moved) return 0;
    if (!topic.isEmpty()) {
        QSqlQuery touch(m_database);
        touch.prepare("UPDATE ai_topics SET updated_at=? WHERE id=?");
        touch.addBindValue(now());
        touch.addBindValue(topic);
        touch.exec();
    }
    emit aiThreadsChanged();
    return moved;
}

QVariantMap ResearchStore::aiThread(const QString &id) const
{
    QSqlQuery query(m_database);
    query.prepare(
        "SELECT title,provider,model,source,created_at,updated_at,trashed_at IS NOT NULL,topic_id FROM ai_threads "
        "WHERE id=?");
    query.addBindValue(id);
    if (!query.exec() || !query.next()) return {};
    QHash<QString, QString> papers;
    QVariantMap thread{{"id", id}, {"title", query.value(0)}, {"provider", query.value(1)}, {"model", query.value(2)},
        {"source", QUrl(query.value(3).toString())}, {"createdAt", query.value(4)}, {"updatedAt", query.value(5)},
        {"trashed", query.value(6).toBool()},
        {"topic", aiChatTopic(query.value(7).toString(), query.value(3).toString(), aiTopicIds(), &papers)}};
    QSqlQuery messages(m_database);
    messages.prepare("SELECT id,role,content,display,context_json,model,created_at FROM ai_messages WHERE thread_id=? "
                     "ORDER BY created_at, role DESC");
    messages.addBindValue(id);
    QVariantList list;
    if (messages.exec())
        while (messages.next())
            list.append(QVariantMap{{"id", messages.value(0)}, {"role", messages.value(1)},
                {"content", messages.value(2)}, {"display", messages.value(3)},
                {"context", QJsonDocument::fromJson(messages.value(4).toByteArray()).toVariant()},
                {"model", messages.value(5)}, {"createdAt", messages.value(6)}});
    thread.insert("messages", list);
    return thread;
}

bool ResearchStore::renameAiThread(const QString &id, const QString &title)
{
    const auto name = title.simplified().left(160);
    if (name.isEmpty()) return false;
    QSqlQuery query(m_database);
    query.prepare("UPDATE ai_threads SET title=? WHERE id=?");
    query.addBindValue(name);
    query.addBindValue(id);
    if (!query.exec() || query.numRowsAffected() != 1) return false;
    emit aiThreadsChanged();
    return true;
}

int ResearchStore::trashAiThreads(const QStringList &ids, bool trashed)
{
    // In the Trash a thread is hidden (list, search) but whole: restoring brings it back as it was.
    int moved = 0;
    const auto now = QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
    for (const auto &id : ids) {
        QSqlQuery query(m_database);
        query.prepare(trashed ? "UPDATE ai_threads SET trashed_at=? WHERE id=? AND trashed_at IS NULL"
                              : "UPDATE ai_threads SET trashed_at=NULL WHERE id=? AND trashed_at IS NOT NULL");
        if (trashed) query.addBindValue(now);
        query.addBindValue(id);
        if (query.exec()) moved += query.numRowsAffected();
    }
    if (!moved) return 0;
    emit aiThreadsChanged();
    if (trashed) {
        const auto days = trashDays();
        emit message((moved == 1 ? QStringLiteral("Moved the conversation to the Trash.")
                                 : QString("Moved %1 conversations to the Trash.").arg(moved))
            + (days > 0 ? QString(" It is deleted for good after %1 days.").arg(days) : QString()));
    }
    return moved;
}

int ResearchStore::purgeAiThreads(const QStringList &ids)
{
    int deleted = 0;
    for (const auto &id : ids)
        if (deleteAiThread(id)) ++deleted;
    return deleted;
}

bool ResearchStore::deleteAiThread(const QString &id)
{
    // Removes the conversation and its links; notes that quoted it keep their text.
    if (!m_database.transaction()) return false;
    const auto run = [&](const QString &sql, int bindings) {
        QSqlQuery query(m_database);
        query.prepare(sql);
        for (int i = 0; i < bindings; ++i) query.addBindValue(id);
        return query.exec();
    };
    const bool ok = run("DELETE FROM ai_messages WHERE thread_id=?", 1) && run("DELETE FROM ai_threads WHERE id=?", 1)
        && run("DELETE FROM ai_responses WHERE id=?", 1)
        && run("DELETE FROM links WHERE (from_kind='ai' AND from_id=?) OR (to_kind='ai' AND to_id=?)", 2);
    if (!ok || !m_database.commit()) {
        m_database.rollback();
        return false;
    }
    emit aiThreadsChanged();
    emit linksChanged();
    return true;
}
