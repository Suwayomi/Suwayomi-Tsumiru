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
