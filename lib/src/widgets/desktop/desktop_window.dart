import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/extensions/custom_extensions.dart';

class _CloseWindowIntent extends Intent {
  const _CloseWindowIntent();
}

class DesktopWindow extends StatelessWidget {
  const DesktopWindow({
    super.key,
    required this.child,
    required this.onClose,
    this.windowKey,
  });

  final Widget child;
  final VoidCallback onClose;
  final Key? windowKey;

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.escape): _CloseWindowIntent(),
    },
    child: Actions(
      actions: {
        _CloseWindowIntent: CallbackAction<_CloseWindowIntent>(
          onInvoke: (_) {
            onClose();
            return null;
          },
        ),
      },
      child: Focus(
        autofocus: true,
        child: Stack(
          children: [
            Positioned.fill(
              child: ModalBarrier(
                onDismiss: onClose,
                color: context.colorScheme.scrim.withValues(alpha: .45),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 1080,
                    maxHeight: 760,
                  ),
                  child: SizedBox.expand(
                    key: windowKey,
                    child: Material(
                      color: context.colorScheme.surface,
                      elevation: 24,
                      shadowColor: context.colorScheme.shadow.withValues(
                        alpha: .55,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: context.colorScheme.outlineVariant,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
