import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/launch_url_in_web.dart';
import 'package:tsumiru/src/utils/misc/toast/toast.dart';

void main() {
  testWidgets(
    'browser failure copies the sign-in link with feedback that excludes its state',
    (tester) async {
      const url =
          'https://tracker.test/authorize?state=secret-nonce&code=private-code';
      const message =
          'Couldn’t open the browser. The sign-in link was copied to the clipboard.';
      String? copied;
      String? launched;
      Toast? toast;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'),
        (call) async {
          launched = (call.arguments as Map)['url'] as String;
          return false;
        },
      );
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          null,
        );
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  toast = Toast(context);
                  await launchUrlInWeb(
                    context,
                    url,
                    toast,
                    AppLocalizations.of(context)!.trackerOAuthBrowserFallback,
                  );
                },
                child: const Text('Sign in'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(launched, url);
      expect(copied, url);
      final visible = find.text(message).evaluate().isNotEmpty;
      final exposed = find.textContaining('secret-nonce').evaluate().isNotEmpty;
      toast?.close();
      await tester.pumpAndSettle();
      expect(visible, isTrue);
      expect(exposed, isFalse);
    },
  );
}
