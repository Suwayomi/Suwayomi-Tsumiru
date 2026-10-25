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
    // Keep previous data during dependency reloads so open drawers retain their Scaffold.
    bool skipLoadingOnReload = false,
    Widget? loadingWidget,
    // Offer the offline bypass only on screens that honor the pin.
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
        // Connection exceptions have empty messages; show the dedicated connection view.
        final unwrapped = error is OperationMessageException
            ? error.exception
            : error;
        final webBasicGated =
            isBasicGatedNotFound(unwrapped) &&
            ProviderScope.containerOf(
              context,
              listen: false,
            ).read(isWebProvider);
        if (webBasicGated) {
          return AppUtils.wrapOn(
            wrapper,
            ServerUnreachableView(
              onRetry: refresh,
              offlineEscape: offlineEscapeHatch,
              webNotFoundVerdict: webBasicGated,
            ),
          );
        }
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
        // Rejected credentials need sign-in rather than another refresh.
        final lower = message.toLowerCase();
        if (isPermissionDenied(unwrapped) ||
            lower.contains('unauthor') ||
            lower.contains('http 401') ||
            lower.contains('http 403')) {
          return AppUtils.wrapOn(
            wrapper,
            ServerUnauthorizedView(
              message: showGenericError || message.isBlank
                  ? context.l10n.serverSignedOutSubtitle
                  : message,
              onRetry: refresh,
              offlineEscape: offlineEscapeHatch,
            ),
          );
        }
        return AppUtils.wrapOn(
          wrapper,
          Emoticons(
            title: showGenericError || message.isBlank
                ? context.l10n.errorSomethingWentWrong
                : message,
            button: (refresh == null && !offlineEscapeHatch)
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
                      if (offlineEscapeHatch) const ViewOfflineButton(),
                    ],
                  ),
          ),
        );
      },
      loading: () => AppUtils.wrapOn(
        wrapper,
        loadingWidget ?? const CenterTsumiruShimmerIndicator(),
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
