import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LinuxWindowFrame extends StatefulWidget {
  const LinuxWindowFrame({super.key, required this.child});

  final Widget child;

  @override
  State<LinuxWindowFrame> createState() => _LinuxWindowFrameState();
}

class _LinuxWindowFrameState extends State<LinuxWindowFrame> {
  static const _channel = MethodChannel('tsumiru/linux_window_frame');
  bool _rounded = true;
  bool _outlined = true;

  @override
  void initState() {
    super.initState();
    // GDK reports quick-tiling as well as maximised and fullscreen transitions.
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'stateChanged') {
        _updateState(Map<Object?, Object?>.from(call.arguments as Map));
      }
    });
    _channel.invokeMapMethod<Object?, Object?>('getState').then((state) {
      if (state != null) _updateState(state);
    });
  }

  void _updateState(Map<Object?, Object?> state) {
    if (!mounted) return;
    setState(() {
      _rounded = state['rounded'] == true;
      _outlined = state['outlined'] == true;
    });
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = _rounded ? BorderRadius.circular(15) : BorderRadius.zero;
    return ClipRRect(
      borderRadius: radius,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: _outlined
              ? Border.all(
                  color: theme.brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: .07)
                      : theme.colorScheme.onSurface.withValues(alpha: .07),
                )
              : null,
        ),
        child: ColoredBox(
          color: theme.colorScheme.surface,
          child: widget.child,
        ),
      ),
    );
  }
}
