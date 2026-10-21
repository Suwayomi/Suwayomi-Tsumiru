import 'package:flutter/material.dart';

import '../../../../utils/extensions/custom_extensions.dart';

class RecommendationLoading extends StatelessWidget {
  const RecommendationLoading({super.key, this.explainServices = false});

  final bool explainServices;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 8),
        Text(
          context.l10n.suggestionsFetching,
          textAlign: TextAlign.center,
          style: context.textTheme.bodyMedium,
        ),
        if (explainServices) ...[
          const SizedBox(height: 8),
          Text(
            context.l10n.suggestionsFetchingSubtitle,
            textAlign: TextAlign.center,
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    ),
  );
}
