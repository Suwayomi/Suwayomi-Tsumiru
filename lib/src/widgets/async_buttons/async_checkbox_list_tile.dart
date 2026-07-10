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
  /// a state that never persisted.
  final Future<void> Function(bool)? onChanged;
  final Widget title;
  @override
  Widget build(BuildContext context) {
    final localValue = useState(value);
    useEffect(() {
      localValue.value = value;
      return null;
    }, [value]);
    return CheckboxListTile(
      value: localValue.value,
      onChanged: onChanged != null
          ? (val) async {
              final previous = localValue.value;
              final next = val.ifNull();
              localValue.value = next;
              try {
                await onChanged!(next);
              } catch (_) {
                localValue.value = previous;
              }
            }
          : null,
      title: title,
    );
  }
}
