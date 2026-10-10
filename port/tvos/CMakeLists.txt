# Apple TV host and SDL around the statically compiled guest image. The
# shared UIKit host (port/ios/host) runs here with the tvOS platform hooks in
# host_platform.m and the CloudKit save mirror in host_cloud_saves.m.
cmake_minimum_required(VERSION 3.24)
project(HaloCE LANGUAGES C CXX OBJC ASM)
set(HALO_BUNDLE_IDENTIFIER "org.haloce.tv" CACHE STRING "App bundle identifier")
set(HALO_ICLOUD_CONTAINER "" CACHE STRING "iCloud container for save mirroring (empty: none)")
set(HALO_GAME_DATA "" CACHE PATH "Folder with the Xbox *.map files built into the app")
set(HALO_CUSTOM_EDITION_DATA "" CACHE PATH "Folder with Custom Edition *.map files built into the app (optional)")
get_filename_component(ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
if(NOT HALO_GAME_DATA)
    message(FATAL_ERROR "HALO_GAME_DATA is required: a folder with the Xbox *.map files (use tools/tvos_build.py --game-data)")
endif()
# SDL 3 turns OpenGL ES off on tvOS; tools/tvos_build.py makes this copy with it on.
if(NOT EXISTS "${ROOT}/build/third_party/SDL3-tvos/CMakeLists.txt")
    message(FATAL_ERROR "build/third_party/SDL3-tvos is missing; build with tools/tvos_build.py")
endif()
set(SDL_SHARED OFF CACHE BOOL "" FORCE)
set(SDL_STATIC ON CACHE BOOL "" FORCE)
set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
set(SDL_TESTS OFF CACHE BOOL "" FORCE)
set(SDL_EXAMPLES OFF CACHE BOOL "" FORCE)
add_subdirectory("${ROOT}/build/third_party/SDL3-tvos" sdl3 EXCLUDE_FROM_ALL)
add_executable(HaloCE MACOSX_BUNDLE
    host_platform.m host_cloud_saves.m Assets.xcassets
    "${ROOT}/port/runtime/xiso.c"
    ../ios/host/host_main.m ../ios/host/host_memory.c ../ios/host/host_loader.c ../ios/host/host_syscall.c ../ios/host/host_gl.c ../ios/host/host_debug.m ../ios/host/host_metalfx.m ../ios/host/host_graphics.m ../ios/host/host_shader_cache.m ../ios/host/guest_call.S
    ../ios/host/host_thread.c ../ios/host/host_sdl.c ../ios/network/room_bridge.c
    "${ROOT}/port/ios/network/host_web_net.c" "${ROOT}/port/ios/network/host_net.c" "${ROOT}/port/ios/network/host_browser.m"
    "${ROOT}/port/linux/src/posix_files.c" ../ios/host/posix_net.c
    "${ROOT}/build/ios/host/bridges.c" "${ROOT}/build/ios/embedded/guest_image.S")
target_include_directories(HaloCE PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}" ../ios/host ../ios/network "${ROOT}/port/web/src" "${ROOT}/port/runtime" "${ROOT}/port/runtime/include"
    "${ROOT}/port/runtime/guest/runtime" "${ROOT}/port/linux/src" "${ROOT}/build/ios/host"
    "${ROOT}/build/ios/gl_include" "${ROOT}/build/ios/embedded")
target_compile_definitions(HaloCE PRIVATE HALO_IOS=1 st_mtim=st_mtimespec st_atim=st_atimespec st_ctim=st_ctimespec)
target_compile_options(HaloCE PRIVATE -Wno-deprecated-declarations)
target_compile_options(HaloCE PRIVATE "$<$<COMPILE_LANGUAGE:OBJC>:-fobjc-arc>")
target_link_libraries(HaloCE PRIVATE SDL3::SDL3-static "-framework QuartzCore" "-framework Foundation" "-framework UIKit" "-framework OpenGLES")
target_link_libraries(HaloCE PRIVATE "-framework Metal" "-framework CoreVideo" "-framework IOSurface" "-framework MetalFX" "-framework GameController" "-framework CloudKit")
set_source_files_properties(Assets.xcassets PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
file(GLOB HALO_LICENSES "${ROOT}/build/ios/licenses/*.txt")
target_sources(HaloCE PRIVATE ${HALO_LICENSES})
set_source_files_properties(${HALO_LICENSES} PROPERTIES MACOSX_PACKAGE_LOCATION Resources/Licenses)
set_target_properties(HaloCE PROPERTIES MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist"
    XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC YES
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${HALO_BUNDLE_IDENTIFIER}"
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY 3
    XCODE_ATTRIBUTE_ASSETCATALOG_COMPILER_APPICON_NAME "App Icon & Top Shelf Image"
    XCODE_ATTRIBUTE_HALO_ICLOUD_CONTAINER "${HALO_ICLOUD_CONTAINER}"
    XCODE_ATTRIBUTE_CODE_SIGN_STYLE Automatic)
if(HALO_DEVELOPMENT_TEAM)
    set_target_properties(HaloCE PROPERTIES XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "${HALO_DEVELOPMENT_TEAM}")
endif()
if(HALO_ICLOUD_CONTAINER)
    set_target_properties(HaloCE PROPERTIES XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${CMAKE_CURRENT_SOURCE_DIR}/Entitlements.plist")
endif()

execute_process(COMMAND git describe --always --dirty WORKING_DIRECTORY "${ROOT}"
    OUTPUT_VARIABLE HALO_BUILD_REVISION OUTPUT_STRIP_TRAILING_WHITESPACE)
target_compile_definitions(HaloCE PRIVATE HALO_BUILD_REVISION="${HALO_BUILD_REVISION}")

# No ANGLE frameworks are embedded yet: tvOS draws with Apple's OpenGL ES
# until an ANGLE tvOS slice is packaged. host_graphics.m picks ANGLE
# automatically once its frameworks are in the bundle.

# Personal build (port/apple/DISTRIBUTION.md): the user's own maps go into the
# bundle. Xcode signs the bundle after this step. Not VERBATIM: the bundle path
# contains ${EFFECTIVE_PLATFORM_NAME}, which Xcode's shell has to expand.
add_custom_command(TARGET HaloCE POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_BUNDLE_CONTENT_DIR:HaloCE>/GameData/maps"
    COMMAND rsync -a --delete --include=*.map --exclude=* "${HALO_GAME_DATA}/" "$<TARGET_BUNDLE_CONTENT_DIR:HaloCE>/GameData/maps/")
if(HALO_CUSTOM_EDITION_DATA)
    add_custom_command(TARGET HaloCE POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_BUNDLE_CONTENT_DIR:HaloCE>/GameData/CustomEdition/maps"
        COMMAND rsync -a --delete --include=*.map --exclude=* "${HALO_CUSTOM_EDITION_DATA}/" "$<TARGET_BUNDLE_CONTENT_DIR:HaloCE>/GameData/CustomEdition/maps/")
endif()

target_sources(HaloCE PRIVATE "${ROOT}/port/apple/DISTRIBUTION.md")
set_source_files_properties("${ROOT}/port/apple/DISTRIBUTION.md" PROPERTIES MACOSX_PACKAGE_LOCATION Resources/Licenses)

target_sources(HaloCE PRIVATE "${ROOT}/port/third_party/monocypher/LICENCE.md")
set_source_files_properties("${ROOT}/port/third_party/monocypher/LICENCE.md" PROPERTIES MACOSX_PACKAGE_LOCATION Resources/Licenses/Monocypher)

target_sources(HaloCE PRIVATE "${ROOT}/port/third_party/expat/COPYING")
set_source_files_properties("${ROOT}/port/third_party/expat/COPYING" PROPERTIES MACOSX_PACKAGE_LOCATION Resources/Licenses/Expat)

# internet play's MQTT brokers; the app copies the list beside config.toml
# at each start (host_main.m)
target_sources(HaloCE PRIVATE "${ROOT}/port/assets/network/brokers.txt")
set_source_files_properties("${ROOT}/port/assets/network/brokers.txt" PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
