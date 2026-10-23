import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../data/recommendations/recommendation_provider.dart';

String recommendationErrorMessage(
  BuildContext context,
  Object error,
  String provider,
) => switch (error) {
  RecommendationServiceUnavailable() =>
    context.l10n.recommendationsServiceUnavailable(provider),
  RecommendationHttpException() ||
  TimeoutException() => context.l10n.recommendationsLoadFailed(provider),
  _ => context.l10n.errorSomethingWentWrong,
};

String joinProviderNames(Iterable<String> names) {
  final unique = names.toSet().toList();
  return unique.join(', ');
}

String suggestionsRowErrorMessage(BuildContext context, Object error) {
  final failures = error is RecommendationAllFailed ? error.failures : null;
  if (failures == null || failures.isEmpty) {
    return context.l10n.suggestionsLoadFailed;
  }
  final names = joinProviderNames([
    for (final failure in failures) failure.name,
  ]);
  if (failures.length == 1 &&
      failures.single.error is RecommendationServiceUnavailable) {
    return context.l10n.recommendationsServiceUnavailable(names);
  }
  return context.l10n.recommendationsLoadFailed(names);
}
