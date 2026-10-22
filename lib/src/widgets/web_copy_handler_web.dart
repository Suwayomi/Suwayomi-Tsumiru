// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:js_interop';

import 'package:web/web.dart' as web;

void Function() attachWebCopyHandler(String? Function() selectedText) {
  final onCopy = ((web.Event event) {
    if (event.defaultPrevented) return;
    final text = selectedText();
    if (text == null || text.isEmpty) return;
    final copy = event as web.ClipboardEvent;
    copy.clipboardData?.setData('text/plain', text);
    copy.preventDefault();
  }).toJS;
  web.document.addEventListener('copy', onCopy);
  return () => web.document.removeEventListener('copy', onCopy);
}
