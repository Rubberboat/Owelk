#pragma once

#include <QHash>
#include <QObject>
#include <QStringList>
#include <QTimer>

class ResearchStore;
class SearchText final : public QObject {
    Q_OBJECT
    Q_PROPERTY(int revision READ revision NOTIFY revisionChanged)
public:
    explicit SearchText(ResearchStore *store);
    int revision() const { return m_revision; }
    // Original first. Expansions are search candidates, never proof that two authors are one person.
    static QStringList localVariants(const QString &query);
    static QStringList personNames(const QString &query);
    static bool matchesAny(const QString &text, const QStringList &variants);
    Q_INVOKABLE QStringList variants(const QString &query) const;
    Q_INVOKABLE bool matches(const QString &text, const QString &query) const;
    Q_INVOKABLE void prepare(const QString &query);
    Q_INVOKABLE QString webQuery(const QString &query) const;
signals:
    void revisionChanged();
    void changed(const QString &query);
    void configurationChanged();

private:
    QString cacheKey(const QString &query) const;
    ResearchStore *m_store;
    int m_revision = 0;
    QTimer m_delay;
    QString m_query, m_configuration;
    mutable QHash<QString, QStringList> m_localCache;
    QHash<QString, QStringList> m_cache;
    QHash<int, QPair<QString, QString>> m_requests;
};
