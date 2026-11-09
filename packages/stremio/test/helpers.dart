import 'dart:convert';
import 'dart:io';

import 'package:stremio/stremio.dart';

String fixtureText(String name) =>
    File('test/fixtures/$name').readAsStringSync();

Object? fixture(String name) => jsonDecode(fixtureText(name));

Addon fixtureAddon(String manifestFixture, String url) => Addon(
  transportUrl: parseAddonUrl(url),
  manifest: AddonManifest.fromJson(fixture(manifestFixture)),
);

/// A minimal stream-only torrent addon manifest.
Addon streamAddon(String url, {String id = 'test.streams'}) => Addon(
  transportUrl: parseAddonUrl(url),
  manifest: AddonManifest.fromJson({
    'id': id,
    'version': '1.0.0',
    'name': id,
    'resources': ['stream'],
    'types': ['movie', 'series'],
    'idPrefixes': ['tt', 'kitsu'],
    'catalogs': <Object?>[],
    'behaviorHints': {'p2p': true},
  }),
);
