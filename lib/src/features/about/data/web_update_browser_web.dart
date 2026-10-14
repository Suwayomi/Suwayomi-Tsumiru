import 'dart:js_interop';

import 'package:web/web.dart' as web;

void Function() listenForWebUpdate(void Function() check) {
  final focus = ((web.Event event) {
    check();
  }).toJS;
  final visibility = ((web.Event event) {
    if (web.document.visibilityState == 'visible') check();
  }).toJS;
  web.window.addEventListener('focus', focus);
  web.document.addEventListener('visibilitychange', visibility);
  return () {
    web.window.removeEventListener('focus', focus);
    web.document.removeEventListener('visibilitychange', visibility);
  };
}

void reloadWebBuild() => web.window.location.reload();

Future<String?> readServedRevision() async {
  try {
    final response = await web.window
        .fetch(
          web.URL('revision', web.document.baseURI).href.toJS,
          web.RequestInit(cache: 'no-store'),
        )
        .toDart;
    if (response.status != 200) return null;
    return (await response.text().toDart).toDart.trim();
  } catch (_) {
    return null;
  }
}
