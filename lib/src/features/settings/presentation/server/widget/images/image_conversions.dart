// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../../../../graphql/__generated__/schema.graphql.dart';

/// Which server map an editor edits: the global `downloadConversions` map or
/// the per-user `serveConversions` map.
enum ImageProcessingKind { download, serve }

/// WebUI's "Target mode" (`Settings.constants.ts`): an editor convenience
/// over the server shape, where a target starting with `http://` or
/// `https://` sends the image to an external converter service and any other
/// target is a MIME type the server converts to itself.
enum ImageConversionTargetMode { disabled, image, url }

const String defaultMimeType = 'default';
const String mimeTypePrefix = 'image/';
const String targetDisabled = 'none';

const double compressionMin = 0;
const double compressionMax = 1;

/// Bounds from `Settings.constants.ts` (`IMAGE_PROCESSING_CALL_TIMEOUT` and
/// `IMAGE_PROCESSING_CONNECT_TIMEOUT`): 10 seconds to 10 minutes.
const int conversionTimeoutMinSeconds = 10;
const int conversionTimeoutMaxSeconds = 600;

int _nextId = 0;

/// Fresh stable id for rules and key/value rows added in the editor.
int freshEditorId() => _nextId++;

/// One `Name`/`Value` row of WebUI's `Search parameters` / `Headers` lists.
class ConversionKeyValue {
  ConversionKeyValue({required this.id, required this.name, required this.value});

  final int id;
  String name;
  String value;

  ConversionKeyValue copy() =>
      ConversionKeyValue(id: id, name: name, value: value);
}

/// One server conversion, as the fragments deliver it. The three GraphQL
/// sources (download fragment, account `serveConversions`, legacy serve
/// fragment) share this shape, so the repositories map to it first and the
/// editor mapping below only exists once.
class ServerConversion {
  ServerConversion({
    required this.mimeType,
    required this.target,
    this.compressionLevel,
    this.callTimeout,
    this.connectTimeout,
    this.headers,
  });

  final String mimeType;
  final String target;
  final double? compressionLevel;
  final String? callTimeout;
  final String? connectTimeout;
  final List<ServerConversionHeader>? headers;
}

class ServerConversionHeader {
  ServerConversionHeader({required this.name, required this.value});

  final String name;
  final String value;
}

/// One editable rule, mirroring WebUI's `TSettingsDownloadConversion`.
class ImageConversion {
  ImageConversion({
    required this.id,
    required this.mimeType,
    required this.target,
    required this.mode,
    this.compressionLevel,
    this.callTimeout,
    this.connectTimeout,
    this.headers,
    List<ConversionKeyValue>? searchParams,
  }) : searchParams = searchParams ?? [];

  final int id;
  String mimeType;
  String target;
  ImageConversionTargetMode mode;
  double? compressionLevel;

  /// ISO-8601 durations, exactly as the server sends them (`PT30S`).
  String? callTimeout;
  String? connectTimeout;
  List<ConversionKeyValue>? headers;
  List<ConversionKeyValue> searchParams;

  ImageConversion copy() => ImageConversion(
    id: id,
    mimeType: mimeType,
    target: target,
    mode: mode,
    compressionLevel: compressionLevel,
    callTimeout: callTimeout,
    connectTimeout: connectTimeout,
    headers: headers?.map((h) => h.copy()).toList(),
    searchParams: searchParams.map((p) => p.copy()).toList(),
  );
}

String normalizeMimeType(String mimeType) =>
    mimeType.startsWith(mimeTypePrefix)
        ? mimeType.substring(mimeTypePrefix.length)
        : mimeType;

bool isDefaultMimeType(String mimeType) =>
    normalizeMimeType(mimeType.toLowerCase().trim()) == defaultMimeType;

bool isUrlTargetMode(String target) =>
    target.isNotEmpty &&
    RegExp(r'^https?://.+').hasMatch(normalizeMimeType(target));

bool isDuplicateConversion(String mimeType, int index, List<ImageConversion> conversions) {
  for (var i = 0; i < index; i++) {
    if (conversions[i].mimeType == mimeType) return true;
  }
  return false;
}

bool isDuplicateKeyValueItem(String name, int index, List<ConversionKeyValue>? items) {
  if (items == null) return false;
  for (var i = 0; i < index; i++) {
    if (items[i].name == name) return true;
  }
  return false;
}

bool _isValidNumberSetting(num? value, num min, num max) =>
    value == null || (value >= min && value <= max);

/// Seconds of an ISO-8601 duration (`PT30S`, `PT10M`, `PT1H30M`), null when
/// absent or unparsable (unparsable counts as unset, like WebUI's koration
/// parse falling back to null through the number check).
int? isoDurationSeconds(String? timeout) {
  if (timeout == null || timeout.isEmpty) return null;
  final match = RegExp(
    r'^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?$',
  ).firstMatch(timeout);
  if (match == null) return null;
  if (match.group(1) == null &&
      match.group(2) == null &&
      match.group(3) == null) {
    return null;
  }
  final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
  final minutes = int.tryParse(match.group(2) ?? '0') ?? 0;
  final seconds = double.tryParse(match.group(3) ?? '0') ?? 0;
  return hours * 3600 + minutes * 60 + seconds.floor();
}

String isoDuration(int seconds) => 'PT${seconds}S';

bool isValidCallTimeoutSetting(String? timeout) => _isValidNumberSetting(
  isoDurationSeconds(timeout),
  conversionTimeoutMinSeconds,
  conversionTimeoutMaxSeconds,
);

bool isValidConnectTimeoutSetting(String? timeout) => _isValidNumberSetting(
  isoDurationSeconds(timeout),
  conversionTimeoutMinSeconds,
  conversionTimeoutMaxSeconds,
);

bool isValidCompressionLevel(double? compression) =>
    _isValidNumberSetting(compression, compressionMin, compressionMax);

bool _isUnsetConversion(String mimeType, String target) =>
    mimeType.isEmpty && target.isEmpty;

bool _isInvalidTarget(
  String target,
  ImageConversionTargetMode mode,
  String mimeType,
) {
  if (isDefaultMimeType(mimeType) && target.isEmpty) return false;
  return mode == ImageConversionTargetMode.url && !isUrlTargetMode(target);
}

/// Mirrors WebUI's `containsInvalidConversion` item predicate: an unset
/// rule, a non-URL target in URL mode, an out-of-range compression or
/// timeout, a duplicate MIME type, or duplicate header/search-param names
/// blocks Save.
bool imageConversionIsInvalid(
  ImageConversion conversion,
  int index,
  List<ImageConversion> conversions,
) {
  if (_isUnsetConversion(conversion.mimeType, conversion.target)) return true;
  if (_isInvalidTarget(conversion.target, conversion.mode, conversion.mimeType)) {
    return true;
  }
  if (!isValidCompressionLevel(conversion.compressionLevel)) return true;
  if (!isValidCallTimeoutSetting(conversion.callTimeout)) return true;
  if (!isValidConnectTimeoutSetting(conversion.connectTimeout)) return true;
  if (isDuplicateConversion(conversion.mimeType, index, conversions)) {
    return true;
  }
  final headers = conversion.headers;
  if (headers != null) {
    for (var i = 0; i < headers.length; i++) {
      if (isDuplicateKeyValueItem(headers[i].name, i, headers)) return true;
    }
  }
  for (var i = 0; i < conversion.searchParams.length; i++) {
    if (isDuplicateKeyValueItem(
      conversion.searchParams[i].name,
      i,
      conversion.searchParams,
    )) {
      return true;
    }
  }
  return false;
}

bool imageConversionsAreInvalid(List<ImageConversion> conversions) {
  for (var i = 0; i < conversions.length; i++) {
    if (imageConversionIsInvalid(conversions[i], i, conversions)) return true;
  }
  return false;
}

ImageConversionTargetMode getTargetMode(String target) {
  final normalized = normalizeMimeType(target);
  if (normalized == targetDisabled) return ImageConversionTargetMode.disabled;
  if (isUrlTargetMode(normalized)) return ImageConversionTargetMode.url;
  return ImageConversionTargetMode.image;
}

/// Query pairs embedded in a URL-mode target, as `Name`/`Value` rows.
/// Repeated keys are kept (flattened, in order) so a duplicated name shows
/// up and is flagged invalid, as in WebUI.
List<({String name, String value})> extractSearchParams(String url) {
  final parsed = Uri.tryParse(url);
  if (parsed == null) return const [];
  return parsed.queryParametersAll.entries
      .expand((e) => e.value.map((v) => (name: e.key, value: v)))
      .toList();
}

/// Raw editor text for the compression field: empty means unset, anything
/// else must parse to an in-range level. Unparsable text is invalid (and
/// blocks Save) instead of being silently dropped.
bool isValidCompressionText(String text) {
  if (text.isEmpty) return true;
  final value = double.tryParse(text);
  return value != null && isValidCompressionLevel(value);
}

/// Raw editor text for a timeout field (whole seconds): empty means unset,
/// anything else must parse to an in-range whole number.
bool isValidTimeoutText(String text) {
  if (text.isEmpty) return true;
  final value = int.tryParse(text);
  return value != null &&
      value >= conversionTimeoutMinSeconds &&
      value <= conversionTimeoutMaxSeconds;
}

List<ConversionKeyValue> _withStableIds(
  List<({String name, String value})> items,
) => items
    .map((item) => ConversionKeyValue(id: _nextId++, name: item.name, value: item.value))
    .toList();

/// Mirrors `addStableIdToConversions`: editor ids plus the mode and the
/// search params derived from the target.
List<ImageConversion> conversionsFromServer(List<ServerConversion> conversions) =>
    conversions
        .map(
          (conversion) => ImageConversion(
            id: _nextId++,
            mimeType: conversion.mimeType,
            target: conversion.target,
            mode: getTargetMode(normalizeMimeType(conversion.target)),
            compressionLevel: conversion.compressionLevel,
            callTimeout: conversion.callTimeout,
            connectTimeout: conversion.connectTimeout,
            headers: conversion.headers == null
                ? null
                : _withStableIds(
                    conversion.headers!
                        .map((h) => (name: h.name, value: h.value))
                        .toList(),
                  ),
            searchParams: _withStableIds(
              extractSearchParams(conversion.target),
            ),
          ),
        )
        .toList();

/// The editor's working copy of a loaded map, mirroring WebUI's
/// `normalizeConversions(maybeAddDefault(addStableIdToConversions(...)))`.
List<ImageConversion> editorConversionsFromServer(
  List<ServerConversion> conversions,
) => normalizeConversions(maybeAddDefault(conversionsFromServer(conversions)));

List<ImageConversion> normalizeConversions(List<ImageConversion> conversions) {
  for (final conversion in conversions) {
    conversion.mimeType = normalizeMimeType(conversion.mimeType);
    conversion.target = normalizeMimeType(conversion.target);
  }
  return conversions;
}

String _toValidServerMimeType(String mimeType) => isDefaultMimeType(mimeType)
    ? defaultMimeType
    : '$mimeTypePrefix$mimeType';

/// Mirrors `toValidServerConversions`: drops unset rules, qualifies MIME
/// targets, keeps URL targets whole, strips editor ids.
List<Input$SettingsDownloadConversionTypeInput> toServerConversionInputs(
  List<ImageConversion> conversions,
) => conversions
    .where((c) => c.mimeType.isNotEmpty && c.target.isNotEmpty)
    .map(
      (c) => Input$SettingsDownloadConversionTypeInput(
        mimeType: _toValidServerMimeType(c.mimeType),
        target: isUrlTargetMode(c.target)
            ? c.target
            : '$mimeTypePrefix${c.target}',
        compressionLevel: c.compressionLevel,
        callTimeout: c.callTimeout,
        connectTimeout: c.connectTimeout,
        headers: c.headers
            ?.map(
              (h) => Input$SettingsDownloadConversionHeaderTypeInput(
                name: h.name,
                value: h.value,
              ),
            )
            .toList(),
      ),
    )
    .toList();

/// Mirrors `maybeAddDefault`: the editor always shows a `default` rule.
List<ImageConversion> maybeAddDefault(List<ImageConversion> conversions) {
  if (conversions.any((c) => isDefaultMimeType(c.mimeType))) return conversions;
  return [
    ImageConversion(
      id: -1,
      mode: ImageConversionTargetMode.image,
      mimeType: defaultMimeType,
      target: '',
    ),
    ...conversions,
  ];
}

List<ConversionKeyValue>? _normalizeHeaders(List<ConversionKeyValue>? headers) =>
    headers?.where((h) => h.name.isNotEmpty).toList();

/// Mirrors `didUpdateConversions`: whether the editor differs from the
/// loaded map, deciding if Save is enabled.
bool imageConversionsChanged(
  List<ImageConversion> conversions,
  List<ImageConversion> tmpConversions,
) {
  if (conversions.length != tmpConversions.length) return true;
  for (var i = 0; i < conversions.length; i++) {
    final org = conversions[i];
    final tmp = tmpConversions[i];
    final orgHeaders = _normalizeHeaders(org.headers);
    final tmpHeaders = _normalizeHeaders(tmp.headers);
    if (normalizeMimeType(org.mimeType) != tmp.mimeType) return true;
    if (normalizeMimeType(org.target) != tmp.target) return true;
    if (org.compressionLevel != tmp.compressionLevel) return true;
    if (org.callTimeout != tmp.callTimeout) return true;
    if (org.connectTimeout != tmp.connectTimeout) return true;
    if ((orgHeaders?.length ?? 0) != (tmpHeaders?.length ?? 0)) return true;
    for (var h = 0; h < (orgHeaders?.length ?? 0); h++) {
      if (orgHeaders![h].name != tmpHeaders![h].name ||
          orgHeaders[h].value != tmpHeaders[h].value) {
        return true;
      }
    }
  }
  return false;
}
