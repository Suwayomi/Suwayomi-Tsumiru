// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

part of '../custom_extensions.dart';

extension AsyncValueExtensions<T> on AsyncValue<T> {
  bool get isNotLoading => !isLoading;

  void _showToastOnError(Toast toast) {
    if (!isRefreshing) {
      whenOrNull(
        error: (error, stackTrace) {
          toast.close();
          toast.showError(error.toString());
        },
      );
    }
  }

  void showToastOnError(Toast? toast, {bool withMicrotask = false}) {
    if (toast == null) return;
    if (withMicrotask) {
      Future.microtask(() => (_showToastOnError(toast)));
    } else {
      _showToastOnError(toast);
    }
  }

  T? valueOrToast(Toast? toast, {bool withMicrotask = false}) =>
      (this..showToastOnError(toast, withMicrotask: withMicrotask)).value;

  Widget showUiWhenData(
    BuildContext context,
    Widget Function(T data) data, {
    VoidCallback? refresh,
    Widget Function(Widget)? wrapper,
    bool showGenericError = false,
    bool addScaffoldWrapper = false,
    // A dependency change routes `when()` through `loading()` for one frame,
    // swapping the `data` Scaffold for the `wrapper` one and back — which closes
    // anything the user had open (e.g. the library organizer's endDrawer). Pass
    // true to keep the previous data on screen.
    bool skipLoadingOnReload = false,
    Widget? loadingWidget,
    // Offer "View offline" on every failure view, unreachable or not — the
    // error stays on screen, the pin is the user's bypass. Only for screens
    // that actually honor the offline pin (the library) — elsewhere the
    // button would flip a switch this screen ignores.
    bool offlineEscapeHatch = false,
  }) {
    if (addScaffoldWrapper) {
      wrapper = (body) => Scaffold(appBar: AppBar(), body: body);
    }
    return when(
      data: data,
      skipError: true,
      skipLoadingOnReload: skipLoadingOnReload,
      error: (error, trace) {
        // A genuine "can't reach the server" failure gets a dedicated view
        // that points at Connection settings, instead of a blank/opaque error
        // (the connection exception's own message is empty).
        final unwrapped = error is OperationMessageException
            ? error.exception
            : error;
        if (isConnectionError(unwrapped)) {
          return AppUtils.wrapOn(
            wrapper,
            ServerUnreachableView(
              onRetry: refresh,
              offlineEscape: offlineEscapeHatch,
            ),
          );
        }
        final message = isPermissionDenied(unwrapped)
            ? context.l10n.accountPermissionDenied
            : error.toString().trim();
        // An auth failure is one the user can only fix in Connection, so give
        // them the way there. Without it "Unauthorized" is a dead end with a
        // Refresh button that can only fail again.
        final authFailure =
            isPermissionDenied(unwrapped) ||
            message.toLowerCase().contains('unauthor');
        return AppUtils.wrapOn(
          wrapper,
          Emoticons(
            title: showGenericError || message.isBlank
                ? context.l10n.errorSomethingWentWrong
                : message,
            // An empty button still reserves spacing in Emoticons.
            button: (refresh == null && !offlineEscapeHatch && !authFailure)
                ? null
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 8,
                    children: [
                      if (refresh != null)
                        TextButton(
                          onPressed: refresh,
                          child: Text(context.l10n.refresh),
                        ),
                      if (authFailure)
                        TextButton(
                          onPressed: () =>
                              const ConnectionRoute().push(context),
                          child: Text(context.l10n.connection),
                        ),
                      if (offlineEscapeHatch) const ViewOfflineButton(),
                    ],
                  ),
          ),
        );
      },
      loading: () => AppUtils.wrapOn(
        wrapper,
        loadingWidget ?? const CenterSorayomiShimmerIndicator(),
      ),
    );
  }

  AsyncValue<U> copyWithData<U>(U Function(T) data) => when(
    skipError: true,
    skipLoadingOnReload: true,
    data: (prev) => AsyncData(data(prev)),
    error: (error, stackTrace) => AsyncError<U>(error, stackTrace),
    loading: () => AsyncLoading<U>(),
  );
}
