import 'json.dart';

/// An addon's `manifest.json`.
final class AddonManifest {
  /// Creates a manifest.
  const AddonManifest({
    required this.id,
    required this.version,
    required this.name,
    this.description,
    this.logo,
    this.background,
    this.types = const [],
    this.resources = const [],
    this.catalogs = const [],
    this.idPrefixes,
    this.adult = false,
    this.p2p = false,
    this.configurable = false,
    this.configurationRequired = false,
    this.raw,
  });

  /// Parses a manifest; throws `AddonResponseException` when `id` or `name`
  /// is missing.
  factory AddonManifest.fromJson(Object? value) {
    final json = jsonObject(value, 'manifest');
    final types = readStrings(json, 'types');
    final idPrefixes = readStringsOrNull(json, 'idPrefixes');
    final hints = json['behaviorHints'] is Map<String, Object?>
        ? json['behaviorHints']! as JsonMap
        : const <String, Object?>{};
    return AddonManifest(
      id: requireString(json, 'id', 'manifest'),
      version: readString(json, 'version') ?? '0.0.0',
      name: requireString(json, 'name', 'manifest'),
      description: readString(json, 'description'),
      logo: readString(json, 'logo'),
      background: readString(json, 'background'),
      types: types,
      resources: List.unmodifiable(
        (json['resources'] is List<Object?>
                ? json['resources']! as List<Object?>
                : const <Object?>[])
            .map((r) => ManifestResource._parse(r, types, idPrefixes))
            .nonNulls,
      ),
      catalogs: List.unmodifiable(
        readObjects(json, 'catalogs').map(ManifestCatalog._parse).nonNulls,
      ),
      idPrefixes: idPrefixes,
      adult: readBool(hints, 'adult'),
      p2p: readBool(hints, 'p2p'),
      configurable: readBool(hints, 'configurable'),
      configurationRequired: readBool(hints, 'configurationRequired'),
      raw: json,
    );
  }

  /// The decoded JSON this manifest was parsed from (for persisting it).
  final Map<String, Object?>? raw;

  /// Dot-separated identifier, e.g. `com.linvo.cinemeta`.
  final String id;

  /// Semantic version string.
  final String version;

  /// Display name.
  final String name;

  /// Display description.
  final String? description;

  /// Logo image URL.
  final String? logo;

  /// Background image URL.
  final String? background;

  /// Content types the addon handles by default (`movie`, `series`, ...).
  final List<String> types;

  /// Resources with their effective types and id prefixes.
  final List<ManifestResource> resources;

  /// Catalogs the addon provides.
  final List<ManifestCatalog> catalogs;

  /// Manifest-level id prefixes; null means any id.
  final List<String>? idPrefixes;

  /// `behaviorHints.adult`.
  final bool adult;

  /// `behaviorHints.p2p`: results are BitTorrent and may expose the user's IP.
  final bool p2p;

  /// `behaviorHints.configurable`.
  final bool configurable;

  /// `behaviorHints.configurationRequired`: unusable until configured.
  final bool configurationRequired;

  /// The catalog with [type] and [id], if declared.
  ManifestCatalog? catalog(String type, String id) {
    for (final c in catalogs) {
      if (c.type == type && c.id == id) return c;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is AddonManifest &&
      other.id == id &&
      other.version == version &&
      other.name == name &&
      other.description == description &&
      other.logo == logo &&
      other.background == background &&
      listEquals(other.types, types) &&
      listEquals(other.resources, resources) &&
      listEquals(other.catalogs, catalogs) &&
      (other.idPrefixes == null) == (idPrefixes == null) &&
      listEquals(other.idPrefixes ?? const [], idPrefixes ?? const []) &&
      other.adult == adult &&
      other.p2p == p2p &&
      other.configurable == configurable &&
      other.configurationRequired == configurationRequired;

  @override
  int get hashCode => Object.hash(
    id,
    version,
    name,
    description,
    logo,
    background,
    Object.hashAll(types),
    Object.hashAll(resources),
    Object.hashAll(catalogs),
    idPrefixes == null ? null : Object.hashAll(idPrefixes!),
    adult,
    p2p,
    configurable,
    configurationRequired,
  );

  @override
  String toString() => 'AddonManifest($id $version, "$name")';
}

/// One entry of `manifest.resources`, normalized so both the string form
/// (`"stream"`) and the object form (`{name, types, idPrefixes}`) carry their
/// effective filters.
final class ManifestResource {
  /// Creates a resource.
  const ManifestResource({
    required this.name,
    this.types = const [],
    this.idPrefixes,
  });

  static ManifestResource? _parse(
    Object? value,
    List<String> manifestTypes,
    List<String>? manifestPrefixes,
  ) => switch (value) {
    final String name when name.isNotEmpty => ManifestResource(
      name: name,
      types: manifestTypes,
      idPrefixes: manifestPrefixes,
    ),
    final Map<String, Object?> json when readString(json, 'name') != null =>
      ManifestResource(
        name: readString(json, 'name')!,
        types: readStringsOrNull(json, 'types') ?? manifestTypes,
        // Object form without idPrefixes matches every id (protocol docs).
        idPrefixes: readStringsOrNull(json, 'idPrefixes'),
      ),
    _ => null,
  };

  /// `catalog`, `meta`, `stream`, `subtitles`, ...
  final String name;

  /// Types this resource serves.
  final List<String> types;

  /// Id prefixes this resource serves; null or empty means any id.
  final List<String>? idPrefixes;

  /// Whether a request for [type]/[id] matches this resource's filters.
  bool matches(String type, String id) =>
      types.contains(type) &&
      (idPrefixes == null ||
          idPrefixes!.isEmpty ||
          idPrefixes!.any(id.startsWith));

  @override
  bool operator ==(Object other) =>
      other is ManifestResource &&
      other.name == name &&
      listEquals(other.types, types) &&
      (other.idPrefixes == null) == (idPrefixes == null) &&
      listEquals(other.idPrefixes ?? const [], idPrefixes ?? const []);

  @override
  int get hashCode => Object.hash(
    name,
    Object.hashAll(types),
    idPrefixes == null ? null : Object.hashAll(idPrefixes!),
  );

  @override
  String toString() =>
      'ManifestResource($name, types: $types, idPrefixes: $idPrefixes)';
}

/// One entry of `manifest.catalogs`.
final class ManifestCatalog {
  /// Creates a catalog.
  const ManifestCatalog({
    required this.type,
    required this.id,
    this.name,
    this.extra = const [],
  });

  static ManifestCatalog? _parse(JsonMap json) {
    final type = readString(json, 'type');
    final id = readString(json, 'id');
    if (type == null || id == null) return null;
    var extra = readObjects(json, 'extra').map(CatalogExtra._parse).nonNulls;
    if (json['extra'] is! List<Object?>) {
      // Legacy short form: extraSupported / extraRequired name lists.
      final required = readStrings(json, 'extraRequired');
      extra = {
        ...readStrings(json, 'extraSupported'),
        ...required,
      }.map((n) => CatalogExtra(name: n, isRequired: required.contains(n)));
    }
    return ManifestCatalog(
      type: type,
      id: id,
      name: readString(json, 'name'),
      extra: List.unmodifiable(extra),
    );
  }

  /// Content type, e.g. `movie`.
  final String type;

  /// Catalog id, unique per addon and type.
  final String id;

  /// Display name.
  final String? name;

  /// Supported extra properties (`search`, `genre`, `skip`, ...).
  final List<CatalogExtra> extra;

  /// Whether the catalog accepts the extra property [name].
  bool supportsExtra(String name) => extra.any((e) => e.name == name);

  /// Extras that must be passed on every request (e.g. search-only catalogs).
  List<CatalogExtra> get requiredExtras =>
      extra.where((e) => e.isRequired).toList(growable: false);

  @override
  bool operator ==(Object other) =>
      other is ManifestCatalog &&
      other.type == type &&
      other.id == id &&
      other.name == name &&
      listEquals(other.extra, extra);

  @override
  int get hashCode => Object.hash(type, id, name, Object.hashAll(extra));

  @override
  String toString() => 'ManifestCatalog($type/$id, extra: $extra)';
}

/// A catalog extra property definition.
final class CatalogExtra {
  /// Creates an extra definition.
  const CatalogExtra({
    required this.name,
    this.isRequired = false,
    this.options = const [],
    this.optionsLimit = 1,
  });

  static CatalogExtra? _parse(JsonMap json) {
    final name = readString(json, 'name');
    if (name == null) return null;
    return CatalogExtra(
      name: name,
      isRequired: readBool(json, 'isRequired'),
      options: readStrings(json, 'options'),
      optionsLimit: readInt(json, 'optionsLimit') ?? 1,
    );
  }

  /// Property name, e.g. `search`.
  final String name;

  /// Must be present on every request.
  final bool isRequired;

  /// Allowed values (e.g. genres); empty means free text.
  final List<String> options;

  /// How many [options] may be selected at once.
  final int optionsLimit;

  @override
  bool operator ==(Object other) =>
      other is CatalogExtra &&
      other.name == name &&
      other.isRequired == isRequired &&
      listEquals(other.options, options) &&
      other.optionsLimit == optionsLimit;

  @override
  int get hashCode =>
      Object.hash(name, isRequired, Object.hashAll(options), optionsLimit);

  @override
  String toString() =>
      'CatalogExtra($name${isRequired ? ', required' : ''}'
      '${options.isEmpty ? '' : ', ${options.length} options'})';
}
