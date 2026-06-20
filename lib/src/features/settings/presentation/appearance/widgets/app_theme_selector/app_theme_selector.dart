import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../constants/app_theme.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/theme/app_color_scheme.dart';
import '../../../../../../utils/theme/theme_tokens.dart';
import 'app_theme_providers.dart';

/// Horizontal curated theme picker. Each card previews the theme's dark
/// surface + accents and shows a check when selected.
class ThemeSelector extends HookConsumerWidget {
  const ThemeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(appThemeKeyProvider) ?? AppTheme.indigoNight;
    final controller = useScrollController();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: SizedBox(
        height: 148,
        child: Scrollbar(
          controller: controller,
          // Sit the horizontal scrollbar in its own lane below the cards
          // instead of overlaying their labels.
          child: ListView(
            controller: controller,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              // Named themes first, Custom last (custom sits mid-enum because
              // values are persisted by index — display order is independent).
              for (final theme in [
                ...AppTheme.values.where((t) => t != AppTheme.custom),
                AppTheme.custom,
              ])
                _ThemeCard(
                  theme: theme,
                  selected: theme == selected,
                  onTap: () =>
                      ref.read(appThemeKeyProvider.notifier).update(theme),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final AppTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Custom has no fixed tokens; preview with its swatch on a neutral dark bg.
    final ColorScheme preview = theme == AppTheme.custom
        ? const ColorScheme.dark()
        : schemeFromTokens(tokensFor(theme, Brightness.dark), Brightness.dark);
    final (accent, accent2) = theme.swatch;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 92,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: preview.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? accent : preview.outline,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _dot(accent),
                  const SizedBox(width: 6),
                  _dot(accent2),
                  const Spacer(),
                  if (selected)
                    Icon(Icons.check_circle, size: 18, color: accent),
                ],
              ),
              const SizedBox(height: 10),
              Container(height: 8, width: 64, color: preview.onSurface),
              const SizedBox(height: 6),
              Container(height: 8, width: 44, color: preview.onSurfaceVariant),
              const Spacer(),
              Text(
                theme.label(context),
                style: TextStyle(color: preview.onSurface, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dot(Color c) => Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );
}

/// Tile to pick a custom seed color; only meaningful when AppTheme.custom.
class CustomColorTile extends ConsumerWidget {
  const CustomColorTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorInt = ref.watch(customThemeColorProvider) ?? 0xFF7C7BFF;
    final color = Color(colorInt);
    return ListTile(
      title: Text(context.l10n.customColor),
      trailing: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      onTap: () async {
        final picked = await showColorPickerDialog(
          context,
          color,
          title: Text(context.l10n.customColor),
          pickersEnabled: const {ColorPickerType.wheel: true},
          enableShadesSelection: false,
        );
        if (!context.mounted) return;
        ref
            .read(customThemeColorProvider.notifier)
            .update(picked.toARGB32());
      },
    );
  }
}
