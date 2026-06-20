import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../utils/theme/brand.dart';

/// The app's primary filled button. Renders the brand gradient component
/// (single source) — not a Material ElevatedButton — so it is never flat.
class AsyncElevatedButton extends HookWidget {
  const AsyncElevatedButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style, // retained for API compatibility; styling is global now
  });
  final AsyncCallback? onPressed;
  final Widget child;
  final ButtonStyle? style;
  @override
  Widget build(BuildContext context) {
    final isLoading = useState(false);
    return BrandButton(
      expand: false,
      loading: isLoading.value,
      onPressed: onPressed == null
          ? null
          : () async {
              isLoading.value = true;
              await onPressed?.call();
              isLoading.value = false;
            },
      label: child,
    );
  }
}
