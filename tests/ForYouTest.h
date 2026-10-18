#pragma once
#include <QObject>

class ForYouTest : public QObject {
    Q_OBJECT
private slots:
    void identityDetailsAndWorkParsing();
    void migrationKeepsExistingPeople();
    void searchCacheKoreanAndRetryRecovery();
    void collectDeduplicateAndFilterBothFollows();
};
