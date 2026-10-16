# 기획서 대비 구현 현황

2026-10-10 기준. 현재는 **PDF 리더 + 웹 탭 + 라이브러리 + 주석·노트와 연결 + 단어·의미 검색 + 탭 그룹 + AI 읽기 보조 + 백업·내보내기 + 폴더 동기화**를 갖춘 Research Workspace입니다. 기획서 v0.1–v0.5와 v1 마무리 항목을 구현했습니다. macOS에서 빌드·자동 검증했고, Linux·Windows는 GitHub Actions CI로 빌드·테스트합니다(실기기 확인은 남음).

핵심 원칙은 **가볍고 빠름**입니다. 시작할 때 라이브러리를 훑지 않고, 무거운 작업(본문 색인·OCR·의미 벡터·백업)은 낮은 우선순위 배경 스레드에서 읽는 동안 멈추며, 선택 기능(의미 검색·OCR·주석 PDF)은 켜거나 설치하기 전에는 아무 비용이 없습니다.

| 기획서 | 현재 구현 | 남은 범위 |
| --- | --- | --- |
| 1–3. 개요·원칙 | 로컬 저장, 원본 PDF 불변, 출처 검증(SHA-256·파일 스탬프 캐시), 외부 전송은 웹 탭·명시적 조회·동의한 AI·의미 검색 엔진 요청만 | 실제 대형 PDF 성능 실측 |
| 4. 객체 모델 | 공통 Document ID(PDF·웹, 탭에도 저장), 공통 DocumentAnchor(위치·문장 인용, 하나의 이동 경로) | 앵커 저장 형식 통합(현재는 읽을 때 구성) |
| 5–6. 실행·Home | 세션 복원, 비정상 종료 감지·안내·편집 초안 복구, Home 검색·웹 검색·이어 읽기 카드·For You·Collections·최근 논문·노트·AI 대화(마지막으로 연 순서) | — |
| 7–10. 문서·웹·탭 | PDF·암호 PDF·분할·탭 단축키, 웹 탭(진행 막대·프레임 PDF 안내), 이름 있는 탭 그룹(접기·Collection 저장), AI 탭 정리(승인 후 적용) | Reader Mode, 웹 탭 상태 유지, OS 창 분리 |
| 11. 정리 | 라이브러리(Papers·Notes·Trash, Collection·Tag·읽기 상태·중복·색인 제외), 논문·노트·AI 대화를 함께 담는 휴지통, 관련 논문·노트 | Smart Collection |
| 12–16. 검색·커맨드 | FTS5 본문(+OCR), 단어 순서 무관·점수 순위, 범위 칩·검색어 조건, 선택적 의미 검색(Ollama·OpenAI), 명령 팔레트 | — |
| 17–21. 주석·연결 | 5색 주석·코멘트, 영역 표시(캡션 함께), 노트 링크·역링크, 주석 포함 PDF 내보내기(표준 주석). 이전 Captures는 주석·노트로 통합(스키마 15) | Figure 자동 인식 |
| 22–27. 노트·AI | Markdown 노트, AI 4종(Claude API, OpenAI API, ChatGPT 계정, Ollama), 모델·추론 강도·Fast, 이미지·PDF/웹 영역 첨부(저장 안 함), Thread(논문별 자동 + 여러 논문을 묶는 나만의 Thread)와 그 안의 Chat, 채팅에 여러 논문(3편까지 전문, 그 이상은 구절 검색)·Collection·라이브러리 전체 첨부, 선호 언어, 논문 비교표, 쪽별 번역·논문 요약, 탭·Collection AI 정리 | 라이브러리 전체에 묻기(v0.6) |
| 28–32. 데이터·기술 | C++20 + Qt Quick/PDF/WebEngine, 공유 폴더를 통한 컴퓨터 간 동기화(Google Drive·Dropbox·Syncthing, 항목별 나중 변경 우선), SQLite(라이브러리 스키마 19, 색인 4, 업그레이드 전 백업), 백업·복원, Markdown·BibTeX 내보내기, 단축키 변경, macOS·Linux·Windows 키 저장소, 로컬 설치 스크립트, 자동 테스트 7묶음 | Linux/Windows 실기기, 배포 패키지 |

## 우선순위

가볍고 빠름을 먼저 지키고, 기획서 순서보다 실제 사용 중 불편한 부분을 먼저 고칩니다. 기능별 사용법은 [README](../README.md)와 각 문서에, 변경 이력은 git 로그에 있습니다.

## 이번 단계 (2026-10-17): People 검색 제한 복구와 유사 후보

- People에서 보이던 `Semantic Scholar is busy`는 429 요청 제한 응답이었습니다. 한 번에 여러 표기를 조회하던 방식을 선택한 표기 한 번 조회로 줄이고, AI 번역 도착 후 자동 재검색을 제거했습니다. 로컬에서 변환할 수 있는 이름은 People 검색을 위해 AI를 추가 호출하지 않습니다.
- 입력 아래 최대 5개의 영문 표기 후보를 보여 줍니다. 후보를 누를 때만 그 표기를 조회합니다. 이는 확인된 인물 정보와 구분해서 표시하며, API가 반환한 실제 저자는 이름 유사도 우선으로 최대 5명을 보여 줍니다. ID가 다른 동명이인을 합치거나 자동 팔로우하지 않습니다.
- 진행 중 중복 요청을 합치고, 성공한 검색 결과는 앱 실행 중 최대 48개·10분 동안 캐시합니다. 429 응답의 `Retry-After`를 반영하고(없으면 60초), 남은 시간 동안 요청을 보내지 않으며 시간이 끝나면 Find와 후보 버튼을 다시 사용할 수 있습니다. 제한이 지속되면 다시 대기하며 자동 반복 요청은 하지 않습니다.
- 제한 중에도 검색 후보와 Semantic Scholar 웹 검색·Google Scholar 링크를 제공합니다. 검색 상태 문구를 줄바꿈해 잘리지 않게 했습니다. 공개 API의 공유 요청 제한은 앱에서 없앨 수 없으며, 웹 검색 결과나 홈페이지로 인물을 확인할 수 있습니다. [Semantic Scholar 요청 제한 안내](https://www.semanticscholar.org/product/api/tutorial).
- 검증: 전체 빌드 성공, 검색 C++ 검사 9개·People UI 10개·기존 한글 검색 UI 8개 통과(초기화/정리 포함). 모의 429 응답 후 대기·요청 억제·재시도 성공, 단일 조회·캐시·ID 중복 제거·상위 5명 정렬, 늦은 AI 응답이 재검색하지 않는 동작을 확인했습니다. 전체 ctest는 8묶음 중 6개 통과했으며, 기존 macOS offscreen 인쇄 대화상자 검사 실패와 Main/WebEngine 초기화 충돌 2개는 남아 있습니다. 실제 공개 API의 제한 해제 여부·검색 품질은 별도 실사용 확인이 필요합니다.

## 지난 단계 (2026-10-17): 한글 이름·주제 검색

- 공통 검색 변환을 Home·통합 검색·라이브러리·PDF 안에서 찾기·People·웹 검색·명령/단축키 및 AI 선택 목록 필터에 연결했습니다. 원래 검색어를 유지하고 한글 이름의 성/이름 순서·붙임표·대표 로마자 표기를 함께 찾습니다. 예: `김주현` → `Juhyun Kim`, `Ju-hyun Kim`, `Kim Juhyeon`. 원래 표기와 확장 표기의 결과를 합칠 때 중복을 제거하며, 날짜·태그·문서 범위 조건은 유지합니다.
- 주요 학술 용어는 로컬에서 확장합니다(`레이더 오도메트리` → `radar odometry`, `기계학습` → `machine learning` 등). For You의 arXiv 주제에도 같은 기본 용어를 적용합니다. 모르는 용어를 번역한 것처럼 꾸미지 않고 원문 검색을 유지합니다.
- 요청에 따라 설정·동의한 AI가 있으면 잠시 입력이 멈춘 뒤 검색어만 자동 번역해 영문 후보를 추가합니다. Settings → Search → Korean search → Translate search terms with AI에서 끌 수 있습니다. AI가 없거나 실패하면 로컬 검색을 유지하며 논문·노트 내용은 보내지 않습니다. 응답은 현재 검색어에만 적용하고 모델별 메모리 캐시와 중복 요청 방지로 반복 요청을 줄입니다. 실제 번역 품질과 과금은 선택한 제공자에 따릅니다.
- 최초 People 구현의 여러 표기 순차 조회는 위 단계에서 단일 조회와 선택형 후보로 변경했습니다. PDF 찾기는 Qt가 반환한 원문 위치·도형을 합쳐 다음/이전 이동과 강조 표시를 유지합니다.
- 검증: 전체 빌드 성공, 한글 검색 C++ 5개·독립 UI 6개 시나리오 통과(초기화/정리 포함 각각 7·8), 기존 PDF 리더 54·People 8·팔레트 18개 검사 통과. 전체 ctest는 8묶음 중 6개 통과, 기존 macOS offscreen 인쇄 타임아웃과 WebEngine 초기화 충돌 2개는 지속됩니다. 실제 Semantic Scholar 결과 품질과 실제 AI 번역 품질은 모의 응답 검사와 별도로 실사용 확인이 필요합니다.
- 한계: 규칙과 기본 어휘만으로 모든 개인 영문 표기·모든 학술 용어를 보장하지는 않습니다. 이름 일치는 인물 확인이 아니므로 소속·홈페이지를 확인해야 합니다. 이름 변환 참고: [국립국어원 로마자 표기](https://m.korean.go.kr/front_eng/roman/roman_01.do), [Unicode 한글 정규화](https://unicode.org/faq/korean.html).

## 이번 단계 (2026-10-16): People에서 사람 확인하기

- Settings → For You → People의 검색 결과와 기존 팔로우 행에 펼치기/접기 화살표를 추가했습니다. 펼치면 소속, 등록된 Homepage, 선택한 저자 ID의 Paper List(Semantic Scholar), Search Google Scholar를 보여줍니다. 홈페이지가 없는 기록은 Search for Homepage로 이름과 알려진 소속을 검색합니다. 검색 링크를 개인 홈페이지로 표시하지 않습니다.
- 링크는 기본 브라우저로 열어 검색 목록과 팔로우 상태를 유지합니다. 소속이 없으면 미등록 안내, 조회 실패 시 재시도와 대체 검색 링크를 제공합니다. 키보드로도 펼치고 접을 수 있습니다.
- 검색은 작은 프로필 필드를 함께 받고, 기존 팔로우는 펼칠 때만 조회합니다. 앱 실행 중 최대 48명까지 캐시하고 진행 중 중복 요청을 합칩니다. 전체 논문 목록은 내려받지 않으며, 기존 팔로우 저장·동기화 형식은 그대로입니다.
- 데이터 필드: [Semantic Scholar Academic Graph API](https://api.semanticscholar.org/api-docs/). 홈페이지는 해당 저자 기록에서 받은 HTTP(S) 주소만 사용합니다.
- 검증: 전체 빌드 성공, 신규 People UI 시나리오 6개 통과(초기화/정리 포함 8), 저장소 테스트의 프로필 파싱·캐시·중복 요청·재시도 검사 통과, offscreen 렌더링 확인. 전체 ctest 7묶음 중 5개 통과; 기존 macOS offscreen 인쇄 타임아웃·전체 리더 WebEngine 초기화 충돌은 지속됩니다. 별도 Settings 테스트는 For You 포함 14개 통과/ChatGPT 시작 로그인 응답 검사 1개 실패입니다.

## 이번 단계 (2026-10-12): 손에 익게

- For You(원본 x-or-b에서 가져옴, 아이콘은 하트): 팔로우한 주제(단어 + arXiv 분야)는 arXiv에서, 팔로우한 사람(이 저장소에서 추가: Settings › For You › People에서 이름으로 찾아 맞는 사람을 고름, Semantic Scholar 저자 기록; Google Scholar에서 팔로우하는 사람을 여기서 다시 고르면 됨)은 그 사람의 기간 안 새 논문(저자 논문 목록의 날짜 → 새 것만 paper/batch로 자세히), 팔로우한 Collection은 Semantic Scholar 추천(그 Collection에서 arXiv ID·DOI가 있는 논문 최대 50편)으로 새 논문을 찾음. 이미 Library에 있거나 Dismiss·Add한 논문, 기간(1·7·30일, 기본 7일)보다 오래된 논문은 빼고, 출처마다 5·10·20편(기본 10), 대기 목록 300편까지. arXiv 요청 사이 3초. Check Now, 또는 하루 한 번 자동(앱을 연 뒤 잠시 후, 동기화 중이면 기다리고 다른 컴퓨터가 오늘 이미 확인했으면 건너뜀). Explain with AI: 새 논문 최대 40편의 제목·저자·연도·abstract(1,200자)와 팔로우 정보를 AI에 보내 0~100점과 25단어 이내 이유(AI 언어 설정)를 받아 점수 순으로(켜는 스위치가 보내기 동의). Home: Continue Reading 아래 새 논문 5편(팔로우가 없으면 설정으로 가는 한 줄, 새 논문이 없으면 숨김). Library › For You 탭(`Papers · For You · Notes · Trash`): 가운데 920px 열, 기간 칩(All·Today·This week·This month), Select(Add·Dismiss), 출처별 보기, 줄마다 제목 → AI 이유 → "Lovelace et al. · 3 days ago · 출처", 마우스를 올리면 Add·Dismiss, 클릭하면 abstract 전체와 Add to Library·Open Page·Dismiss. Settings → For You에 주제·Collection·자동 확인·AI·기간·목록 유지 기간(7·15·30·60일·항상, 기본 30일)·출처당 편수·Check Now. Collection 우클릭 "Follow in For You". Add: PDF를 받아(arXiv PDF 또는 공개 PDF, 진짜 PDF인지 확인) Paper names 구성으로 이름 짓고 Collection 추천이면 그 Collection에, 제목·저자·연도·DOI·arXiv ID를 채움. 무료 PDF가 없는 논문(Semantic Scholar가 DOI 링크만 줌)은 "No free PDF"로 표시되고 Add 대신 Get PDF on Its Page(여러 편 Add에서는 빠지고 알림). 직접 받기가 실패하거나 PDF가 아닌 답이 오면 그 PDF 주소를 웹 탭에서 받음(이유를 알림). For You에서 연 논문 페이지 탭은 거기서 받은 PDF를 열지 않고 Library에 안 읽음으로 넣은 뒤 닫히고, 그 PDF는 Add처럼 제목·저자·연도·Collection을 받으며 목록에서 빠짐(Home에서 연 페이지도 같음). Preview(열린 논문 또는 마우스를 올렸을 때의 눈 아이콘): PDF를 캐시(`<data>/foryou-preview`, 일주일)에 받아 목록 오른쪽에 보여주고 목록은 왼쪽으로; 미리보기 중 다른 논문을 누르면 그것을 보여줌; 위에 Add to Library·Dismiss·닫기(Esc); 핀치·⌘/Ctrl+휠은 모든 쪽을 함께 확대(포인터 아래 위치 유지); Add는 미리 받은 파일을 다시 받지 않고 씀. abstract는 For You 목록에 있는 동안만 보임. 주제·팔로우·찾은 논문·AI 이유·Dismiss/Add 기록은 동기화(스키마 18: foryou_topics·foryou_follows·foryou_items·foryou_meta, 스키마 19: foryou_people; 이 저장소의 18은 우리 17 위의 For You 표만, 원본의 18과는 다른 단계). 기간·자동 확인·유지 기간·편수는 컴퓨터마다. 밖으로 나가는 것: arXiv에 주제 단어·분야, Semantic Scholar에 팔로우한 Collection 논문의 arXiv ID·DOI와 찾는 사람 이름·팔로우한 사람의 저자 ID, AI(켰을 때)에 새 논문의 제목·abstract와 팔로우 정보.
- AI: Chat이 Thread에 모임(논문마다 자동 Thread, 여러 논문을 묶는 나만의 Thread; 스키마 17).
- AI Thread 정리: 모든 Thread(General·논문·나만의)에 `…` 버튼(행에 마우스를 올리거나 선택했을 때, 위쪽 제목 줄 오른쪽)과 우클릭 메뉴: New Chat, Rename…(나만의), Merge Into ▸(다른 Thread로 Chat을 옮겨 합침), Delete ▸ 하나(빨간색)를 누르면 두 가지로 나뉨: Delete Thread and Chats…(Chat은 Library의 Trash로, 되살릴 수 있음), Delete Thread, Keep Chats…(나만의 Thread는 Chat이 각 논문 Thread로, 논문 Thread는 General로; General은 남길 곳이 없어 흐리게). 지우는 항목은 빨간색이고, Thread를 지울 때와 Chat 여러 개를 한 번에 지울 때(메뉴·Delete 키)는 먼저 확인(Chat 하나는 바로 Trash로). Chat 행에도 `…`. Threads 목록에서 Thread 왼쪽 화살표로 그 자리에서 펼치면 그 안의 Chat들이 들여쓰기로 보이고(선택은 그대로), 누르면 그 Thread에서 열림(우클릭은 Chat 메뉴). All Chats는 이미 전부라 펼치지 않음. 논문 Thread(와 논문에 대한 Chat)의 `…`/우클릭 맨 위: 그 논문이 다른 탭에 열려 있으면 `Go to Paper`(그 탭으로, 분할 화면의 다른 쪽이어도), 닫혀 있으면 `Open Paper`, 파일이 없어졌으면 `Locate PDF…`(앞에 보고 있는 논문이면 안 보임). 논문 Thread는 Chat이 있는 동안만 있음: 마지막 Chat을 지우거나 옮기거나 합치면, 또는 Thread를 지우면 앞에 열린 논문이어도 사라지고(빈 Thread도 지울 수 있음), 그 논문에 새로 물으면 다시 생김. 질문은 보내는 순간 Chat에 저장(제목만 있는 Chat이 남지 않음). 답을 기다리는 중에 목록으로 돌아가거나 다른 Chat을 열어도 답은 계속 와서 저장되고(목록에 "Answering…", 끝나면 알림), 다시 열면 이어서 보임. 답을 못 받은 질문은 그대로 남고 아래에 이유(또는 Stopped.)를 표시, 이어 묻기에는 답이 있는 대화만 보냄. Chat은 General·논문 Thread로도 옮길 수 있고 옮긴 곳에 남음. Thread 목록에서 질문하면 그 Thread에 새 Chat(논문 Thread는 그 논문, General은 논문 없이, All Chats는 앞에 열린 논문의 Thread, 없으면 General). 좁은 패널의 Threads 목록 아래에도 질문 칸. Chat을 열면 맨 아래(가장 최근 질문)부터 보이고, 답이 와도 보던 자리를 지킴.
- 단축키 한눈에 보기: `?`, `⌘/`, 상태 표시줄 `?`, Help 메뉴, `/shortcuts`(`/list`).
- AI 채팅에 여러 논문(원본 x-or-b에서 가져옴): 첨부(클립) 메뉴의 `Papers…`(열린 탭의 논문이 먼저, 그다음 Library; 여러 편을 골라 Attach), `Collection…`, `Whole Library`. Library의 논문이나 PDF를 AI 패널에 끌어다 놓아도 됨. 3편까지는 통째로 읽고(한 편 분량을 나눠 씀), 그보다 많거나 Collection·라이브러리 전체면 질문마다 답에 맞는 구절을 찾아 보냄(Chat의 논문도 함께). 여러 편일 때 인용은 `[P2 p. 3: "…"]`처럼 어느 논문인지 표시되고 그 PDF의 그 쪽으로 링크(P1은 Chat의 논문). 다시 연 Chat은 마지막 질문이 찾던 곳(Collection·라이브러리·여러 논문)에서 계속 찾음. 첨부한 논문은 그 Chat과 연결됨. Thread 목록 아래에서 첨부하고 물으면 그 Thread의 논문 다음(P2부터)으로 들어감.
- Library 선택 모드(원본 x-or-b에서 가져옴): Add 옆 체크 버튼으로 켜면 클릭으로 논문을 고름(열리지 않음). 바에 Select All / Delete(고른 게 있을 때) / Done, Esc로 나가고 Delete·Backspace는 고른 논문을 Trash로(입력 칸에서는 글자 지우기). 모드 밖 ⌘/Ctrl-클릭·Shift-클릭은 그대로. 목록의 논문을 끌면 포인터를 따라다니는 라벨이 생기고 왼쪽 Collection(또는 AI 패널, Library 패널)에 놓을 수 있음.
- 뒤로/앞으로(원본 x-or-b에서 가져옴): 브라우저처럼 다녀온 곳(Home, 탭: Library·논문·노트·웹 페이지)을 오감. 앞의 탭 안에서 갈 곳(웹 탭의 이전 페이지, 논문의 링크·인용 이동)을 먼저 따르고, 그다음 장소 사이. 상태 표시줄 왼쪽 끝의 `<` `>`, `⌥←`/`⌥→`(Windows·Linux `Alt+←`/`Alt+→`), View 메뉴. 새 곳으로 가면 앞쪽 기록은 지워짐.
- 단축키 설정(Settings → Shortcuts)을 종류별 섹션으로(Search and places·Tabs·Splits·Panels·Reading·Notes and AI; 원본 x-or-b에서 가져옴). 새로 바꿀 수 있는 키: 이전/다음 쪽(`⌘[`·`⌘]`), 뒤로/앞으로, Fit Width(`⌘0`), Fit Page(`⌥⌘0`), Highlight Selection(`⌃⌘H`, Windows·Linux `Ctrl+Alt+H`), Comment(`⌃⌘M`), Dark Pages(`⇧⌘D`), Ask AI(`⇧⌘A`: 선택한 글, 없으면 앞의 논문에 새 Chat), 패널 열고 닫기(Library `⇧⌘E`, Document `⇧⌘O`, Annotations `⇧⌘M`, AI `⇧⌘I`). View 메뉴에도 있음.
- 논문에서 `←`/`→`는 이전/다음 쪽(새 쪽의 맨 위로). 쪽이 보기보다 넓으면 먼저 옆으로 움직이고 가장자리에서 쪽을 넘김. 입력 칸에 커서가 있으면 그 칸이 방향키를 씀. 단축키 시트에도 표시.
- 저장된 탭 중 열 수 없는 것만 빼고 나머지를 엶(전부 못 읽으면 탭 없이 시작, 원래 세션은 한 번 보관).
- PDF 끌어 넣기: 창 어디에 놓아도(Finder·다운로드 폴더·브라우저 다운로드 목록) PDF 폴더로 옮기고 Library에 추가, 6개까지는 탭으로 엶. 폴더는 Collection으로 가져오고, 웹 주소는 웹 탭. Settings → Data에서 옮기기/복사 선택.
- PDF 폴더 바꾸기: Settings → Data → PDF folder → `Change…`. 이미 있던 PDF도 새 폴더로 옮기고 주석·노트 연결은 그대로.
- 추가할 때 중복 확인: 끌어 넣거나 + (Add PDFs…·Add Folder…)로 추가할 때, 웹에서 받을 때 이미 있는 논문(같은 파일, DOI·arXiv 번호·제목이 같은 논문)이면 묻고, `Open It`은 있는 것을 열고 그 파일 이름을 알려 줌. 폴더째 끌어 넣기(하위 폴더 포함)와 메뉴로 추가한 PDF도 PDF 폴더로 옮김(Settings → Data → Adding PDFs에서 복사로 바꿈).
- 논문 이름(파일 이름·보이는 이름): Settings → Data → Paper names에서 제목, 첫 저자 성(여러 명이면 "et al."), 연도(4자리일 때만), arXiv ID를 각각 켜고 끄고 순서를 바꿈(예시 미리보기, 원본 x-or-b의 방식). " - "로 잇고 파일 이름에서는 제목을 120자에서 다른 부분이 쓴 만큼 줄임(최소 40). 기본값은 저자·연도·제목(`Vaswani et al. - 2017 - Attention Is All You Need`). Library·탭·검색에 보이는 이름도 같은 구성(웹 페이지는 원래 제목, 내보내기와 AI에 보내는 제목은 논문 제목 그대로). PDF 폴더의 파일은 논문 정보가 생기거나 바뀌거나 구성을 바꾸면 그 이름으로 바뀜(같은 이름이면 번호; 한동안 탭에 열려 있던 논문은 다음 실행 때; Settings → Data의 Name files after their papers로 끔). 다운로드, 논문 메뉴 `Rename File After Paper`, Library 선택 `Rename Files After Papers`, `Rename Now`도 같은 구성(모두 이미 그 이름이면 그렇다고 알림; 같은 이름 옆의 "이름 (1)"은 실행할 때마다 번호가 바뀌지 않고 그대로). Owelk PDF 폴더의 파일만 바꾸고, 노트·주석은 그대로.
- Windows 설치: `tools/install-local.ps1`(x-or-b의 스크립트에 winget이 자기 자신을 부르던 문제와 32비트 PowerShell 문제 수정).
- 웹 검색: Home 웹 검색 칸 오른쪽에서 Scholar·arXiv·Google·DuckDuckGo를 바로 고름. 어디서든 `arxiv: 단어`, `scholar: 단어`로 한 번만 다른 곳에서 검색. Settings → Web → Search engines(원본 x-or-b에서 가져옴): 엔진마다 작은 accent 알약 `Default`, 눈 아이콘으로 Home 엔진 버튼에서 숨기기(숨기면 줄 그은 눈에 흐리게, 기본 엔진은 항상 보임), 직접 추가할 때 `google.com` 같은 사이트만 쳐도 검색 주소와 이름이 채워짐(%s 주소도 그대로 됨).
- Google 계정: Settings → Web → Google account. Sign In…은 Settings를 닫고 Google 로그인 페이지를 웹 탭으로 엶(비밀번호는 Google 페이지에 직접 입력, Owelk는 모름). 웹 탭들은 하나의 영구 프로필을 쓰므로 한 번 로그인하면 Scholar·YouTube·Google이 모든 웹 탭에서, 다시 켠 뒤에도 로그인 상태. 상태는 프로필 쿠키로 판단(시작 때는 프로필의 Cookies 파일을 읽기 전용으로 읽고, 이후에는 쿠키 변화를 따라감; 엔진은 페이지가 하나 열리기 전에는 저장된 쿠키를 알려 주지 않음). Sign Out은 Google·YouTube 쿠키를 지움, Account…는 myaccount.google.com. Google이 내장 브라우저의 로그인을 막는 경우가 있어 로그인 페이지(accounts.google.com)만 지금의 Firefox로 보이게 함: 요청의 User-Agent와, 그 페이지의 스크립트가 보는 navigator(userAgent·platform·vendor 등, userAgentData·window.chrome 없음)가 서로 맞게(Sign in as Firefox, 기본 켬, qutebrowser와 같은 우회; 버전은 달력을 따라감: 2026-10-12의 158부터 4주마다 하나씩, 오래된 Firefox는 Google이 거절하므로). Google이 "브라우저 또는 앱이 안전하지 않을 수 있습니다"(…/signin/rejected)를 보이면 무엇을 해 볼지 알림(Sign in as Firefox를 반대로).
- 가볍게: Release 빌드는 기호를 빼고(macOS `-dead_strip -x`, Linux `--gc-sections --strip-all`, 숨김 visibility) -O2, MicroTeX는 크기 최적화, 글꼴 리소스 압축. Windows 설치는 번역·VC 설치 파일·소프트웨어 OpenGL·D3D 컴파일러·쓰지 않는 플러그인·WebEngine 개발자 도구를 빼고 복사. 실행 중에는 설정값·키체인·최근 논문을 메모리에 두고, 목록 행마다 읽던 읽기 위치를 열 때 읽으며, 본문 색인 진행은 문서 목록과 따로 알리고, 노트 저장은 링크가 그대로면 링크를 다시 쓰지 않음. 쓰지 않던 코드(폴더 가져오기 옛 경로, 웹 문서 등록, 신호·속성 몇 개, include) 정리.
- 제목 표시줄: macOS와 Windows 11의 시스템 제목 표시줄(창 버튼 있는 줄)이 테마의 창 색을 따르고, 버튼·제목은 밝게/어둡게 맞춤(Windows 10은 밝게/어둡게만). Settings → Appearance → Theme의 "Title bar in theme colors"로 끔. 같은 곳의 Customize…로 지금 테마를 복사한 Custom 테마를 만들고 바로 아래에서 창·제목 표시줄, 사이드바, 문서, 메뉴, 글자, 선, PDF 주변 색을 고름.

## 이번 단계 (2026-10-10): 구조 단순화

- Workspaces 제거: 논문이 있던 워크스페이스는 같은 이름의 Collection이 됩니다(스키마 14, 업그레이드 전 백업).
- Captures를 주석으로 통합: 문장 캡처는 하이라이트, 영역 캡처는 새 영역 주석(캡션·메모 유지), 웹 캡처는 그림이 든 노트가 됩니다(스키마 15, 같은 ID·링크 유지). 새 `Mark Region` 도구, AI의 PDF·웹 영역 첨부는 저장하지 않는 그림.
- Document 패널 네 칸: Contents(Outline·Pages), Annotations(이 논문에 대한 노트 + 모든 주석; 리더 옆 메모 열을 대신함), Symbols, Related(Library·Cites·Cited by). 새 노트는 논문 옆 분할에 링크와 함께 열림.
- AI 답변 Save as Note: 질문 인용, 이 논문의 노트에 덧붙이기. 노트의 AI 링크는 휴지통이면 Restore 안내, 영구 삭제면 회색 `Deleted conversation`.
- Library: Papers · Notes · Trash, 논문·노트·AI 대화를 함께 담는 휴지통(지울 항목을 링크한 노트가 있으면 먼저 알림, 기간이 지나면 노트도 자동 삭제). Library 패널이 Library의 고르는 곳: All Papers·Favorites·Unsorted·Unread·Reading·Read·Collection·Tag를 누르면 Library 탭(없으면 열림)의 목록에 그 논문들이 나오고, 탭이 앞에 있는 동안 그 줄이 강조됨. 패널이 열려 있으면 Library 탭의 자체 사이드바는 숨고 목록 위에 지금 보이는 것의 이름(하위 Collection은 "상위 › 하위")이 나옴; 패널을 닫으면 사이드바가 다시 나옴. Collection은 하위 Collection으로 접히고 펼쳐짐(패널과 사이드바가 같은 상태를 씀, 이 컴퓨터의 설정 `library.openCollections`): 화살표는 접기/펴기만, 이름을 누르면 보여주면서 펼치고, 보이는 중에 다시 누르면 접힘; 다른 곳에서 고른 Collection은 상위가 펼쳐져 보임. Collection 우클릭은 Add PDFs·New Sub-collection·Rename·Follow in For You·Delete. 그 밖에 Notes(+)와 폴더/최근 파일. 탭에서 필터를 바꾼 뒤에도 패널에서 고른 것이 목록에 그대로 반영됨(탭과 목록의 필터가 어긋나던 문제 수정).
- Home: 검색창 하나(라이브러리 결과와 웹 행: 주소·`arxiv:` 같은 엔진 접두어면 웹이 맨 위, 단어면 맨 아래, Ctrl/⌘+Return은 웹, 엔진 칩은 칸 오른쪽 끝, Cmd+K 팔레트도 같은 웹 행), 이어 읽기 카드, Collections | Recent Papers, Notes | AI Conversations(마지막으로 연 순서, 고정 자리 안에서 상자가 항목 수만큼). 본문 색인 상태는 색인 중·실패일 때만 보이고 Settings → Search로 옮김. 색인 목록(원본 x-or-b에서 가져옴): PDF가 사라진 논문은 휴지통 버튼으로 Library에서 빼고(여럿이면 위의 Remove N Missing), Locate the original PDF는 재연결 창을 다시 엶. 다른 컴퓨터에서 지워진(동기화로 들어온) 논문이나 Library에 없는 항목은 동기화 뒤와 시작 25초 뒤 이 컴퓨터의 색인에서도 빠짐.

## 지난 단계 (2026-10-09): 어려운 부분 읽기 돕기

- 그림·표·알고리즘·수식 위에서 우클릭하면 `Ask AI about Figure 3`처럼 그 대상을 찾아(캡션·번호·영역, 2단 쪽은 단 단위) 이미지와 이름을 AI 대화에 첨부합니다. 열려 있는 대화가 있으면(패널이 숨겨져 있어도) 거기에, 없으면 그 논문으로 새 대화를 엽니다. 선택한 글과 PDF·웹 영역도 같습니다.
- 우클릭은 상황별로 필요한 것만 보여 줍니다(선택 / 대상 위 / 빈 본문). 채팅 첨부 메뉴는 This Paper · Region of the PDF · Image.
- Gloss: 선택한 단어는 문맥상 뜻과 번역, 문장은 번역을 옆 팝업에 바로 보여 줍니다(빠른 모델, 대화에 남기지 않음).
- Document 패널 Symbols 칸: 논문의 기호 목록(뜻, 정의된 쪽 / Background, 누르면 정의 문장으로 이동·강조·Back). 목록이 있으면 기호에 마우스를 올릴 때 뜻이 뜹니다(글리프 어디서나 인식). Related에 연결된 노트를 합쳤습니다.
- Settings → AI: 기본 모델·추론 강도를 목록에서 고름, 설명 수준(쉽게·예시 / 간단히), 모든 질문에 붙는 추가 지시, Gloss 모델·추론 강도(Gloss 창에서도 바꿈).
- AI 패널: 지난 질문 위에 함께 보낸 첨부(논문·선택·그림 이름과 미리보기, 마우스를 올리면 크게)가 보입니다. 대화는 여러 개 골라 휴지통으로 옮기고, Library의 Trash(논문·노트·AI 대화를 함께)에서 되살리거나 영구 삭제합니다(30일 뒤 자동 삭제).
- 논문 본문은 요청 맨 앞에 두고 캐시 표시를 붙여, 같은 논문에 대한 반복 질문 비용을 줄였습니다(Claude·OpenAI).
- 웹에서 받은 PDF는 `제목.pdf`로 저장합니다(Settings → Web에서 웹사이트 이름으로 되돌림).

## 지난 단계 (2026-10-08): 컴퓨터 간 동기화

- Settings → Data → Sync에서 공유 폴더(Google Drive·Dropbox·Syncthing 등)를 고르면 논문·PDF·주석·노트·Collection·Tag·읽기 위치·AI 대화를 다른 컴퓨터와 맞춥니다. 설정·세션·검색 색인은 각자 둡니다. 자세한 내용은 [SYNC.md](SYNC.md).
- 컴퓨터마다 자기 변경 기록만 쓰고(충돌 사본 없음), 항목별로 나중 변경이 남습니다. 양쪽에 같은 PDF가 있었다면 하나로 합칩니다. 동기화를 켜기 전에는 아무 비용이 없습니다.
- 그 밖에: 라이브러리 전체·Collection에 묻기(쪽 인용), 답변 도착 알림 카드, 웹 탭 상태 유지, 주석 크기 조절·텍스트 상자 글자 크기, 인용 미리보기 목록.
- PDF 보관(`문서/Owelk Library/Papers`, 원본은 그대로)과 Library 휴지통(되살리기, 7·30일 뒤 자동 비우기).
- AI 패널: 채팅형 질문 말풍선, 선택 가능한 답변, 질문으로·최신으로 이동, LaTeX 수식(MicroTeX), 생각 과정 요약(접힘), 답변 한도 64k와 잘림 표시.

## 지난 단계 (2026-10-06): 정리·읽기 편의

- 탭: 세로 탭(너비 조절, 그룹 접기·이름, 접은 레일에서 논문은 제목 첫 글자 타일), 탭 영역 빈 곳 우클릭(새 탭·정렬·중복 닫기·AI 정리·가로/세로 전환), Edge식 그룹.
- Library 패널(Collections·Workspaces·Tags·Folder)과 Collection 만들기·이름 바꾸기·삭제, 끌어 놓기, Unsorted·넣을 곳 제안·여러 논문 선택.
- 논문 추가: Collection 안에 바로 추가, 폴더 한 번에(하위 폴더를 Collection 트리로). 삭제는 `Delete Paper` 하나(Library › Trash에서 되살리기, 7·30일 뒤 자동 비우기 또는 직접 비우기).
- AI 주제별 정리(기존 Collection 재사용·새로 만들기, Apply 전에는 아무것도 안 바뀜).
- 읽기: 인용·그림·표·수식 참조에 포인터를 올리면 대상 미리보기(링크가 없거나 깨진 출판사 PDF는 본문 글자에서 찾음), Fit Page 보기, `⌘[`/`⌘]` 쪽 넘김, 페이지 옆 노트, 주석 실행 취소.
- AI 정리 제안(탭·Collection)은 Apply 전에 항목 단위로 고칠 수 있습니다(빼기·옮기기·새 그룹).
- 그림·표 미리보기는 그림/표 자체를 단에 맞춰 보여 주고 카드 안에서 스크롤. 인용 카드의 Find Paper(DOI·arXiv·검색).
- AI 논문 비교표(열 지정, 노트로 저장), Semantic Scholar 인용 관계(Cites·Cited by, Library 표시, 한 달 캐시).
- 앱: 아이콘(macOS·Windows·Linux), Finder에서 PDF 열기·실행 중인 창으로 넘기기, 닫을 탭이 없으면 ⌘W로 창 닫기.
- 참조: 여러 논문 인용(`[12–14]`)은 항목 목록, 링크 있는 PDF도 Find Paper, 링크·미리보기·목차로 이동한 뒤 `Back to p. N`·⌥←로 돌아가기.
- 두 줄짜리 글자 묶음을 주는 PDF에서 선택 영역 높이가 두 배가 되던 문제 수정. 선택 없이 우클릭: AI로 묻기·쪽별 번역·논문 요약.
- 설치: `tools/install-local.sh`(macOS·Ubuntu).
- 핀치 후 다시 그리는 동안 배경 PDF 작업(색인·논문 정보)이 기다리고, 이미 보이는 쪽에는 로딩 표시를 띄우지 않습니다(논문 추가 중 다시 그리기 250–305ms → 112–115ms).

## 지난 단계 (2026-10-05): 디자인 개편

- 테마 엔진(`Theme`, 7종 + 사용자 테마, 강조색 7, 글자 크기 11–17, Dark pages), 앱 전체 컨트롤 스타일 `OwelkStyle`(호버·선택·포커스·주요 버튼 한 가지씩), 아이콘 글꼴(Lucide 일부) 하나와 `IconButton`, 글자 대신 아이콘.
- 목록 행 구분선·둥근 그룹 카드·알약 탭·공통 칩, 잘린 글자 호버 툴팁, 메뉴 너비 자동.
- 우클릭 규칙 통일(논문 메뉴 하나, 탭 종류별 메뉴, 위험 동작은 맨 끝 빨강), 중복 ⋯ 제거, 형광펜·그리기 색은 도구 우클릭, 페이지 우클릭은 그 위치의 동작만.
- Settings 카테고리화(Appearance·Web·Search·AI·Shortcuts·Data). 인쇄: 프린터가 없으면 인쇄용 PDF 저장.
- 가만히 있어도 CPU를 쓰던 계정 확인 루프를 없앴습니다(시작 후 CPU 3.6초 → 0.7초, 메모리 −15MB).

## 지난 단계 (2026-10-04): v0.5와 v1 마무리

- 플랫폼: Linux·Windows 지원(키 저장소, 경로, Codex 실행, 글꼴, 단축키 기본값), CI 3종, 설치 규칙. 인쇄 수정(한 번 검증·300dpi·대화상자 앞에).
- v0.5: 검색 순위, 선택적 의미 검색, 관련 논문·노트, 이름 있는 탭 그룹, AI 탭 정리.
- v1: 암호 PDF, OCR(Tesseract), 백업·복원·비정상 종료 복구·편집 초안, Markdown·BibTeX·주석 PDF 내보내기, 단축키 변경, DocumentAnchor.

## 검증

C++ 테스트(저장·마이그레이션·색인·재연결·주석·인쇄·주석 PDF·AI·의미 검색)와 offscreen UI 테스트(리더·작업 공간·웹·라이브러리·노트·AI 패널·검색 등)를 실행합니다. 웹·AI·의미 검색·OCR은 로컬 서버와 가짜 실행 파일로 검증하며 실제 키·계정·엔진은 사용자 확인이 필요합니다. 색인 DB 2→4 업그레이드를 실제 데이터 사본으로 확인했습니다.

## 다음 단계

**실사용 확인(Mac↔Ubuntu 동기화, Linux·Windows CI 결과, 의미 검색·OCR 실제 엔진, 백업 복원) → iPad 검토.** 세부 항목은 [NEXT.md](NEXT.md)에 있습니다.

## 2026-10-16: 원문 이동 전 확인

- AI 답변·노트의 원문/하이라이트 링크, PDF 내부 링크·참조 미리보기를 누르면 `Go to source?` 확인창을 표시합니다. `Cancel` 또는 Esc는 현재 위치와 이동 기록을 유지하고, `Go to Source`만 실제 이동합니다.
- 같은 PDF의 참조·AI 인용 이동은 기존 `Back to p. …`/뒤로 가기를 유지합니다. 일반 페이지 넘김·목차·검색에는 확인창을 추가하지 않습니다.
- 변경 전: 링크 클릭 즉시 이동. 변경 후: 링크 클릭 → 확인 → 이동 또는 현재 화면 유지.

- 검증: 빌드 성공. 리더 확인/취소/미리보기/복귀 4개와 작업공간 인용/노트 이동 2개 테스트 통과. store_and_pdf, paper_index, source_relink, ai_providers, semantic_search 통과.
- 전체 검증 한계: annotations 실행이 완료되지 않아 중단. Main을 만드는 UI 테스트는 테스트 시작 전 SIGSEGV로 종료되며, 변경 전 커밋의 QML에서도 동일하게 재현됨. 이번 기능은 Main 대신 DocumentWorkspace를 직접 사용하는 별도 offscreen 테스트로 확인.

## 2026-10-16: 읽기 보조 개선
- Gloss: 선택 좌표·쪽·파일 스탬프·제공자·모델·추론 강도·언어별 캐시. 실제 선택 위치에서 문맥을 추출하고, 닫힌 요청의 늦은 답변은 무시합니다.
- 검증: 빌드, Gloss 캐시 분리 및 모의 AI 응답 테스트 통과.
- 참조/주석: 참조가 아닌 본문에서는 문서 전체를 추출하지 않고, 오래된 호버 요청은 페이지 경계에서 중단합니다. 참조 텍스트 캐시는 파일 스탬프로 무효화합니다. 주석 로컬 변경은 해당 문서 리더만 갱신하고, 새 결과가 도착할 때까지 기존 표시를 유지합니다(전체 동기화·재연결은 전체 갱신 유지).
- 검증: 참조 탐색, 미리보기, 주석 저장·삭제·실행 취소 테스트 통과.
- 논문 길잡이: 리더 More/페이지 우클릭의 Paper Guide with AI. 기존 대화에 연구 질문→방법→결과→한계→그림·표를 간결하게 표시하며, 원문 인용 링크는 이동 확인창을 사용합니다. 저자 명시 한계/AI 추론은 별도 소제목으로 구분하고, 자료에 없는 근거는 생성하지 않도록 요구합니다.
- 검증: 길잡이 프롬프트·언어·인용 규칙 테스트 통과. 실제 모델의 답변 품질은 별도 실사용 확인 대상입니다.
- 집중 읽기: F8/View → Reading Focus/상태 표시줄 Focus로 패널·가로/세로 탭·리더 도구를 숨기고 복원합니다. 배치 설정은 수정하지 않습니다. AI나 패널을 명시적으로 열면 집중 읽기를 종료합니다.
- 확대 메뉴의 Fit Left/Right Column은 수동 단 맞춤(재배치 없음)입니다. More → Reading Bar는 포인터 줄에 임시 표시를 띄우며 주석을 저장하지 않습니다.
- 검증: 집중 읽기 도구 복원·페이지 유지, 좌우 단 전환·원본 좌표 유지, 원문 이동 회귀 테스트 통과.
- 그림·표·수식 고정: 참조 미리보기 Pin 또는 대상 우클릭 Pin for Reference. 본문 스크롤과 별개로 우측 카드에 유지하며 Unpin/닫기 또는 PDF 변경으로 해제합니다. PDF 원본이나 주석을 만들지 않는 세션 기능입니다.
- 검증: 고정 중 페이지 이동·미리보기 종료에도 유지, 명시적 해제와 다른 문서 전환 테스트 통과.
- 이어 읽기 맥락: 리더 More → Reading Checkpoint…에서 다음에 확인할 내용을 500자까지 저장합니다. Home의 Continue Reading에 메모·최근 표시·최근 질문을 함께 표시합니다. 이 메모는 현재 컴퓨터 설정에 저장되며 PDF 원본·기존 노트는 수정하지 않습니다.
- 검증: 재실행 복원·논문별 분리·휴지통 대화 제외·메모 취소/저장, 작업공간 통합 6개 동작 테스트 통과.
- 최종 검증: 빌드 성공. PDF 리더 테스트 54개·읽기 보조 작업공간 테스트 8개 통과(각 초기화/정리 포함). 전체 ctest는 저장·색인·재연결·AI·의미 검색 5/7 묶음 통과. 인쇄 테스트는 기존 macOS offscreen 동작에서 60초 시간 초과, 전체 UI는 기존 Main/WebEngine 초기화 SIGSEGV가 유지됩니다. 앞선 변경 전 QML 재현과 같은 오류이며, 리더·작업공간은 별도 실행으로 검증했습니다.
- 마무리: Gloss 모델을 바꾸면 이전 요청을 취소하고 요청 시작 시 언어·모델 설정을 고정합니다. 집중 읽기 중 패널 단축키는 해당 패널을 열며 모드를 종료합니다. 인용 목록 이동 테스트도 확인창 승인 절차를 따릅니다.
