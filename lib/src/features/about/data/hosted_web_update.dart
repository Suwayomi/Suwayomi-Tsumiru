import '../../settings/presentation/server/widget/client/server_url_tile/web_default_server_url.dart';

bool isServerHostedWeb({
  required bool isWeb,
  required String pageBase,
  required String? serverUrl,
}) {
  if (!isWeb || serverUrl == null) return false;
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

bool installedTsumiruDiffers(String? tag, String version) {
  if (tag == null ||
      !RegExp(
        r'^v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$',
      ).hasMatch(tag)) {
    return false;
  }
  return tag != 'v$version';
}
