# Windows: builds kinora_engine.dll from the shared sources; Flutter copies it
# next to Kinora.exe. Needs prebuilt/x64-windows-static-md (see tool/fetch_prebuilt.sh).
cmake_minimum_required(VERSION 3.14)
project(kinora_engine LANGUAGES C CXX)

add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")

set(kinora_engine_bundled_libraries
  $<TARGET_FILE:kinora_engine>
  PARENT_SCOPE
)
