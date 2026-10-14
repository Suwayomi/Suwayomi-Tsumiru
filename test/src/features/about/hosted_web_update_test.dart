import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/about/data/hosted_web_update.dart';

void main() {
  test('hosting requires web and matching normalised origin and base path', () {
    bool hosted(
      String base,
      String? server, {
      bool web = true,
      String? revision = 'v1.5.0',
    }) => isServerHostedWeb(
      isWeb: web,
      pageBase: base,
      serverUrl: server,
      revision: revision,
    );
    expect(hosted('https://example.com/', 'https://example.com'), isTrue);
    expect(
      hosted(
        'https://EXAMPLE.com:443/reader/',
        ' https://example.com/reader/ ',
      ),
      isTrue,
    );
    expect(
      hosted('https://example.com/reader/', 'https://example.com'),
      isFalse,
    );
    expect(
      hosted('https://example.com/', 'https://other.example.com'),
      isFalse,
    );
    expect(hosted('https://example.com/', 'http://example.com'), isFalse);
    expect(
      hosted('http://example.com:4602/', 'http://example.com:4567'),
      isFalse,
    );
    expect(
      hosted('https://example.com/', 'https://example.com', web: false),
      isFalse,
    );
    expect(
      hosted('https://example.com/', 'https://example.com', revision: null),
      isFalse,
    );
    expect(
      hosted('https://example.com/', 'https://example.com', revision: 'r3518'),
      isFalse,
    );
    expect(hosted('invalid', 'invalid'), isFalse);
    expect(hosted('https://example.com/', null), isFalse);
  });

  test('only a different Tsumiru release tag requires reloading', () {
    expect(installedTsumiruDiffers('v1.5.0', '1.5.0'), isFalse);
    expect(installedTsumiruDiffers('v1.5.1', '1.5.0'), isTrue);
    expect(
      installedTsumiruDiffers('v1.5.1', '1.5.0', flavor: 'TSUMIRU'),
      isTrue,
    );
    expect(
      installedTsumiruDiffers('v1.5.1', '1.5.0', flavor: 'WEBUI'),
      isFalse,
    );
    expect(
      installedTsumiruDiffers('v1.5.1', '1.5.0', flavor: 'CUSTOM'),
      isFalse,
    );
    expect(installedTsumiruDiffers('v1.4.0', '1.5.0'), isTrue);
    expect(installedTsumiruDiffers('r3518', '1.5.0'), isFalse);
    expect(installedTsumiruDiffers('1.5.1', '1.5.0'), isFalse);
    expect(installedTsumiruDiffers(null, '1.5.0'), isFalse);
    expect(installedTsumiruDiffers('vgarbage', '1.5.0'), isFalse);
  });
}
