// Copyright (c) 2023 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../utils/extensions/custom_extensions.dart';

class AsyncCheckboxListTile extends HookWidget {
  const AsyncCheckboxListTile({
    super.key,
    required this.value,
    this.onChanged,
    required this.title,
  });

  final bool value;

  /// Runs the change. The checkbox flips optimistically before this is awaited
  /// and reverts if it throws — so a failed toggle doesn't leave the box showing
  /// a state that never persisted. Callers own user-facing error reporting; the
  /// throw is only used here to trigger the revert.
  final Future<void> Function(bool)? onChanged;
  final Widget title;
  @override
  Widget build(BuildContext context) {
    final localValue = useState(value);
    final inFlight = useState(false);
    useEffect(() {
      localValue.value = value;
      return null;
    }, [value]);
    return CheckboxListTile(
      // Disabled while a change is in flight so overlapping toggles can't leave
      // the revert pointing at a stale, mid-flight value.
      onChanged: onChanged != null && !inFlight.value
          ? (val) async {
              final previous = localValue.value;
              final next = val.ifNull();
              localValue.value = next;
              inFlight.value = true;
              try {
                await onChanged!(next);
              } catch (_) {
                localValue.value = previous;
              } finally {
                inFlight.value = false;
              }
            }
          : null,
      value: localValue.value,
      title: title,
    );
  }
}
