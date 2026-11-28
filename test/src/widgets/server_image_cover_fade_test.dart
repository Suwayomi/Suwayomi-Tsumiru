// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tsumiru/src/widgets/server_image.dart';

void main() {
  // A 16:9 cover in a 2:3 tile: it must fill the tile (cropped), not shrink to
  // a 200 × 112.5 strip once the fade-in has run.
  testWidgets('a wide cover fills a fixed tile after the fade', (tester) async {
    final bytes = Uint8List.fromList(
      img.encodePng(img.Image(width: 160, height: 90)),
    );
    // Never loaded before, so it decodes asynchronously and goes through the fade.
    final image = MemoryImage(bytes);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 200,
            height: 300,
            child: Image(
              image: image,
              fit: BoxFit.cover,
              frameBuilder: coverFadeFrameBuilder(
                const Duration(milliseconds: 150),
                (_) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
    // The first frame shows the placeholder; let the decode finish, then fade.
    expect(find.byType(RawImage), findsNothing);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    expect(find.byType(RawImage), findsOneWidget);
    expect(tester.getSize(find.byType(RawImage)), const Size(200, 300));
  });
}
