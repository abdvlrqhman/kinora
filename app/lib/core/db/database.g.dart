// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $AddonsTable extends Addons with TableInfo<$AddonsTable, Addon> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AddonsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _transportUrlMeta = const VerificationMeta(
    'transportUrl',
  );
  @override
  late final GeneratedColumn<String> transportUrl = GeneratedColumn<String>(
    'transport_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _manifestJsonMeta = const VerificationMeta(
    'manifestJson',
  );
  @override
  late final GeneratedColumn<String> manifestJson = GeneratedColumn<String>(
    'manifest_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    transportUrl,
    manifestJson,
    enabled,
    position,
    addedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'addons';
  @override
  VerificationContext validateIntegrity(
    Insertable<Addon> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('transport_url')) {
      context.handle(
        _transportUrlMeta,
        transportUrl.isAcceptableOrUnknown(
          data['transport_url']!,
          _transportUrlMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_transportUrlMeta);
    }
    if (data.containsKey('manifest_json')) {
      context.handle(
        _manifestJsonMeta,
        manifestJson.isAcceptableOrUnknown(
          data['manifest_json']!,
          _manifestJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_manifestJsonMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Addon map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Addon(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      transportUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transport_url'],
      )!,
      manifestJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manifest_json'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $AddonsTable createAlias(String alias) {
    return $AddonsTable(attachedDatabase, alias);
  }
}

class Addon extends DataClass implements Insertable<Addon> {
  final int id;

  /// Base URL (manifest URL without `/manifest.json`), config segments kept.
  final String transportUrl;
  final String manifestJson;
  final bool enabled;
  final int position;
  final DateTime addedAt;
  const Addon({
    required this.id,
    required this.transportUrl,
    required this.manifestJson,
    required this.enabled,
    required this.position,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['transport_url'] = Variable<String>(transportUrl);
    map['manifest_json'] = Variable<String>(manifestJson);
    map['enabled'] = Variable<bool>(enabled);
    map['position'] = Variable<int>(position);
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  AddonsCompanion toCompanion(bool nullToAbsent) {
    return AddonsCompanion(
      id: Value(id),
      transportUrl: Value(transportUrl),
      manifestJson: Value(manifestJson),
      enabled: Value(enabled),
      position: Value(position),
      addedAt: Value(addedAt),
    );
  }

  factory Addon.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Addon(
      id: serializer.fromJson<int>(json['id']),
      transportUrl: serializer.fromJson<String>(json['transportUrl']),
      manifestJson: serializer.fromJson<String>(json['manifestJson']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      position: serializer.fromJson<int>(json['position']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'transportUrl': serializer.toJson<String>(transportUrl),
      'manifestJson': serializer.toJson<String>(manifestJson),
      'enabled': serializer.toJson<bool>(enabled),
      'position': serializer.toJson<int>(position),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  Addon copyWith({
    int? id,
    String? transportUrl,
    String? manifestJson,
    bool? enabled,
    int? position,
    DateTime? addedAt,
  }) => Addon(
    id: id ?? this.id,
    transportUrl: transportUrl ?? this.transportUrl,
    manifestJson: manifestJson ?? this.manifestJson,
    enabled: enabled ?? this.enabled,
    position: position ?? this.position,
    addedAt: addedAt ?? this.addedAt,
  );
  Addon copyWithCompanion(AddonsCompanion data) {
    return Addon(
      id: data.id.present ? data.id.value : this.id,
      transportUrl: data.transportUrl.present
          ? data.transportUrl.value
          : this.transportUrl,
      manifestJson: data.manifestJson.present
          ? data.manifestJson.value
          : this.manifestJson,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      position: data.position.present ? data.position.value : this.position,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Addon(')
          ..write('id: $id, ')
          ..write('transportUrl: $transportUrl, ')
          ..write('manifestJson: $manifestJson, ')
          ..write('enabled: $enabled, ')
          ..write('position: $position, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, transportUrl, manifestJson, enabled, position, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Addon &&
          other.id == this.id &&
          other.transportUrl == this.transportUrl &&
          other.manifestJson == this.manifestJson &&
          other.enabled == this.enabled &&
          other.position == this.position &&
          other.addedAt == this.addedAt);
}

class AddonsCompanion extends UpdateCompanion<Addon> {
  final Value<int> id;
  final Value<String> transportUrl;
  final Value<String> manifestJson;
  final Value<bool> enabled;
  final Value<int> position;
  final Value<DateTime> addedAt;
  const AddonsCompanion({
    this.id = const Value.absent(),
    this.transportUrl = const Value.absent(),
    this.manifestJson = const Value.absent(),
    this.enabled = const Value.absent(),
    this.position = const Value.absent(),
    this.addedAt = const Value.absent(),
  });
  AddonsCompanion.insert({
    this.id = const Value.absent(),
    required String transportUrl,
    required String manifestJson,
    this.enabled = const Value.absent(),
    this.position = const Value.absent(),
    this.addedAt = const Value.absent(),
  }) : transportUrl = Value(transportUrl),
       manifestJson = Value(manifestJson);
  static Insertable<Addon> custom({
    Expression<int>? id,
    Expression<String>? transportUrl,
    Expression<String>? manifestJson,
    Expression<bool>? enabled,
    Expression<int>? position,
    Expression<DateTime>? addedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (transportUrl != null) 'transport_url': transportUrl,
      if (manifestJson != null) 'manifest_json': manifestJson,
      if (enabled != null) 'enabled': enabled,
      if (position != null) 'position': position,
      if (addedAt != null) 'added_at': addedAt,
    });
  }

  AddonsCompanion copyWith({
    Value<int>? id,
    Value<String>? transportUrl,
    Value<String>? manifestJson,
    Value<bool>? enabled,
    Value<int>? position,
    Value<DateTime>? addedAt,
  }) {
    return AddonsCompanion(
      id: id ?? this.id,
      transportUrl: transportUrl ?? this.transportUrl,
      manifestJson: manifestJson ?? this.manifestJson,
      enabled: enabled ?? this.enabled,
      position: position ?? this.position,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (transportUrl.present) {
      map['transport_url'] = Variable<String>(transportUrl.value);
    }
    if (manifestJson.present) {
      map['manifest_json'] = Variable<String>(manifestJson.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AddonsCompanion(')
          ..write('id: $id, ')
          ..write('transportUrl: $transportUrl, ')
          ..write('manifestJson: $manifestJson, ')
          ..write('enabled: $enabled, ')
          ..write('position: $position, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }
}

class $LibraryItemsTable extends LibraryItems
    with TableInfo<$LibraryItemsTable, LibraryItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LibraryItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mediaIdMeta = const VerificationMeta(
    'mediaId',
  );
  @override
  late final GeneratedColumn<String> mediaId = GeneratedColumn<String>(
    'media_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _posterMeta = const VerificationMeta('poster');
  @override
  late final GeneratedColumn<String> poster = GeneratedColumn<String>(
    'poster',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _backgroundMeta = const VerificationMeta(
    'background',
  );
  @override
  late final GeneratedColumn<String> background = GeneratedColumn<String>(
    'background',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    mediaId,
    type,
    name,
    poster,
    background,
    addedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'library_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<LibraryItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('media_id')) {
      context.handle(
        _mediaIdMeta,
        mediaId.isAcceptableOrUnknown(data['media_id']!, _mediaIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('poster')) {
      context.handle(
        _posterMeta,
        poster.isAcceptableOrUnknown(data['poster']!, _posterMeta),
      );
    }
    if (data.containsKey('background')) {
      context.handle(
        _backgroundMeta,
        background.isAcceptableOrUnknown(data['background']!, _backgroundMeta),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {mediaId};
  @override
  LibraryItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LibraryItem(
      mediaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      poster: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}poster'],
      ),
      background: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}background'],
      ),
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $LibraryItemsTable createAlias(String alias) {
    return $LibraryItemsTable(attachedDatabase, alias);
  }
}

class LibraryItem extends DataClass implements Insertable<LibraryItem> {
  final String mediaId;
  final String type;
  final String name;
  final String? poster;
  final String? background;
  final DateTime addedAt;
  const LibraryItem({
    required this.mediaId,
    required this.type,
    required this.name,
    this.poster,
    this.background,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['media_id'] = Variable<String>(mediaId);
    map['type'] = Variable<String>(type);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || poster != null) {
      map['poster'] = Variable<String>(poster);
    }
    if (!nullToAbsent || background != null) {
      map['background'] = Variable<String>(background);
    }
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  LibraryItemsCompanion toCompanion(bool nullToAbsent) {
    return LibraryItemsCompanion(
      mediaId: Value(mediaId),
      type: Value(type),
      name: Value(name),
      poster: poster == null && nullToAbsent
          ? const Value.absent()
          : Value(poster),
      background: background == null && nullToAbsent
          ? const Value.absent()
          : Value(background),
      addedAt: Value(addedAt),
    );
  }

  factory LibraryItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LibraryItem(
      mediaId: serializer.fromJson<String>(json['mediaId']),
      type: serializer.fromJson<String>(json['type']),
      name: serializer.fromJson<String>(json['name']),
      poster: serializer.fromJson<String?>(json['poster']),
      background: serializer.fromJson<String?>(json['background']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'mediaId': serializer.toJson<String>(mediaId),
      'type': serializer.toJson<String>(type),
      'name': serializer.toJson<String>(name),
      'poster': serializer.toJson<String?>(poster),
      'background': serializer.toJson<String?>(background),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  LibraryItem copyWith({
    String? mediaId,
    String? type,
    String? name,
    Value<String?> poster = const Value.absent(),
    Value<String?> background = const Value.absent(),
    DateTime? addedAt,
  }) => LibraryItem(
    mediaId: mediaId ?? this.mediaId,
    type: type ?? this.type,
    name: name ?? this.name,
    poster: poster.present ? poster.value : this.poster,
    background: background.present ? background.value : this.background,
    addedAt: addedAt ?? this.addedAt,
  );
  LibraryItem copyWithCompanion(LibraryItemsCompanion data) {
    return LibraryItem(
      mediaId: data.mediaId.present ? data.mediaId.value : this.mediaId,
      type: data.type.present ? data.type.value : this.type,
      name: data.name.present ? data.name.value : this.name,
      poster: data.poster.present ? data.poster.value : this.poster,
      background: data.background.present
          ? data.background.value
          : this.background,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LibraryItem(')
          ..write('mediaId: $mediaId, ')
          ..write('type: $type, ')
          ..write('name: $name, ')
          ..write('poster: $poster, ')
          ..write('background: $background, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(mediaId, type, name, poster, background, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LibraryItem &&
          other.mediaId == this.mediaId &&
          other.type == this.type &&
          other.name == this.name &&
          other.poster == this.poster &&
          other.background == this.background &&
          other.addedAt == this.addedAt);
}

class LibraryItemsCompanion extends UpdateCompanion<LibraryItem> {
  final Value<String> mediaId;
  final Value<String> type;
  final Value<String> name;
  final Value<String?> poster;
  final Value<String?> background;
  final Value<DateTime> addedAt;
  final Value<int> rowid;
  const LibraryItemsCompanion({
    this.mediaId = const Value.absent(),
    this.type = const Value.absent(),
    this.name = const Value.absent(),
    this.poster = const Value.absent(),
    this.background = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LibraryItemsCompanion.insert({
    required String mediaId,
    required String type,
    required String name,
    this.poster = const Value.absent(),
    this.background = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : mediaId = Value(mediaId),
       type = Value(type),
       name = Value(name);
  static Insertable<LibraryItem> custom({
    Expression<String>? mediaId,
    Expression<String>? type,
    Expression<String>? name,
    Expression<String>? poster,
    Expression<String>? background,
    Expression<DateTime>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mediaId != null) 'media_id': mediaId,
      if (type != null) 'type': type,
      if (name != null) 'name': name,
      if (poster != null) 'poster': poster,
      if (background != null) 'background': background,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LibraryItemsCompanion copyWith({
    Value<String>? mediaId,
    Value<String>? type,
    Value<String>? name,
    Value<String?>? poster,
    Value<String?>? background,
    Value<DateTime>? addedAt,
    Value<int>? rowid,
  }) {
    return LibraryItemsCompanion(
      mediaId: mediaId ?? this.mediaId,
      type: type ?? this.type,
      name: name ?? this.name,
      poster: poster ?? this.poster,
      background: background ?? this.background,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mediaId.present) {
      map['media_id'] = Variable<String>(mediaId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (poster.present) {
      map['poster'] = Variable<String>(poster.value);
    }
    if (background.present) {
      map['background'] = Variable<String>(background.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LibraryItemsCompanion(')
          ..write('mediaId: $mediaId, ')
          ..write('type: $type, ')
          ..write('name: $name, ')
          ..write('poster: $poster, ')
          ..write('background: $background, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WatchProgressTable extends WatchProgress
    with TableInfo<$WatchProgressTable, WatchProgressData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WatchProgressTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _videoIdMeta = const VerificationMeta(
    'videoId',
  );
  @override
  late final GeneratedColumn<String> videoId = GeneratedColumn<String>(
    'video_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mediaIdMeta = const VerificationMeta(
    'mediaId',
  );
  @override
  late final GeneratedColumn<String> mediaId = GeneratedColumn<String>(
    'media_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _episodeTitleMeta = const VerificationMeta(
    'episodeTitle',
  );
  @override
  late final GeneratedColumn<String> episodeTitle = GeneratedColumn<String>(
    'episode_title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _seasonMeta = const VerificationMeta('season');
  @override
  late final GeneratedColumn<int> season = GeneratedColumn<int>(
    'season',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _episodeMeta = const VerificationMeta(
    'episode',
  );
  @override
  late final GeneratedColumn<int> episode = GeneratedColumn<int>(
    'episode',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _positionMsMeta = const VerificationMeta(
    'positionMs',
  );
  @override
  late final GeneratedColumn<int> positionMs = GeneratedColumn<int>(
    'position_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completedMeta = const VerificationMeta(
    'completed',
  );
  @override
  late final GeneratedColumn<bool> completed = GeneratedColumn<bool>(
    'completed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("completed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _posterMeta = const VerificationMeta('poster');
  @override
  late final GeneratedColumn<String> poster = GeneratedColumn<String>(
    'poster',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stillMeta = const VerificationMeta('still');
  @override
  late final GeneratedColumn<String> still = GeneratedColumn<String>(
    'still',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    videoId,
    mediaId,
    type,
    name,
    episodeTitle,
    season,
    episode,
    positionMs,
    durationMs,
    completed,
    poster,
    still,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'watch_progress';
  @override
  VerificationContext validateIntegrity(
    Insertable<WatchProgressData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('video_id')) {
      context.handle(
        _videoIdMeta,
        videoId.isAcceptableOrUnknown(data['video_id']!, _videoIdMeta),
      );
    } else if (isInserting) {
      context.missing(_videoIdMeta);
    }
    if (data.containsKey('media_id')) {
      context.handle(
        _mediaIdMeta,
        mediaId.isAcceptableOrUnknown(data['media_id']!, _mediaIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('episode_title')) {
      context.handle(
        _episodeTitleMeta,
        episodeTitle.isAcceptableOrUnknown(
          data['episode_title']!,
          _episodeTitleMeta,
        ),
      );
    }
    if (data.containsKey('season')) {
      context.handle(
        _seasonMeta,
        season.isAcceptableOrUnknown(data['season']!, _seasonMeta),
      );
    }
    if (data.containsKey('episode')) {
      context.handle(
        _episodeMeta,
        episode.isAcceptableOrUnknown(data['episode']!, _episodeMeta),
      );
    }
    if (data.containsKey('position_ms')) {
      context.handle(
        _positionMsMeta,
        positionMs.isAcceptableOrUnknown(data['position_ms']!, _positionMsMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMsMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    } else if (isInserting) {
      context.missing(_durationMsMeta);
    }
    if (data.containsKey('completed')) {
      context.handle(
        _completedMeta,
        completed.isAcceptableOrUnknown(data['completed']!, _completedMeta),
      );
    }
    if (data.containsKey('poster')) {
      context.handle(
        _posterMeta,
        poster.isAcceptableOrUnknown(data['poster']!, _posterMeta),
      );
    }
    if (data.containsKey('still')) {
      context.handle(
        _stillMeta,
        still.isAcceptableOrUnknown(data['still']!, _stillMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {videoId};
  @override
  WatchProgressData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WatchProgressData(
      videoId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}video_id'],
      )!,
      mediaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      episodeTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}episode_title'],
      ),
      season: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}season'],
      ),
      episode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}episode'],
      ),
      positionMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position_ms'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      completed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}completed'],
      )!,
      poster: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}poster'],
      ),
      still: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}still'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $WatchProgressTable createAlias(String alias) {
    return $WatchProgressTable(attachedDatabase, alias);
  }
}

class WatchProgressData extends DataClass
    implements Insertable<WatchProgressData> {
  final String videoId;
  final String mediaId;
  final String type;
  final String name;
  final String? episodeTitle;
  final int? season;
  final int? episode;
  final int positionMs;
  final int durationMs;
  final bool completed;
  final String? poster;
  final String? still;
  final DateTime updatedAt;
  const WatchProgressData({
    required this.videoId,
    required this.mediaId,
    required this.type,
    required this.name,
    this.episodeTitle,
    this.season,
    this.episode,
    required this.positionMs,
    required this.durationMs,
    required this.completed,
    this.poster,
    this.still,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['video_id'] = Variable<String>(videoId);
    map['media_id'] = Variable<String>(mediaId);
    map['type'] = Variable<String>(type);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || episodeTitle != null) {
      map['episode_title'] = Variable<String>(episodeTitle);
    }
    if (!nullToAbsent || season != null) {
      map['season'] = Variable<int>(season);
    }
    if (!nullToAbsent || episode != null) {
      map['episode'] = Variable<int>(episode);
    }
    map['position_ms'] = Variable<int>(positionMs);
    map['duration_ms'] = Variable<int>(durationMs);
    map['completed'] = Variable<bool>(completed);
    if (!nullToAbsent || poster != null) {
      map['poster'] = Variable<String>(poster);
    }
    if (!nullToAbsent || still != null) {
      map['still'] = Variable<String>(still);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  WatchProgressCompanion toCompanion(bool nullToAbsent) {
    return WatchProgressCompanion(
      videoId: Value(videoId),
      mediaId: Value(mediaId),
      type: Value(type),
      name: Value(name),
      episodeTitle: episodeTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(episodeTitle),
      season: season == null && nullToAbsent
          ? const Value.absent()
          : Value(season),
      episode: episode == null && nullToAbsent
          ? const Value.absent()
          : Value(episode),
      positionMs: Value(positionMs),
      durationMs: Value(durationMs),
      completed: Value(completed),
      poster: poster == null && nullToAbsent
          ? const Value.absent()
          : Value(poster),
      still: still == null && nullToAbsent
          ? const Value.absent()
          : Value(still),
      updatedAt: Value(updatedAt),
    );
  }

  factory WatchProgressData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WatchProgressData(
      videoId: serializer.fromJson<String>(json['videoId']),
      mediaId: serializer.fromJson<String>(json['mediaId']),
      type: serializer.fromJson<String>(json['type']),
      name: serializer.fromJson<String>(json['name']),
      episodeTitle: serializer.fromJson<String?>(json['episodeTitle']),
      season: serializer.fromJson<int?>(json['season']),
      episode: serializer.fromJson<int?>(json['episode']),
      positionMs: serializer.fromJson<int>(json['positionMs']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      completed: serializer.fromJson<bool>(json['completed']),
      poster: serializer.fromJson<String?>(json['poster']),
      still: serializer.fromJson<String?>(json['still']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'videoId': serializer.toJson<String>(videoId),
      'mediaId': serializer.toJson<String>(mediaId),
      'type': serializer.toJson<String>(type),
      'name': serializer.toJson<String>(name),
      'episodeTitle': serializer.toJson<String?>(episodeTitle),
      'season': serializer.toJson<int?>(season),
      'episode': serializer.toJson<int?>(episode),
      'positionMs': serializer.toJson<int>(positionMs),
      'durationMs': serializer.toJson<int>(durationMs),
      'completed': serializer.toJson<bool>(completed),
      'poster': serializer.toJson<String?>(poster),
      'still': serializer.toJson<String?>(still),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  WatchProgressData copyWith({
    String? videoId,
    String? mediaId,
    String? type,
    String? name,
    Value<String?> episodeTitle = const Value.absent(),
    Value<int?> season = const Value.absent(),
    Value<int?> episode = const Value.absent(),
    int? positionMs,
    int? durationMs,
    bool? completed,
    Value<String?> poster = const Value.absent(),
    Value<String?> still = const Value.absent(),
    DateTime? updatedAt,
  }) => WatchProgressData(
    videoId: videoId ?? this.videoId,
    mediaId: mediaId ?? this.mediaId,
    type: type ?? this.type,
    name: name ?? this.name,
    episodeTitle: episodeTitle.present ? episodeTitle.value : this.episodeTitle,
    season: season.present ? season.value : this.season,
    episode: episode.present ? episode.value : this.episode,
    positionMs: positionMs ?? this.positionMs,
    durationMs: durationMs ?? this.durationMs,
    completed: completed ?? this.completed,
    poster: poster.present ? poster.value : this.poster,
    still: still.present ? still.value : this.still,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  WatchProgressData copyWithCompanion(WatchProgressCompanion data) {
    return WatchProgressData(
      videoId: data.videoId.present ? data.videoId.value : this.videoId,
      mediaId: data.mediaId.present ? data.mediaId.value : this.mediaId,
      type: data.type.present ? data.type.value : this.type,
      name: data.name.present ? data.name.value : this.name,
      episodeTitle: data.episodeTitle.present
          ? data.episodeTitle.value
          : this.episodeTitle,
      season: data.season.present ? data.season.value : this.season,
      episode: data.episode.present ? data.episode.value : this.episode,
      positionMs: data.positionMs.present
          ? data.positionMs.value
          : this.positionMs,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      completed: data.completed.present ? data.completed.value : this.completed,
      poster: data.poster.present ? data.poster.value : this.poster,
      still: data.still.present ? data.still.value : this.still,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WatchProgressData(')
          ..write('videoId: $videoId, ')
          ..write('mediaId: $mediaId, ')
          ..write('type: $type, ')
          ..write('name: $name, ')
          ..write('episodeTitle: $episodeTitle, ')
          ..write('season: $season, ')
          ..write('episode: $episode, ')
          ..write('positionMs: $positionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('completed: $completed, ')
          ..write('poster: $poster, ')
          ..write('still: $still, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    videoId,
    mediaId,
    type,
    name,
    episodeTitle,
    season,
    episode,
    positionMs,
    durationMs,
    completed,
    poster,
    still,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WatchProgressData &&
          other.videoId == this.videoId &&
          other.mediaId == this.mediaId &&
          other.type == this.type &&
          other.name == this.name &&
          other.episodeTitle == this.episodeTitle &&
          other.season == this.season &&
          other.episode == this.episode &&
          other.positionMs == this.positionMs &&
          other.durationMs == this.durationMs &&
          other.completed == this.completed &&
          other.poster == this.poster &&
          other.still == this.still &&
          other.updatedAt == this.updatedAt);
}

class WatchProgressCompanion extends UpdateCompanion<WatchProgressData> {
  final Value<String> videoId;
  final Value<String> mediaId;
  final Value<String> type;
  final Value<String> name;
  final Value<String?> episodeTitle;
  final Value<int?> season;
  final Value<int?> episode;
  final Value<int> positionMs;
  final Value<int> durationMs;
  final Value<bool> completed;
  final Value<String?> poster;
  final Value<String?> still;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const WatchProgressCompanion({
    this.videoId = const Value.absent(),
    this.mediaId = const Value.absent(),
    this.type = const Value.absent(),
    this.name = const Value.absent(),
    this.episodeTitle = const Value.absent(),
    this.season = const Value.absent(),
    this.episode = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.completed = const Value.absent(),
    this.poster = const Value.absent(),
    this.still = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WatchProgressCompanion.insert({
    required String videoId,
    required String mediaId,
    required String type,
    required String name,
    this.episodeTitle = const Value.absent(),
    this.season = const Value.absent(),
    this.episode = const Value.absent(),
    required int positionMs,
    required int durationMs,
    this.completed = const Value.absent(),
    this.poster = const Value.absent(),
    this.still = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : videoId = Value(videoId),
       mediaId = Value(mediaId),
       type = Value(type),
       name = Value(name),
       positionMs = Value(positionMs),
       durationMs = Value(durationMs);
  static Insertable<WatchProgressData> custom({
    Expression<String>? videoId,
    Expression<String>? mediaId,
    Expression<String>? type,
    Expression<String>? name,
    Expression<String>? episodeTitle,
    Expression<int>? season,
    Expression<int>? episode,
    Expression<int>? positionMs,
    Expression<int>? durationMs,
    Expression<bool>? completed,
    Expression<String>? poster,
    Expression<String>? still,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (videoId != null) 'video_id': videoId,
      if (mediaId != null) 'media_id': mediaId,
      if (type != null) 'type': type,
      if (name != null) 'name': name,
      if (episodeTitle != null) 'episode_title': episodeTitle,
      if (season != null) 'season': season,
      if (episode != null) 'episode': episode,
      if (positionMs != null) 'position_ms': positionMs,
      if (durationMs != null) 'duration_ms': durationMs,
      if (completed != null) 'completed': completed,
      if (poster != null) 'poster': poster,
      if (still != null) 'still': still,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WatchProgressCompanion copyWith({
    Value<String>? videoId,
    Value<String>? mediaId,
    Value<String>? type,
    Value<String>? name,
    Value<String?>? episodeTitle,
    Value<int?>? season,
    Value<int?>? episode,
    Value<int>? positionMs,
    Value<int>? durationMs,
    Value<bool>? completed,
    Value<String?>? poster,
    Value<String?>? still,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return WatchProgressCompanion(
      videoId: videoId ?? this.videoId,
      mediaId: mediaId ?? this.mediaId,
      type: type ?? this.type,
      name: name ?? this.name,
      episodeTitle: episodeTitle ?? this.episodeTitle,
      season: season ?? this.season,
      episode: episode ?? this.episode,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      completed: completed ?? this.completed,
      poster: poster ?? this.poster,
      still: still ?? this.still,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (videoId.present) {
      map['video_id'] = Variable<String>(videoId.value);
    }
    if (mediaId.present) {
      map['media_id'] = Variable<String>(mediaId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (episodeTitle.present) {
      map['episode_title'] = Variable<String>(episodeTitle.value);
    }
    if (season.present) {
      map['season'] = Variable<int>(season.value);
    }
    if (episode.present) {
      map['episode'] = Variable<int>(episode.value);
    }
    if (positionMs.present) {
      map['position_ms'] = Variable<int>(positionMs.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (completed.present) {
      map['completed'] = Variable<bool>(completed.value);
    }
    if (poster.present) {
      map['poster'] = Variable<String>(poster.value);
    }
    if (still.present) {
      map['still'] = Variable<String>(still.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WatchProgressCompanion(')
          ..write('videoId: $videoId, ')
          ..write('mediaId: $mediaId, ')
          ..write('type: $type, ')
          ..write('name: $name, ')
          ..write('episodeTitle: $episodeTitle, ')
          ..write('season: $season, ')
          ..write('episode: $episode, ')
          ..write('positionMs: $positionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('completed: $completed, ')
          ..write('poster: $poster, ')
          ..write('still: $still, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TrackMemoryTable extends TrackMemory
    with TableInfo<$TrackMemoryTable, TrackMemoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TrackMemoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _audioLanguageMeta = const VerificationMeta(
    'audioLanguage',
  );
  @override
  late final GeneratedColumn<String> audioLanguage = GeneratedColumn<String>(
    'audio_language',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _audioTrackIdMeta = const VerificationMeta(
    'audioTrackId',
  );
  @override
  late final GeneratedColumn<String> audioTrackId = GeneratedColumn<String>(
    'audio_track_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _subtitleLanguageMeta = const VerificationMeta(
    'subtitleLanguage',
  );
  @override
  late final GeneratedColumn<String> subtitleLanguage = GeneratedColumn<String>(
    'subtitle_language',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _subtitleVariantMeta = const VerificationMeta(
    'subtitleVariant',
  );
  @override
  late final GeneratedColumn<String> subtitleVariant = GeneratedColumn<String>(
    'subtitle_variant',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _subtitleIdMeta = const VerificationMeta(
    'subtitleId',
  );
  @override
  late final GeneratedColumn<String> subtitleId = GeneratedColumn<String>(
    'subtitle_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _subtitleOffsetMsMeta = const VerificationMeta(
    'subtitleOffsetMs',
  );
  @override
  late final GeneratedColumn<int> subtitleOffsetMs = GeneratedColumn<int>(
    'subtitle_offset_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    key,
    audioLanguage,
    audioTrackId,
    subtitleLanguage,
    subtitleVariant,
    subtitleId,
    subtitleOffsetMs,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'track_memory';
  @override
  VerificationContext validateIntegrity(
    Insertable<TrackMemoryData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('audio_language')) {
      context.handle(
        _audioLanguageMeta,
        audioLanguage.isAcceptableOrUnknown(
          data['audio_language']!,
          _audioLanguageMeta,
        ),
      );
    }
    if (data.containsKey('audio_track_id')) {
      context.handle(
        _audioTrackIdMeta,
        audioTrackId.isAcceptableOrUnknown(
          data['audio_track_id']!,
          _audioTrackIdMeta,
        ),
      );
    }
    if (data.containsKey('subtitle_language')) {
      context.handle(
        _subtitleLanguageMeta,
        subtitleLanguage.isAcceptableOrUnknown(
          data['subtitle_language']!,
          _subtitleLanguageMeta,
        ),
      );
    }
    if (data.containsKey('subtitle_variant')) {
      context.handle(
        _subtitleVariantMeta,
        subtitleVariant.isAcceptableOrUnknown(
          data['subtitle_variant']!,
          _subtitleVariantMeta,
        ),
      );
    }
    if (data.containsKey('subtitle_id')) {
      context.handle(
        _subtitleIdMeta,
        subtitleId.isAcceptableOrUnknown(data['subtitle_id']!, _subtitleIdMeta),
      );
    }
    if (data.containsKey('subtitle_offset_ms')) {
      context.handle(
        _subtitleOffsetMsMeta,
        subtitleOffsetMs.isAcceptableOrUnknown(
          data['subtitle_offset_ms']!,
          _subtitleOffsetMsMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  TrackMemoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TrackMemoryData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      audioLanguage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}audio_language'],
      ),
      audioTrackId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}audio_track_id'],
      ),
      subtitleLanguage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subtitle_language'],
      ),
      subtitleVariant: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subtitle_variant'],
      ),
      subtitleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subtitle_id'],
      ),
      subtitleOffsetMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}subtitle_offset_ms'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $TrackMemoryTable createAlias(String alias) {
    return $TrackMemoryTable(attachedDatabase, alias);
  }
}

class TrackMemoryData extends DataClass implements Insertable<TrackMemoryData> {
  final String key;
  final String? audioLanguage;
  final String? audioTrackId;
  final String? subtitleLanguage;

  /// 'off' | 'normal' | 'sdh' | 'forced'
  final String? subtitleVariant;
  final String? subtitleId;
  final int subtitleOffsetMs;
  final DateTime updatedAt;
  const TrackMemoryData({
    required this.key,
    this.audioLanguage,
    this.audioTrackId,
    this.subtitleLanguage,
    this.subtitleVariant,
    this.subtitleId,
    required this.subtitleOffsetMs,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    if (!nullToAbsent || audioLanguage != null) {
      map['audio_language'] = Variable<String>(audioLanguage);
    }
    if (!nullToAbsent || audioTrackId != null) {
      map['audio_track_id'] = Variable<String>(audioTrackId);
    }
    if (!nullToAbsent || subtitleLanguage != null) {
      map['subtitle_language'] = Variable<String>(subtitleLanguage);
    }
    if (!nullToAbsent || subtitleVariant != null) {
      map['subtitle_variant'] = Variable<String>(subtitleVariant);
    }
    if (!nullToAbsent || subtitleId != null) {
      map['subtitle_id'] = Variable<String>(subtitleId);
    }
    map['subtitle_offset_ms'] = Variable<int>(subtitleOffsetMs);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  TrackMemoryCompanion toCompanion(bool nullToAbsent) {
    return TrackMemoryCompanion(
      key: Value(key),
      audioLanguage: audioLanguage == null && nullToAbsent
          ? const Value.absent()
          : Value(audioLanguage),
      audioTrackId: audioTrackId == null && nullToAbsent
          ? const Value.absent()
          : Value(audioTrackId),
      subtitleLanguage: subtitleLanguage == null && nullToAbsent
          ? const Value.absent()
          : Value(subtitleLanguage),
      subtitleVariant: subtitleVariant == null && nullToAbsent
          ? const Value.absent()
          : Value(subtitleVariant),
      subtitleId: subtitleId == null && nullToAbsent
          ? const Value.absent()
          : Value(subtitleId),
      subtitleOffsetMs: Value(subtitleOffsetMs),
      updatedAt: Value(updatedAt),
    );
  }

  factory TrackMemoryData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TrackMemoryData(
      key: serializer.fromJson<String>(json['key']),
      audioLanguage: serializer.fromJson<String?>(json['audioLanguage']),
      audioTrackId: serializer.fromJson<String?>(json['audioTrackId']),
      subtitleLanguage: serializer.fromJson<String?>(json['subtitleLanguage']),
      subtitleVariant: serializer.fromJson<String?>(json['subtitleVariant']),
      subtitleId: serializer.fromJson<String?>(json['subtitleId']),
      subtitleOffsetMs: serializer.fromJson<int>(json['subtitleOffsetMs']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'audioLanguage': serializer.toJson<String?>(audioLanguage),
      'audioTrackId': serializer.toJson<String?>(audioTrackId),
      'subtitleLanguage': serializer.toJson<String?>(subtitleLanguage),
      'subtitleVariant': serializer.toJson<String?>(subtitleVariant),
      'subtitleId': serializer.toJson<String?>(subtitleId),
      'subtitleOffsetMs': serializer.toJson<int>(subtitleOffsetMs),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  TrackMemoryData copyWith({
    String? key,
    Value<String?> audioLanguage = const Value.absent(),
    Value<String?> audioTrackId = const Value.absent(),
    Value<String?> subtitleLanguage = const Value.absent(),
    Value<String?> subtitleVariant = const Value.absent(),
    Value<String?> subtitleId = const Value.absent(),
    int? subtitleOffsetMs,
    DateTime? updatedAt,
  }) => TrackMemoryData(
    key: key ?? this.key,
    audioLanguage: audioLanguage.present
        ? audioLanguage.value
        : this.audioLanguage,
    audioTrackId: audioTrackId.present ? audioTrackId.value : this.audioTrackId,
    subtitleLanguage: subtitleLanguage.present
        ? subtitleLanguage.value
        : this.subtitleLanguage,
    subtitleVariant: subtitleVariant.present
        ? subtitleVariant.value
        : this.subtitleVariant,
    subtitleId: subtitleId.present ? subtitleId.value : this.subtitleId,
    subtitleOffsetMs: subtitleOffsetMs ?? this.subtitleOffsetMs,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  TrackMemoryData copyWithCompanion(TrackMemoryCompanion data) {
    return TrackMemoryData(
      key: data.key.present ? data.key.value : this.key,
      audioLanguage: data.audioLanguage.present
          ? data.audioLanguage.value
          : this.audioLanguage,
      audioTrackId: data.audioTrackId.present
          ? data.audioTrackId.value
          : this.audioTrackId,
      subtitleLanguage: data.subtitleLanguage.present
          ? data.subtitleLanguage.value
          : this.subtitleLanguage,
      subtitleVariant: data.subtitleVariant.present
          ? data.subtitleVariant.value
          : this.subtitleVariant,
      subtitleId: data.subtitleId.present
          ? data.subtitleId.value
          : this.subtitleId,
      subtitleOffsetMs: data.subtitleOffsetMs.present
          ? data.subtitleOffsetMs.value
          : this.subtitleOffsetMs,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrackMemoryData(')
          ..write('key: $key, ')
          ..write('audioLanguage: $audioLanguage, ')
          ..write('audioTrackId: $audioTrackId, ')
          ..write('subtitleLanguage: $subtitleLanguage, ')
          ..write('subtitleVariant: $subtitleVariant, ')
          ..write('subtitleId: $subtitleId, ')
          ..write('subtitleOffsetMs: $subtitleOffsetMs, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    key,
    audioLanguage,
    audioTrackId,
    subtitleLanguage,
    subtitleVariant,
    subtitleId,
    subtitleOffsetMs,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrackMemoryData &&
          other.key == this.key &&
          other.audioLanguage == this.audioLanguage &&
          other.audioTrackId == this.audioTrackId &&
          other.subtitleLanguage == this.subtitleLanguage &&
          other.subtitleVariant == this.subtitleVariant &&
          other.subtitleId == this.subtitleId &&
          other.subtitleOffsetMs == this.subtitleOffsetMs &&
          other.updatedAt == this.updatedAt);
}

class TrackMemoryCompanion extends UpdateCompanion<TrackMemoryData> {
  final Value<String> key;
  final Value<String?> audioLanguage;
  final Value<String?> audioTrackId;
  final Value<String?> subtitleLanguage;
  final Value<String?> subtitleVariant;
  final Value<String?> subtitleId;
  final Value<int> subtitleOffsetMs;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const TrackMemoryCompanion({
    this.key = const Value.absent(),
    this.audioLanguage = const Value.absent(),
    this.audioTrackId = const Value.absent(),
    this.subtitleLanguage = const Value.absent(),
    this.subtitleVariant = const Value.absent(),
    this.subtitleId = const Value.absent(),
    this.subtitleOffsetMs = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TrackMemoryCompanion.insert({
    required String key,
    this.audioLanguage = const Value.absent(),
    this.audioTrackId = const Value.absent(),
    this.subtitleLanguage = const Value.absent(),
    this.subtitleVariant = const Value.absent(),
    this.subtitleId = const Value.absent(),
    this.subtitleOffsetMs = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key);
  static Insertable<TrackMemoryData> custom({
    Expression<String>? key,
    Expression<String>? audioLanguage,
    Expression<String>? audioTrackId,
    Expression<String>? subtitleLanguage,
    Expression<String>? subtitleVariant,
    Expression<String>? subtitleId,
    Expression<int>? subtitleOffsetMs,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (audioLanguage != null) 'audio_language': audioLanguage,
      if (audioTrackId != null) 'audio_track_id': audioTrackId,
      if (subtitleLanguage != null) 'subtitle_language': subtitleLanguage,
      if (subtitleVariant != null) 'subtitle_variant': subtitleVariant,
      if (subtitleId != null) 'subtitle_id': subtitleId,
      if (subtitleOffsetMs != null) 'subtitle_offset_ms': subtitleOffsetMs,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TrackMemoryCompanion copyWith({
    Value<String>? key,
    Value<String?>? audioLanguage,
    Value<String?>? audioTrackId,
    Value<String?>? subtitleLanguage,
    Value<String?>? subtitleVariant,
    Value<String?>? subtitleId,
    Value<int>? subtitleOffsetMs,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return TrackMemoryCompanion(
      key: key ?? this.key,
      audioLanguage: audioLanguage ?? this.audioLanguage,
      audioTrackId: audioTrackId ?? this.audioTrackId,
      subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
      subtitleVariant: subtitleVariant ?? this.subtitleVariant,
      subtitleId: subtitleId ?? this.subtitleId,
      subtitleOffsetMs: subtitleOffsetMs ?? this.subtitleOffsetMs,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (audioLanguage.present) {
      map['audio_language'] = Variable<String>(audioLanguage.value);
    }
    if (audioTrackId.present) {
      map['audio_track_id'] = Variable<String>(audioTrackId.value);
    }
    if (subtitleLanguage.present) {
      map['subtitle_language'] = Variable<String>(subtitleLanguage.value);
    }
    if (subtitleVariant.present) {
      map['subtitle_variant'] = Variable<String>(subtitleVariant.value);
    }
    if (subtitleId.present) {
      map['subtitle_id'] = Variable<String>(subtitleId.value);
    }
    if (subtitleOffsetMs.present) {
      map['subtitle_offset_ms'] = Variable<int>(subtitleOffsetMs.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TrackMemoryCompanion(')
          ..write('key: $key, ')
          ..write('audioLanguage: $audioLanguage, ')
          ..write('audioTrackId: $audioTrackId, ')
          ..write('subtitleLanguage: $subtitleLanguage, ')
          ..write('subtitleVariant: $subtitleVariant, ')
          ..write('subtitleId: $subtitleId, ')
          ..write('subtitleOffsetMs: $subtitleOffsetMs, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DownloadsTable extends Downloads
    with TableInfo<$DownloadsTable, Download> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DownloadsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mediaIdMeta = const VerificationMeta(
    'mediaId',
  );
  @override
  late final GeneratedColumn<String> mediaId = GeneratedColumn<String>(
    'media_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _videoIdMeta = const VerificationMeta(
    'videoId',
  );
  @override
  late final GeneratedColumn<String> videoId = GeneratedColumn<String>(
    'video_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _episodeTitleMeta = const VerificationMeta(
    'episodeTitle',
  );
  @override
  late final GeneratedColumn<String> episodeTitle = GeneratedColumn<String>(
    'episode_title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _seasonMeta = const VerificationMeta('season');
  @override
  late final GeneratedColumn<int> season = GeneratedColumn<int>(
    'season',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _episodeMeta = const VerificationMeta(
    'episode',
  );
  @override
  late final GeneratedColumn<int> episode = GeneratedColumn<int>(
    'episode',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _posterMeta = const VerificationMeta('poster');
  @override
  late final GeneratedColumn<String> poster = GeneratedColumn<String>(
    'poster',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stillMeta = const VerificationMeta('still');
  @override
  late final GeneratedColumn<String> still = GeneratedColumn<String>(
    'still',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _releaseNameMeta = const VerificationMeta(
    'releaseName',
  );
  @override
  late final GeneratedColumn<String> releaseName = GeneratedColumn<String>(
    'release_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _infoHashMeta = const VerificationMeta(
    'infoHash',
  );
  @override
  late final GeneratedColumn<String> infoHash = GeneratedColumn<String>(
    'info_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fileIndexMeta = const VerificationMeta(
    'fileIndex',
  );
  @override
  late final GeneratedColumn<int> fileIndex = GeneratedColumn<int>(
    'file_index',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _magnetMeta = const VerificationMeta('magnet');
  @override
  late final GeneratedColumn<String> magnet = GeneratedColumn<String>(
    'magnet',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _directoryMeta = const VerificationMeta(
    'directory',
  );
  @override
  late final GeneratedColumn<String> directory = GeneratedColumn<String>(
    'directory',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _totalBytesMeta = const VerificationMeta(
    'totalBytes',
  );
  @override
  late final GeneratedColumn<int> totalBytes = GeneratedColumn<int>(
    'total_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _doneBytesMeta = const VerificationMeta(
    'doneBytes',
  );
  @override
  late final GeneratedColumn<int> doneBytes = GeneratedColumn<int>(
    'done_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _subtitlesJsonMeta = const VerificationMeta(
    'subtitlesJson',
  );
  @override
  late final GeneratedColumn<String> subtitlesJson = GeneratedColumn<String>(
    'subtitles_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    mediaId,
    videoId,
    type,
    title,
    episodeTitle,
    season,
    episode,
    poster,
    still,
    releaseName,
    kind,
    infoHash,
    fileIndex,
    url,
    magnet,
    directory,
    filePath,
    totalBytes,
    doneBytes,
    state,
    error,
    subtitlesJson,
    createdAt,
    completedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'downloads';
  @override
  VerificationContext validateIntegrity(
    Insertable<Download> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('media_id')) {
      context.handle(
        _mediaIdMeta,
        mediaId.isAcceptableOrUnknown(data['media_id']!, _mediaIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaIdMeta);
    }
    if (data.containsKey('video_id')) {
      context.handle(
        _videoIdMeta,
        videoId.isAcceptableOrUnknown(data['video_id']!, _videoIdMeta),
      );
    } else if (isInserting) {
      context.missing(_videoIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('episode_title')) {
      context.handle(
        _episodeTitleMeta,
        episodeTitle.isAcceptableOrUnknown(
          data['episode_title']!,
          _episodeTitleMeta,
        ),
      );
    }
    if (data.containsKey('season')) {
      context.handle(
        _seasonMeta,
        season.isAcceptableOrUnknown(data['season']!, _seasonMeta),
      );
    }
    if (data.containsKey('episode')) {
      context.handle(
        _episodeMeta,
        episode.isAcceptableOrUnknown(data['episode']!, _episodeMeta),
      );
    }
    if (data.containsKey('poster')) {
      context.handle(
        _posterMeta,
        poster.isAcceptableOrUnknown(data['poster']!, _posterMeta),
      );
    }
    if (data.containsKey('still')) {
      context.handle(
        _stillMeta,
        still.isAcceptableOrUnknown(data['still']!, _stillMeta),
      );
    }
    if (data.containsKey('release_name')) {
      context.handle(
        _releaseNameMeta,
        releaseName.isAcceptableOrUnknown(
          data['release_name']!,
          _releaseNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_releaseNameMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('info_hash')) {
      context.handle(
        _infoHashMeta,
        infoHash.isAcceptableOrUnknown(data['info_hash']!, _infoHashMeta),
      );
    }
    if (data.containsKey('file_index')) {
      context.handle(
        _fileIndexMeta,
        fileIndex.isAcceptableOrUnknown(data['file_index']!, _fileIndexMeta),
      );
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    }
    if (data.containsKey('magnet')) {
      context.handle(
        _magnetMeta,
        magnet.isAcceptableOrUnknown(data['magnet']!, _magnetMeta),
      );
    }
    if (data.containsKey('directory')) {
      context.handle(
        _directoryMeta,
        directory.isAcceptableOrUnknown(data['directory']!, _directoryMeta),
      );
    } else if (isInserting) {
      context.missing(_directoryMeta);
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    }
    if (data.containsKey('total_bytes')) {
      context.handle(
        _totalBytesMeta,
        totalBytes.isAcceptableOrUnknown(data['total_bytes']!, _totalBytesMeta),
      );
    }
    if (data.containsKey('done_bytes')) {
      context.handle(
        _doneBytesMeta,
        doneBytes.isAcceptableOrUnknown(data['done_bytes']!, _doneBytesMeta),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('error')) {
      context.handle(
        _errorMeta,
        error.isAcceptableOrUnknown(data['error']!, _errorMeta),
      );
    }
    if (data.containsKey('subtitles_json')) {
      context.handle(
        _subtitlesJsonMeta,
        subtitlesJson.isAcceptableOrUnknown(
          data['subtitles_json']!,
          _subtitlesJsonMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Download map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Download(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      mediaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_id'],
      )!,
      videoId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}video_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      episodeTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}episode_title'],
      ),
      season: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}season'],
      ),
      episode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}episode'],
      ),
      poster: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}poster'],
      ),
      still: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}still'],
      ),
      releaseName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}release_name'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      infoHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}info_hash'],
      ),
      fileIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_index'],
      ),
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      ),
      magnet: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}magnet'],
      ),
      directory: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}directory'],
      )!,
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      ),
      totalBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_bytes'],
      )!,
      doneBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}done_bytes'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      error: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error'],
      ),
      subtitlesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subtitles_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
    );
  }

  @override
  $DownloadsTable createAlias(String alias) {
    return $DownloadsTable(attachedDatabase, alias);
  }
}

class Download extends DataClass implements Insertable<Download> {
  final String id;
  final String mediaId;
  final String videoId;
  final String type;
  final String title;
  final String? episodeTitle;
  final int? season;
  final int? episode;
  final String? poster;
  final String? still;
  final String releaseName;

  /// 'torrent' | 'http'
  final String kind;
  final String? infoHash;
  final int? fileIndex;
  final String? url;
  final String? magnet;

  /// Folder holding the video (and its subtitles).
  final String directory;

  /// Final video file once known.
  final String? filePath;
  final int totalBytes;
  final int doneBytes;

  /// 'queued' | 'downloading' | 'paused' | 'completed' | 'failed'
  final String state;
  final String? error;

  /// JSON list of {lang, path, label} saved next to the video.
  final String subtitlesJson;
  final DateTime createdAt;
  final DateTime? completedAt;
  const Download({
    required this.id,
    required this.mediaId,
    required this.videoId,
    required this.type,
    required this.title,
    this.episodeTitle,
    this.season,
    this.episode,
    this.poster,
    this.still,
    required this.releaseName,
    required this.kind,
    this.infoHash,
    this.fileIndex,
    this.url,
    this.magnet,
    required this.directory,
    this.filePath,
    required this.totalBytes,
    required this.doneBytes,
    required this.state,
    this.error,
    required this.subtitlesJson,
    required this.createdAt,
    this.completedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['media_id'] = Variable<String>(mediaId);
    map['video_id'] = Variable<String>(videoId);
    map['type'] = Variable<String>(type);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || episodeTitle != null) {
      map['episode_title'] = Variable<String>(episodeTitle);
    }
    if (!nullToAbsent || season != null) {
      map['season'] = Variable<int>(season);
    }
    if (!nullToAbsent || episode != null) {
      map['episode'] = Variable<int>(episode);
    }
    if (!nullToAbsent || poster != null) {
      map['poster'] = Variable<String>(poster);
    }
    if (!nullToAbsent || still != null) {
      map['still'] = Variable<String>(still);
    }
    map['release_name'] = Variable<String>(releaseName);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || infoHash != null) {
      map['info_hash'] = Variable<String>(infoHash);
    }
    if (!nullToAbsent || fileIndex != null) {
      map['file_index'] = Variable<int>(fileIndex);
    }
    if (!nullToAbsent || url != null) {
      map['url'] = Variable<String>(url);
    }
    if (!nullToAbsent || magnet != null) {
      map['magnet'] = Variable<String>(magnet);
    }
    map['directory'] = Variable<String>(directory);
    if (!nullToAbsent || filePath != null) {
      map['file_path'] = Variable<String>(filePath);
    }
    map['total_bytes'] = Variable<int>(totalBytes);
    map['done_bytes'] = Variable<int>(doneBytes);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    map['subtitles_json'] = Variable<String>(subtitlesJson);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    return map;
  }

  DownloadsCompanion toCompanion(bool nullToAbsent) {
    return DownloadsCompanion(
      id: Value(id),
      mediaId: Value(mediaId),
      videoId: Value(videoId),
      type: Value(type),
      title: Value(title),
      episodeTitle: episodeTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(episodeTitle),
      season: season == null && nullToAbsent
          ? const Value.absent()
          : Value(season),
      episode: episode == null && nullToAbsent
          ? const Value.absent()
          : Value(episode),
      poster: poster == null && nullToAbsent
          ? const Value.absent()
          : Value(poster),
      still: still == null && nullToAbsent
          ? const Value.absent()
          : Value(still),
      releaseName: Value(releaseName),
      kind: Value(kind),
      infoHash: infoHash == null && nullToAbsent
          ? const Value.absent()
          : Value(infoHash),
      fileIndex: fileIndex == null && nullToAbsent
          ? const Value.absent()
          : Value(fileIndex),
      url: url == null && nullToAbsent ? const Value.absent() : Value(url),
      magnet: magnet == null && nullToAbsent
          ? const Value.absent()
          : Value(magnet),
      directory: Value(directory),
      filePath: filePath == null && nullToAbsent
          ? const Value.absent()
          : Value(filePath),
      totalBytes: Value(totalBytes),
      doneBytes: Value(doneBytes),
      state: Value(state),
      error: error == null && nullToAbsent
          ? const Value.absent()
          : Value(error),
      subtitlesJson: Value(subtitlesJson),
      createdAt: Value(createdAt),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
    );
  }

  factory Download.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Download(
      id: serializer.fromJson<String>(json['id']),
      mediaId: serializer.fromJson<String>(json['mediaId']),
      videoId: serializer.fromJson<String>(json['videoId']),
      type: serializer.fromJson<String>(json['type']),
      title: serializer.fromJson<String>(json['title']),
      episodeTitle: serializer.fromJson<String?>(json['episodeTitle']),
      season: serializer.fromJson<int?>(json['season']),
      episode: serializer.fromJson<int?>(json['episode']),
      poster: serializer.fromJson<String?>(json['poster']),
      still: serializer.fromJson<String?>(json['still']),
      releaseName: serializer.fromJson<String>(json['releaseName']),
      kind: serializer.fromJson<String>(json['kind']),
      infoHash: serializer.fromJson<String?>(json['infoHash']),
      fileIndex: serializer.fromJson<int?>(json['fileIndex']),
      url: serializer.fromJson<String?>(json['url']),
      magnet: serializer.fromJson<String?>(json['magnet']),
      directory: serializer.fromJson<String>(json['directory']),
      filePath: serializer.fromJson<String?>(json['filePath']),
      totalBytes: serializer.fromJson<int>(json['totalBytes']),
      doneBytes: serializer.fromJson<int>(json['doneBytes']),
      state: serializer.fromJson<String>(json['state']),
      error: serializer.fromJson<String?>(json['error']),
      subtitlesJson: serializer.fromJson<String>(json['subtitlesJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'mediaId': serializer.toJson<String>(mediaId),
      'videoId': serializer.toJson<String>(videoId),
      'type': serializer.toJson<String>(type),
      'title': serializer.toJson<String>(title),
      'episodeTitle': serializer.toJson<String?>(episodeTitle),
      'season': serializer.toJson<int?>(season),
      'episode': serializer.toJson<int?>(episode),
      'poster': serializer.toJson<String?>(poster),
      'still': serializer.toJson<String?>(still),
      'releaseName': serializer.toJson<String>(releaseName),
      'kind': serializer.toJson<String>(kind),
      'infoHash': serializer.toJson<String?>(infoHash),
      'fileIndex': serializer.toJson<int?>(fileIndex),
      'url': serializer.toJson<String?>(url),
      'magnet': serializer.toJson<String?>(magnet),
      'directory': serializer.toJson<String>(directory),
      'filePath': serializer.toJson<String?>(filePath),
      'totalBytes': serializer.toJson<int>(totalBytes),
      'doneBytes': serializer.toJson<int>(doneBytes),
      'state': serializer.toJson<String>(state),
      'error': serializer.toJson<String?>(error),
      'subtitlesJson': serializer.toJson<String>(subtitlesJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
    };
  }

  Download copyWith({
    String? id,
    String? mediaId,
    String? videoId,
    String? type,
    String? title,
    Value<String?> episodeTitle = const Value.absent(),
    Value<int?> season = const Value.absent(),
    Value<int?> episode = const Value.absent(),
    Value<String?> poster = const Value.absent(),
    Value<String?> still = const Value.absent(),
    String? releaseName,
    String? kind,
    Value<String?> infoHash = const Value.absent(),
    Value<int?> fileIndex = const Value.absent(),
    Value<String?> url = const Value.absent(),
    Value<String?> magnet = const Value.absent(),
    String? directory,
    Value<String?> filePath = const Value.absent(),
    int? totalBytes,
    int? doneBytes,
    String? state,
    Value<String?> error = const Value.absent(),
    String? subtitlesJson,
    DateTime? createdAt,
    Value<DateTime?> completedAt = const Value.absent(),
  }) => Download(
    id: id ?? this.id,
    mediaId: mediaId ?? this.mediaId,
    videoId: videoId ?? this.videoId,
    type: type ?? this.type,
    title: title ?? this.title,
    episodeTitle: episodeTitle.present ? episodeTitle.value : this.episodeTitle,
    season: season.present ? season.value : this.season,
    episode: episode.present ? episode.value : this.episode,
    poster: poster.present ? poster.value : this.poster,
    still: still.present ? still.value : this.still,
    releaseName: releaseName ?? this.releaseName,
    kind: kind ?? this.kind,
    infoHash: infoHash.present ? infoHash.value : this.infoHash,
    fileIndex: fileIndex.present ? fileIndex.value : this.fileIndex,
    url: url.present ? url.value : this.url,
    magnet: magnet.present ? magnet.value : this.magnet,
    directory: directory ?? this.directory,
    filePath: filePath.present ? filePath.value : this.filePath,
    totalBytes: totalBytes ?? this.totalBytes,
    doneBytes: doneBytes ?? this.doneBytes,
    state: state ?? this.state,
    error: error.present ? error.value : this.error,
    subtitlesJson: subtitlesJson ?? this.subtitlesJson,
    createdAt: createdAt ?? this.createdAt,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
  );
  Download copyWithCompanion(DownloadsCompanion data) {
    return Download(
      id: data.id.present ? data.id.value : this.id,
      mediaId: data.mediaId.present ? data.mediaId.value : this.mediaId,
      videoId: data.videoId.present ? data.videoId.value : this.videoId,
      type: data.type.present ? data.type.value : this.type,
      title: data.title.present ? data.title.value : this.title,
      episodeTitle: data.episodeTitle.present
          ? data.episodeTitle.value
          : this.episodeTitle,
      season: data.season.present ? data.season.value : this.season,
      episode: data.episode.present ? data.episode.value : this.episode,
      poster: data.poster.present ? data.poster.value : this.poster,
      still: data.still.present ? data.still.value : this.still,
      releaseName: data.releaseName.present
          ? data.releaseName.value
          : this.releaseName,
      kind: data.kind.present ? data.kind.value : this.kind,
      infoHash: data.infoHash.present ? data.infoHash.value : this.infoHash,
      fileIndex: data.fileIndex.present ? data.fileIndex.value : this.fileIndex,
      url: data.url.present ? data.url.value : this.url,
      magnet: data.magnet.present ? data.magnet.value : this.magnet,
      directory: data.directory.present ? data.directory.value : this.directory,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      totalBytes: data.totalBytes.present
          ? data.totalBytes.value
          : this.totalBytes,
      doneBytes: data.doneBytes.present ? data.doneBytes.value : this.doneBytes,
      state: data.state.present ? data.state.value : this.state,
      error: data.error.present ? data.error.value : this.error,
      subtitlesJson: data.subtitlesJson.present
          ? data.subtitlesJson.value
          : this.subtitlesJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Download(')
          ..write('id: $id, ')
          ..write('mediaId: $mediaId, ')
          ..write('videoId: $videoId, ')
          ..write('type: $type, ')
          ..write('title: $title, ')
          ..write('episodeTitle: $episodeTitle, ')
          ..write('season: $season, ')
          ..write('episode: $episode, ')
          ..write('poster: $poster, ')
          ..write('still: $still, ')
          ..write('releaseName: $releaseName, ')
          ..write('kind: $kind, ')
          ..write('infoHash: $infoHash, ')
          ..write('fileIndex: $fileIndex, ')
          ..write('url: $url, ')
          ..write('magnet: $magnet, ')
          ..write('directory: $directory, ')
          ..write('filePath: $filePath, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('doneBytes: $doneBytes, ')
          ..write('state: $state, ')
          ..write('error: $error, ')
          ..write('subtitlesJson: $subtitlesJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('completedAt: $completedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    mediaId,
    videoId,
    type,
    title,
    episodeTitle,
    season,
    episode,
    poster,
    still,
    releaseName,
    kind,
    infoHash,
    fileIndex,
    url,
    magnet,
    directory,
    filePath,
    totalBytes,
    doneBytes,
    state,
    error,
    subtitlesJson,
    createdAt,
    completedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Download &&
          other.id == this.id &&
          other.mediaId == this.mediaId &&
          other.videoId == this.videoId &&
          other.type == this.type &&
          other.title == this.title &&
          other.episodeTitle == this.episodeTitle &&
          other.season == this.season &&
          other.episode == this.episode &&
          other.poster == this.poster &&
          other.still == this.still &&
          other.releaseName == this.releaseName &&
          other.kind == this.kind &&
          other.infoHash == this.infoHash &&
          other.fileIndex == this.fileIndex &&
          other.url == this.url &&
          other.magnet == this.magnet &&
          other.directory == this.directory &&
          other.filePath == this.filePath &&
          other.totalBytes == this.totalBytes &&
          other.doneBytes == this.doneBytes &&
          other.state == this.state &&
          other.error == this.error &&
          other.subtitlesJson == this.subtitlesJson &&
          other.createdAt == this.createdAt &&
          other.completedAt == this.completedAt);
}

class DownloadsCompanion extends UpdateCompanion<Download> {
  final Value<String> id;
  final Value<String> mediaId;
  final Value<String> videoId;
  final Value<String> type;
  final Value<String> title;
  final Value<String?> episodeTitle;
  final Value<int?> season;
  final Value<int?> episode;
  final Value<String?> poster;
  final Value<String?> still;
  final Value<String> releaseName;
  final Value<String> kind;
  final Value<String?> infoHash;
  final Value<int?> fileIndex;
  final Value<String?> url;
  final Value<String?> magnet;
  final Value<String> directory;
  final Value<String?> filePath;
  final Value<int> totalBytes;
  final Value<int> doneBytes;
  final Value<String> state;
  final Value<String?> error;
  final Value<String> subtitlesJson;
  final Value<DateTime> createdAt;
  final Value<DateTime?> completedAt;
  final Value<int> rowid;
  const DownloadsCompanion({
    this.id = const Value.absent(),
    this.mediaId = const Value.absent(),
    this.videoId = const Value.absent(),
    this.type = const Value.absent(),
    this.title = const Value.absent(),
    this.episodeTitle = const Value.absent(),
    this.season = const Value.absent(),
    this.episode = const Value.absent(),
    this.poster = const Value.absent(),
    this.still = const Value.absent(),
    this.releaseName = const Value.absent(),
    this.kind = const Value.absent(),
    this.infoHash = const Value.absent(),
    this.fileIndex = const Value.absent(),
    this.url = const Value.absent(),
    this.magnet = const Value.absent(),
    this.directory = const Value.absent(),
    this.filePath = const Value.absent(),
    this.totalBytes = const Value.absent(),
    this.doneBytes = const Value.absent(),
    this.state = const Value.absent(),
    this.error = const Value.absent(),
    this.subtitlesJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DownloadsCompanion.insert({
    required String id,
    required String mediaId,
    required String videoId,
    required String type,
    required String title,
    this.episodeTitle = const Value.absent(),
    this.season = const Value.absent(),
    this.episode = const Value.absent(),
    this.poster = const Value.absent(),
    this.still = const Value.absent(),
    required String releaseName,
    required String kind,
    this.infoHash = const Value.absent(),
    this.fileIndex = const Value.absent(),
    this.url = const Value.absent(),
    this.magnet = const Value.absent(),
    required String directory,
    this.filePath = const Value.absent(),
    this.totalBytes = const Value.absent(),
    this.doneBytes = const Value.absent(),
    required String state,
    this.error = const Value.absent(),
    this.subtitlesJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       mediaId = Value(mediaId),
       videoId = Value(videoId),
       type = Value(type),
       title = Value(title),
       releaseName = Value(releaseName),
       kind = Value(kind),
       directory = Value(directory),
       state = Value(state);
  static Insertable<Download> custom({
    Expression<String>? id,
    Expression<String>? mediaId,
    Expression<String>? videoId,
    Expression<String>? type,
    Expression<String>? title,
    Expression<String>? episodeTitle,
    Expression<int>? season,
    Expression<int>? episode,
    Expression<String>? poster,
    Expression<String>? still,
    Expression<String>? releaseName,
    Expression<String>? kind,
    Expression<String>? infoHash,
    Expression<int>? fileIndex,
    Expression<String>? url,
    Expression<String>? magnet,
    Expression<String>? directory,
    Expression<String>? filePath,
    Expression<int>? totalBytes,
    Expression<int>? doneBytes,
    Expression<String>? state,
    Expression<String>? error,
    Expression<String>? subtitlesJson,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? completedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (mediaId != null) 'media_id': mediaId,
      if (videoId != null) 'video_id': videoId,
      if (type != null) 'type': type,
      if (title != null) 'title': title,
      if (episodeTitle != null) 'episode_title': episodeTitle,
      if (season != null) 'season': season,
      if (episode != null) 'episode': episode,
      if (poster != null) 'poster': poster,
      if (still != null) 'still': still,
      if (releaseName != null) 'release_name': releaseName,
      if (kind != null) 'kind': kind,
      if (infoHash != null) 'info_hash': infoHash,
      if (fileIndex != null) 'file_index': fileIndex,
      if (url != null) 'url': url,
      if (magnet != null) 'magnet': magnet,
      if (directory != null) 'directory': directory,
      if (filePath != null) 'file_path': filePath,
      if (totalBytes != null) 'total_bytes': totalBytes,
      if (doneBytes != null) 'done_bytes': doneBytes,
      if (state != null) 'state': state,
      if (error != null) 'error': error,
      if (subtitlesJson != null) 'subtitles_json': subtitlesJson,
      if (createdAt != null) 'created_at': createdAt,
      if (completedAt != null) 'completed_at': completedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DownloadsCompanion copyWith({
    Value<String>? id,
    Value<String>? mediaId,
    Value<String>? videoId,
    Value<String>? type,
    Value<String>? title,
    Value<String?>? episodeTitle,
    Value<int?>? season,
    Value<int?>? episode,
    Value<String?>? poster,
    Value<String?>? still,
    Value<String>? releaseName,
    Value<String>? kind,
    Value<String?>? infoHash,
    Value<int?>? fileIndex,
    Value<String?>? url,
    Value<String?>? magnet,
    Value<String>? directory,
    Value<String?>? filePath,
    Value<int>? totalBytes,
    Value<int>? doneBytes,
    Value<String>? state,
    Value<String?>? error,
    Value<String>? subtitlesJson,
    Value<DateTime>? createdAt,
    Value<DateTime?>? completedAt,
    Value<int>? rowid,
  }) {
    return DownloadsCompanion(
      id: id ?? this.id,
      mediaId: mediaId ?? this.mediaId,
      videoId: videoId ?? this.videoId,
      type: type ?? this.type,
      title: title ?? this.title,
      episodeTitle: episodeTitle ?? this.episodeTitle,
      season: season ?? this.season,
      episode: episode ?? this.episode,
      poster: poster ?? this.poster,
      still: still ?? this.still,
      releaseName: releaseName ?? this.releaseName,
      kind: kind ?? this.kind,
      infoHash: infoHash ?? this.infoHash,
      fileIndex: fileIndex ?? this.fileIndex,
      url: url ?? this.url,
      magnet: magnet ?? this.magnet,
      directory: directory ?? this.directory,
      filePath: filePath ?? this.filePath,
      totalBytes: totalBytes ?? this.totalBytes,
      doneBytes: doneBytes ?? this.doneBytes,
      state: state ?? this.state,
      error: error ?? this.error,
      subtitlesJson: subtitlesJson ?? this.subtitlesJson,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (mediaId.present) {
      map['media_id'] = Variable<String>(mediaId.value);
    }
    if (videoId.present) {
      map['video_id'] = Variable<String>(videoId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (episodeTitle.present) {
      map['episode_title'] = Variable<String>(episodeTitle.value);
    }
    if (season.present) {
      map['season'] = Variable<int>(season.value);
    }
    if (episode.present) {
      map['episode'] = Variable<int>(episode.value);
    }
    if (poster.present) {
      map['poster'] = Variable<String>(poster.value);
    }
    if (still.present) {
      map['still'] = Variable<String>(still.value);
    }
    if (releaseName.present) {
      map['release_name'] = Variable<String>(releaseName.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (infoHash.present) {
      map['info_hash'] = Variable<String>(infoHash.value);
    }
    if (fileIndex.present) {
      map['file_index'] = Variable<int>(fileIndex.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (magnet.present) {
      map['magnet'] = Variable<String>(magnet.value);
    }
    if (directory.present) {
      map['directory'] = Variable<String>(directory.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (totalBytes.present) {
      map['total_bytes'] = Variable<int>(totalBytes.value);
    }
    if (doneBytes.present) {
      map['done_bytes'] = Variable<int>(doneBytes.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (subtitlesJson.present) {
      map['subtitles_json'] = Variable<String>(subtitlesJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DownloadsCompanion(')
          ..write('id: $id, ')
          ..write('mediaId: $mediaId, ')
          ..write('videoId: $videoId, ')
          ..write('type: $type, ')
          ..write('title: $title, ')
          ..write('episodeTitle: $episodeTitle, ')
          ..write('season: $season, ')
          ..write('episode: $episode, ')
          ..write('poster: $poster, ')
          ..write('still: $still, ')
          ..write('releaseName: $releaseName, ')
          ..write('kind: $kind, ')
          ..write('infoHash: $infoHash, ')
          ..write('fileIndex: $fileIndex, ')
          ..write('url: $url, ')
          ..write('magnet: $magnet, ')
          ..write('directory: $directory, ')
          ..write('filePath: $filePath, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('doneBytes: $doneBytes, ')
          ..write('state: $state, ')
          ..write('error: $error, ')
          ..write('subtitlesJson: $subtitlesJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $KeyValuesTable extends KeyValues
    with TableInfo<$KeyValuesTable, KeyValue> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KeyValuesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'key_values';
  @override
  VerificationContext validateIntegrity(
    Insertable<KeyValue> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  KeyValue map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KeyValue(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $KeyValuesTable createAlias(String alias) {
    return $KeyValuesTable(attachedDatabase, alias);
  }
}

class KeyValue extends DataClass implements Insertable<KeyValue> {
  final String key;
  final String value;
  const KeyValue({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  KeyValuesCompanion toCompanion(bool nullToAbsent) {
    return KeyValuesCompanion(key: Value(key), value: Value(value));
  }

  factory KeyValue.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KeyValue(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  KeyValue copyWith({String? key, String? value}) =>
      KeyValue(key: key ?? this.key, value: value ?? this.value);
  KeyValue copyWithCompanion(KeyValuesCompanion data) {
    return KeyValue(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KeyValue(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KeyValue && other.key == this.key && other.value == this.value);
}

class KeyValuesCompanion extends UpdateCompanion<KeyValue> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const KeyValuesCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KeyValuesCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<KeyValue> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KeyValuesCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return KeyValuesCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KeyValuesCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SearchHistoryTable extends SearchHistory
    with TableInfo<$SearchHistoryTable, SearchHistoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SearchHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _queryMeta = const VerificationMeta('query');
  @override
  late final GeneratedColumn<String> query = GeneratedColumn<String>(
    'query',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _atMeta = const VerificationMeta('at');
  @override
  late final GeneratedColumn<DateTime> at = GeneratedColumn<DateTime>(
    'at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [query, at];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'search_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<SearchHistoryData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('query')) {
      context.handle(
        _queryMeta,
        query.isAcceptableOrUnknown(data['query']!, _queryMeta),
      );
    } else if (isInserting) {
      context.missing(_queryMeta);
    }
    if (data.containsKey('at')) {
      context.handle(_atMeta, at.isAcceptableOrUnknown(data['at']!, _atMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {query};
  @override
  SearchHistoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SearchHistoryData(
      query: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}query'],
      )!,
      at: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}at'],
      )!,
    );
  }

  @override
  $SearchHistoryTable createAlias(String alias) {
    return $SearchHistoryTable(attachedDatabase, alias);
  }
}

class SearchHistoryData extends DataClass
    implements Insertable<SearchHistoryData> {
  final String query;
  final DateTime at;
  const SearchHistoryData({required this.query, required this.at});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['query'] = Variable<String>(query);
    map['at'] = Variable<DateTime>(at);
    return map;
  }

  SearchHistoryCompanion toCompanion(bool nullToAbsent) {
    return SearchHistoryCompanion(query: Value(query), at: Value(at));
  }

  factory SearchHistoryData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SearchHistoryData(
      query: serializer.fromJson<String>(json['query']),
      at: serializer.fromJson<DateTime>(json['at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'query': serializer.toJson<String>(query),
      'at': serializer.toJson<DateTime>(at),
    };
  }

  SearchHistoryData copyWith({String? query, DateTime? at}) =>
      SearchHistoryData(query: query ?? this.query, at: at ?? this.at);
  SearchHistoryData copyWithCompanion(SearchHistoryCompanion data) {
    return SearchHistoryData(
      query: data.query.present ? data.query.value : this.query,
      at: data.at.present ? data.at.value : this.at,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SearchHistoryData(')
          ..write('query: $query, ')
          ..write('at: $at')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(query, at);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SearchHistoryData &&
          other.query == this.query &&
          other.at == this.at);
}

class SearchHistoryCompanion extends UpdateCompanion<SearchHistoryData> {
  final Value<String> query;
  final Value<DateTime> at;
  final Value<int> rowid;
  const SearchHistoryCompanion({
    this.query = const Value.absent(),
    this.at = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SearchHistoryCompanion.insert({
    required String query,
    this.at = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : query = Value(query);
  static Insertable<SearchHistoryData> custom({
    Expression<String>? query,
    Expression<DateTime>? at,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (query != null) 'query': query,
      if (at != null) 'at': at,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SearchHistoryCompanion copyWith({
    Value<String>? query,
    Value<DateTime>? at,
    Value<int>? rowid,
  }) {
    return SearchHistoryCompanion(
      query: query ?? this.query,
      at: at ?? this.at,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (query.present) {
      map['query'] = Variable<String>(query.value);
    }
    if (at.present) {
      map['at'] = Variable<DateTime>(at.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SearchHistoryCompanion(')
          ..write('query: $query, ')
          ..write('at: $at, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $AddonsTable addons = $AddonsTable(this);
  late final $LibraryItemsTable libraryItems = $LibraryItemsTable(this);
  late final $WatchProgressTable watchProgress = $WatchProgressTable(this);
  late final $TrackMemoryTable trackMemory = $TrackMemoryTable(this);
  late final $DownloadsTable downloads = $DownloadsTable(this);
  late final $KeyValuesTable keyValues = $KeyValuesTable(this);
  late final $SearchHistoryTable searchHistory = $SearchHistoryTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    addons,
    libraryItems,
    watchProgress,
    trackMemory,
    downloads,
    keyValues,
    searchHistory,
  ];
}

typedef $$AddonsTableCreateCompanionBuilder = AddonsCompanion Function({
  Value<int> id,
  required String transportUrl,
  required String manifestJson,
  Value<bool> enabled,
  Value<int> position,
  Value<DateTime> addedAt,
});
typedef $$AddonsTableUpdateCompanionBuilder = AddonsCompanion Function({
  Value<int> id,
  Value<String> transportUrl,
  Value<String> manifestJson,
  Value<bool> enabled,
  Value<int> position,
  Value<DateTime> addedAt,
});

class $$AddonsTableFilterComposer
    extends Composer<_$AppDatabase, $AddonsTable> {
  $$AddonsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get transportUrl => $composableBuilder(
    column: $table.transportUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get manifestJson => $composableBuilder(
    column: $table.manifestJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AddonsTableOrderingComposer
    extends Composer<_$AppDatabase, $AddonsTable> {
  $$AddonsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get transportUrl => $composableBuilder(
    column: $table.transportUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get manifestJson => $composableBuilder(
    column: $table.manifestJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AddonsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AddonsTable> {
  $$AddonsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get transportUrl => $composableBuilder(
    column: $table.transportUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get manifestJson => $composableBuilder(
    column: $table.manifestJson,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$AddonsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AddonsTable,
          Addon,
          $$AddonsTableFilterComposer,
          $$AddonsTableOrderingComposer,
          $$AddonsTableAnnotationComposer,
          $$AddonsTableCreateCompanionBuilder,
          $$AddonsTableUpdateCompanionBuilder,
          (Addon, BaseReferences<_$AppDatabase, $AddonsTable, Addon>),
          Addon,
          PrefetchHooks Function()
        > {
  $$AddonsTableTableManager(_$AppDatabase db, $AddonsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AddonsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AddonsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AddonsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> transportUrl = const Value.absent(),
                Value<String> manifestJson = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
              }) => AddonsCompanion(
                id: id,
                transportUrl: transportUrl,
                manifestJson: manifestJson,
                enabled: enabled,
                position: position,
                addedAt: addedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String transportUrl,
                required String manifestJson,
                Value<bool> enabled = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
              }) => AddonsCompanion.insert(
                id: id,
                transportUrl: transportUrl,
                manifestJson: manifestJson,
                enabled: enabled,
                position: position,
                addedAt: addedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AddonsTable, Addon>(table),
                  BaseReferences<_$AppDatabase, $AddonsTable, Addon>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AddonsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AddonsTable,
      Addon,
      $$AddonsTableFilterComposer,
      $$AddonsTableOrderingComposer,
      $$AddonsTableAnnotationComposer,
      $$AddonsTableCreateCompanionBuilder,
      $$AddonsTableUpdateCompanionBuilder,
      (Addon, BaseReferences<_$AppDatabase, $AddonsTable, Addon>),
      Addon,
      PrefetchHooks Function()
    >;
typedef $$LibraryItemsTableCreateCompanionBuilder =
    LibraryItemsCompanion Function({
      required String mediaId,
      required String type,
      required String name,
      Value<String?> poster,
      Value<String?> background,
      Value<DateTime> addedAt,
      Value<int> rowid,
    });
typedef $$LibraryItemsTableUpdateCompanionBuilder =
    LibraryItemsCompanion Function({
      Value<String> mediaId,
      Value<String> type,
      Value<String> name,
      Value<String?> poster,
      Value<String?> background,
      Value<DateTime> addedAt,
      Value<int> rowid,
    });

class $$LibraryItemsTableFilterComposer
    extends Composer<_$AppDatabase, $LibraryItemsTable> {
  $$LibraryItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get mediaId => $composableBuilder(
    column: $table.mediaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get poster => $composableBuilder(
    column: $table.poster,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get background => $composableBuilder(
    column: $table.background,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LibraryItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $LibraryItemsTable> {
  $$LibraryItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get mediaId => $composableBuilder(
    column: $table.mediaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get poster => $composableBuilder(
    column: $table.poster,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get background => $composableBuilder(
    column: $table.background,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LibraryItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LibraryItemsTable> {
  $$LibraryItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get mediaId =>
      $composableBuilder(column: $table.mediaId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get poster =>
      $composableBuilder(column: $table.poster, builder: (column) => column);

  GeneratedColumn<String> get background => $composableBuilder(
    column: $table.background,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$LibraryItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LibraryItemsTable,
          LibraryItem,
          $$LibraryItemsTableFilterComposer,
          $$LibraryItemsTableOrderingComposer,
          $$LibraryItemsTableAnnotationComposer,
          $$LibraryItemsTableCreateCompanionBuilder,
          $$LibraryItemsTableUpdateCompanionBuilder,
          (
            LibraryItem,
            BaseReferences<_$AppDatabase, $LibraryItemsTable, LibraryItem>,
          ),
          LibraryItem,
          PrefetchHooks Function()
        > {
  $$LibraryItemsTableTableManager(_$AppDatabase db, $LibraryItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LibraryItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LibraryItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LibraryItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> mediaId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> poster = const Value.absent(),
                Value<String?> background = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LibraryItemsCompanion(
                mediaId: mediaId,
                type: type,
                name: name,
                poster: poster,
                background: background,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String mediaId,
                required String type,
                required String name,
                Value<String?> poster = const Value.absent(),
                Value<String?> background = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LibraryItemsCompanion.insert(
                mediaId: mediaId,
                type: type,
                name: name,
                poster: poster,
                background: background,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LibraryItemsTable, LibraryItem>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $LibraryItemsTable,
                    LibraryItem
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LibraryItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LibraryItemsTable,
      LibraryItem,
      $$LibraryItemsTableFilterComposer,
      $$LibraryItemsTableOrderingComposer,
      $$LibraryItemsTableAnnotationComposer,
      $$LibraryItemsTableCreateCompanionBuilder,
      $$LibraryItemsTableUpdateCompanionBuilder,
      (
        LibraryItem,
        BaseReferences<_$AppDatabase, $LibraryItemsTable, LibraryItem>,
      ),
      LibraryItem,
      PrefetchHooks Function()
    >;
typedef $$WatchProgressTableCreateCompanionBuilder =
    WatchProgressCompanion Function({
      required String videoId,
      required String mediaId,
      required String type,
      required String name,
      Value<String?> episodeTitle,
      Value<int?> season,
      Value<int?> episode,
      required int positionMs,
      required int durationMs,
      Value<bool> completed,
      Value<String?> poster,
      Value<String?> still,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$WatchProgressTableUpdateCompanionBuilder =
    WatchProgressCompanion Function({
      Value<String> videoId,
      Value<String> mediaId,
      Value<String> type,
      Value<String> name,
      Value<String?> episodeTitle,
      Value<int?> season,
      Value<int?> episode,
      Value<int> positionMs,
      Value<int> durationMs,
      Value<bool> completed,
      Value<String?> poster,
      Value<String?> still,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$WatchProgressTableFilterComposer
    extends Composer<_$AppDatabase, $WatchProgressTable> {
  $$WatchProgressTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get videoId => $composableBuilder(
    column: $table.videoId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaId => $composableBuilder(
    column: $table.mediaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get episodeTitle => $composableBuilder(
    column: $table.episodeTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get season => $composableBuilder(
    column: $table.season,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get episode => $composableBuilder(
    column: $table.episode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get poster => $composableBuilder(
    column: $table.poster,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get still => $composableBuilder(
    column: $table.still,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WatchProgressTableOrderingComposer
    extends Composer<_$AppDatabase, $WatchProgressTable> {
  $$WatchProgressTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get videoId => $composableBuilder(
    column: $table.videoId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaId => $composableBuilder(
    column: $table.mediaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get episodeTitle => $composableBuilder(
    column: $table.episodeTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get season => $composableBuilder(
    column: $table.season,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get episode => $composableBuilder(
    column: $table.episode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get poster => $composableBuilder(
    column: $table.poster,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get still => $composableBuilder(
    column: $table.still,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WatchProgressTableAnnotationComposer
    extends Composer<_$AppDatabase, $WatchProgressTable> {
  $$WatchProgressTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get videoId =>
      $composableBuilder(column: $table.videoId, builder: (column) => column);

  GeneratedColumn<String> get mediaId =>
      $composableBuilder(column: $table.mediaId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get episodeTitle => $composableBuilder(
    column: $table.episodeTitle,
    builder: (column) => column,
  );

  GeneratedColumn<int> get season =>
      $composableBuilder(column: $table.season, builder: (column) => column);

  GeneratedColumn<int> get episode =>
      $composableBuilder(column: $table.episode, builder: (column) => column);

  GeneratedColumn<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get completed =>
      $composableBuilder(column: $table.completed, builder: (column) => column);

  GeneratedColumn<String> get poster =>
      $composableBuilder(column: $table.poster, builder: (column) => column);

  GeneratedColumn<String> get still =>
      $composableBuilder(column: $table.still, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$WatchProgressTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WatchProgressTable,
          WatchProgressData,
          $$WatchProgressTableFilterComposer,
          $$WatchProgressTableOrderingComposer,
          $$WatchProgressTableAnnotationComposer,
          $$WatchProgressTableCreateCompanionBuilder,
          $$WatchProgressTableUpdateCompanionBuilder,
          (
            WatchProgressData,
            BaseReferences<
              _$AppDatabase,
              $WatchProgressTable,
              WatchProgressData
            >,
          ),
          WatchProgressData,
          PrefetchHooks Function()
        > {
  $$WatchProgressTableTableManager(_$AppDatabase db, $WatchProgressTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WatchProgressTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WatchProgressTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WatchProgressTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> videoId = const Value.absent(),
                Value<String> mediaId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> episodeTitle = const Value.absent(),
                Value<int?> season = const Value.absent(),
                Value<int?> episode = const Value.absent(),
                Value<int> positionMs = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<bool> completed = const Value.absent(),
                Value<String?> poster = const Value.absent(),
                Value<String?> still = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WatchProgressCompanion(
                videoId: videoId,
                mediaId: mediaId,
                type: type,
                name: name,
                episodeTitle: episodeTitle,
                season: season,
                episode: episode,
                positionMs: positionMs,
                durationMs: durationMs,
                completed: completed,
                poster: poster,
                still: still,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String videoId,
                required String mediaId,
                required String type,
                required String name,
                Value<String?> episodeTitle = const Value.absent(),
                Value<int?> season = const Value.absent(),
                Value<int?> episode = const Value.absent(),
                required int positionMs,
                required int durationMs,
                Value<bool> completed = const Value.absent(),
                Value<String?> poster = const Value.absent(),
                Value<String?> still = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WatchProgressCompanion.insert(
                videoId: videoId,
                mediaId: mediaId,
                type: type,
                name: name,
                episodeTitle: episodeTitle,
                season: season,
                episode: episode,
                positionMs: positionMs,
                durationMs: durationMs,
                completed: completed,
                poster: poster,
                still: still,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WatchProgressTable, WatchProgressData>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $WatchProgressTable,
                    WatchProgressData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WatchProgressTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WatchProgressTable,
      WatchProgressData,
      $$WatchProgressTableFilterComposer,
      $$WatchProgressTableOrderingComposer,
      $$WatchProgressTableAnnotationComposer,
      $$WatchProgressTableCreateCompanionBuilder,
      $$WatchProgressTableUpdateCompanionBuilder,
      (
        WatchProgressData,
        BaseReferences<_$AppDatabase, $WatchProgressTable, WatchProgressData>,
      ),
      WatchProgressData,
      PrefetchHooks Function()
    >;
typedef $$TrackMemoryTableCreateCompanionBuilder =
    TrackMemoryCompanion Function({
      required String key,
      Value<String?> audioLanguage,
      Value<String?> audioTrackId,
      Value<String?> subtitleLanguage,
      Value<String?> subtitleVariant,
      Value<String?> subtitleId,
      Value<int> subtitleOffsetMs,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$TrackMemoryTableUpdateCompanionBuilder =
    TrackMemoryCompanion Function({
      Value<String> key,
      Value<String?> audioLanguage,
      Value<String?> audioTrackId,
      Value<String?> subtitleLanguage,
      Value<String?> subtitleVariant,
      Value<String?> subtitleId,
      Value<int> subtitleOffsetMs,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$TrackMemoryTableFilterComposer
    extends Composer<_$AppDatabase, $TrackMemoryTable> {
  $$TrackMemoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get audioLanguage => $composableBuilder(
    column: $table.audioLanguage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get audioTrackId => $composableBuilder(
    column: $table.audioTrackId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subtitleLanguage => $composableBuilder(
    column: $table.subtitleLanguage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subtitleVariant => $composableBuilder(
    column: $table.subtitleVariant,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subtitleId => $composableBuilder(
    column: $table.subtitleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get subtitleOffsetMs => $composableBuilder(
    column: $table.subtitleOffsetMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TrackMemoryTableOrderingComposer
    extends Composer<_$AppDatabase, $TrackMemoryTable> {
  $$TrackMemoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get audioLanguage => $composableBuilder(
    column: $table.audioLanguage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get audioTrackId => $composableBuilder(
    column: $table.audioTrackId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subtitleLanguage => $composableBuilder(
    column: $table.subtitleLanguage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subtitleVariant => $composableBuilder(
    column: $table.subtitleVariant,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subtitleId => $composableBuilder(
    column: $table.subtitleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get subtitleOffsetMs => $composableBuilder(
    column: $table.subtitleOffsetMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TrackMemoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $TrackMemoryTable> {
  $$TrackMemoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get audioLanguage => $composableBuilder(
    column: $table.audioLanguage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get audioTrackId => $composableBuilder(
    column: $table.audioTrackId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get subtitleLanguage => $composableBuilder(
    column: $table.subtitleLanguage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get subtitleVariant => $composableBuilder(
    column: $table.subtitleVariant,
    builder: (column) => column,
  );

  GeneratedColumn<String> get subtitleId => $composableBuilder(
    column: $table.subtitleId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get subtitleOffsetMs => $composableBuilder(
    column: $table.subtitleOffsetMs,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$TrackMemoryTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TrackMemoryTable,
          TrackMemoryData,
          $$TrackMemoryTableFilterComposer,
          $$TrackMemoryTableOrderingComposer,
          $$TrackMemoryTableAnnotationComposer,
          $$TrackMemoryTableCreateCompanionBuilder,
          $$TrackMemoryTableUpdateCompanionBuilder,
          (
            TrackMemoryData,
            BaseReferences<_$AppDatabase, $TrackMemoryTable, TrackMemoryData>,
          ),
          TrackMemoryData,
          PrefetchHooks Function()
        > {
  $$TrackMemoryTableTableManager(_$AppDatabase db, $TrackMemoryTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TrackMemoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TrackMemoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TrackMemoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String?> audioLanguage = const Value.absent(),
                Value<String?> audioTrackId = const Value.absent(),
                Value<String?> subtitleLanguage = const Value.absent(),
                Value<String?> subtitleVariant = const Value.absent(),
                Value<String?> subtitleId = const Value.absent(),
                Value<int> subtitleOffsetMs = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TrackMemoryCompanion(
                key: key,
                audioLanguage: audioLanguage,
                audioTrackId: audioTrackId,
                subtitleLanguage: subtitleLanguage,
                subtitleVariant: subtitleVariant,
                subtitleId: subtitleId,
                subtitleOffsetMs: subtitleOffsetMs,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                Value<String?> audioLanguage = const Value.absent(),
                Value<String?> audioTrackId = const Value.absent(),
                Value<String?> subtitleLanguage = const Value.absent(),
                Value<String?> subtitleVariant = const Value.absent(),
                Value<String?> subtitleId = const Value.absent(),
                Value<int> subtitleOffsetMs = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TrackMemoryCompanion.insert(
                key: key,
                audioLanguage: audioLanguage,
                audioTrackId: audioTrackId,
                subtitleLanguage: subtitleLanguage,
                subtitleVariant: subtitleVariant,
                subtitleId: subtitleId,
                subtitleOffsetMs: subtitleOffsetMs,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TrackMemoryTable, TrackMemoryData>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $TrackMemoryTable,
                    TrackMemoryData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TrackMemoryTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TrackMemoryTable,
      TrackMemoryData,
      $$TrackMemoryTableFilterComposer,
      $$TrackMemoryTableOrderingComposer,
      $$TrackMemoryTableAnnotationComposer,
      $$TrackMemoryTableCreateCompanionBuilder,
      $$TrackMemoryTableUpdateCompanionBuilder,
      (
        TrackMemoryData,
        BaseReferences<_$AppDatabase, $TrackMemoryTable, TrackMemoryData>,
      ),
      TrackMemoryData,
      PrefetchHooks Function()
    >;
typedef $$DownloadsTableCreateCompanionBuilder = DownloadsCompanion Function({
  required String id,
  required String mediaId,
  required String videoId,
  required String type,
  required String title,
  Value<String?> episodeTitle,
  Value<int?> season,
  Value<int?> episode,
  Value<String?> poster,
  Value<String?> still,
  required String releaseName,
  required String kind,
  Value<String?> infoHash,
  Value<int?> fileIndex,
  Value<String?> url,
  Value<String?> magnet,
  required String directory,
  Value<String?> filePath,
  Value<int> totalBytes,
  Value<int> doneBytes,
  required String state,
  Value<String?> error,
  Value<String> subtitlesJson,
  Value<DateTime> createdAt,
  Value<DateTime?> completedAt,
  Value<int> rowid,
});
typedef $$DownloadsTableUpdateCompanionBuilder = DownloadsCompanion Function({
  Value<String> id,
  Value<String> mediaId,
  Value<String> videoId,
  Value<String> type,
  Value<String> title,
  Value<String?> episodeTitle,
  Value<int?> season,
  Value<int?> episode,
  Value<String?> poster,
  Value<String?> still,
  Value<String> releaseName,
  Value<String> kind,
  Value<String?> infoHash,
  Value<int?> fileIndex,
  Value<String?> url,
  Value<String?> magnet,
  Value<String> directory,
  Value<String?> filePath,
  Value<int> totalBytes,
  Value<int> doneBytes,
  Value<String> state,
  Value<String?> error,
  Value<String> subtitlesJson,
  Value<DateTime> createdAt,
  Value<DateTime?> completedAt,
  Value<int> rowid,
});

class $$DownloadsTableFilterComposer
    extends Composer<_$AppDatabase, $DownloadsTable> {
  $$DownloadsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaId => $composableBuilder(
    column: $table.mediaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get videoId => $composableBuilder(
    column: $table.videoId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get episodeTitle => $composableBuilder(
    column: $table.episodeTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get season => $composableBuilder(
    column: $table.season,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get episode => $composableBuilder(
    column: $table.episode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get poster => $composableBuilder(
    column: $table.poster,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get still => $composableBuilder(
    column: $table.still,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get releaseName => $composableBuilder(
    column: $table.releaseName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get infoHash => $composableBuilder(
    column: $table.infoHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileIndex => $composableBuilder(
    column: $table.fileIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get magnet => $composableBuilder(
    column: $table.magnet,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get directory => $composableBuilder(
    column: $table.directory,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get doneBytes => $composableBuilder(
    column: $table.doneBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subtitlesJson => $composableBuilder(
    column: $table.subtitlesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DownloadsTableOrderingComposer
    extends Composer<_$AppDatabase, $DownloadsTable> {
  $$DownloadsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaId => $composableBuilder(
    column: $table.mediaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get videoId => $composableBuilder(
    column: $table.videoId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get episodeTitle => $composableBuilder(
    column: $table.episodeTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get season => $composableBuilder(
    column: $table.season,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get episode => $composableBuilder(
    column: $table.episode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get poster => $composableBuilder(
    column: $table.poster,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get still => $composableBuilder(
    column: $table.still,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get releaseName => $composableBuilder(
    column: $table.releaseName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get infoHash => $composableBuilder(
    column: $table.infoHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileIndex => $composableBuilder(
    column: $table.fileIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get magnet => $composableBuilder(
    column: $table.magnet,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get directory => $composableBuilder(
    column: $table.directory,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get doneBytes => $composableBuilder(
    column: $table.doneBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subtitlesJson => $composableBuilder(
    column: $table.subtitlesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DownloadsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DownloadsTable> {
  $$DownloadsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get mediaId =>
      $composableBuilder(column: $table.mediaId, builder: (column) => column);

  GeneratedColumn<String> get videoId =>
      $composableBuilder(column: $table.videoId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get episodeTitle => $composableBuilder(
    column: $table.episodeTitle,
    builder: (column) => column,
  );

  GeneratedColumn<int> get season =>
      $composableBuilder(column: $table.season, builder: (column) => column);

  GeneratedColumn<int> get episode =>
      $composableBuilder(column: $table.episode, builder: (column) => column);

  GeneratedColumn<String> get poster =>
      $composableBuilder(column: $table.poster, builder: (column) => column);

  GeneratedColumn<String> get still =>
      $composableBuilder(column: $table.still, builder: (column) => column);

  GeneratedColumn<String> get releaseName => $composableBuilder(
    column: $table.releaseName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get infoHash =>
      $composableBuilder(column: $table.infoHash, builder: (column) => column);

  GeneratedColumn<int> get fileIndex =>
      $composableBuilder(column: $table.fileIndex, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get magnet =>
      $composableBuilder(column: $table.magnet, builder: (column) => column);

  GeneratedColumn<String> get directory =>
      $composableBuilder(column: $table.directory, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get doneBytes =>
      $composableBuilder(column: $table.doneBytes, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);

  GeneratedColumn<String> get subtitlesJson => $composableBuilder(
    column: $table.subtitlesJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );
}

class $$DownloadsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DownloadsTable,
          Download,
          $$DownloadsTableFilterComposer,
          $$DownloadsTableOrderingComposer,
          $$DownloadsTableAnnotationComposer,
          $$DownloadsTableCreateCompanionBuilder,
          $$DownloadsTableUpdateCompanionBuilder,
          (Download, BaseReferences<_$AppDatabase, $DownloadsTable, Download>),
          Download,
          PrefetchHooks Function()
        > {
  $$DownloadsTableTableManager(_$AppDatabase db, $DownloadsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DownloadsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DownloadsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DownloadsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> mediaId = const Value.absent(),
                Value<String> videoId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> episodeTitle = const Value.absent(),
                Value<int?> season = const Value.absent(),
                Value<int?> episode = const Value.absent(),
                Value<String?> poster = const Value.absent(),
                Value<String?> still = const Value.absent(),
                Value<String> releaseName = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String?> infoHash = const Value.absent(),
                Value<int?> fileIndex = const Value.absent(),
                Value<String?> url = const Value.absent(),
                Value<String?> magnet = const Value.absent(),
                Value<String> directory = const Value.absent(),
                Value<String?> filePath = const Value.absent(),
                Value<int> totalBytes = const Value.absent(),
                Value<int> doneBytes = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<String> subtitlesJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DownloadsCompanion(
                id: id,
                mediaId: mediaId,
                videoId: videoId,
                type: type,
                title: title,
                episodeTitle: episodeTitle,
                season: season,
                episode: episode,
                poster: poster,
                still: still,
                releaseName: releaseName,
                kind: kind,
                infoHash: infoHash,
                fileIndex: fileIndex,
                url: url,
                magnet: magnet,
                directory: directory,
                filePath: filePath,
                totalBytes: totalBytes,
                doneBytes: doneBytes,
                state: state,
                error: error,
                subtitlesJson: subtitlesJson,
                createdAt: createdAt,
                completedAt: completedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String mediaId,
                required String videoId,
                required String type,
                required String title,
                Value<String?> episodeTitle = const Value.absent(),
                Value<int?> season = const Value.absent(),
                Value<int?> episode = const Value.absent(),
                Value<String?> poster = const Value.absent(),
                Value<String?> still = const Value.absent(),
                required String releaseName,
                required String kind,
                Value<String?> infoHash = const Value.absent(),
                Value<int?> fileIndex = const Value.absent(),
                Value<String?> url = const Value.absent(),
                Value<String?> magnet = const Value.absent(),
                required String directory,
                Value<String?> filePath = const Value.absent(),
                Value<int> totalBytes = const Value.absent(),
                Value<int> doneBytes = const Value.absent(),
                required String state,
                Value<String?> error = const Value.absent(),
                Value<String> subtitlesJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DownloadsCompanion.insert(
                id: id,
                mediaId: mediaId,
                videoId: videoId,
                type: type,
                title: title,
                episodeTitle: episodeTitle,
                season: season,
                episode: episode,
                poster: poster,
                still: still,
                releaseName: releaseName,
                kind: kind,
                infoHash: infoHash,
                fileIndex: fileIndex,
                url: url,
                magnet: magnet,
                directory: directory,
                filePath: filePath,
                totalBytes: totalBytes,
                doneBytes: doneBytes,
                state: state,
                error: error,
                subtitlesJson: subtitlesJson,
                createdAt: createdAt,
                completedAt: completedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DownloadsTable, Download>(table),
                  BaseReferences<_$AppDatabase, $DownloadsTable, Download>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DownloadsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DownloadsTable,
      Download,
      $$DownloadsTableFilterComposer,
      $$DownloadsTableOrderingComposer,
      $$DownloadsTableAnnotationComposer,
      $$DownloadsTableCreateCompanionBuilder,
      $$DownloadsTableUpdateCompanionBuilder,
      (Download, BaseReferences<_$AppDatabase, $DownloadsTable, Download>),
      Download,
      PrefetchHooks Function()
    >;
typedef $$KeyValuesTableCreateCompanionBuilder = KeyValuesCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$KeyValuesTableUpdateCompanionBuilder = KeyValuesCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$KeyValuesTableFilterComposer
    extends Composer<_$AppDatabase, $KeyValuesTable> {
  $$KeyValuesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$KeyValuesTableOrderingComposer
    extends Composer<_$AppDatabase, $KeyValuesTable> {
  $$KeyValuesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$KeyValuesTableAnnotationComposer
    extends Composer<_$AppDatabase, $KeyValuesTable> {
  $$KeyValuesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$KeyValuesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $KeyValuesTable,
          KeyValue,
          $$KeyValuesTableFilterComposer,
          $$KeyValuesTableOrderingComposer,
          $$KeyValuesTableAnnotationComposer,
          $$KeyValuesTableCreateCompanionBuilder,
          $$KeyValuesTableUpdateCompanionBuilder,
          (KeyValue, BaseReferences<_$AppDatabase, $KeyValuesTable, KeyValue>),
          KeyValue,
          PrefetchHooks Function()
        > {
  $$KeyValuesTableTableManager(_$AppDatabase db, $KeyValuesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KeyValuesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KeyValuesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KeyValuesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => KeyValuesCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) => KeyValuesCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$KeyValuesTable, KeyValue>(table),
                  BaseReferences<_$AppDatabase, $KeyValuesTable, KeyValue>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$KeyValuesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $KeyValuesTable,
      KeyValue,
      $$KeyValuesTableFilterComposer,
      $$KeyValuesTableOrderingComposer,
      $$KeyValuesTableAnnotationComposer,
      $$KeyValuesTableCreateCompanionBuilder,
      $$KeyValuesTableUpdateCompanionBuilder,
      (KeyValue, BaseReferences<_$AppDatabase, $KeyValuesTable, KeyValue>),
      KeyValue,
      PrefetchHooks Function()
    >;
typedef $$SearchHistoryTableCreateCompanionBuilder =
    SearchHistoryCompanion Function({
      required String query,
      Value<DateTime> at,
      Value<int> rowid,
    });
typedef $$SearchHistoryTableUpdateCompanionBuilder =
    SearchHistoryCompanion Function({
      Value<String> query,
      Value<DateTime> at,
      Value<int> rowid,
    });

class $$SearchHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $SearchHistoryTable> {
  $$SearchHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get query => $composableBuilder(
    column: $table.query,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SearchHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $SearchHistoryTable> {
  $$SearchHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get query => $composableBuilder(
    column: $table.query,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SearchHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $SearchHistoryTable> {
  $$SearchHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get query =>
      $composableBuilder(column: $table.query, builder: (column) => column);

  GeneratedColumn<DateTime> get at =>
      $composableBuilder(column: $table.at, builder: (column) => column);
}

class $$SearchHistoryTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SearchHistoryTable,
          SearchHistoryData,
          $$SearchHistoryTableFilterComposer,
          $$SearchHistoryTableOrderingComposer,
          $$SearchHistoryTableAnnotationComposer,
          $$SearchHistoryTableCreateCompanionBuilder,
          $$SearchHistoryTableUpdateCompanionBuilder,
          (
            SearchHistoryData,
            BaseReferences<
              _$AppDatabase,
              $SearchHistoryTable,
              SearchHistoryData
            >,
          ),
          SearchHistoryData,
          PrefetchHooks Function()
        > {
  $$SearchHistoryTableTableManager(_$AppDatabase db, $SearchHistoryTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SearchHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SearchHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SearchHistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> query = const Value.absent(),
            Value<DateTime> at = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => SearchHistoryCompanion(query: query, at: at, rowid: rowid),
          createCompanionCallback:
              ({
                required String query,
                Value<DateTime> at = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SearchHistoryCompanion.insert(
                query: query,
                at: at,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SearchHistoryTable, SearchHistoryData>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SearchHistoryTable,
                    SearchHistoryData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SearchHistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SearchHistoryTable,
      SearchHistoryData,
      $$SearchHistoryTableFilterComposer,
      $$SearchHistoryTableOrderingComposer,
      $$SearchHistoryTableAnnotationComposer,
      $$SearchHistoryTableCreateCompanionBuilder,
      $$SearchHistoryTableUpdateCompanionBuilder,
      (
        SearchHistoryData,
        BaseReferences<_$AppDatabase, $SearchHistoryTable, SearchHistoryData>,
      ),
      SearchHistoryData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$AddonsTableTableManager get addons =>
      $$AddonsTableTableManager(_db, _db.addons);
  $$LibraryItemsTableTableManager get libraryItems =>
      $$LibraryItemsTableTableManager(_db, _db.libraryItems);
  $$WatchProgressTableTableManager get watchProgress =>
      $$WatchProgressTableTableManager(_db, _db.watchProgress);
  $$TrackMemoryTableTableManager get trackMemory =>
      $$TrackMemoryTableTableManager(_db, _db.trackMemory);
  $$DownloadsTableTableManager get downloads =>
      $$DownloadsTableTableManager(_db, _db.downloads);
  $$KeyValuesTableTableManager get keyValues =>
      $$KeyValuesTableTableManager(_db, _db.keyValues);
  $$SearchHistoryTableTableManager get searchHistory =>
      $$SearchHistoryTableTableManager(_db, _db.searchHistory);
}
