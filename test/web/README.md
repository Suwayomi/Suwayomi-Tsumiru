# Simple Login browser integration

`simple_login_live_test.dart` is opt-in. It needs an isolated Suwayomi server
using Simple Login, a working WebUI landing page, and a manga with a cover.
Use `localhost` for both the browser test runner and the server URL to test
same-site requests across different ports.

```sh
flutter test --platform chrome test/web/simple_login_live_test.dart \
  --dart-define=SIMPLE_LOGIN_TEST_URL=http://localhost:4613 \
  --dart-define=SIMPLE_LOGIN_TEST_USER=testreader \
  --dart-define=SIMPLE_LOGIN_TEST_PASSWORD=local-test-password \
  --dart-define=SIMPLE_LOGIN_TEST_COVER_PATH=/api/v1/manga/1/thumbnail \
  --dart-define=SIMPLE_LOGIN_TEST_EXTERNAL_IMAGE=http://localhost:4614/image.png \
  --dart-define=SIMPLE_LOGIN_TEST_CROSS_SITE_URL=http://127.0.0.1:4613
```

The external-image fixture must return an image with
`Access-Control-Allow-Origin: *` and no credentialed CORS permission. It checks
that the image cache and ordinary external HTTP requests retain their default
credential policy. The cross-site URL must reach the same Simple Login server
through a different site; `127.0.0.1` and `localhost` satisfy that condition.
Those two checks run only when their URLs are supplied.

The test signs in through the coordinator, fetches protected GraphQL data with
the application client, downloads and decodes a protected cover, and checks
that rejected logins save neither a password nor a session marker. Run it only
against a test account and test server.
