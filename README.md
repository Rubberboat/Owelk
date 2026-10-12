# Owelk

논문 읽는 앱. 빠르고, 가볍고, 내 컴퓨터에만 있습니다.

PDF 리더 · 주석 · 노트 · 라이브러리 · 검색 · AI · 웹 탭 · 컴퓨터 간 동기화.
나머지는 써 보면 압니다.

## 설치

```sh
tools/install-local.sh          # 빌드하고 설치. 업데이트는 git pull 후 다시
tools/install-local.sh --clean  # 처음부터 다시 빌드
```

- **macOS**: Homebrew의 Qt를 씁니다. `~/Applications/Owelk.app`에 설치됩니다.
- **Linux** (Ubuntu 24.04 등): 공식 Qt 6.11을 `~/Qt`에 받아 씁니다(처음 한 번 약 1.5 GB). 앱 메뉴에 들어갑니다.
- 라이브러리·노트·설정은 앱 데이터 폴더에 있어서 다시 설치해도 그대로입니다.

있으면 더 좋은 것(없어도 돌아감):
[Tesseract](https://github.com/tesseract-ocr/tesseract)(스캔 PDF 검색) ·
[Ollama](https://ollama.com)(의미 검색) ·
AI 키 또는 ChatGPT 계정(AI 기능).

## 개발

```sh
cmake -S . -B build -DCMAKE_PREFIX_PATH="$(brew --prefix qt)"
cmake --build build --parallel 6
ctest --test-dir build --output-on-failure
open -n build/owelk.app --args --data-dir "$PWD/build/manual-data"   # 테스트용 데이터로 실행
```

C++20, Qt 6.11 (Quick · PDF · WebEngine), SQLite. macOS · Linux · Windows.

## 원칙

- 원본 PDF는 건드리지 않습니다. 주석은 Owelk에 따로 저장되고, 원하면 주석 포함 사본으로 내보냅니다.
- 밖으로 나가는 건 웹 탭, 직접 누른 조회, 동의한 AI 요청뿐입니다.
- 무거운 일(색인·OCR·백업)은 읽는 동안 쉽니다.

## 더 보기

[진행 현황](docs/STATUS.md) · [다음 할 일](docs/NEXT.md) · [동기화](docs/SYNC.md) · [주석](docs/HIGHLIGHTS.md) · [검색](docs/SEARCH.md) · [PDF 재연결](docs/RELINK.md) · [디자인](docs/DESIGN.md) · [성능](docs/PERFORMANCE.md)
