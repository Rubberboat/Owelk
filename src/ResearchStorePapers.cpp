#include "FileFingerprint.h"
#include "LibrarySync.h"
#include "PaperMetadata.h"
#include "PaperIndex.h"
#include "ResearchStore.h"
#include "WorkerConnection.h"

#include <QDateTime>
#include <QTimer>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFutureWatcher>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QSqlQuery>
#include <QStorageInfo>
#include <QtConcurrent>

// "Keep PDFs in Owelk": opened, added and downloaded PDFs get a copy in the PDF folder (which sync
// fills too), so the Library does not depend on files scattered over the disk, as in note apps.
// Opened and added originals are never moved or deleted; PDFs dropped on Owelk move in.
namespace {
QString uniqueFile(const QString &folder, const QString &suggested)
{
    // Keep only a plain file name; never let a server or another computer choose the folder.
    auto name = QFileInfo(suggested).fileName().remove(QRegularExpression("[\\x00-\\x1f/\\\\:]")).trimmed();
    if (name.isEmpty() || name.startsWith('.')) name = "download.pdf";
    const QFileInfo base(name);
    const auto stem = base.completeBaseName(), suffix = base.suffix().isEmpty() ? QString() : "." + base.suffix();
    for (int n = 1; QFileInfo::exists(folder + "/" + name) && n < 1000; ++n)
        name = QStringLiteral("%1 (%2)%3").arg(stem).arg(n).arg(suffix);
    return folder + "/" + name;
}

bool copyInto(const QString &from, const QString &to)
{
    const auto part = to + ".part";
    QFile::remove(part);
    if (QDir().mkpath(QFileInfo(to).absolutePath()) && QFile::copy(from, part) && QFile::rename(part, to)) return true;
    QFile::remove(part);
    return false;
}

// A move within one disk is a rename: the file itself changes folder and nothing is copied.
// (QFile::rename alone would fall back to copy-and-delete across disks.)
bool renameOnDisk(const QString &from, const QString &to)
{
    QDir().mkpath(QFileInfo(to).absolutePath());
    return QStorageInfo(QFileInfo(from).absolutePath()) == QStorageInfo(QFileInfo(to).absolutePath())
        && QFile::rename(from, to);
}

// Already named stem, or so with the number another file of that name made necessary.
bool namedAs(const QString &current, const QString &stem)
{
    const QRegularExpression numbered(
        "^" + QRegularExpression::escape(stem) + " \\(\\d+\\)$", QRegularExpression::CaseInsensitiveOption);
    return current.compare(stem, Qt::CaseInsensitive) == 0 || numbered.match(current).hasMatch();
}

// The Library's file for a PDF: a path the Library already uses stays; identical bytes map to the
// paper that has them; anything else is copied into the PDF folder, or with `move` moved there (from
// another disk: copied, checked byte for byte, and the original sent to the system Trash). The input
// comes back when nothing applies or copying fails, so opening never breaks because of this.
QUrl adoptFile(QSqlDatabase &db, const QString &folder, const QUrl &source, QHash<QString, QUrl> *batch, bool move,
    bool separate = false)
{
    const auto path = source.toLocalFile();
    const QFileInfo info(path);
    if (!source.isLocalFile() || !info.isFile() || info.suffix().compare("pdf", Qt::CaseInsensitive)) return source;
    QSqlQuery known(db);
    known.prepare("SELECT 1 FROM documents WHERE url=?");
    known.addBindValue(source.toString());
    if (known.exec() && known.next()) return source;
    const auto hash = FileFingerprint::sha256(path);
    if (hash.isEmpty()) return source;
    if (!separate && batch && batch->contains(hash)) return batch->value(hash);
    const bool inside = info.absoluteFilePath().startsWith(folder + "/");
    QSqlQuery same(db);
    same.prepare("SELECT url FROM documents WHERE sha256=? AND kind='pdf' ORDER BY removed_at IS NOT NULL LIMIT 1");
    same.addBindValue(hash);
    // A separate copy (the reader chose to keep both) skips the paper that has the same bytes.
    if (!separate && same.exec() && same.next()) {
        const QUrl existing(same.value(0).toString());
        const auto existingPath = existing.toLocalFile();
        if (QFileInfo::exists(existingPath) && QFileInfo(existingPath) != info) {
            // A fresh download of a paper Owelk already keeps is not kept twice, and a dropped copy of
            // it leaves its folder (for the system Trash) as a moved file would.
            if (inside) QFile::remove(path);
            else if (move && existingPath.startsWith(folder + "/")) QFile::moveToTrash(path);
            return existing;
        }
    }
    if (inside) return source;
    const auto target = uniqueFile(folder, info.fileName());
    if (!(move && renameOnDisk(path, target))) {
        if (!copyInto(path, target)) return source;
        if (move && FileFingerprint::sha256(target) == hash) QFile::moveToTrash(path);
    }
    FileFingerprint::remember(target, FileFingerprint::stamp(target), hash);
    const auto url = QUrl::fromLocalFile(target);
    if (batch) batch->insert(hash, url);
    return url;
}
} // namespace

bool ResearchStore::keepsPdfs() const
{
    return setting("library.keepPdfs", "1") == "1";
}

QString ResearchStore::papersFolder() const
{
    return m_papers;
}

// The usual data folder keeps PDFs in Documents/Owelk Library/Papers, where people look for files
// (not Documents/Owelk, a common place for a project checkout); a data folder
// given on the command line (development, tests) keeps them inside itself.
QString ResearchStore::defaultPapersFolder(const QString &directory)
{
    const auto documents = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    if (directory == QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation) && !documents.isEmpty())
        return documents + "/Owelk Library/Papers";
    return directory + "/papers";
}

// PDFs kept in the data folder's papers/ (before the PDF folder moved to Documents) follow it: each
// file moves, then its paper switches over the way Locate Original PDF does (the old path still
// finds it). Only files directly in the old folder move.
void ResearchStore::relocatePapers()
{
    const QStringList olds{m_directory + "/papers"};
    if (olds.contains(m_papers) || !QFileInfo(olds.first()).isDir()) return;
    QSqlQuery query(m_database);
    QList<QPair<QString, QString>> papers;
    if (!query.exec("SELECT url,sha256 FROM documents WHERE url LIKE 'file:%'")) return;
    while (query.next()) {
        const auto path = QUrl(query.value(0).toString()).toLocalFile();
        if (olds.contains(QFileInfo(path).absolutePath())) papers.append({path, query.value(1).toString()});
    }
    query.finish();
    int moved = 0;
    for (const auto &[path, hash] : std::as_const(papers)) {
        const auto target = uniqueFile(m_papers, QFileInfo(path).fileName());
        const bool present = QFileInfo::exists(path);
        if (present && (!QDir().mkpath(m_papers) || !QFile::rename(path, target))) continue;
        const auto from = QUrl::fromLocalFile(path), to = QUrl::fromLocalFile(target);
        QString error;
        if (!applyRelink(from, to, hash, &error)) {
            if (present) QFile::rename(target, path);
            continue;
        }
        m_relinks.insert(from.toString(), to.toString());
        m_index->relocateSource(from, to);
        // A paper still arriving through sync lands in the new place.
        QSqlQuery pending(m_database);
        pending.prepare("UPDATE sync_files SET local=? WHERE local=?");
        pending.addBindValue(target);
        pending.addBindValue(path);
        pending.exec();
        ++moved;
    }
    QDir().rmdir(m_directory + "/papers"); // Only when nothing else is left in it.
    if (moved) m_startupMessage = QString("Owelk's PDFs now live in %1.").arg(QDir::toNativeSeparators(m_papers));
}

void ResearchStore::nameDownloadedPdf(const QUrl &file)
{
    const auto path = file.toLocalFile();
    if (setting("web.pdfNames", "title") != "title" || !file.isLocalFile() || !path.startsWith(papersFolder() + "/")) {
        QMetaObject::invokeMethod(this, [this, file] { emit downloadNamed(file, file); }, Qt::QueuedConnection);
        return;
    }
    using Named = QPair<QString, QString>; // File name stem, content hash.
    auto *watcher = new QFutureWatcher<Named>(this);
    connect(watcher, &QFutureWatcherBase::finished, this, [this, watcher, file, path] {
        watcher->deleteLater();
        const auto [stem, hash] = watcher->result();
        auto named = file;
        // A file the Library already uses keeps its name; only a fresh download is renamed.
        QSqlQuery known(m_database);
        known.prepare("SELECT 1 FROM documents WHERE url=?");
        known.addBindValue(file.toString());
        const bool used = known.exec() && known.next();
        if (!used && !stem.isEmpty() && stem != QFileInfo(path).completeBaseName() && QFileInfo(path).isFile()) {
            const auto target = uniqueFile(papersFolder(), stem + ".pdf");
            if (QFile::rename(path, target)) {
                if (!hash.isEmpty()) FileFingerprint::remember(target, FileFingerprint::stamp(target), hash);
                named = QUrl::fromLocalFile(target);
            }
        }
        emit downloadNamed(file, named);
    });
    // The same name kept PDFs take ("Author Year - Title"), or the title alone when that is turned off.
    const bool full = setting("library.namePdfs", "1") == "1";
    watcher->setFuture(QtConcurrent::run(&m_metadataWorkers, [path, full] {
        const auto paper = extractPaperMetadata(path);
        const auto stem = full ? PaperMetadataText::paperFileStem(paper.title, paper.authors, paper.year)
                               : PaperMetadataText::fileStem(paper);
        return Named(stem, FileFingerprint::sha256(path));
    }));
}

QUrl ResearchStore::papersFolderUrl() const
{
    QDir().mkpath(papersFolder());
    return QUrl::fromLocalFile(papersFolder());
}

void ResearchStore::scheduleNamingPdfs()
{
    if (m_namingPending) return;
    m_namingPending = true;
    QTimer::singleShot(2000, this, [this] {
        m_namingPending = false;
        namePdfFiles(false);
    });
}

void ResearchStore::namePdfFiles(bool starting)
{
    if (!keepsPdfs() || setting("library.namePdfs", "1") != "1") return;
    if (m_copyingPdfs || m_relinking) {
        scheduleNamingPdfs();
        return;
    }
    const auto open = starting ? QSet<QString>() : openSources();
    const auto now = QDateTime::currentDateTimeUtc();
    struct Rename {
        QString from, stem, hash;
    };
    QList<Rename> renames;
    QSqlQuery query(m_database);
    if (!query.exec("SELECT url,title,authors,year,sha256,added_at FROM documents "
                    "WHERE kind='pdf' AND removed_at IS NULL AND url LIKE 'file:%'"))
        return;
    while (query.next()) {
        const QUrl url(query.value(0).toString());
        const QFileInfo info(url.toLocalFile());
        if (info.absolutePath() != m_papers || !info.isFile()) continue;
        // A paper read for a while keeps its file until the next start; a fresh one is named now.
        const auto added = QDateTime::fromString(query.value(5).toString(), Qt::ISODateWithMs);
        if (open.contains(url.toString()) && (!added.isValid() || added.secsTo(now) > 120)) continue;
        const auto stem = PaperMetadataText::paperFileStem(
            query.value(1).toString(), query.value(2).toString(), query.value(3).toString());
        if (stem.isEmpty()) continue;
        if (namedAs(info.completeBaseName(), stem)) continue;
        renames.append({info.absoluteFilePath(), stem, query.value(4).toString()});
    }
    query.finish();
    int named = 0;
    // A file another program holds open (on Windows) is named on a later pass.
    for (const auto &item : std::as_const(renames))
        if (renameKeptPdf(item.from, item.stem, item.hash)) ++named;
    if (!named) return;
    loadDocumentNames();
    announceDocumentsChanged();
}

bool ResearchStore::renameKeptPdf(const QString &path, const QString &stem, const QString &hash)
{
    const auto target = uniqueFile(m_papers, stem + ".pdf");
    if (!renameOnDisk(path, target)) return false;
    const auto from = QUrl::fromLocalFile(path), to = QUrl::fromLocalFile(target);
    QString error;
    if (!applyRelink(from, to, hash, &error)) {
        QFile::rename(target, path);
        return false;
    }
    if (!hash.isEmpty()) FileFingerprint::remember(target, FileFingerprint::stamp(target), hash);
    m_relinks.insert(from.toString(), to.toString());
    m_index->relocateSource(from, to);
    QSqlQuery pending(m_database);
    pending.prepare("UPDATE sync_files SET local=? WHERE local=?");
    pending.addBindValue(target);
    pending.addBindValue(path);
    pending.exec();
    emit sourceRelinked(from, to);
    return true;
}

bool ResearchStore::keptByOwelk(const QUrl &source) const
{
    const auto url = resolvedSource(source);
    if (!url.isLocalFile()) return false;
    const QFileInfo info(url.toLocalFile());
    return info.isFile() && info.absolutePath() == m_papers;
}

int ResearchStore::renamePapersToTitles(const QVariantList &sources)
{
    if (m_copyingPdfs || m_relinking) {
        emit message("PDFs are being copied or moved; rename them once that is done.");
        return 0;
    }
    const bool full = setting("library.namePdfs", "1") == "1";
    int renamed = 0, held = 0;
    for (const auto &value : sources) {
        const auto from = resolvedSource(value.toUrl());
        if (!keptByOwelk(from)) continue;
        QSqlQuery query(m_database);
        query.prepare("SELECT title,authors,year,sha256 FROM documents WHERE url=? AND removed_at IS NULL");
        query.addBindValue(from.toString());
        if (!query.exec() || !query.next()) continue;
        PaperMetadata paper;
        paper.title = query.value(0).toString();
        const auto stem = full ? PaperMetadataText::paperFileStem(paper.title, query.value(1).toString(), query.value(2).toString())
                               : PaperMetadataText::fileStem(paper);
        const auto hash = query.value(3).toString();
        query.finish();
        const auto path = from.toLocalFile();
        if (stem.isEmpty() || namedAs(QFileInfo(path).completeBaseName(), stem)) continue;
        if (renameKeptPdf(path, stem, hash)) ++renamed;
        else ++held;
    }
    if (renamed) {
        loadDocumentNames();
        announceDocumentsChanged();
    }
    if (held)
        emit message(QString("Renamed %1 of %2 PDFs; the rest are open in another program.").arg(renamed).arg(renamed + held));
    else if (renamed)
        emit message(renamed == 1 ? QString("Renamed the PDF after its paper.")
                                  : QString("Renamed %1 PDFs after their papers.").arg(renamed));
    else
        emit message("No PDF needed a new name (only Owelk's own copies of papers with a known title are renamed).");
    return renamed;
}

bool ResearchStore::choosePapersFolder(const QUrl &folder)
{
    if (!folder.isLocalFile() || m_copyingPdfs || m_relinking || busy()) return false;
    const auto target = QDir::cleanPath(QDir(folder.toLocalFile()).absolutePath());
    if (target == m_papers) return true;
    // Not the data folder itself (the database lives there), and a folder Owelk can write to.
    if (target == QDir::cleanPath(QDir(m_directory).absolutePath()) || !QDir().mkpath(target)
        || !QFileInfo(target).isWritable() || !setSetting("library.folder", target))
        return false;
    const auto old = m_papers;
    m_papers = target;
    m_sync->setPapersFolder(m_papers);
    // Every paper whose file lies directly in the old folder follows it, papers in the Trash too.
    struct Move {
        QString from, to, hash;
        bool copied = false;
    };
    QList<Move> moves;
    QSqlQuery query(m_database);
    if (query.exec("SELECT url,sha256 FROM documents WHERE url LIKE 'file:%'"))
        while (query.next()) {
            const auto path = QUrl(query.value(0).toString()).toLocalFile();
            if (QFileInfo(path).absolutePath() == old && QFileInfo(path).isFile())
                moves.append({path, {}, query.value(1).toString()});
        }
    if (moves.isEmpty()) {
        emit message(QString("New PDFs will be kept in %1.").arg(QDir::toNativeSeparators(target)));
        return true;
    }
    m_copyingPdfs = true;
    emit copyingPdfsChanged();
    auto *watcher = new QFutureWatcher<QList<Move>>(this);
    connect(watcher, &QFutureWatcher<QList<Move>>::finished, this, [this, watcher, old, target] {
        const auto done = watcher->result();
        watcher->deleteLater();
        int moved = 0;
        for (const auto &move : done) {
            if (move.to.isEmpty()) continue;
            const auto from = QUrl::fromLocalFile(move.from), to = QUrl::fromLocalFile(move.to);
            QString error;
            if (!applyRelink(from, to, move.hash, &error)) {
                // The paper keeps its file where it was.
                if (move.copied) QFile::remove(move.to);
                else QFile::rename(move.to, move.from);
                continue;
            }
            // A copy on another disk replaced Owelk's old file, which goes to the system Trash.
            if (move.copied) QFile::moveToTrash(move.from);
            m_relinks.insert(from.toString(), to.toString());
            m_index->relocateSource(from, to);
            QSqlQuery pending(m_database);
            pending.prepare("UPDATE sync_files SET local=? WHERE local=?");
            pending.addBindValue(move.to);
            pending.addBindValue(move.from);
            pending.exec();
            emit sourceRelinked(from, to);
            ++moved;
        }
        // Owelk's own default folder goes once it is empty; a folder the reader chose stays.
        if (old == defaultPapersFolder(m_directory) && QDir().rmdir(old)) QDir().rmdir(QFileInfo(old).absolutePath());
        loadDocumentNames();
        announceDocumentsChanged();
        emit highlightsChanged();
        m_copyingPdfs = false;
        emit copyingPdfsChanged();
        emit message(moved == done.size()
                ? QString("Moved %1 PDFs to %2.").arg(moved).arg(QDir::toNativeSeparators(target))
                : QString("Moved %1 of %2 PDFs to %3; the rest stay in %4.")
                      .arg(moved)
                      .arg(done.size())
                      .arg(QDir::toNativeSeparators(target), QDir::toNativeSeparators(old)));
    });
    watcher->setFuture(QtConcurrent::run(&m_metadataWorkers, [moves, target]() mutable {
        for (auto &move : moves) {
            const auto file = uniqueFile(target, QFileInfo(move.from).fileName());
            if (move.hash.isEmpty()) move.hash = FileFingerprint::sha256(move.from);
            if (move.hash.isEmpty()) continue;
            if (renameOnDisk(move.from, file)) {
                move.to = file;
                continue;
            }
            // Another disk: only a byte-for-byte copy takes the old file's place.
            if (!copyInto(move.from, file) || FileFingerprint::sha256(file) != FileFingerprint::sha256(move.from)) {
                QFile::remove(file);
                continue;
            }
            move.to = file;
            move.copied = true;
        }
        return moves;
    }));
    return true;
}

QUrl ResearchStore::adoptPdf(const QUrl &source)
{
    return adoptPdf(source, nullptr);
}

QUrl ResearchStore::adoptPdf(const QUrl &source, QHash<QString, QUrl> *batch, bool move, bool separate)
{
    const auto url = resolvedSource(source);
    return keepsPdfs() ? adoptFile(m_database, papersFolder(), url, batch, move, separate) : url;
}

int ResearchStore::outsidePdfCount() const
{
    QSqlQuery query(m_database);
    int count = 0;
    if (!query.exec("SELECT url FROM documents WHERE kind='pdf' AND removed_at IS NULL")) return 0;
    while (query.next()) {
        const auto path = QUrl(query.value(0).toString()).toLocalFile();
        if (!path.isEmpty() && !path.startsWith(papersFolder() + "/") && QFileInfo::exists(path)) ++count;
    }
    return count;
}

void ResearchStore::copyPdfsIntoLibrary()
{
    if (m_copyingPdfs || m_relinking || busy()) return;
    struct Move {
        QUrl from, to;
        QString hash;
    };
    QList<Move> moves;
    QSqlQuery query(m_database);
    if (query.exec("SELECT url FROM documents WHERE kind='pdf' AND removed_at IS NULL"))
        while (query.next()) {
            const QUrl url(query.value(0).toString());
            const auto path = url.toLocalFile();
            if (!path.isEmpty() && !path.startsWith(papersFolder() + "/") && QFileInfo::exists(path))
                moves.append({url, {}, {}});
        }
    if (moves.isEmpty()) return;
    m_copyingPdfs = true;
    emit copyingPdfsChanged();
    auto *watcher = new QFutureWatcher<QList<Move>>(this);
    connect(watcher, &QFutureWatcher<QList<Move>>::finished, this, [this, watcher] {
        const auto done = watcher->result();
        watcher->deleteLater();
        // The same one-URL change as Locate Original PDF, for each paper whose copy matched byte for byte.
        int copied = 0;
        for (const auto &move : done) {
            QString error;
            if (move.to.isEmpty()) continue;
            if (!applyRelink(move.from, move.to, move.hash, &error)) {
                QFile::remove(move.to.toLocalFile());
                continue;
            }
            m_relinks.insert(move.from.toString(), move.to.toString());
            m_index->relocateSource(move.from, move.to);
            emit sourceRelinked(move.from, move.to);
            ++copied;
        }
        loadDocumentNames();
        announceDocumentsChanged();
        emit highlightsChanged();
        m_copyingPdfs = false;
        emit copyingPdfsChanged();
        emit message(copied == done.size()
                ? QString("Copied %1 PDFs into the Library. The originals were left where they were.").arg(copied)
                : QString("Copied %1 of %2 PDFs into the Library; the rest stay where they are.")
                      .arg(copied)
                      .arg(done.size()));
    });
    const auto folder = papersFolder();
    watcher->setFuture(QtConcurrent::run(&m_metadataWorkers, [moves, folder]() mutable {
        for (auto &move : moves) {
            const auto path = move.from.toLocalFile();
            const auto target = uniqueFile(folder, QFileInfo(path).fileName());
            const auto hash = FileFingerprint::sha256(path);
            if (hash.isEmpty() || !copyInto(path, target)) continue;
            // Only a byte-for-byte copy replaces the original in the Library.
            if (FileFingerprint::sha256(target) != hash) {
                QFile::remove(target);
                continue;
            }
            move.to = QUrl::fromLocalFile(target);
            move.hash = hash;
        }
        return moves;
    }));
}

// Owelk's paper Trash. Delete Paper hides a paper (with its notes, collections and tags kept) and
// marks when; Restore brings it all back. Deleting for good, by hand or after the chosen number of
// days, removes the paper with its annotations, and sends a PDF Owelk keeps to the
// system Trash (a file outside Owelk's folder is left alone). Opening the PDF again also restores.
int ResearchStore::deletePapers(const QVariantList &sources)
{
    const auto now = QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
    QVariantList deleted;
    for (const auto &value : sources) {
        const auto url = value.toUrl();
        const auto document = findDocument(url);
        if (document.isEmpty()) continue;
        QSqlQuery query(m_database);
        query.prepare("UPDATE documents SET removed_at=?,trashed_at=? WHERE id=? AND trashed_at IS NULL");
        query.addBindValue(now);
        query.addBindValue(now);
        query.addBindValue(document);
        if (!query.exec() || query.numRowsAffected() != 1) continue;
        query.prepare("DELETE FROM recent_documents WHERE document_id=?");
        query.addBindValue(document);
        query.exec();
        m_index->remove(resolvedSource(url));
        deleted << resolvedSource(url);
    }
    if (deleted.isEmpty()) return 0;
    announceDocumentsChanged();
    emit papersDeleted(deleted);
    const auto days = trashDays();
    emit message((deleted.size() == 1 ? QStringLiteral("Moved the paper to the Trash.")
                                      : QString("Moved %1 papers to the Trash.").arg(deleted.size()))
        + (days > 0 ? QString(" It is deleted for good after %1 days.").arg(days) : QString()));
    return int(deleted.size());
}

int ResearchStore::restorePapers(const QVariantList &sources)
{
    int restored = 0;
    for (const auto &value : sources) {
        const auto document = findDocument(value.toUrl());
        QSqlQuery query(m_database);
        query.prepare("UPDATE documents SET removed_at=NULL,trashed_at=NULL WHERE id=? AND trashed_at IS NOT NULL");
        query.addBindValue(document);
        if (document.isEmpty() || !query.exec() || query.numRowsAffected() != 1) continue;
        m_index->enqueue(resolvedSource(value.toUrl()));
        ++restored;
    }
    if (restored) announceDocumentsChanged();
    return restored;
}

int ResearchStore::purgePapers(const QVariantList &sources)
{
    int purged = 0;
    QStringList annotationImages;
    QList<QUrl> files;
    for (const auto &value : sources) {
        const auto url = resolvedSource(value.toUrl());
        const auto document = findDocument(url);
        if (document.isEmpty()) continue;
        const auto rows = [&](const QString &sql) {
            QStringList values;
            QSqlQuery query(m_database);
            query.prepare(sql);
            query.addBindValue(document);
            if (query.exec())
                while (query.next()) values << query.value(0).toString();
            return values;
        };
        const auto highlights = rows("SELECT id FROM highlights WHERE document_id=?");
        annotationImages += rows("SELECT image FROM highlights WHERE document_id=? AND image<>''");
        if (!m_database.transaction()) continue;
        bool ok = true;
        const auto run = [&](const QString &sql, const QVariantList &args) {
            QSqlQuery query(m_database);
            query.prepare(sql);
            for (const auto &arg : args) query.addBindValue(arg);
            ok = ok && query.exec();
        };
        for (const auto &id : highlights)
            run("DELETE FROM links WHERE (from_kind='highlight' AND from_id=?) OR (to_kind='highlight' AND to_id=?)",
                {id, id});
        for (const auto *table :
            {"highlights", "recent_documents", "reading_positions", "collection_documents", "document_tags"})
            run(QStringLiteral("DELETE FROM %1 WHERE document_id=?").arg(table), {document});
        run("DELETE FROM links WHERE (from_kind='document' AND from_id=?) OR (to_kind='document' AND to_id=?)",
            {document, document});
        run("DELETE FROM documents WHERE id=?", {document});
        if (!ok || !m_database.commit()) {
            m_database.rollback();
            continue;
        }
        m_index->remove(url);
        files << url;
        ++purged;
    }
    if (!purged) return 0;
    // Files go only after the rows: at worst an unused file stays behind, never a paper without its file.
    for (const auto &url : std::as_const(files))
        if (url.toLocalFile().startsWith(papersFolder() + "/")) QFile::moveToTrash(url.toLocalFile());
    for (const auto &image : std::as_const(annotationImages)) {
        QSqlQuery used(m_database);
        used.prepare("SELECT 1 FROM highlights WHERE image=?");
        used.addBindValue(image);
        if (used.exec() && !used.next()) QFile::remove(m_directory + "/annotations/" + image);
    }
    announceDocumentsChanged();
    emit highlightsChanged();
    emit linksChanged();
    return purged;
}
