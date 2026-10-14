# 기획서 대비 구현 현황

2026-10-10 기준. 현재는 **PDF 리더 + 웹 탭 + 라이브러리 + 주석·노트와 연결 + 단어·의미 검색 + 탭 그룹 + AI 읽기 보조 + 백업·내보내기 + 폴더 동기화**를 갖춘 Research Workspace입니다. 기획서 v0.1–v0.5와 v1 마무리 항목을 구현했습니다. macOS에서 빌드·자동 검증했고, Linux·Windows는 GitHub Actions CI로 빌드·테스트합니다(실기기 확인은 남음).

핵심 원칙은 **가볍고 빠름**입니다. 시작할 때 라이브러리를 훑지 않고, 무거운 작업(본문 색인·OCR·의미 벡터·백업)은 낮은 우선순위 배경 스레드에서 읽는 동안 멈추며, 선택 기능(의미 검색·OCR·주석 PDF)은 켜거나 설치하기 전에는 아무 비용이 없습니다.

| 기획서 | 현재 구현 | 남은 범위 |
| --- | --- | --- |
| 1–3. 개요·원칙 | 로컬 저장, 원본 PDF 불변, 출처 검증(SHA-256·파일 스탬프 캐시), 외부 전송은 웹 탭·명시적 조회·동의한 AI·의미 검색 엔진 요청만 | 실제 대형 PDF 성능 실측 |
| 4. 객체 모델 | 공통 Document ID(PDF·웹, 탭에도 저장), 공통 DocumentAnchor(위치·문장 인용, 하나의 이동 경로) | 앵커 저장 형식 통합(현재는 읽을 때 구성) |
| 5–6. 실행·Home | 세션 복원, 비정상 종료 감지·안내·편집 초안 복구, Home 검색·웹 검색·이어 읽기 카드·Collections·최근 논문·노트·AI 대화(마지막으로 연 순서) | — |
| 7–10. 문서·웹·탭 | PDF·암호 PDF·분할·탭 단축키, 웹 탭(진행 막대·프레임 PDF 안내), 이름 있는 탭 그룹(접기·Collection 저장), AI 탭 정리(승인 후 적용) | Reader Mode, 웹 탭 상태 유지, OS 창 분리 |
| 11. 정리 | 라이브러리(Papers·Notes·Trash, Collection·Tag·읽기 상태·중복·색인 제외), 논문·노트·AI 대화를 함께 담는 휴지통, 관련 논문·노트 | Smart Collection |
| 12–16. 검색·커맨드 | FTS5 본문(+OCR), 단어 순서 무관·점수 순위, 범위 칩·검색어 조건, 선택적 의미 검색(Ollama·OpenAI), 명령 팔레트 | — |
| 17–21. 주석·연결 | 5색 주석·코멘트, 영역 표시(캡션 함께), 노트 링크·역링크, 주석 포함 PDF 내보내기(표준 주석). 이전 Captures는 주석·노트로 통합(스키마 15) | Figure 자동 인식 |
| 22–27. 노트·AI | Markdown 노트, AI 4종(Claude API, OpenAI API, ChatGPT 계정, Ollama), 모델·추론 강도·Fast, 이미지·PDF/웹 영역 첨부(저장 안 함), Thread(논문별 자동 + 여러 논문을 묶는 나만의 Thread)와 그 안의 Chat, 선호 언어, 논문 비교표, 쪽별 번역·논문 요약, 탭·Collection AI 정리 | 라이브러리 전체에 묻기(v0.6) |
| 28–32. 데이터·기술 | C++20 + Qt Quick/PDF/WebEngine, 공유 폴더를 통한 컴퓨터 간 동기화(Google Drive·Dropbox·Syncthing, 항목별 나중 변경 우선), SQLite(라이브러리 스키마 17, 색인 4, 업그레이드 전 백업), 백업·복원, Markdown·BibTeX 내보내기, 단축키 변경, macOS·Linux·Windows 키 저장소, 로컬 설치 스크립트, 자동 테스트 7묶음 | Linux/Windows 실기기, 배포 패키지 |

## 우선순위

가볍고 빠름을 먼저 지키고, 기획서 순서보다 실제 사용 중 불편한 부분을 먼저 고칩니다. 기능별 사용법은 [README](../README.md)와 각 문서에, 변경 이력은 git 로그에 있습니다.

## 이번 단계 (2026-10-12): 손에 익게

- AI: Chat이 Thread에 모임(논문마다 자동 Thread, 여러 논문을 묶는 나만의 Thread; 스키마 17).
- AI Thread 정리: 모든 Thread(General·논문·나만의)에 `…` 버튼(행에 마우스를 올리거나 선택했을 때, 위쪽 제목 줄 오른쪽)과 우클릭 메뉴: New Chat, Rename…(나만의), Merge Into ▸(다른 Thread로 Chat을 옮겨 합침), Delete Thread and Chats…(Chat은 Library의 Trash로, 되살릴 수 있음), Delete Thread, Keep Chats…(나만의). 지우는 항목은 빨간색이고, Thread를 지울 때와 Chat 여러 개를 한 번에 지울 때(메뉴·Delete 키)는 먼저 확인(Chat 하나는 바로 Trash로). Chat 행에도 `…`. 논문 Thread(와 논문에 대한 Chat)의 `…`/우클릭 맨 위: 그 논문이 다른 탭에 열려 있으면 `Go to Paper`(그 탭으로, 분할 화면의 다른 쪽이어도), 닫혀 있으면 `Open Paper`, 파일이 없어졌으면 `Locate PDF…`(앞에 보고 있는 논문이면 안 보임). 논문 Thread는 Chat이 있는 동안만 있음: 마지막 Chat을 지우거나 옮기거나 합치면, 또는 Thread를 지우면 앞에 열린 논문이어도 사라지고(빈 Thread도 지울 수 있음), 그 논문에 새로 물으면 다시 생김. 질문은 보내는 순간 Chat에 저장(제목만 있는 Chat이 남지 않음). 답을 기다리는 중에 목록으로 돌아가거나 다른 Chat을 열어도 답은 계속 와서 저장되고(목록에 "Answering…", 끝나면 알림), 다시 열면 이어서 보임. 답을 못 받은 질문은 그대로 남고 아래에 이유(또는 Stopped.)를 표시, 이어 묻기에는 답이 있는 대화만 보냄. Chat은 General·논문 Thread로도 옮길 수 있고 옮긴 곳에 남음. Thread 목록에서 질문하면 그 Thread에 새 Chat(논문 Thread는 그 논문, General은 논문 없이, All Chats는 앞에 열린 논문의 Thread, 없으면 General). 좁은 패널의 Threads 목록 아래에도 질문 칸. Chat을 열면 맨 아래(가장 최근 질문)부터 보이고, 답이 와도 보던 자리를 지킴.
- 단축키 한눈에 보기: `?`, `⌘/`, 상태 표시줄 `?`, Help 메뉴, `/shortcuts`(`/list`).
- 단축키 설정(Settings → Shortcuts)을 종류별 섹션으로(Search and places·Tabs·Splits·Panels·Reading·Notes and AI; 원본 x-or-b에서 가져옴). 새로 바꿀 수 있는 키: 이전/다음 쪽(`⌘[`·`⌘]`), Fit Width(`⌘0`), Fit Page(`⌥⌘0`), Highlight Selection(`⌃⌘H`, Windows·Linux `Ctrl+Alt+H`), Comment(`⌃⌘M`), Dark Pages(`⇧⌘D`), Ask AI(`⇧⌘A`: 선택한 글, 없으면 앞의 논문에 새 Chat), 패널 열고 닫기(Library `⇧⌘E`, Document `⇧⌘O`, Annotations `⇧⌘M`, AI `⇧⌘I`). View 메뉴에도 있음.
- 저장된 탭 중 열 수 없는 것만 빼고 나머지를 엶(전부 못 읽으면 탭 없이 시작, 원래 세션은 한 번 보관).
- PDF 끌어 넣기: 창 어디에 놓아도(Finder·다운로드 폴더·브라우저 다운로드 목록) PDF 폴더로 옮기고 Library에 추가, 6개까지는 탭으로 엶. 폴더는 Collection으로 가져오고, 웹 주소는 웹 탭. Settings → Data에서 옮기기/복사 선택.
- PDF 폴더 바꾸기: Settings → Data → PDF folder → `Change…`. 이미 있던 PDF도 새 폴더로 옮기고 주석·노트 연결은 그대로.
- 추가할 때 중복 확인: 끌어 넣거나 + (Add PDFs…·Add Folder…)로 추가할 때, 웹에서 받을 때 이미 있는 논문(같은 파일, DOI·arXiv 번호·제목이 같은 논문)이면 묻고, `Open It`은 있는 것을 열고 그 파일 이름을 알려 줌. 폴더째 끌어 넣기(하위 폴더 포함)와 메뉴로 추가한 PDF도 PDF 폴더로 옮김(Settings → Data → Adding PDFs에서 복사로 바꿈).
- PDF 파일 이름: PDF 폴더의 파일은 논문 정보가 생기거나 바뀌면 `저자 연도 - 제목.pdf`로 바뀜(같은 이름이면 번호). 한동안 탭에 열려 있던 논문은 다음 실행 때. Settings → Data에서 끔. 원본(x-or-b)의 수동 이름 바꾸기도 가져옴: 논문 메뉴 `Rename File After Paper`, Library 선택 `Rename Files After Papers`, Settings → Data `Rename Now`(열려 있는 논문도 바로; 자동 이름이 꺼져 있으면 제목만). Owelk PDF 폴더의 파일만 바꾸고, 노트·주석은 그대로.
- Windows 설치: `tools/install-local.ps1`(x-or-b의 스크립트에 winget이 자기 자신을 부르던 문제와 32비트 PowerShell 문제 수정).
- 웹 검색: Home 웹 검색 칸 오른쪽에서 Scholar·arXiv·Google·DuckDuckGo를 바로 고름. 어디서든 `arxiv: 단어`, `scholar: 단어`로 한 번만 다른 곳에서 검색.
- Tor로 웹 보기: Settings → Web → Browse through Tor(기본 꺼짐, 각자 켬). 켜면 Owelk가 Tor를 직접 띄워 웹 탭과 Home 웹 검색만 Tor로 내보냄(출구 나라 선택, New Identity, 웹 탭 도구 막대의 Tor 칩). 논문 정보·인용·AI·의미 검색은 그대로 직접 연결. Tor가 준비 전이거나 없으면 직접 연결로 새지 않고 기다리며, 켜고 끄는 순간에 요청한 페이지도 새 경로가 잡힐 때까지 기다림(Chromium이 바뀐 프록시를 다음 요청 때에야 읽기 때문). 설치 스크립트가 Tor를 한 번 물어봄(macOS `brew install tor`, Windows는 torproject.org의 Tor Expert Bundle을 SHA-256 확인 후 받음, `-Tor`).
- 가볍게: Release 빌드는 기호를 빼고(macOS `-dead_strip -x`, Linux `--gc-sections --strip-all`, 숨김 visibility) -O2, MicroTeX는 크기 최적화, 글꼴 리소스 압축. Windows 설치는 번역·VC 설치 파일·소프트웨어 OpenGL·D3D 컴파일러·쓰지 않는 플러그인·WebEngine 개발자 도구를 빼고 복사. 실행 중에는 설정값·키체인·최근 논문을 메모리에 두고, 목록 행마다 읽던 읽기 위치를 열 때 읽으며, 본문 색인 진행은 문서 목록과 따로 알리고, 노트 저장은 링크가 그대로면 링크를 다시 쓰지 않음. 쓰지 않던 코드(폴더 가져오기 옛 경로, 웹 문서 등록, 신호·속성 몇 개, include) 정리.
- 제목 표시줄: macOS와 Windows 11의 시스템 제목 표시줄(창 버튼 있는 줄)이 테마의 창 색을 따르고, 버튼·제목은 밝게/어둡게 맞춤(Windows 10은 밝게/어둡게만). Settings → Appearance → Theme의 "Title bar in theme colors"로 끔. 같은 곳의 Customize…로 지금 테마를 복사한 Custom 테마를 만들고 바로 아래에서 창·제목 표시줄, 사이드바, 문서, 메뉴, 글자, 선, PDF 주변 색을 고름.

## 이번 단계 (2026-10-10): 구조 단순화

- Workspaces 제거: 논문이 있던 워크스페이스는 같은 이름의 Collection이 됩니다(스키마 14, 업그레이드 전 백업).
- Captures를 주석으로 통합: 문장 캡처는 하이라이트, 영역 캡처는 새 영역 주석(캡션·메모 유지), 웹 캡처는 그림이 든 노트가 됩니다(스키마 15, 같은 ID·링크 유지). 새 `Mark Region` 도구, AI의 PDF·웹 영역 첨부는 저장하지 않는 그림.
- Document 패널 네 칸: Contents(Outline·Pages), Annotations(이 논문에 대한 노트 + 모든 주석; 리더 옆 메모 열을 대신함), Symbols, Related(Library·Cites·Cited by). 새 노트는 논문 옆 분할에 링크와 함께 열림.
- AI 답변 Save as Note: 질문 인용, 이 논문의 노트에 덧붙이기. 노트의 AI 링크는 휴지통이면 Restore 안내, 영구 삭제면 회색 `Deleted conversation`.
- Library: Papers · Notes · Trash, 논문·노트·AI 대화를 함께 담는 휴지통(지울 항목을 링크한 노트가 있으면 먼저 알림, 기간이 지나면 노트도 자동 삭제). Library 패널은 Open Library·펼쳐지는 Favorites·Collections·Tags·Notes(+).
- Home: 검색창 하나(라이브러리 결과와 웹 행: 주소·`arxiv:` 같은 엔진 접두어면 웹이 맨 위, 단어면 맨 아래, Ctrl/⌘+Return은 웹, 엔진 칩은 칸 오른쪽 끝, Cmd+K 팔레트도 같은 웹 행), 이어 읽기 카드, Collections | Recent Papers, Notes | AI Conversations(마지막으로 연 순서, 고정 자리 안에서 상자가 항목 수만큼). 본문 색인 상태는 색인 중·실패일 때만 보이고 Settings → Search로 옮김.

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

- 탭: 세로 탭(너비 조절, 그룹 접기·이름), 탭 영역 빈 곳 우클릭(새 탭·정렬·중복 닫기·AI 정리·가로/세로 전환), Edge식 그룹.
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
