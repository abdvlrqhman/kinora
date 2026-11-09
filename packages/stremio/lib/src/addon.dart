import 'errors.dart';
import 'manifest.dart';

const _manifestPath = '/manifest.json';

/// Turns what a user pastes into the addon's `manifest.json` URL.
///
/// Accepts `stremio://host/path/manifest.json`, `https://…/manifest.json`,
/// a base URL (`https://host/config`) or a bare `host/path`. Configuration
/// segments in the path are kept byte for byte (existing percent-escapes are
/// not decoded; characters illegal in a URL path are percent-encoded).
/// Throws [InvalidAddonUrlException].
Uri parseAddonUrl(String input) {
  var text = input.trim();
  if (text.isEmpty) throw InvalidAddonUrlException(input, 'empty URL');
  final lower = text.toLowerCase();
  if (lower.startsWith('stremio://')) {
    text = 'https://${text.substring('stremio://'.length)}';
  } else if (!lower.contains('://')) {
    text = 'https://$text';
  }
  final uri = Uri.tryParse(text);
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host.isEmpty) {
    throw InvalidAddonUrlException(input, 'not an http(s) addon URL');
  }
  var path = uri.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (!path.endsWith(_manifestPath)) path = '$path$_manifestPath';
  // Rebuild from the encoded parts so escapes such as %2F survive untouched.
  return Uri.parse(
    '${uri.scheme}://${uri.authority}$path${uri.hasQuery ? '?${uri.query}' : ''}',
  );
}

/// An installed addon: where it lives plus what it declares.
final class Addon {
  /// Creates an addon; [transportUrl] must be a normalized manifest URL
  /// (see [parseAddonUrl]).
  const Addon({required this.transportUrl, required this.manifest});

  /// URL of `manifest.json`, including any configuration path segments.
  /// Two installs of the same addon with different configs differ here.
  final Uri transportUrl;

  /// The parsed manifest.
  final AddonManifest manifest;

  /// Whether the addon should be asked for [resource] of [type]/[id].
  ///
  /// For `catalog`, [id] is the catalog id and must be declared in
  /// `manifest.catalogs`. For other resources the resource's types and
  /// id prefixes (falling back to the manifest's) must match.
  bool supports(String resource, String type, String id) {
    if (resource == 'catalog') return manifest.catalog(type, id) != null;
    return manifest.resources.any(
      (r) => r.name == resource && r.matches(type, id),
    );
  }

  /// URL of `/{resource}/{type}/{id}[/{extra}].json` on this addon.
  ///
  /// [type], [id] and each extra key/value are percent-encoded like
  /// `encodeURIComponent`; extras keep their map order.
  Uri resourceUrl(
    String resource,
    String type,
    String id, {
    Map<String, String> extra = const {},
  }) {
    final t = transportUrl.toString();
    final q = t.indexOf('?');
    final base = (q < 0 ? t : t.substring(0, q));
    final root = base.endsWith(_manifestPath)
        ? base.substring(0, base.length - _manifestPath.length)
        : base.replaceFirst(RegExp(r'/+$'), '');
    final extraPart = extra.isEmpty
        ? ''
        : '/${extra.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&')}';
    return Uri.parse(
      '$root/${Uri.encodeComponent(resource)}/${Uri.encodeComponent(type)}/'
      '${Uri.encodeComponent(id)}$extraPart.json'
      '${q < 0 ? '' : t.substring(q)}',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Addon &&
      other.transportUrl == transportUrl &&
      other.manifest == manifest;

  @override
  int get hashCode => Object.hash(transportUrl, manifest);

  @override
  String toString() => 'Addon(${manifest.name}, $transportUrl)';
}
