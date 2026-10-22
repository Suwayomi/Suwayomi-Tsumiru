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
