#include "SearchText.h"
#include "ResearchStore.h"
#include "ai/AiService.h"

#include <QRegularExpression>
#include <QSet>
#include <algorithm>

namespace {
QString normalized(const QString &text)
{
    return text.normalized(QString::NormalizationForm_KC).simplified();
}
void append(QStringList &list, const QString &text, int limit = 24)
{
    const auto value = normalized(text);
    if (!value.isEmpty() && list.size() < limit && !list.contains(value, Qt::CaseInsensitive)) list << value;
}
const QHash<QString, QStringList> &families()
{
    static const QHash<QString, QStringList> values{{"김", {"Kim", "Gim"}}, {"이", {"Lee", "Yi", "Rhee"}},
        {"박", {"Park", "Bak", "Pak"}}, {"최", {"Choi", "Choe"}}, {"정", {"Jung", "Jeong", "Chung"}},
        {"강", {"Kang", "Gang"}}, {"조", {"Cho", "Jo"}}, {"윤", {"Yoon", "Yun"}}, {"장", {"Jang", "Chang"}},
        {"임", {"Lim", "Im"}}, {"오", {"Oh", "O"}}, {"한", {"Han"}}, {"신", {"Shin", "Sin"}}, {"서", {"Seo", "Suh"}},
        {"권", {"Kwon", "Gwon"}}, {"황", {"Hwang"}}, {"안", {"Ahn", "An"}}, {"송", {"Song"}}, {"류", {"Ryu", "Ryoo"}},
        {"유", {"Yoo", "Yu"}}, {"홍", {"Hong"}}, {"전", {"Jeon", "Jun", "Chun"}}, {"고", {"Ko", "Go"}},
        {"문", {"Moon", "Mun"}}, {"손", {"Son", "Sohn"}}, {"양", {"Yang"}}, {"배", {"Bae"}}, {"백", {"Baek", "Paik"}},
        {"허", {"Heo", "Huh"}}, {"남", {"Nam"}}, {"심", {"Shim", "Sim"}}, {"노", {"Noh", "Roh", "No"}}, {"하", {"Ha"}},
        {"곽", {"Kwak", "Gwak"}}, {"성", {"Sung", "Seong"}}, {"차", {"Cha"}}, {"주", {"Joo", "Ju"}},
        {"우", {"Woo", "U"}}, {"구", {"Koo", "Gu"}}, {"민", {"Min"}}, {"진", {"Jin"}}, {"지", {"Ji"}},
        {"엄", {"Um", "Eom"}}, {"채", {"Chae"}}, {"원", {"Won"}}, {"천", {"Chun", "Cheon"}}, {"방", {"Bang"}},
        {"공", {"Gong", "Kong"}}, {"현", {"Hyun", "Hyeon"}}, {"함", {"Ham"}}, {"변", {"Byun", "Byeon"}},
        {"염", {"Yeom"}}, {"여", {"Yeo"}}, {"추", {"Choo", "Chu"}}, {"도", {"Do", "Doh"}}, {"소", {"So"}},
        {"석", {"Seok", "Suk"}}, {"선", {"Sun", "Seon"}}, {"설", {"Seol"}}, {"마", {"Ma"}}, {"길", {"Gil", "Kil"}},
        {"연", {"Yeon"}}, {"위", {"Wi"}}, {"표", {"Pyo"}}, {"명", {"Myung", "Myeong"}}, {"기", {"Ki", "Gi"}},
        {"반", {"Ban"}}, {"왕", {"Wang"}}, {"남궁", {"Namgung", "Namkoong"}}, {"황보", {"Hwangbo"}},
        {"제갈", {"Jegal"}}, {"선우", {"Sunwoo", "Seonu"}}, {"독고", {"Dokgo"}}, {"사공", {"Sagong"}}};
    return values;
}
QStringList syllable(QChar character)
{
    // Unicode Hangul decomposition; personal-name syllables retain their own spelling (no assimilation).
    static const QStringList initials = QString("g kk n d tt r m b pp s ss - j jj ch k t p h").split(' ');
    static const QStringList vowels
        = QString("a ae ya yae eo e yeo ye o wa wae oe yo u wo we wi yu eu ui i").split(' ');
    static const QStringList finals = QString("- k k k n n n t l k m l l l p l m p p t t ng t t k t p h").split(' ');
    const int code = character.unicode() - 0xac00;
    if (code < 0 || code >= 11172) return {};
    const auto spelling = (initials[code / 588] + vowels[(code % 588) / 28] + finals[code % 28]).remove('-');
    static const QHash<QString, QStringList> customary{{"주", {"ju", "joo"}}, {"현", {"hyun", "hyeon"}},
        {"정", {"jung", "jeong"}}, {"영", {"young", "yeong"}}, {"성", {"sung", "seong"}}, {"석", {"seok", "suk"}},
        {"승", {"seung", "sung"}}, {"우", {"woo", "u"}}, {"윤", {"yoon", "yun"}}, {"수", {"su", "soo"}},
        {"준", {"jun", "joon"}}, {"철", {"chul", "cheol"}}, {"희", {"hee", "hui"}}, {"은", {"eun"}},
        {"선", {"sun", "seon"}}, {"혁", {"hyuk", "hyeok"}}, {"욱", {"wook", "uk"}}, {"규", {"kyu", "gyu"}},
        {"경", {"kyung", "gyeong"}}, {"기", {"ki", "gi"}}, {"태", {"tae"}}};
    auto result = customary.value(QString(character));
    append(result, spelling);
    return result;
}
// Compact, offline vocabulary. AI can add free-form translations; unknown words remain intact.
const QList<QStringList> &vocabulary()
{
    static const QList<QStringList> values{{"자기 지도 학습", "self supervised learning"},
        {"자기지도학습", "self supervised learning"}, {"강화학습", "reinforcement learning"},
        {"강화 학습", "reinforcement learning"}, {"기계학습", "machine learning"}, {"기계 학습", "machine learning"},
        {"머신러닝", "machine learning"}, {"딥러닝", "deep learning"}, {"심층학습", "deep learning"},
        {"인공지능", "artificial intelligence"}, {"신경망", "neural network"},
        {"자연어 처리", "natural language processing"}, {"컴퓨터 비전", "computer vision"},
        {"객체 검출", "object detection"}, {"객체 탐지", "object detection"}, {"의미 분할", "semantic segmentation"},
        {"영상 분할", "image segmentation"}, {"대규모 언어 모델", "large language model"},
        {"거대 언어 모델", "large language model"}, {"언어 모델", "language model"}, {"확산 모델", "diffusion model"},
        {"생성 모델", "generative model"}, {"동시적 위치추정 및 지도작성", "simultaneous localization and mapping"},
        {"슬램", "SLAM"}, {"위치 추정", "localization"}, {"위치추정", "localization"},
        {"자율 주행", "autonomous driving"}, {"자율주행", "autonomous driving"}, {"라이다", "lidar"},
        {"레이더", "radar"}, {"오도메트리", "odometry"}, {"주행거리계", "odometry"}, {"센서 융합", "sensor fusion"},
        {"점군", "point cloud"}, {"포인트 클라우드", "point cloud"}, {"루프 폐쇄", "loop closure"},
        {"가림", "occlusion"}, {"로봇", "robot"}, {"로보틱스", "robotics"}, {"추적", "tracking"},
        {"최적화", "optimization"}, {"보정", "calibration"}, {"분류", "classification"}, {"회귀", "regression"},
        {"군집화", "clustering"}, {"전이 학습", "transfer learning"}, {"표현 학습", "representation learning"},
        {"대조 학습", "contrastive learning"}, {"다중 모달", "multimodal"}, {"멀티모달", "multimodal"},
        {"데이터셋", "dataset"}, {"벤치마크", "benchmark"}, {"주의 기제", "attention"}, {"트랜스포머", "transformer"},
        {"그래프", "graph"}, {"확률", "probability"}, {"통계", "statistics"}, {"인과 추론", "causal inference"},
        {"유전체", "genomics"}, {"단백질", "protein"}, {"생물학", "biology"}, {"양자", "quantum"},
        {"반도체", "semiconductor"}, {"배터리", "battery"}, {"기후 변화", "climate change"}, {"경제학", "economics"},
        {"검색", "search"}, {"설정", "settings"}, {"라이브러리", "library"}, {"논문", "paper"}, {"주석", "annotation"},
        {"노트", "note"}, {"번역", "translate"}, {"요약", "summary"}, {"인쇄", "print"}, {"내보내기", "export"},
        {"열기", "open"}, {"닫기", "close"}, {"뒤로", "back"}, {"앞으로", "forward"}, {"확대", "zoom in"},
        {"축소", "zoom out"}, {"집중", "focus"}, {"단축키", "shortcuts"}, {"테마", "theme"}};
    return values;
}
}

QStringList SearchText::personNames(const QString &query)
{
    QString name = normalized(query);
    name.remove(' ');
    static const QRegularExpression hangul("^[가-힣]{2,5}$");
    if (!hangul.match(name).hasMatch()) return {};
    const int familySize = families().contains(name.left(2)) && name.size() > 2 ? 2 : 1;
    const auto surnames = families().value(name.left(familySize));
    if (surnames.isEmpty() || name.size() - familySize > 3) return {};
    QList<QStringList> given{{}};
    for (const auto ch : name.mid(familySize)) {
        QList<QStringList> next;
        for (const auto &part : given)
            for (const auto &spelling : syllable(ch))
                if (next.size() < 8) next << (part + QStringList{spelling});
        given = next;
    }
    QStringList result;
    for (const auto &part : given)
        for (const auto &family : surnames) {
            auto first = part.join("");
            first[0] = first[0].toUpper();
            append(result, first + ' ' + family);
            append(result, family + ' ' + first);
            append(result, part.join(' ') + ' ' + family);
            append(result, part.join('-') + ' ' + family);
            append(result, family + ' ' + part.join('-'));
        }
    return result;
}

QStringList SearchText::localVariants(const QString &query)
{
    const auto original = normalized(query).left(512);
    QStringList result;
    append(result, original);
    if (original.isEmpty()) return result;
    auto translated = original;
    // Longest expressions precede their component words. Keep the user's original as the first candidate.
    static const auto words = [] {
        auto entries = vocabulary();
        std::stable_sort(
            entries.begin(), entries.end(), [](const auto &a, const auto &b) { return a[0].size() > b[0].size(); });
        return entries;
    }();
    for (const auto &word : words) translated.replace(word[0], word[1]);
    append(result, translated);
    const auto tokens = translated.split(' ', Qt::SkipEmptyParts);
    for (const auto &token : tokens) {
        if (token.size() < 3) continue; // A common one-syllable surname alone is too broad in general search.
        const auto names = personNames(token);
        for (const auto &name : names) {
            auto variant = translated;
            variant.replace(token, name);
            append(result, variant);
        }
    }
    // Names typed with a space between surname and given name.
    if (original.contains(' ') && translated == original)
        for (const auto &name : personNames(original)) append(result, name);
    return result;
}

bool SearchText::matchesAny(const QString &text, const QStringList &variants)
{
    const auto haystack = normalized(text).toCaseFolded();
    auto compact = haystack;
    compact.remove(QRegularExpression("[\\s-]+"));
    for (const auto &variant : variants) {
        const auto needle = normalized(variant).toCaseFolded();
        if (needle.isEmpty()) return true;
        const auto terms = needle.split(' ', Qt::SkipEmptyParts);
        if (std::all_of(terms.begin(), terms.end(), [&](const auto &t) { return haystack.contains(t); })) return true;
        auto joined = needle;
        joined.remove(QRegularExpression("[\\s-]+"));
        if (compact.contains(joined)) return true;
    }
    return variants.isEmpty();
}

SearchText::SearchText(ResearchStore *store) : QObject(store), m_store(store)
{
    const auto revise = [this] {
        ++m_revision;
        emit revisionChanged();
    };
    connect(this, &SearchText::changed, this, revise);
    connect(this, &SearchText::configurationChanged, this, revise);
    m_delay.setSingleShot(true);
    m_delay.setInterval(600);
    auto *ai = qobject_cast<AiService *>(store->ai());
    const auto configuration = [this] {
        const auto next = m_store->setting("search.aiTranslation", "1") + '|' + cacheKey({});
        if (next == m_configuration) return;
        m_configuration = next;
        m_delay.stop();
        emit configurationChanged();
    };
    connect(store, &ResearchStore::settingsChanged, this, configuration);
    connect(ai, &AiService::providersChanged, this, configuration);
    connect(&m_delay, &QTimer::timeout, this, [this, ai] {
        if (m_store->setting("search.aiTranslation", "1") != "1" || !ai->canSend()) return;
        const auto key = cacheKey(m_query);
        if (m_cache.contains(key)) return;
        m_cache.insert(key, {}); // Includes pending/failed requests; typing cannot trigger a retry storm.
        m_requests.insert(ai->translateSearch(m_query), {key, m_query});
    });
    connect(ai, &AiService::searchTranslated, this, [this](int id, const QStringList &terms, const QString &) {
        if (!m_requests.contains(id)) return;
        const auto [key, query] = m_requests.take(id);
        if (m_cache.size() > 128) m_cache.clear();
        m_cache.insert(key, terms);
        if (!terms.isEmpty()) emit changed(query);
    });
}
QString SearchText::cacheKey(const QString &query) const
{
    auto *ai = qobject_cast<AiService *>(m_store->ai());
    return ai->provider() + '|' + ai->model(ai->provider()) + '|' + m_store->setting("ai.baseUrl." + ai->provider())
        + '|' + normalized(query);
}
QStringList SearchText::variants(const QString &query) const
{
    if (!m_localCache.contains(query)) {
        if (m_localCache.size() >= 128) m_localCache.clear();
        m_localCache.insert(query, localVariants(query));
    }
    auto list = m_localCache.value(query);
    if (m_store->setting("search.aiTranslation", "1") == "1")
        for (const auto &term : m_cache.value(cacheKey(query))) append(list, term, 28);
    return list;
}
bool SearchText::matches(const QString &text, const QString &query) const
{
    return matchesAny(text, variants(query));
}
void SearchText::prepare(const QString &query)
{
    static const QRegularExpression hangul("[가-힣]");
    const auto value = normalized(query);
    if (value != m_query) {
        m_delay.stop();
        m_query = value;
    }
    if (value.size() > 256 || value.size() < 2 || !hangul.match(value).hasMatch()
        || m_store->setting("search.aiTranslation", "1") != "1" || m_cache.contains(cacheKey(value)))
        return;
    m_query = value;
    m_delay.start();
}
QString SearchText::webQuery(const QString &query) const
{
    const auto list = variants(query);
    if (list.size() < 2) return query;
    // Keep Korean usable on multilingual engines, with the best English alternative beside it.
    return '(' + list.first() + ") OR (" + list[1] + ')';
}
