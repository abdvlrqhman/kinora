# Windows x64: static libtorrent/Boost/OpenSSL inside kinora_engine.dll, with
# the shared C runtime Flutter's runner uses.
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_BUILD_TYPE release)
