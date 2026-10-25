// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:gap/gap.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../constants/app_sizes.dart';
import '../../../routes/router_config.dart';
import '../../extensions/custom_extensions.dart';
import '../../motion/reduce_motion.dart';
import '../../network/graphql_errors.dart';

part 'toast.g.dart';

class Toast {
  Toast(this._context) {
    // A pending Undo keeps its overlay; re-pointing would strand its queued followers.
    // A closed cover view leaves that overlay unmounted, so re-init then.
    final current = FToast().context;
    if (!_actionVisible || current == null || !current.mounted) {
      _fToast = FToast().init(_context);
    }
  }
  final BuildContext _context;
  FToast _fToast = FToast();

  static bool _actionVisible = false;
  static Timer? _actionTimer;

  Duration get _fadeDuration =>
      _context.reduceMotion ? Duration.zero : const Duration(milliseconds: 350);

  void show(
    String msg, {
    bool withMicrotask = false,
    bool instantShow = false,
  }) {
    toast() {
      if (instantShow && !_actionVisible) close();
      _fToast.showToast(
        child: ToastWidget(text: msg),
        gravity: ToastGravity.BOTTOM,
        positionedToastBuilder: _centeredBuilder(),
        fadeDuration: _fadeDuration,
      );
    }

    if (withMicrotask) {
      Future.microtask(toast);
    } else {
      toast();
    }
  }

  void showWithAction(
    String msg, {
    required String actionLabel,
    required VoidCallback onAction,
    Duration duration = const Duration(seconds: 5),
    BuildContext? overlayContext,
  }) {
    final target = overlayContext != null && overlayContext.mounted
        ? overlayContext
        : _context;
    // Anchor to the root navigator so the entry lands above every route, including dialogs.
    final rootContext = Navigator.of(target, rootNavigator: true).context;
    _fToast = FToast().init(rootContext);
    // FToast queues behind earlier toasts; drop the queue so Undo shows now.
    _fToast.removeQueuedCustomToasts();
    _actionTimer?.cancel();
    _actionVisible = true;
    _fToast.showToast(
      child: ToastWidget(
        text: msg,
        action: TextButton(
          onPressed: () {
            _actionTimer?.cancel();
            _actionVisible = false;
            close();
            onAction();
          },
          style: TextButton.styleFrom(
            foregroundColor: _context.colorScheme.primary,
          ),
          child: Text(actionLabel),
        ),
      ),
      gravity: ToastGravity.BOTTOM,
      positionedToastBuilder: _centeredBuilder(),
      toastDuration: duration,
      fadeDuration: _fadeDuration,
    );
    // Start after display so the guard tracks the visible toast.
    _actionTimer = Timer(
      duration + _fadeDuration,
      () => _actionVisible = false,
    );
  }

  void showError(
    String error, {
    bool withMicrotask = false,
    bool instantShow = false,
  }) {
    final text = isPermissionDenied(error)
        ? _context.l10n.accountPermissionDenied
        : error.trim().isNotBlank
        ? error.trim()
        : _context.l10n.errorSomethingWentWrong;
    toast() {
      if (instantShow && !_actionVisible) close();
      _fToast.showToast(
        child: ToastWidget(text: text, isError: true),
        gravity: ToastGravity.TOP,
        positionedToastBuilder: _centeredBuilder(),
        fadeDuration: _fadeDuration,
      );
    }

    if (withMicrotask) {
      Future.microtask(toast);
    } else {
      toast();
    }
  }

  void close() => _fToast.removeCustomToast();

  PositionedToastBuilder? _centeredBuilder() {
    if (_context.windowSizeClass < WindowSizeClass.medium) return null;
    return (context, child, gravity) {
      final toast = Align(
        alignment: gravity == ToastGravity.TOP
            ? Alignment.topCenter
            : Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: child,
        ),
      );
      if (gravity == ToastGravity.TOP) {
        return Positioned(top: 100, left: 24, right: 24, child: toast);
      }
      final bottomInset = MediaQuery.of(context).viewPadding.bottom;
      return Positioned(
        bottom: bottomInset + 24,
        left: 24,
        right: 24,
        child: toast,
      );
    };
  }
}

class ToastWidget extends StatelessWidget {
  const ToastWidget({
    super.key,
    required this.text,
    this.icon,
    this.action,
    this.isError = false,
  });
  final String text;
  final Widget? icon;
  final Widget? action;
  final bool isError;
  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final leading =
        icon ??
        (isError ? Icon(Icons.error_outline, color: scheme.error) : null);
    Widget textWidget = Text(
      text,
      style: TextStyle(color: scheme.onSurface),
      textAlign: action != null ? TextAlign.left : TextAlign.center,
    );
    return Container(
      padding: KEdgeInsets.h16v8.size,
      decoration: BoxDecoration(
        borderRadius: KBorderRadius.r16.radius,
        color: scheme.surfaceContainerHigh,
        border: Border.all(
          color: isError ? scheme.error : scheme.outlineVariant,
        ),
        // No panel shadow token in the theme; shadow role keeps it neutral in every theme.
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: leading != null
          ? Row(
              children: [
                leading,
                const Gap(16),
                Flexible(child: textWidget),
              ],
            )
          : action != null
          ? Row(
              children: [
                Flexible(child: textWidget),
                action!,
              ],
            )
          : textWidget,
    );
  }
}

@riverpod
Toast? toast(Ref ref) {
  final context = rootNavigatorKey.currentContext;
  if (context == null) {
    return null;
  }
  return Toast(context);
}
