import '../../settings/presentation/server/widget/client/server_url_tile/web_default_server_url.dart';

bool isServerHostedWeb({
  required bool isWeb,
  required String pageBase,
  required String? serverUrl,
  required String? revision,
}) {
  if (!isWeb || serverUrl == null || !isTsumiruTag(revision)) return false;
  final page = Uri.tryParse(pageBase.trim());
  final server = Uri.tryParse(serverUrl.trim());
  if (page == null ||
      server == null ||
      !page.hasAuthority ||
      !server.hasAuthority ||
      !['http', 'https'].contains(page.scheme) ||
      !['http', 'https'].contains(server.scheme)) {
    return false;
  }
  return webDefaultServerUrl(
        page.toString(),
      ).replaceFirst(RegExp(r'/+$'), '') ==
      webDefaultServerUrl(server.toString()).replaceFirst(RegExp(r'/+$'), '');
}

bool isTsumiruTag(String? tag) =>
    tag != null && RegExp(r'^v\d+\.\d+\.\d+').hasMatch(tag);

bool installedTsumiruDiffers(String? tag, String version, {String? flavor}) {
  if (flavor != null && flavor != 'TSUMIRU') return false;
  return isTsumiruTag(tag) && tag != 'v$version';
}
