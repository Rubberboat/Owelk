cmake_minimum_required(VERSION 3.24)
project(Owelk VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
find_package(Qt6 6.9 REQUIRED COMPONENTS Quick QuickControls2 Pdf PdfQuick Sql Concurrent PrintSupport Widgets Network WebEngineQuick)
qt_standard_project_setup(REQUIRES 6.9)
# A smaller build. -O2 rather than CMake's -O3 for Release. Everything Owelk compiles ends up inside the one
# program, so none of its symbols need to be visible outside it (the Release link then drops them).
if(NOT MSVC)
    string(REPLACE "-O3" "-O2" CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE}")
endif()
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
set(CMAKE_VISIBILITY_INLINES_HIDDEN ON)

qt_add_library(owelk_core STATIC src/SearchText.cpp src/SearchText.h src/ResearchStore.cpp src/ResearchStoreHighlights.cpp src/ResearchStoreRelink.cpp src/ResearchStoreSearch.cpp src/ResearchStoreDocuments.cpp src/ResearchStoreLibrary.cpp src/ResearchStoreNotes.cpp src/ResearchStoreAi.cpp src/ResearchStoreBackup.cpp src/ResearchStoreExport.cpp src/ResearchStoreAnchors.cpp src/ResearchStoreHistory.cpp src/ResearchStoreCitations.cpp src/LibrarySync.cpp src/LibrarySync.h src/ForYou.cpp src/ForYouOpenAlex.cpp src/ForYou.h src/ResearchStorePapers.cpp src/ResearchStoreTrash.cpp src/MathRenderer.cpp src/MathRenderer.h src/PaperMetadata.cpp src/PaperMetadata.h src/MetadataLookup.cpp src/MetadataLookup.h src/ai/AiService.cpp src/ai/AiService.h src/ai/AiProviders.cpp src/ai/AiProviders.h src/ai/AiContext.cpp src/ai/AiContext.h src/ai/Keychain.cpp src/ai/Keychain.h src/ResearchStore.h src/SelectionGeometry.cpp src/SelectionGeometry.h src/PaperIndex.cpp src/PaperIndex.h src/ReferenceFinder.cpp src/ReferenceFinder.h src/AppInstance.cpp src/AppInstance.h src/SemanticIndex.cpp src/SemanticIndex.h src/PdfPrinting.cpp src/PdfPrinting.h src/PdfAccess.cpp src/PdfAccess.h src/AnnotatedPdf.cpp src/AnnotatedPdf.h src/FileFingerprint.cpp src/FileFingerprint.h src/SchemaMigration.h src/WorkerConnection.h src/ui/Theme.cpp src/ui/Theme.h src/ui/AppIcon.cpp src/ui/AppIcon.h src/ui/WindowChrome.cpp src/ui/WindowChrome.h)
target_link_libraries(owelk_core PUBLIC Qt6::Core Qt6::Gui Qt6::Pdf Qt6::Sql Qt6::Concurrent Qt6::PrintSupport Qt6::Widgets Qt6::Network)
target_include_directories(owelk_core PUBLIC src src/ai src/ui)
# Annotated PDF export writes real PDF annotations with qpdf (brew qpdf, apt libqpdf-dev, vcpkg qpdf).
find_package(qpdf CONFIG QUIET)
if(TARGET qpdf::libqpdf)
    target_link_libraries(owelk_core PUBLIC qpdf::libqpdf)
    # POINTERHOLDER_TRANSITION=4: use std::shared_ptr; silences qpdf 11's transition warning.
    target_compile_definitions(owelk_core PUBLIC OWELK_HAVE_QPDF POINTERHOLDER_TRANSITION=4)
else()
    message(STATUS "qpdf not found: annotated PDF export is disabled")
endif()
target_sources(owelk_core PRIVATE src/AnnotationImage.cpp src/AnnotationImage.h)
# LaTeX math as images (MicroTeX with its Qt painter back end and TeX fonts; see third_party/README.md).
file(GLOB_RECURSE owelk_microtex_sources CONFIGURE_DEPENDS third_party/microtex/src/*.cpp)
add_library(owelk_microtex STATIC ${owelk_microtex_sources} third_party/tinyxml2/tinyxml2.cpp)
target_include_directories(owelk_microtex PUBLIC third_party/microtex/src PRIVATE third_party/tinyxml2)
target_compile_definitions(owelk_microtex PUBLIC BUILD_QT)
target_link_libraries(owelk_microtex PRIVATE Qt6::Gui)
set_target_properties(owelk_microtex PROPERTIES AUTOMOC OFF AUTOUIC OFF AUTORCC OFF)
# Optimized for size: its tables are read once and formula images are cached, so speed hardly matters.
if(MSVC)
    target_compile_options(owelk_microtex PRIVATE /utf-8 /W0 $<$<CONFIG:Release>:/O1>)
else()
    target_compile_options(owelk_microtex PRIVATE -w $<$<CONFIG:Release>:-Os>)
endif()
target_link_libraries(owelk_core PRIVATE owelk_microtex)
file(GLOB_RECURSE owelk_math_fonts RELATIVE ${CMAKE_CURRENT_SOURCE_DIR}/third_party/microtex CONFIGURE_DEPENDS third_party/microtex/res/fonts/*.ttf)
list(TRANSFORM owelk_math_fonts PREPEND third_party/microtex/)
# Fonts shrink by about a third: rcc compresses them only below its default 70% threshold.
qt_add_resources(owelk_core "math_fonts" PREFIX "/" BASE third_party/microtex OPTIONS --threshold 30 FILES ${owelk_math_fonts})
# The icon font (a Lucide subset, see tools/icons.py), loaded once by Theme.
qt_add_resources(owelk_core "icons" PREFIX "/owelk" BASE resources OPTIONS --threshold 30 FILES resources/icons/lucide.ttf resources/app/owelk.png resources/app/owelk-white.png resources/app/owelk-navy.png)
# Optional: dark (inverted) PDF pages need a compiled shader (Qt ShaderTools at build time only).
find_package(Qt6 QUIET COMPONENTS ShaderTools)
if(TARGET Qt6::ShaderTools)
    qt_add_shaders(owelk_core "shaders" PREFIX "/owelk" FILES shaders/invert.frag)
    target_compile_definitions(owelk_core PUBLIC OWELK_HAVE_SHADERS)
else()
    message(STATUS "Qt ShaderTools not found: the invert-pages option is hidden")
endif()
if(APPLE)
    enable_language(OBJCXX)
    target_sources(owelk_core PRIVATE src/ui/AppIconMac.mm src/ui/WindowChromeMac.mm)
    target_link_libraries(owelk_core PUBLIC "-framework ImageIO" "-framework CoreGraphics" "-framework CoreFoundation" "-framework Security" "-framework AppKit")
elseif(WIN32)
    target_link_libraries(owelk_core PUBLIC Advapi32 Dwmapi)
else()
    # Keys go to the desktop keyring when libsecret is available; otherwise to an owner-only file.
    find_package(PkgConfig QUIET)
    if(PKG_CONFIG_FOUND)
        pkg_check_modules(LIBSECRET IMPORTED_TARGET libsecret-1)
    endif()
    if(LIBSECRET_FOUND)
        target_link_libraries(owelk_core PUBLIC PkgConfig::LIBSECRET)
        target_compile_definitions(owelk_core PUBLIC OWELK_HAVE_LIBSECRET)
    endif()
endif()

add_subdirectory(style)

# The app icon (tools/app_icon.cpp makes these from resources/app/owelk-mark.png).
set(owelk_icon_sources)
if(APPLE)
    set(owelk_icon_sources resources/app/owelk.icns)
    set_source_files_properties(resources/app/owelk.icns PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
elseif(WIN32)
    set(owelk_icon_sources resources/app/owelk.rc)
endif()
qt_add_executable(owelk MACOSX_BUNDLE src/main.cpp src/ui/WebAccounts.cpp ${owelk_icon_sources})
qt_add_qml_module(owelk
    URI Owelk VERSION 1.0
    QML_FILES qml/SearchFilters.qml qml/AnnotationColors.qml qml/AnnotationEditor.qml
    QML_FILES qml/ReadingFocus.qml qml/ReadingFocusBar.qml qml/Main.qml qml/ReaderPane.qml qml/PdfCanvas.qml qml/ExpandedPdfSearch.qml qml/CommandPalette.qml qml/FilePanel.qml qml/DockSidebar.qml qml/HomeView.qml qml/StatusIcon.qml qml/DocumentWorkspace.qml qml/DocumentGroup.qml qml/WorkspaceTree.js qml/CollectionTree.js qml/WebSearch.js qml/RecentPaperDelegate.qml qml/PaperMenu.qml qml/AnnotationList.qml qml/TabsPanel.qml qml/TabStripMenu.qml qml/ConfirmDialog.qml qml/PaletteMatch.js qml/StrokePath.js qml/SearchPalette.qml qml/PdfNavigationPanel.qml qml/ResearchSearch.qml qml/SearchResultDelegate.qml qml/IndexStatus.qml qml/RelinkDialog.qml qml/PaperDetailsDialog.qml qml/WebPane.qml qml/SettingsDialog.qml qml/SettingsGroup.qml qml/SettingsRow.qml qml/SettingsAppearance.qml qml/SettingsWeb.qml qml/SettingsSearch.qml qml/SettingsAi.qml qml/SettingsShortcuts.qml qml/SettingsData.qml qml/SettingsForYou.qml qml/PersonRow.qml qml/OpenAlexFollowing.qml qml/LibraryView.qml qml/NotePane.qml qml/LinkToNoteDialog.qml qml/AiController.qml qml/AiPanel.qml qml/GlossPopup.qml qml/AiNames.js qml/Platform.js qml/Shortcuts.js qml/OrganizeTabsDialog.qml qml/OrganizePapersDialog.qml qml/GroupEditor.qml qml/ComparePapersDialog.qml qml/AiNotice.qml qml/ShortcutSheet.qml qml/DuplicateDialog.qml
)
target_link_libraries(owelk PRIVATE owelk_core owelk_styleplugin Qt6::Quick Qt6::QuickControls2 Qt6::PdfQuick Qt6::WebEngineQuick)
# Release: leave out unused code and the symbol table (about 1.3 MB; crash reports show addresses).
if(APPLE)
    target_link_options(owelk PRIVATE $<$<CONFIG:Release>:LINKER:-dead_strip,-x>)
elseif(UNIX)
    target_link_options(owelk PRIVATE $<$<CONFIG:Release>:LINKER:--gc-sections,--strip-all>)
endif()
set_target_properties(owelk PROPERTIES
    MACOSX_BUNDLE_BUNDLE_NAME Owelk
    MACOSX_BUNDLE_GUI_IDENTIFIER org.owelk.reader
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION}
    MACOSX_BUNDLE_ICON_FILE owelk.icns
    MACOSX_BUNDLE_INFO_PLIST ${CMAKE_CURRENT_SOURCE_DIR}/resources/app/Info.plist.in
    WIN32_EXECUTABLE TRUE
)

# Install with the Qt runtime it needs (QML modules, Pdf, WebEngine): `cmake --install build`.
include(GNUInstallDirs)
install(TARGETS owelk BUNDLE DESTINATION . RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
# Windows copies Qt next to the program; leave out what Owelk never loads (about 100 MB): translations
# (Owelk is in English; WebEngine keeps its en-US pack), the Visual C++ installer (the build machine has the
# runtime), software OpenGL and Direct3D compilers (Qt Quick uses Direct3D 11), QML debugging, position,
# network-information, other SQL drivers, unused image formats and WebEngine's developer tools.
set(owelk_deploy_options)
if(WIN32)
    set(owelk_deploy_options NO_TRANSLATIONS NO_COMPILER_RUNTIME DEPLOY_TOOL_OPTIONS
        --no-opengl-sw --no-system-d3d-compiler --no-system-dxc-compiler
        --skip-plugin-types qmltooling,generic,position,networkinformation
        --exclude-plugins qsqlodbc,qsqlpsql,qsqlmimer,qsqlibase,qtiff,qtga,qwbmp,qicns,qpdf)
endif()
qt_generate_deploy_qml_app_script(TARGET owelk OUTPUT_SCRIPT owelk_deploy_script NO_UNSUPPORTED_PLATFORM_ERROR
    ${owelk_deploy_options})
install(SCRIPT ${owelk_deploy_script})
if(WIN32)
    install(CODE [[
        file(GLOB_RECURSE owelk_devtools "${CMAKE_INSTALL_PREFIX}/*qtwebengine_devtools_resources*.pak")
        if(owelk_devtools)
            file(REMOVE ${owelk_devtools})
        endif()
    ]])
endif()
if(UNIX AND NOT APPLE)
    install(FILES resources/app/owelk.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
    install(FILES resources/app/owelk.png DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/512x512/apps)
endif()

include(CTest)
if(BUILD_TESTING)
    find_package(Qt6 REQUIRED COMPONENTS Test QuickTest)
    qt_add_executable(owelk_tests tests/ResearchStoreTest.cpp)
    target_link_libraries(owelk_tests PRIVATE owelk_core Qt6::Test)
    target_compile_definitions(owelk_tests PRIVATE TEST_DATA_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests/data"
        TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests")
    add_test(NAME store_and_pdf COMMAND owelk_tests)
    set_tests_properties(store_and_pdf PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
    qt_add_executable(owelk_follow_tests tests/ForYouTest.cpp tests/ForYouTest.h)
    target_link_libraries(owelk_follow_tests PRIVATE owelk_core Qt6::Test)
    add_test(NAME openalex_following COMMAND owelk_follow_tests)
    set_tests_properties(openalex_following PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
    qt_add_executable(owelk_search_tests tests/SearchTextTest.cpp)
    target_link_libraries(owelk_search_tests PRIVATE owelk_core Qt6::Test)
    add_test(NAME korean_search COMMAND owelk_search_tests)
    set_tests_properties(korean_search PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
    qt_add_executable(owelk_index_tests tests/PaperIndexTest.cpp)
    target_link_libraries(owelk_index_tests PRIVATE owelk_core Qt6::Test)
    add_test(NAME paper_index COMMAND owelk_index_tests)
    set_tests_properties(paper_index PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
    qt_add_executable(owelk_relink_tests tests/RelinkTest.cpp)
    target_link_libraries(owelk_relink_tests PRIVATE owelk_core Qt6::Test)
    add_test(NAME source_relink COMMAND owelk_relink_tests)
    set_tests_properties(source_relink PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
    qt_add_executable(owelk_annotation_tests tests/AnnotationTest.cpp)
    target_link_libraries(owelk_annotation_tests PRIVATE owelk_core Qt6::Test)
    add_test(NAME annotations COMMAND owelk_annotation_tests)
    set_tests_properties(annotations PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
    qt_add_executable(owelk_ai_tests tests/AiTest.cpp)
    target_link_libraries(owelk_ai_tests PRIVATE owelk_core Qt6::Test)
    target_compile_definitions(owelk_ai_tests PRIVATE QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests")
    add_test(NAME ai_providers COMMAND owelk_ai_tests)
    set_tests_properties(ai_providers PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
    qt_add_executable(owelk_semantic_tests tests/SemanticTest.cpp)
    target_link_libraries(owelk_semantic_tests PRIVATE owelk_core Qt6::Test)
    add_test(NAME semantic_search COMMAND owelk_semantic_tests)
    set_tests_properties(semantic_search PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
    qt_add_executable(owelk_fixtures tests/fixtures.cpp)
    target_link_libraries(owelk_fixtures PRIVATE Qt6::Gui)
    qt_add_executable(owelk_ui_tests tests/ReaderUiTest.cpp src/ui/WebAccounts.cpp)
    target_link_libraries(owelk_ui_tests PRIVATE owelk_core owelk_styleplugin Qt6::QuickTest Qt6::QuickControls2 Qt6::PdfQuick Qt6::WebEngineQuick Qt6::Network)
    target_compile_definitions(owelk_ui_tests PRIVATE QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests")
    add_test(NAME reading_focus_ui COMMAND owelk_ui_tests -input "${CMAKE_CURRENT_SOURCE_DIR}/tests/tst_focus.qml")
    add_test(NAME pdf_printing_ui COMMAND owelk_ui_tests -input "${CMAKE_CURRENT_SOURCE_DIR}/tests/tst_printing.qml")
    add_test(NAME openalex_following_ui COMMAND owelk_ui_tests -input "${CMAKE_CURRENT_SOURCE_DIR}/tests/tst_openalex.qml")
    set_tests_properties(reading_focus_ui pdf_printing_ui openalex_following_ui PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software")
    add_test(NAME reader_interactions COMMAND owelk_ui_tests)
    set_tests_properties(reader_interactions PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software")
endif()
