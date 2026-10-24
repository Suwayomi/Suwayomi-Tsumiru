// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../constants/app_distribution.dart';
import '../../../constants/db_keys.dart';
import '../../../constants/endpoints.dart';
import '../../../constants/urls.dart';
import '../../../global_providers/global_providers.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/misc/graphql_undefined_field.dart';
import '../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../settings/presentation/server/data/web_interface_repository.dart';
import '../../settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../../settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../domain/about/about_dto.dart';
import '../domain/server_update/server_update.dart';
import '../presentation/about/controllers/about_controller.dart';
import 'graphql/__generated__/about_webui.graphql.dart';
import 'graphql/__generated__/query.graphql.dart';
import 'hosted_web_update.dart';
import 'web_update_browser.dart';

part 'about_repository.g.dart';

class AboutRepository {
  final GraphQLClient client;
  final PackageInfo packageInfo;
  final Future<bool> Function()? isServerHosted;
  AboutRepository({
    required this.client,
    required this.packageInfo,
    this.isServerHosted,
  });

  Future<AboutDto?> getAbout() =>
      client.query$GetAbout().getData((a) => a.aboutServer);

  Future<Query$GetAboutWebUI$aboutWebUI?> getAboutWebUI() async {
    try {
      return await client
          .query$GetAboutWebUI(
            Options$Query$GetAboutWebUI(fetchPolicy: FetchPolicy.noCache),
          )
          .getData((a) => a.aboutWebUI);
    } on OperationMessageException catch (error) {
      if (onlyUndefinedFieldErrors(error, type: 'Query')) return null;
      rethrow;
    }
  }

  Future<List<ServerUpdate>?> checkServerUpdate() => client
      .query$GetServerUpdate()
      .getData((a) => a.checkForServerUpdates.map((e) => e.toDto).toList());

  Future<AsyncValue<Version?>> checkUpdate() async {
    if (isGooglePlayBuild) return const AsyncData(null);
    if (await isServerHosted?.call() ?? false) return const AsyncData(null);
    final gitResponse = await AsyncValue.guard<Map<String, dynamic>?>(
      () async => json.decode(
        (await http.get(
          Uri.parse(AppUrls.sorayomiLatestReleaseApiUrl.url),
        )).body,
      ),
    );
    return gitResponse.copyWithData<Version?>((data) {
      String? tag = data?["tag_name"];
      // Release tags are "v0.4.0"; pub_semver can't parse the leading "v".
      Version? latestReleaseBuildNumber = tag != null
          ? Version.parse(tag.startsWith('v') ? tag.substring(1) : tag)
          : null;
      Version? packageBuildNumber = Version.parse(packageInfo.version);
      if (latestReleaseBuildNumber != null &&
          latestReleaseBuildNumber
              .compareTo(packageBuildNumber)
              .isGreaterThan(0)) {
        return latestReleaseBuildNumber;
      }
      return null;
    });
  }
}

@riverpod
AboutRepository aboutRepository(Ref ref) => AboutRepository(
  client: ref.watch(graphQlClientProvider),
  packageInfo: ref.watch(packageInfoProvider),
  isServerHosted: () async {
    await ref.read(startupWebRevisionProvider.future);
    return ref.read(serverHostedWebProvider);
  },
);

/// The release version the user opted to skip in the update prompt. Empty
/// until they tick "Don't remind me about this version".
@riverpod
class DismissedUpdateVersion extends _$DismissedUpdateVersion
    with SharedPreferenceClientMixin<String> {
  @override
  String? build() => initialize(DBKeys.dismissedUpdateVersion);
}

@riverpod
class LastSeenServerVersion extends _$LastSeenServerVersion
    with SharedPreferenceClientMixin<String> {
  @override
  String? build() => initialize(DBKeys.lastSeenServerVersion);
}

final startupWebRevisionProvider = FutureProvider<String?>(
  (ref) => kIsWeb ? readServedRevision() : null,
);

final serverHostedWebProvider = Provider<bool>(
  (ref) => isServerHostedWeb(
    isWeb: kIsWeb,
    revision: ref.watch(startupWebRevisionProvider).value,
    pageBase: kIsWeb ? webInitialServerUrl() : '',
    serverUrl: Endpoints.baseApi(
      baseUrl: ref.watch(serverUrlProvider),
      port: ref.watch(serverPortProvider),
      addPort: ref.watch(serverPortToggleProvider).ifNull(),
      appendApiToUrl: false,
    ),
  ),
);

class WebBuildReloadRequired extends Notifier<bool> {
  @override
  bool build() => false;
  Future<void> check() async {
    if (!ref.read(serverHostedWebProvider)) return;
    final revision = await readServedRevision();
    String? flavor;
    try {
      flavor = (await ref.read(webInterfaceRepositoryProvider).settings())
          ?.webUIFlavor
          .name;
    } catch (_) {}
    if (installedTsumiruDiffers(
      revision,
      ref.read(packageInfoProvider).version,
      flavor: flavor,
    )) {
      state = true;
    }
  }
}

final webBuildReloadRequiredProvider =
    NotifierProvider<WebBuildReloadRequired, bool>(WebBuildReloadRequired.new);
