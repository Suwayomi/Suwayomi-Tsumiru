// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

part of '../custom_extensions.dart';

/// Width classes from Material's window size classes: compact < 600,
/// medium 600-839, expanded 840-1199, large 1200-1599, extra-large >= 1600.
enum WindowSizeClass { compact, medium, expanded, large, extraLarge }

extension WindowSizeClassOrder on WindowSizeClass {
  bool operator >=(WindowSizeClass other) => index >= other.index;
  bool operator >(WindowSizeClass other) => index > other.index;
  bool operator <=(WindowSizeClass other) => index <= other.index;
  bool operator <(WindowSizeClass other) => index < other.index;
}

extension ContextExtensions on BuildContext {
  String get location {
    GoRouter router = GoRouter.of(this);
    final RouteMatch lastMatch =
        router.routerDelegate.currentConfiguration.last;
    final RouteMatchList matchList = lastMatch is ImperativeRouteMatch
        ? lastMatch.matches
        : router.routerDelegate.currentConfiguration;
    return matchList.uri.path;
  }

  void get hideKeyboard => FocusScope.of(this).unfocus();


  double get horizontal =>
      (MediaQuery.of(this).orientation == Orientation.portrait
      ? MediaQuery.of(this).size.width
      : MediaQuery.of(this).size.height);
  double horizontalScale({double scale = 1}) => scale * horizontal;

  double verticalScale({double scale = 1}) => scale * vertical;
  double get vertical =>
      (MediaQuery.of(this).orientation == Orientation.landscape
      ? MediaQuery.of(this).size.width
      : MediaQuery.of(this).size.height);

  Size get mediaQuerySize => MediaQuery.of(this).size;

  double get height => mediaQuerySize.height;

  double get width => mediaQuerySize.width;


  double widthScale({double scale = 1}) => scale * width;

  double heightScale({double scale = 1}) => scale * height;

  /// Subtract reducedBy percent, then divide by dividedBy.
  double heightTransformer({double dividedBy = 1, double reducedBy = 0.0}) =>
      (mediaQuerySize.height - ((mediaQuerySize.height / 100) * reducedBy)) /
      dividedBy;

  /// Subtract reducedBy percent, then divide by dividedBy.
  double widthTransformer({double dividedBy = 1, double reducedBy = 0.0}) =>
      (mediaQuerySize.width - ((mediaQuerySize.width / 100) * reducedBy)) /
      dividedBy;

  double ratio({
    double dividedBy = 1,
    double reducedByW = 0.0,
    double reducedByH = 0.0,
  }) =>
      heightTransformer(dividedBy: dividedBy, reducedBy: reducedByH) /
      widthTransformer(dividedBy: dividedBy, reducedBy: reducedByW);

  ThemeData get theme => Theme.of(this);

  bool get isDarkMode => (theme.brightness == Brightness.dark);

  Color? get iconColor => theme.iconTheme.color;

  TextTheme get textTheme => Theme.of(this).textTheme;

  EdgeInsets get mediaQueryPadding => MediaQuery.of(this).padding;

  MediaQueryData get mediaQuery => MediaQuery.of(this);

  EdgeInsets get mediaQueryViewPadding => MediaQuery.of(this).viewPadding;

  EdgeInsets get mediaQueryViewInsets => MediaQuery.of(this).viewInsets;

  Orientation get orientation => MediaQuery.of(this).orientation;

  bool get isLandscape => orientation == Orientation.landscape;

  bool get isPortrait => orientation == Orientation.portrait;

  double get devicePixelRatio => MediaQuery.of(this).devicePixelRatio;

  TextScaler get textScaleFactor => MediaQuery.of(this).textScaler;

  double get mediaQueryShortestSide => mediaQuerySize.shortestSide;

  /// Material window size class, determined by width only.
  WindowSizeClass get windowSizeClass {
    if (width < 600) return WindowSizeClass.compact;
    if (width < 840) return WindowSizeClass.medium;
    if (width < 1200) return WindowSizeClass.expanded;
    if (width < 1600) return WindowSizeClass.large;
    return WindowSizeClass.extraLarge;
  }

  /// Require 600 px on both axes so landscape phones retain their compact shell.
  bool get usesDesktopShell =>
      windowSizeClass >= WindowSizeClass.medium &&
      mediaQueryShortestSide >= 600;

  AppLocalizations get l10n => AppLocalizations.of(this)!;

  void navPop<T>([T? result]) => Navigator.pop<T>(this, result);

  Locale get currentLocale => Localizations.localeOf(this);

  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  /// Prefer the widest eligible non-null value; fall back to the narrowest supplied value.
  T responsiveValue<T>({T? watch, T? mobile, T? tablet, T? desktop}) {
    assert(
      watch != null || mobile != null || tablet != null || desktop != null,
    );

    var deviceWidth = mediaQuerySize.width;
    final strictValues = [
      if (deviceWidth >= 1200) desktop, //desktop is allowed
      if (deviceWidth >= 600) tablet, //tablet is allowed
      if (deviceWidth >= 300) mobile, //mobile is allowed
      watch, //watch is allowed
    ].whereType<T>();
    final looseValues = [watch, mobile, tablet, desktop].whereType<T>();
    return strictValues.firstOrNull ?? looseValues.first;
  }

  Future<T?> pushBottomSheet<T>(Widget sheet) async {
    return showModalBottomSheet<T>(
      context: this,
      useSafeArea: true,
      isScrollControlled: true,
      enableDrag: false,
      isDismissible: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: sheet,
      ),
      sheetAnimationStyle: motionStyle,
    );
  }

  Future<T?> showFullScreenDialog<T>(Widget dialog) async {
    return showDialog<T>(
      context: this,
      useSafeArea: true,
      useRootNavigator: false,
      barrierDismissible: true,
      builder: (context) => Dialog.fullscreen(child: dialog),
      animationStyle: motionStyle,
    );
  }
}
