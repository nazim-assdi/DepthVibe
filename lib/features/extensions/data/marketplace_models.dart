enum MarketplacePackageType {
  depthVibe,
  premiereUxp,
  afterEffectsCep,
  afterEffectsUxpBeta,
}

class MarketplaceExtension {
  const MarketplaceExtension({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.publisherId,
    required this.publisherName,
    required this.keyId,
    required this.packageType,
    required this.targetHosts,
    required this.downloadUrl,
    required this.sha256,
    required this.releaseNotes,
    required this.minimumHostVersion,
  });

  final String id;
  final String name;
  final String version;
  final String description;
  final String publisherId;
  final String publisherName;
  final String keyId;
  final MarketplacePackageType packageType;
  final List<String> targetHosts;
  final Uri downloadUrl;
  final String sha256;
  final String releaseNotes;
  final String minimumHostVersion;

  factory MarketplaceExtension.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Marketplace entry must be an object.');
    }
    final json = <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
    final typeName = _readString(json['packageType'], 'packageType', 40);
    final packageType = switch (typeName) {
      'dvext' => MarketplacePackageType.depthVibe,
      'premiere-uxp' => MarketplacePackageType.premiereUxp,
      'after-effects-cep' => MarketplacePackageType.afterEffectsCep,
      'after-effects-uxp-beta' => MarketplacePackageType.afterEffectsUxpBeta,
      _ => throw FormatException('Unsupported package type: ' + typeName),
    };
    final rawHosts = json['targetHosts'];
    if (rawHosts is! List ||
        rawHosts.isEmpty ||
        rawHosts.length > 8 ||
        rawHosts.any((item) => item is! String)) {
      throw const FormatException('Invalid marketplace targetHosts.');
    }
    final downloadUrl = Uri.tryParse(
      _readString(json['downloadUrl'], 'downloadUrl', 2048),
    );
    if (downloadUrl == null || downloadUrl.scheme != 'https') {
      throw const FormatException('Marketplace downloads must use HTTPS.');
    }
    final digest = _readString(json['sha256'], 'sha256', 64).toLowerCase();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('Invalid SHA-256 package digest.');
    }
    final version = _readString(json['version'], 'version', 40);
    if (!RegExp(r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?
        .hasMatch(version)) {
      throw const FormatException('Marketplace version must be semver.');
    }
    return MarketplaceExtension(
      id: _readString(json['id'], 'id', 100),
      name: _readString(json['name'], 'name', 120),
      version: version,
      description: _readString(json['description'] ?? '', 'description', 800, allowEmpty: true),
      publisherId: _readString(json['publisherId'], 'publisherId', 80),
      publisherName: _readString(json['publisherName'], 'publisherName', 100),
      keyId: _readString(json['keyId'], 'keyId', 80),
      packageType: packageType,
      targetHosts: List.unmodifiable((rawHosts as List).cast<String>()),
      downloadUrl: downloadUrl,
      sha256: digest,
      releaseNotes: _readString(json['releaseNotes'] ?? '', 'releaseNotes', 4000, allowEmpty: true),
      minimumHostVersion:
          _readString(json['minimumHostVersion'] ?? '', 'minimumHostVersion', 40, allowEmpty: true),
    );
  }

  String get installLabel => switch (packageType) {
        MarketplacePackageType.depthVibe => 'Install to DepthVibe',
        MarketplacePackageType.premiereUxp => 'Open Premiere UXP installer',
        MarketplacePackageType.afterEffectsCep => 'Install After Effects CEP',
        MarketplacePackageType.afterEffectsUxpBeta =>
          'Open After Effects Beta UXP package',
      };
}

class SignedMarketplaceCatalog {
  const SignedMarketplaceCatalog({
    required this.publisherId,
    required this.keyId,
    required this.generatedAt,
    required this.entries,
    required this.signature,
    required this.canonicalPayload,
  });

  final String publisherId;
  final String keyId;
  final DateTime generatedAt;
  final List<MarketplaceExtension> entries;
  final String signature;
  final List<int> canonicalPayload;

  factory SignedMarketplaceCatalog.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Marketplace catalog must be an object.');
    }
    final json = <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
    if (json['format'] != 'DepthVibe.Marketplace' ||
        json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported marketplace catalog format.');
    }
    final rawEntries = json['entries'];
    if (rawEntries is! List || rawEntries.length > 2000) {
      throw const FormatException('Marketplace catalog entry count is invalid.');
    }
    final signature = _readString(json['signature'], 'signature', 256);
    final payload = Map<String, Object?>.from(json)..remove('signature');
    final entries = rawEntries
        .map(MarketplaceExtension.fromJson)
        .toList(growable: false);
    final entryIds = <String>{};
    for (final item in entries) {
      if (!entryIds.add(item.id)) {
        throw FormatException('Duplicate marketplace extension ID: ' + item.id);
      }
      if (item.publisherId != json['publisherId'] ||
          item.keyId != json['keyId']) {
        throw const FormatException(
          'All catalog entries must be signed by the catalog publisher key.',
        );
      }
    }
    return SignedMarketplaceCatalog(
      publisherId: _readString(json['publisherId'], 'publisherId', 80),
      keyId: _readString(json['keyId'], 'keyId', 80),
      generatedAt: DateTime.tryParse(
            _readString(json['generatedAt'], 'generatedAt', 48),
          )?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      entries: List.unmodifiable(entries),
      signature: signature,
      canonicalPayload: _canonicalJson(payload),
    );
  }
}

String _readString(
  Object? value,
  String name,
  int maxLength, {
  bool allowEmpty = false,
}) {
  if (value is! String ||
      value.length > maxLength ||
      (!allowEmpty && value.trim().isEmpty)) {
    throw FormatException('Invalid marketplace field: ' + name + '.');
  }
  return value.trim();
}

List<int> _canonicalJson(Object? value) {
  Object? sortValue(Object? item) {
    if (item is Map) {
      final keys = item.keys.whereType<String>().toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: sortValue(item[key]),
      };
    }
    if (item is List) return item.map(sortValue).toList();
    return item;
  }
  return utf8.encode(jsonEncode(sortValue(value)));
}
)
        .hasMatch(version)) {
      throw const FormatException('Marketplace version must be semver.');
    }
    return MarketplaceExtension(
      id: _readString(json['id'], 'id', 100),
      name: _readString(json['name'], 'name', 120),
      version: version,
      description: _readString(json['description'] ?? '', 'description', 800, allowEmpty: true),
      publisherId: _readString(json['publisherId'], 'publisherId', 80),
      publisherName: _readString(json['publisherName'], 'publisherName', 100),
      keyId: _readString(json['keyId'], 'keyId', 80),
      packageType: packageType,
      targetHosts: List.unmodifiable((rawHosts as List).cast<String>()),
      downloadUrl: downloadUrl,
      sha256: digest,
      releaseNotes: _readString(json['releaseNotes'] ?? '', 'releaseNotes', 4000, allowEmpty: true),
      minimumHostVersion:
          _readString(json['minimumHostVersion'] ?? '', 'minimumHostVersion', 40, allowEmpty: true),
    );
  }

  String get installLabel => switch (packageType) {
        MarketplacePackageType.depthVibe => 'Install to DepthVibe',
        MarketplacePackageType.premiereUxp => 'Open Premiere UXP installer',
        MarketplacePackageType.afterEffectsCep => 'Install After Effects CEP',
        MarketplacePackageType.afterEffectsUxpBeta =>
          'Open After Effects Beta UXP package',
      };
}

class SignedMarketplaceCatalog {
  const SignedMarketplaceCatalog({
    required this.publisherId,
    required this.keyId,
    required this.generatedAt,
    required this.entries,
    required this.signature,
    required this.canonicalPayload,
  });

  final String publisherId;
  final String keyId;
  final DateTime generatedAt;
  final List<MarketplaceExtension> entries;
  final String signature;
  final List<int> canonicalPayload;

  factory SignedMarketplaceCatalog.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Marketplace catalog must be an object.');
    }
    final json = <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
    if (json['format'] != 'DepthVibe.Marketplace' ||
        json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported marketplace catalog format.');
    }
    final rawEntries = json['entries'];
    if (rawEntries is! List || rawEntries.length > 2000) {
      throw const FormatException('Marketplace catalog entry count is invalid.');
    }
    final signature = _readString(json['signature'], 'signature', 256);
    final payload = Map<String, Object?>.from(json)..remove('signature');
    final entries = rawEntries
        .map(MarketplaceExtension.fromJson)
        .toList(growable: false);
    final entryIds = <String>{};
    for (final item in entries) {
      if (!entryIds.add(item.id)) {
        throw FormatException('Duplicate marketplace extension ID: ' + item.id);
      }
      if (item.publisherId != json['publisherId'] ||
          item.keyId != json['keyId']) {
        throw const FormatException(
          'All catalog entries must be signed by the catalog publisher key.',
        );
      }
    }
    return SignedMarketplaceCatalog(
      publisherId: _readString(json['publisherId'], 'publisherId', 80),
      keyId: _readString(json['keyId'], 'keyId', 80),
      generatedAt: DateTime.tryParse(
            _readString(json['generatedAt'], 'generatedAt', 48),
          )?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      entries: List.unmodifiable(entries),
      signature: signature,
      canonicalPayload: _canonicalJson(payload),
    );
  }
}

String _readString(
  Object? value,
  String name,
  int maxLength, {
  bool allowEmpty = false,
}) {
  if (value is! String ||
      value.length > maxLength ||
      (!allowEmpty && value.trim().isEmpty)) {
    throw FormatException('Invalid marketplace field: ' + name + '.');
  }
  return value.trim();
}

List<int> _canonicalJson(Object? value) {
  Object? sortValue(Object? item) {
    if (item is Map) {
      final keys = item.keys.whereType<String>().toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: sortValue(item[key]),
      };
    }
    if (item is List) return item.map(sortValue).toList();
    return item;
  }
  return utf8.encode(jsonEncode(sortValue(value)));
}
