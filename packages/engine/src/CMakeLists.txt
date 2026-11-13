# Builds libkinora_engine (Android via the Android Gradle Plugin, Windows via
# the plugin's windows/CMakeLists.txt, or the host for native tests:
# cmake -S src -B build -DKN_PREBUILT=<vcpkg x64-linux dir>).
# The Flutter tooling requires CMake 3.10 compatibility.
cmake_minimum_required(VERSION 3.10)
project(kinora_engine_library VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(ANDROID)
  if(ANDROID_ABI STREQUAL "arm64-v8a")
    set(KN_TRIPLET arm64-android)
  elseif(ANDROID_ABI STREQUAL "armeabi-v7a")
    set(KN_TRIPLET arm-neon-android)
  elseif(ANDROID_ABI STREQUAL "x86_64")
    set(KN_TRIPLET x64-android)
  else()
    message(FATAL_ERROR "kinora_engine: unsupported Android ABI ${ANDROID_ABI}")
  endif()
  set(KN_PREBUILT "${CMAKE_CURRENT_SOURCE_DIR}/../prebuilt/${KN_TRIPLET}")
elseif(NOT KN_PREBUILT AND WIN32)
  set(KN_PREBUILT "${CMAKE_CURRENT_SOURCE_DIR}/../prebuilt/x64-windows-static-md")
elseif(NOT KN_PREBUILT)
  set(KN_PREBUILT "${CMAKE_CURRENT_SOURCE_DIR}/../prebuilt/x64-linux")
endif()

if(WIN32)
  set(KN_TORRENT_LIB "${KN_PREBUILT}/lib/torrent-rasterbar.lib")
else()
  set(KN_TORRENT_LIB "${KN_PREBUILT}/lib/libtorrent-rasterbar.a")
endif()
if(NOT EXISTS "${KN_TORRENT_LIB}")
  message(FATAL_ERROR
    "kinora_engine: libtorrent not found in ${KN_PREBUILT}. "
    "CI downloads it from the engine workflow; locally run "
    "packages/engine/tool/fetch_prebuilt.sh.")
endif()

if(MSVC)
  # libtorrent is built against the release C runtime: use it in Debug too
  # (only a C API crosses the DLL boundary, so the app may differ).
  foreach(flags CMAKE_C_FLAGS_DEBUG CMAKE_CXX_FLAGS_DEBUG)
    string(REPLACE "/MDd" "/MD" ${flags} "${${flags}}")
    string(REPLACE "/RTC1" "" ${flags} "${${flags}}")
  endforeach()
endif()

add_library(kinora_engine SHARED kinora_engine.cpp)
set_target_properties(kinora_engine PROPERTIES
  OUTPUT_NAME "kinora_engine"
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON)
target_include_directories(kinora_engine PRIVATE "${KN_PREBUILT}/include")
# Must match the flags libtorrent was built with (see its pkg-config file).
target_compile_definitions(kinora_engine PRIVATE
  DART_SHARED_LIB
  # 64-bit file offsets on 32-bit Android (armeabi-v7a): files > 2 GiB.
  _FILE_OFFSET_BITS=64
  BOOST_ASIO_NO_DEPRECATED BOOST_SYSTEM_USE_UTF8
  TORRENT_ABI_VERSION=100 TORRENT_USE_RTC=0
  TORRENT_USE_OPENSSL TORRENT_USE_LIBCRYPTO TORRENT_SSL_PEERS
  OPENSSL_NO_SSL2 OPENSSL_NO_SSL3 OPENSSL_NO_TLS1 OPENSSL_NO_TLS1_1 OPENSSL_NO_DTLS1)

if(WIN32)
  # libtorrent's public Windows defines (its CMakeLists, v2.1.2; vcpkg bakes
  # the OpenSSL and ABI ones into config.hpp), and the Windows version it
  # targets: Boost.Asio's types depend on it.
  target_compile_definitions(kinora_engine PRIVATE
    _WIN32_WINNT=0x0A00 BOOST_ASIO_ENABLE_CANCELIO WIN32_LEAN_AND_MEAN NOMINMAX
    BOOST_ALL_NO_LIB _SCL_SECURE_NO_DEPRECATE _CRT_SECURE_NO_DEPRECATE
    _SILENCE_CXX17_ALLOCATOR_VOID_DEPRECATION_WARNING
    $<$<CONFIG:Debug>:_ITERATOR_DEBUG_LEVEL=0>)
  target_compile_options(kinora_engine PRIVATE
    /EHsc /GR /O2 /utf-8 /bigobj /permissive- /Zc:__cplusplus)
  file(GLOB KN_LIBS "${KN_PREBUILT}/lib/*.lib")
  target_link_libraries(kinora_engine PRIVATE
    ${KN_LIBS} ws2_32 mswsock iphlpapi crypt32 bcrypt dbghelp advapi32 user32)
  return()
endif()

target_compile_options(kinora_engine PRIVATE -fexceptions -frtti -O2)

file(GLOB KN_BOOST_LIBS "${KN_PREBUILT}/lib/libboost_*.a")
target_link_libraries(kinora_engine PRIVATE
  "${KN_PREBUILT}/lib/libtorrent-rasterbar.a"
  ${KN_BOOST_LIBS}
  "${KN_PREBUILT}/lib/libssl.a"
  "${KN_PREBUILT}/lib/libcrypto.a"
  ${CMAKE_DL_LIBS})

if(ANDROID)
  target_link_libraries(kinora_engine PRIVATE log)
  # 16 KB pages (Android 15+), keep static-lib symbols private, drop dead code.
  target_link_options(kinora_engine PRIVATE
    "-Wl,-z,max-page-size=16384" "-Wl,--exclude-libs,ALL" "-Wl,--gc-sections")
else()
  find_package(Threads REQUIRED)
  target_link_libraries(kinora_engine PRIVATE Threads::Threads)
  target_link_options(kinora_engine PRIVATE "-Wl,--exclude-libs,ALL")
endif()
