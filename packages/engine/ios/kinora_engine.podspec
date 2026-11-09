# libtorrent engine + HTTP range server. The static libraries in prebuilt/ are
# produced by the `engine` CI workflow (vcpkg, arm64-ios).
Pod::Spec.new do |s|
  s.name             = 'kinora_engine'
  s.version          = '0.1.0'
  s.summary          = 'libtorrent session and streaming server for Kinora.'
  s.homepage         = 'https://github.com/abdvlrqhman/kinora'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Abdulrahman Ali' => 'abdvlrqhman@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.0'
  s.vendored_libraries = 'prebuilt/lib/*.a'
  s.frameworks       = 'CoreFoundation', 'SystemConfiguration'
  s.libraries        = 'c++'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 x86_64',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/prebuilt/include"',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'OTHER_CPLUSPLUSFLAGS' => '$(inherited) -fexceptions -frtti',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) BOOST_ASIO_NO_DEPRECATED=1 BOOST_SYSTEM_USE_UTF8=1 TORRENT_ABI_VERSION=100 TORRENT_USE_RTC=0 TORRENT_USE_OPENSSL=1 TORRENT_USE_LIBCRYPTO=1 TORRENT_SSL_PEERS=1 OPENSSL_NO_SSL2=1 OPENSSL_NO_SSL3=1 OPENSSL_NO_TLS1=1 OPENSSL_NO_TLS1_1=1 OPENSSL_NO_DTLS1=1',
  }
  s.swift_version = '5.0'
end
