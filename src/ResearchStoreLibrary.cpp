#include "ResearchStore.h"
#include "PaperIndex.h"
#include "FileFingerprint.h"
#include "PaperMetadata.h"

#include <QDateTime>
#include <QDirIterator>
#include <QFile>
#include <QFutureWatcher>
#include <QtConcurrent>
#include <QFileInfo>
#include <QGuiApplication>
#include <QRegularExpression>
#include <QSet>
#include <QSqlQuery>
#include <QUuid>

namespace {
QString now()
{
    return QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
}
QString newId()
{
    return QUuid::createUuid().toString(QUuid::WithoutBraces);
}
}

// Documents in scope of the library filters. Keys (all optional): text, state (unread|reading|read),
// favorite (bool), unsorted (bool: in no collection), collection (id), tag (id), yearFrom, yearTo, sort
// (opened|added|title|year).
QVariantList ResearchStore::libraryDocuments(const QVariantMap &filter) const
{
    QStringList where{"d.url LIKE 'file:%'", "d.removed_at IS NULL"};
    QVariantList args;
    const auto text = filter.value("text").toString().trimmed();
    if (!text.isEmpty()) {
        where << "(instr(lower(d.title),lower(?))>0 OR instr(lower(d.authors),lower(?))>0 OR "
                 "instr(lower(d.url),lower(?))>0 OR d.year=? OR instr(lower(d.doi),lower(?))>0 OR d.arxiv=?)";
        for (int i = 0; i < 6; ++i) args << text;
    }
    if (filter.contains("state")) {
        where << "d.reading_state=?";
        args << filter.value("state").toString();
    }
    if (filter.value("favorite").toBool()) where << "d.favorite=1";
    if (filter.value("unsorted").toBool()) where << "d.id NOT IN (SELECT document_id FROM collection_documents)";
    if (filter.contains("collection")) {
        // A collection includes the papers of its sub-collections.
        where << "d.id IN (WITH RECURSIVE tree(id) AS (SELECT ? UNION SELECT c.id FROM collections c JOIN tree ON "
                 "c.parent_id=tree.id) SELECT document_id FROM collection_documents WHERE collection_id IN tree)";
        args << filter.value("collection").toString();
    }
    if (filter.contains("tag")) {
        where << "d.id IN (SELECT document_id FROM document_tags WHERE tag_id=?)";
        args << filter.value("tag").toString();
    }
    if (filter.contains("yearFrom")) {
        where << "d.year<>'' AND CAST(d.year AS INTEGER)>=?";
        args << filter.value("yearFrom").toInt();
    }
    if (filter.contains("yearTo")) {
        where << "d.year<>'' AND CAST(d.year AS INTEGER)<=?";
        args << filter.value("yearTo").toInt();
    }
    const auto sort = filter.value("sort").toString();
    const QString order = sort == "title" ? "coalesce(nullif(d.title,''),d.url) COLLATE NOCASE"
        : sort == "year"                  ? "d.year DESC, d.title COLLATE NOCASE"
        : sort == "added"                 ? "d.added_at DESC"
                                          : "r.opened_at IS NULL, r.opened_at DESC, d.added_at DESC";
    QSqlQuery query(m_database);
    query.prepare("SELECT d.id,d.url,d.authors,d.year,d.reading_state,d.favorite,d.excluded_from_index,d.sha256,"
                  "(SELECT group_concat(t.name, ', ') FROM document_tags dt JOIN tags t ON t.id=dt.tag_id "
                  "WHERE dt.document_id=d.id),"
                  "(d.sha256<>'' AND EXISTS(SELECT 1 FROM documents o WHERE o.sha256=d.sha256 AND o.id<>d.id)) "
                  "FROM documents d LEFT JOIN recent_documents r ON r.document_id=d.id WHERE "
        + where.join(" AND ") + " ORDER BY " + order);
    for (const auto &arg : args) query.addBindValue(arg);
    QVariantList rows;
    if (!query.exec()) return rows;
    while (query.next()) {
        const QUrl url(query.value(1).toString());
        rows.append(QVariantMap{{"id", query.value(0)}, {"url", url}, {"name", displayName(url)},
            {"fileName", fileName(url)}, {"authors", query.value(2)}, {"year", query.value(3)},
            {"readingState", query.value(4)}, {"favorite", query.value(5).toBool()},
            {"excluded", query.value(6).toBool()}, {"tags", query.value(8).toString()},
            {"duplicate", query.value(9).toBool()}});
    }
    return rows;
}

void ResearchStore::markOpened(const QString &kind, const QString &id)
{
    if (!QStringList{"note", "ai", "collection"}.contains(kind) || id.isEmpty()) return;
    QSqlQuery query(m_database);
    query.prepare("INSERT OR REPLACE INTO recent_items(kind,id,opened_at) VALUES(?,?,?)");
    query.addBindValue(kind);
    query.addBindValue(id);
    query.addBindValue(QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs));
    query.exec();
}

QVariantList ResearchStore::recentItems(const QString &kind, int limit) const
{
    QVariantList rows;
    QSqlQuery query(m_database);
    if (kind == "note")
        query.prepare("SELECT n.id,n.title FROM notes n LEFT JOIN recent_items r ON r.kind='note' AND r.id=n.id "
                      "WHERE n.deleted_at IS NULL ORDER BY max(coalesce(r.opened_at,''),n.updated_at) DESC LIMIT ?");
    else if (kind == "ai")
        query.prepare("SELECT t.id,t.title,t.source FROM ai_threads t LEFT JOIN recent_items r ON r.kind='ai' AND "
                      "r.id=t.id WHERE t.trashed_at IS NULL ORDER BY max(coalesce(r.opened_at,''),t.updated_at) DESC "
                      "LIMIT ?");
    else if (kind == "collection")
        query.prepare(
            "SELECT c.id,c.name,(SELECT count(*) FROM collection_documents cd JOIN documents d ON d.id=cd.document_id "
            "WHERE cd.collection_id=c.id AND d.removed_at IS NULL),max(coalesce(r.opened_at,''),coalesce((SELECT "
            "max(rd.opened_at) FROM collection_documents cd JOIN recent_documents rd ON rd.document_id=cd.document_id "
            "WHERE cd.collection_id=c.id),'')) AS last FROM collections c LEFT JOIN recent_items r ON "
            "r.kind='collection' AND r.id=c.id ORDER BY last DESC, c.name COLLATE NOCASE LIMIT ?");
    else
        return rows;
    query.addBindValue(limit);
    if (!query.exec()) return rows;
    while (query.next()) {
        if (kind == "note")
            rows.append(QVariantMap{{"id", query.value(0)},
                {"title", query.value(1).toString().isEmpty() ? "Untitled note" : query.value(1).toString()}});
        else if (kind == "ai") {
            const QUrl source(query.value(2).toString());
            rows.append(QVariantMap{{"id", query.value(0)}, {"title", query.value(1)},
                {"paper", source.isLocalFile() ? displayName(source) : QString()}});
        } else
            rows.append(QVariantMap{{"id", query.value(0)}, {"name", query.value(1)}, {"count", query.value(2)}});
    }
    return rows;
}

QVariantList ResearchStore::collections() const
{
    QVariantList rows;
    QSqlQuery query(m_database);
    query.exec("SELECT c.id,c.name,coalesce(c.parent_id,''),(SELECT count(*) FROM collection_documents cd "
               "JOIN documents d ON d.id=cd.document_id WHERE cd.collection_id=c.id AND d.removed_at IS NULL) FROM "
               "collections c ORDER BY c.name COLLATE NOCASE");
    QList<QVariantMap> all;
    while (query.next())
        all.append({{"id", query.value(0)}, {"name", query.value(1)}, {"parentId", query.value(2)},
            {"count", query.value(3)}});
    // Depth-first order with depth, ready for an indented list.
    std::function<void(const QString &, int)> add = [&](const QString &parent, int depth) {
        for (auto row : all)
            if (row["parentId"].toString() == parent) {
                row.insert("depth", depth);
                rows.append(row);
                if (depth < 16) add(row["id"].toString(), depth + 1);
            }
    };
    add(QString(), 0);
    return rows;
}

QString ResearchStore::createCollection(const QString &name, const QString &parentId)
{
    const auto trimmed = name.simplified();
    if (trimmed.isEmpty() || trimmed.size() > 120) {
        emit message("Enter a collection name (1–120 characters).");
        return {};
    }
    const auto id = newId();
    QSqlQuery query(m_database);
    query.prepare("INSERT INTO collections(id,name,parent_id,created_at) "
                  "SELECT ?,?,?,? WHERE ? IS NULL OR EXISTS(SELECT 1 FROM collections WHERE id=?)");
    const QVariant parent = parentId.isEmpty() ? QVariant() : QVariant(parentId);
    query.addBindValue(id);
    query.addBindValue(trimmed);
    query.addBindValue(parent);
    query.addBindValue(now());
    query.addBindValue(parent);
    query.addBindValue(parent);
    if (!query.exec() || query.numRowsAffected() != 1) return {};
    announceDocumentsChanged();
    return id;
}

bool ResearchStore::renameCollection(const QString &id, const QString &name)
{
    const auto trimmed = name.simplified();
    if (trimmed.isEmpty() || trimmed.size() > 120) return false;
    QSqlQuery query(m_database);
    query.prepare("UPDATE collections SET name=? WHERE id=?");
    query.addBindValue(trimmed);
    query.addBindValue(id);
    if (!query.exec() || query.numRowsAffected() != 1) return false;
    announceDocumentsChanged();
    return true;
}

bool ResearchStore::deleteCollection(const QString &id)
{
    // Only the grouping is removed; papers stay in the library and sub-collections move up one level.
    if (!m_database.transaction()) return false;
    const auto run = [&](const QString &sql) {
        QSqlQuery query(m_database);
        query.prepare(sql);
        query.addBindValue(id);
        return query.exec();
    };
    QSqlQuery reparent(m_database);
    reparent.prepare(
        "UPDATE collections SET parent_id=(SELECT parent_id FROM collections WHERE id=?) WHERE parent_id=?");
    reparent.addBindValue(id);
    reparent.addBindValue(id);
    const bool ok = reparent.exec() && run("DELETE FROM collection_documents WHERE collection_id=?")
        && run("DELETE FROM collections WHERE id=?");
    if (!ok || !m_database.commit()) {
        m_database.rollback();
        return false;
    }
    announceDocumentsChanged();
    return true;
}

bool ResearchStore::setDocumentCollection(const QUrl &source, const QString &collectionId, bool member)
{
    const auto document = ensureDocument(source);
    if (document.isEmpty()) return false;
    QSqlQuery query(m_database);
    query.prepare(member
            ? "INSERT OR IGNORE INTO collection_documents SELECT ?,? WHERE EXISTS(SELECT 1 FROM collections WHERE id=?)"
            : "DELETE FROM collection_documents WHERE collection_id=? AND document_id=?");
    query.addBindValue(collectionId);
    query.addBindValue(document);
    if (member) query.addBindValue(collectionId);
    if (!query.exec()) return false;
    announceDocumentsChanged();
    return true;
}

QVariantList ResearchStore::tags() const
{
    QVariantList rows;
    QSqlQuery query(m_database);
    query.exec("SELECT t.id,t.name,count(d.id) FROM tags t LEFT JOIN document_tags dt ON dt.tag_id=t.id "
               "LEFT JOIN documents d ON d.id=dt.document_id AND d.removed_at IS NULL "
               "GROUP BY t.id ORDER BY t.name COLLATE NOCASE");
    while (query.next())
        rows.append(QVariantMap{{"id", query.value(0)}, {"name", query.value(1)}, {"count", query.value(2)}});
    return rows;
}

bool ResearchStore::setDocumentTags(const QUrl &source, const QStringList &names)
{
    const auto document = ensureDocument(source);
    if (document.isEmpty() || !m_database.transaction()) return false;
    const auto fail = [this] {
        m_database.rollback();
        emit message("Cannot save tags.");
        return false;
    };
    QSqlQuery clear(m_database);
    clear.prepare("DELETE FROM document_tags WHERE document_id=?");
    clear.addBindValue(document);
    if (!clear.exec()) return fail();
    QSet<QString> seen;
    for (const auto &raw : names) {
        const auto name = raw.simplified();
        if (name.isEmpty() || name.size() > 60 || seen.contains(name.toLower())) continue;
        seen.insert(name.toLower());
        QSqlQuery tag(m_database);
        tag.prepare("INSERT OR IGNORE INTO tags(id,name) VALUES(?,?)");
        tag.addBindValue(newId());
        tag.addBindValue(name);
        QSqlQuery link(m_database);
        link.prepare("INSERT OR IGNORE INTO document_tags SELECT ?,id FROM tags WHERE name=?");
        link.addBindValue(document);
        link.addBindValue(name);
        if (!tag.exec() || !link.exec()) return fail();
    }
    // Tags nobody uses any more disappear from the list.
    QSqlQuery orphans(m_database);
    if (!orphans.exec("DELETE FROM tags WHERE id NOT IN (SELECT tag_id FROM document_tags)") || !m_database.commit())
        return fail();
    announceDocumentsChanged();
    return true;
}

QVariantMap ResearchStore::documentOrganization(const QUrl &source) const
{
    const auto document = findDocument(source);
    QStringList tagNames, collectionIds;
    QSqlQuery query(m_database);
    query.prepare(
        "SELECT t.name FROM document_tags dt JOIN tags t ON t.id=dt.tag_id WHERE dt.document_id=? ORDER BY t.name");
    query.addBindValue(document);
    if (query.exec())
        while (query.next()) tagNames << query.value(0).toString();
    query.prepare("SELECT collection_id FROM collection_documents WHERE document_id=?");
    query.addBindValue(document);
    if (query.exec())
        while (query.next()) collectionIds << query.value(0).toString();
    return {{"tags", tagNames}, {"collections", collectionIds}};
}

bool ResearchStore::setExcludedFromIndex(const QUrl &source, bool excluded)
{
    const auto document = ensureDocument(source);
    QSqlQuery query(m_database);
    query.prepare("UPDATE documents SET excluded_from_index=? WHERE id=?");
    query.addBindValue(excluded ? 1 : 0);
    query.addBindValue(document);
    if (document.isEmpty() || !query.exec() || query.numRowsAffected() != 1) return false;
    if (excluded)
        m_index->remove(resolvedSource(source));
    else
        m_index->enqueue(resolvedSource(source));
    emit message(excluded ? "Removed from the text index. Its pages no longer appear in PDF text search."
                          : "Added back to the text index.");
    announceDocumentsChanged();
    return true;
}

bool ResearchStore::excludedFromIndex(const QUrl &source) const
{
    QSqlQuery query(m_database);
    query.prepare("SELECT excluded_from_index FROM documents WHERE url=?");
    query.addBindValue(resolvedSource(source).toString());
    return query.exec() && query.next() && query.value(0).toBool();
}

int ResearchStore::unsortedCount() const
{
    QSqlQuery query(m_database);
    query.exec("SELECT count(*) FROM documents WHERE url LIKE 'file:%' AND removed_at IS NULL AND id NOT IN (SELECT "
               "document_id FROM collection_documents)");
    return query.next() ? query.value(0).toInt() : 0;
}

bool ResearchStore::setDocumentsCollection(const QVariantList &sources, const QString &collectionId, bool member)
{
    if (sources.isEmpty() || !m_database.transaction()) return false;
    for (const auto &value : sources) {
        const auto document = ensureDocument(value.toUrl());
        if (document.isEmpty()) continue;
        QSqlQuery query(m_database);
        query.prepare(member ? "INSERT OR IGNORE INTO collection_documents SELECT ?,? WHERE EXISTS(SELECT 1 FROM "
                               "collections WHERE id=?)"
                             : "DELETE FROM collection_documents WHERE collection_id=? AND document_id=?");
        query.addBindValue(collectionId);
        query.addBindValue(document);
        if (member) query.addBindValue(collectionId);
        if (!query.exec()) {
            m_database.rollback();
            return false;
        }
    }
    if (!m_database.commit()) return false;
    announceDocumentsChanged();
    return true;
}

int ResearchStore::suggestCollections(const QUrl &source)
{
    const int request = ++m_suggestRequest;
    const auto document = findDocument(source);
    const auto answer = [this, request, source](const QVariantList &list) {
        QMetaObject::invokeMethod(
            this, [=, this] { emit collectionsSuggested(request, source, list); }, Qt::QueuedConnection);
    };
    if (document.isEmpty()) {
        answer({});
        return request;
    }
    if (m_suggestions.contains(document)) {
        answer(m_suggestions.value(document));
        return request;
    }
    // Nothing to suggest without collections.
    QSqlQuery any(m_database);
    if (!any.exec("SELECT 1 FROM collections LIMIT 1") || !any.next()) {
        answer({});
        return request;
    }
    const int related = relatedTo(source);
    auto connection = std::make_shared<QMetaObject::Connection>();
    *connection = connect(this, &ResearchStore::relatedFound, this,
        [this, related, request, source, document, connection](
            int id, const QVariantList &papers, const QVariantList &) {
            if (id != related) return;
            disconnect(*connection);
            QSet<QString> mine;
            QSqlQuery own(m_database);
            own.prepare("SELECT collection_id FROM collection_documents WHERE document_id=?");
            own.addBindValue(document);
            if (own.exec())
                while (own.next()) mine.insert(own.value(0).toString());
            // Each similar paper votes for its collections; closer papers count more.
            QHash<QString, double> score;
            QHash<QString, QString> names;
            for (int i = 0; i < papers.size() && i < 10; ++i) {
                const auto other = findDocument(papers[i].toMap().value("source").toUrl());
                if (other.isEmpty() || other == document) continue;
                QSqlQuery query(m_database);
                query.prepare("SELECT c.id,c.name FROM collection_documents cd JOIN collections c ON "
                              "c.id=cd.collection_id WHERE cd.document_id=?");
                query.addBindValue(other);
                if (!query.exec()) continue;
                while (query.next()) {
                    const auto collection = query.value(0).toString();
                    if (mine.contains(collection)) continue;
                    score[collection] += 1.0 / (1 + i);
                    names[collection] = query.value(1).toString();
                }
            }
            QList<QPair<double, QString>> ranked;
            for (auto it = score.cbegin(); it != score.cend(); ++it)
                if (it.value() >= .3) ranked.append({it.value(), it.key()});
            std::sort(ranked.begin(), ranked.end(), [](const auto &a, const auto &b) { return a.first > b.first; });
            QVariantList list;
            for (const auto &entry : ranked)
                if (list.size() < 2)
                    list.append(QVariantMap{{"id", entry.second}, {"name", names.value(entry.second)}});
            m_suggestions.insert(document, list);
            emit collectionsSuggested(request, source, list);
        });
    return request;
}

int ResearchStore::keyboardModifiers() const
{
    return int(QGuiApplication::keyboardModifiers());
}

int ResearchStore::addDocuments(const QVariantList &sources, const QString &collectionId)
{
    const auto added = addPdfs(sources, collectionId, false);
    if (!added.isEmpty())
        emit message(added.size() == 1 ? QStringLiteral("Added 1 PDF to the Library.")
                                       : QString("Added %1 PDFs to the Library.").arg(added.size()));
    else
        emit message("No PDFs were added. Choose PDF files.");
    return int(added.size());
}

QVariantList ResearchStore::takePdfs(const QVariantList &items, const QVariantMap &options)
{
    const bool move = keepsPdfs() && setting("library.dropMoves", "1") == "1";
    const auto collection = options.value("collection").toString();
    const bool asCollections = options.value("foldersAsCollections").toBool();
    // Files by the collection they go to: the one given, or their folder's when folders become collections.
    QMap<QString, QVariantList> groups;
    QHash<QString, QStringList> paths;
    QSet<QString> separate;
    for (const auto &value : items) {
        const auto item = value.toMap();
        const auto url = item.isEmpty() ? value.toUrl() : item.value("source").toUrl();
        if (!url.isLocalFile()) continue;
        if (item.value("separate").toBool()) separate.insert(url.toString());
        QString key;
        if (asCollections && !item.value("folder").toString().isEmpty()) {
            auto names = QStringList{QFileInfo(item.value("folder").toString()).fileName()};
            names += item.value("relativeDir").toString().split('/', Qt::SkipEmptyParts);
            key = names.join('/');
            paths.insert(key, names);
        }
        groups[key].append(url);
    }
    QVariantList added;
    int made = 0;
    for (auto it = groups.cbegin(); it != groups.cend(); ++it) {
        const auto target = it.key().isEmpty() ? collection : collectionAt(collection, paths.value(it.key()), &made);
        for (const auto &url : addPdfs(it.value(), target, move, separate))
            if (!added.contains(url)) added.append(url);
    }
    if (added.isEmpty()) {
        emit message("No PDFs were added.");
        return added;
    }
    const auto count = added.size() == 1 ? QStringLiteral("1 PDF") : QString("%1 PDFs").arg(added.size());
    emit message((move ? QString("Moved %1 to %2 and added %3 to the Library")
                             .arg(count, QFileInfo(papersFolder()).fileName(), added.size() == 1 ? "it" : "them")
                       : QString("Added %1 to the Library").arg(count))
        + (made ? QString(", in %1 new collections.").arg(made) : QStringLiteral(".")));
    return added;
}

QString ResearchStore::collectionAt(const QString &parent, const QStringList &names, int *made)
{
    // Each name is a collection inside the one before (an existing one of that name is used).
    auto target = parent;
    for (const auto &name : names) {
        QString found;
        for (const auto &value : collections()) {
            const auto c = value.toMap();
            if (c["parentId"].toString() == target && c["name"].toString().compare(name, Qt::CaseInsensitive) == 0) {
                found = c["id"].toString();
                break;
            }
        }
        if (found.isEmpty()) {
            found = createCollection(name, target);
            if (made) ++*made;
        }
        target = found;
    }
    return target;
}

namespace {
// A title as a key: letters and digits only, in lower case; short ones ("Introduction") say too little.
QString titleKey(const QString &title)
{
    QString key;
    for (const auto c : title.toLower())
        if (c.isLetterOrNumber()) key += c;
    return key.size() >= 12 ? key : QString();
}
QString arxivKey(const QString &id)
{
    static const QRegularExpression version("v\\d+$");
    return id.trimmed().toLower().remove(version);
}
}

int ResearchStore::inspectPdfs(const QVariantList &sources)
{
    const int request = ++m_inspectRequest;
    QStringList inputs;
    for (const auto &value : sources)
        if (value.toUrl().isLocalFile()) inputs << value.toUrl().toLocalFile();
    struct Found {
        QString path, folder, relativeDir, hash, title, doi, arxiv;
    };
    // Shown with its progress in the status bar: looking (files found so far), then checking (n of all).
    const auto task = QStringLiteral("inspect:%1").arg(request);
    startTask(task, "Looking for PDFs…");
    auto *watcher = new QFutureWatcher<QList<Found>>(this);
    connect(watcher, &QFutureWatcher<QList<Found>>::finished, this, [this, watcher, request, task] {
        const auto found = watcher->result();
        watcher->deleteLater();
        finishTask(task);
        // The Library's papers by file and by paper (only those whose file is there to open).
        QHash<QString, QString> byHash, byDoi, byArxiv, byTitle;
        QSqlQuery query(m_database);
        query.exec("SELECT url,sha256,doi,arxiv,title FROM documents WHERE kind='pdf' AND removed_at IS NULL "
                   "ORDER BY added_at");
        while (query.next()) {
            const auto url = query.value(0).toString();
            if (!QFileInfo::exists(QUrl(url).toLocalFile())) continue;
            const auto add = [&](QHash<QString, QString> &map, const QString &key) {
                if (!key.isEmpty() && !map.contains(key)) map.insert(key, url);
            };
            add(byHash, query.value(1).toString());
            add(byDoi, query.value(2).toString().trimmed().toLower());
            add(byArxiv, arxivKey(query.value(3).toString()));
            add(byTitle, titleKey(query.value(4).toString()));
        }
        QVariantList items;
        for (const auto &f : found) {
            const auto source = QUrl::fromLocalFile(f.path);
            QString existing, reason;
            const auto match = [&](const QHash<QString, QString> &map, const QString &key, const char *why) {
                if (existing.isEmpty() && !key.isEmpty() && map.contains(key)) {
                    existing = map.value(key);
                    reason = why;
                }
            };
            match(byHash, f.hash, "file");
            match(byDoi, f.doi.trimmed().toLower(), "doi");
            match(byArxiv, arxivKey(f.arxiv), "arxiv");
            match(byTitle, titleKey(f.title), "title");
            // The Library's own file, dropped again, is no duplicate of itself.
            if (existing == source.toString()) existing.clear();
            QVariantMap item{{"source", source}, {"name", QFileInfo(f.path).fileName()}, {"folder", f.folder},
                {"relativeDir", f.relativeDir}, {"duplicate", !existing.isEmpty()}, {"reason", reason}};
            if (!existing.isEmpty()) {
                const QUrl url(existing);
                item.insert("existing", url);
                item.insert("existingName", QFileInfo(url.toLocalFile()).fileName());
                item.insert("existingTitle", displayName(url));
            }
            items.append(item);
        }
        emit pdfsInspected(request, items);
    });
    watcher->setFuture(QtConcurrent::run(&m_fileWorkers, [this, inputs, task] {
        QList<Found> found;
        for (const auto &input : inputs) {
            const QFileInfo info(input);
            if (info.isDir()) {
                // A folder: the PDFs in it and its subfolders (hidden ones and links skipped).
                const QDir base(info.absoluteFilePath());
                QDirIterator it(base.absolutePath(), {"*.pdf", "*.PDF"}, QDir::Files | QDir::Readable | QDir::NoSymLinks,
                    QDirIterator::Subdirectories);
                while (it.hasNext() && found.size() < 10000) {
                    const auto path = it.next();
                    const QFileInfo file(path);
                    if (file.isHidden() || base.relativeFilePath(path).contains("/.")) continue;
                    const auto dir = base.relativeFilePath(file.absolutePath());
                    found.append({file.absoluteFilePath(), base.absolutePath(), dir == "." ? QString() : dir});
                    if (found.size() % 25 == 0)
                        reportTask(task, 0, 0, QString("Looking for PDFs… %1 found").arg(found.size()));
                }
            } else if (info.isFile() && !info.suffix().compare("pdf", Qt::CaseInsensitive) && found.size() < 10000) {
                found.append({info.absoluteFilePath()});
            }
        }
        // What each is: its bytes, and the paper its first page names.
        int checked = 0;
        for (auto &f : found) {
            if (found.size() > 1) reportTask(task, checked++, found.size(), "Checking PDFs");
            f.hash = FileFingerprint::sha256(f.path);
            const auto paper = extractPaperMetadata(f.path);
            f.title = paper.title;
            f.doi = paper.doi;
            f.arxiv = paper.arxiv;
        }
        return found;
    }));
    return request;
}

bool ResearchStore::discardDownload(const QUrl &file)
{
    const auto path = file.toLocalFile();
    const auto folder = QFileInfo(path).absolutePath();
    const auto downloads = QFileInfo(downloadTarget("x").value("directory").toString()).absoluteFilePath();
    if (!file.isLocalFile() || !QFileInfo(path).isFile() || !findDocument(file).isEmpty()
        || (folder != papersFolder() && folder != downloads))
        return false;
    return QFile::moveToTrash(path);
}

bool ResearchStore::isFolder(const QUrl &url) const
{
    return url.isLocalFile() && QFileInfo(url.toLocalFile()).isDir();
}

QVariantList ResearchStore::addPdfs(
    const QVariantList &sources, const QString &collectionId, bool move, const QSet<QString> &separate)
{
    QVariantList added;
    QHash<QString, QUrl> batch; // Two files with the same bytes become one paper.
    for (const auto &value : sources) {
        const QFileInfo info(value.toUrl().toLocalFile());
        if (!value.toUrl().isLocalFile() || !info.isFile() || !info.isReadable()
            || info.suffix().compare("pdf", Qt::CaseInsensitive))
            continue;
        const bool own = separate.contains(value.toUrl().toString());
        const auto url = adoptPdf(value.toUrl(), &batch, move, own);
        const auto document = ensureDocument(url);
        // Kept as a paper of its own: no "same file as" notice for it.
        if (own) {
            const auto hash = FileFingerprint::sha256(url.toLocalFile());
            QSqlQuery ack(m_database);
            ack.prepare("UPDATE documents SET sha256=?,duplicate_ack=? WHERE id=?");
            ack.addBindValue(hash);
            ack.addBindValue(hash);
            ack.addBindValue(document);
            ack.exec();
        }
        if (document.isEmpty()) continue;
        QSqlQuery restore(m_database);
        restore.prepare("UPDATE documents SET removed_at=NULL,trashed_at=NULL WHERE id=?");
        restore.addBindValue(document);
        restore.exec();
        refreshMetadata(document, resolvedSource(url), false, true);
        m_index->enqueue(url);
        if (!added.contains(url)) added.append(url);
    }
    if (!collectionId.isEmpty() && !added.isEmpty()) setDocumentsCollection(added, collectionId, true);
    announceDocumentsChanged();
    emit homeChanged();
    return added;
}

int ResearchStore::removeFromLibrary(const QVariantList &sources)
{
    int removed = 0;
    const auto now = QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
    for (const auto &value : sources) {
        const auto url = value.toUrl();
        const auto document = findDocument(url);
        if (document.isEmpty()) continue;
        QSqlQuery hide(m_database);
        hide.prepare("UPDATE documents SET removed_at=? WHERE id=? AND removed_at IS NULL");
        hide.addBindValue(now);
        hide.addBindValue(document);
        if (!hide.exec() || hide.numRowsAffected() != 1) continue;
        for (const auto *sql :
            {"DELETE FROM recent_documents WHERE document_id=?", "DELETE FROM collection_documents WHERE document_id=?",
                "DELETE FROM document_tags WHERE document_id=?"}) {
            QSqlQuery query(m_database);
            query.prepare(sql);
            query.addBindValue(document);
            query.exec();
        }
        m_index->remove(resolvedSource(url));
        ++removed;
    }
    if (!removed) return 0;
    announceDocumentsChanged();
    emit recentDocumentsChanged();
    emit homeChanged();
    emit message(removed == 1 ? QStringLiteral("Removed from the Library. The PDF file was kept.")
                              : QString("Removed %1 papers from the Library. The PDF files were kept.").arg(removed));
    return removed;
}
