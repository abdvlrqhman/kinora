import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../core/log.dart';

/// Kinora's releases: the public GitHub API, no account or key.
const _releases =
    'https://api.github.com/repos/abdvlrqhman/kinora/releases?per_page=30';

/// A newer Kinora on GitHub.
final class KinoraRelease {
  const KinoraRelease({
    required this.version,
    required this.page,
    required this.assets,
    this.notes = '',
  });

  /// "0.1.8".
  final String version;
  final Uri page;

  /// File name → download link.
  final Map<String, Uri> assets;

  /// What changed (the release's notes: commit titles and their details).
  final String notes;

  /// The APK for this phone's processor (64-bit unless it's an old one).
  Uri? apkFor({required bool arm64}) =>
      assets[arm64
          ? 'Kinora-arm64-v8a-release.apk'
          : 'Kinora-armeabi-v7a-release.apk'];

  Uri? get ipa => assets['Kinora.ipa'];

  Uri? get windowsSetup => assets['Kinora-Setup-x64.exe'];

  Uri? get windowsZip => assets['Kinora-windows-x64.zip'];

  /// Parses GitHub's latest-release response.
  static KinoraRelease? fromJson(Map<String, Object?> j) {
    final tag = j['tag_name'];
    final page = Uri.tryParse(j['html_url'] as String? ?? '');
    if (tag is! String ||
        page == null ||
        j['draft'] == true ||
        j['prerelease'] == true) {
      return null;
    }
    return KinoraRelease(
      version: tag.startsWith('v') ? tag.substring(1) : tag,
      page: page,
      notes: j['body'] as String? ?? '',
      assets: {
        for (final a
            in (j['assets'] as List<Object?>? ?? const [])
                .whereType<Map<String, Object?>>())
          if (a['name'] case final String name)
            if (Uri.tryParse(a['browser_download_url'] as String? ?? '')
                case final url?)
              name: url,
      },
    );
  }
}

/// Whether [candidate] ("0.1.8") is newer than [current] ("0.1.7").
bool isNewer(String candidate, String current) {
  List<int> parts(String v) => [
    for (final p in v.split('+').first.split('.')) int.tryParse(p) ?? 0,
  ];
  final a = parts(candidate), b = parts(current);
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// The newest release when it's newer than [current], else null (also
/// when GitHub can't be reached: updates are never in the way). Its notes
/// cover every release since [current], so skipping versions loses no news.
Future<KinoraRelease?> newerRelease(http.Client client, String current) async {
  try {
    final res = await client
        .get(
          Uri.parse(_releases),
          headers: {'accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final newer = [
      for (final j in (jsonDecode(
        res.body,
      ) as List<Object?>).whereType<Map<String, Object?>>())
        if (KinoraRelease.fromJson(j) case final r?
            when isNewer(r.version, current))
          r,
    ]..sort((a, b) => isNewer(a.version, b.version) ? 1 : -1);
    if (newer.isEmpty) return null;
    final latest = newer.last;
    return KinoraRelease(
      version: latest.version,
      page: latest.page,
      assets: latest.assets,
      notes: mergedNotes(newer),
    );
  } on Object catch (e) {
    Log.d('updates', 'check: $e');
    return null;
  }
}

/// The notes of [releases] (oldest first) as one changelog; a change two
/// releases both list (their "### " titles match) shows once.
String mergedNotes(List<KinoraRelease> releases) {
  final seen = <String>{};
  final out = StringBuffer();
  for (final r in releases) {
    for (final part in r.notes.split(RegExp(r'^(?=### )', multiLine: true))) {
      final text = part.trim();
      if (text.isEmpty || !seen.add(text.split('\n').first.trim())) continue;
      out.write('$text\n\n');
    }
  }
  return out.toString().trim();
}

/// Android: downloads the APK (reporting 0..1) and opens it, which shows
/// the system installer. The first time, Android asks to allow installs
/// from Kinora. Returns false when the file couldn't be fetched or opened.
Future<bool> installAndroid(
  http.Client client,
  KinoraRelease release,
  Directory cache, {
  required void Function(double) onProgress,
}) async {
  // Dart's version string names the processor ("on android_arm64").
  final arm64 =
      Platform.version.contains('arm64') || Platform.version.contains('x64');
  final url = release.apkFor(arm64: arm64);
  if (url == null) return false;
  final dir = await Directory('${cache.path}/updates').create(recursive: true);
  final file = File('${dir.path}/Kinora-${release.version}.apk');
  try {
    final res = await client.send(http.Request('GET', url));
    if (res.statusCode != 200) return false;
    final total = res.contentLength ?? 0;
    var got = 0;
    final sink = file.openWrite();
    try {
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress(got / total);
      }
    } finally {
      await sink.close();
    }
    return await FileDownloader().openFile(
      filePath: file.path,
      mimeType: 'application/vnd.android.package-archive',
    );
  } on Object catch (e) {
    Log.w('updates', 'download: $e');
    return false;
  }
}

/// Windows: the browser downloads the new version's installer (older
/// releases: the zip; none: the release page).
Future<void> installWindows(KinoraRelease release) => launchUrl(
  release.windowsSetup ?? release.windowsZip ?? release.page,
  mode: LaunchMode.externalApplication,
);

/// iPhone: hands the IPA to SideStore (it re-signs and installs), or opens
/// the release page when SideStore isn't there.
Future<void> installIos(KinoraRelease release) async {
  final ipa = release.ipa;
  if (ipa != null) {
    final store = Uri.parse(
      'sidestore://install?url=${Uri.encodeComponent(ipa.toString())}',
    );
    try {
      if (await launchUrl(store, mode: LaunchMode.externalApplication)) return;
    } on Object {
      // Not installed: the page instead.
    }
  }
  await launchUrl(release.page, mode: LaunchMode.externalApplication);
}
