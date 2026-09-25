import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../constants/app_theme.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/theme/app_color_scheme.dart';
import '../../../../../../utils/theme/theme_tokens.dart';
import 'app_theme_providers.dart';

/// Horizontal curated theme picker. Each card previews the theme's surface +
/// accents at the brightness currently in use, and shows a check when selected.
///
/// Give it a [title] to get a header row carrying that title plus a pair of
/// scroll arrows, shown only while the cards overflow.
class ThemeSelector extends HookConsumerWidget {
  const ThemeSelector({super.key, this.title});

  final Widget? title;

  /// Card height; 16px shorter than the 148 the scrollbar lane used to need.
  static const _cardsHeight = 132.0;
  static const _arrowSize = 34.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(appThemeKeyProvider) ?? AppTheme.indigoNight;
    final controller = useScrollController();
    // Bumped on every scroll (controller listener) and on first layout or a
    // viewport resize (metrics notification), so the arrows track both ends.
    final rebuild = useState(0);
    useEffect(
      () {
        void onScroll() => rebuild.value++;
        controller.addListener(onScroll);
        return () => controller.removeListener(onScroll);
      },
      [controller],
    );

    final position = controller.hasClients ? controller.position : null;
    final maxExtent = position?.maxScrollExtent ?? 0;
    final offset = position?.pixels ?? 0;
    final canScroll = maxExtent > 0;
    final cs = Theme.of(context).colorScheme;

    void scrollBy(double direction) {
      final position = controller.position;
      final target =
          position.pixels + direction * position.viewportDimension * 0.8;
      controller.animateTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }

    Widget arrow({
      required IconData icon,
      required String tooltip,
      required bool enabled,
      required VoidCallback onPressed,
    }) => Opacity(
      opacity: enabled ? 1 : 0.4,
      child: IconButton.outlined(
        onPressed: enabled ? onPressed : null,
        tooltip: tooltip,
        icon: Icon(icon, size: 20),
        style: IconButton.styleFrom(
          minimumSize: const Size.square(_arrowSize),
          maximumSize: const Size.square(_arrowSize),
          padding: EdgeInsets.zero,
          foregroundColor: cs.onSurface,
          backgroundColor: cs.surfaceContainer,
          side: BorderSide(color: cs.outlineVariant),
          shape: const CircleBorder(),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Row(
            children: [
              Expanded(child: title!),
              if (canScroll) ...[
                arrow(
                  icon: Icons.chevron_left_rounded,
                  tooltip: context.l10n.back,
                  enabled: offset > 0,
                  onPressed: () => scrollBy(-1),
                ),
                const SizedBox(width: 8),
                arrow(
                  icon: Icons.chevron_right_rounded,
                  tooltip: context.l10n.next,
                  enabled: offset < maxExtent,
                  onPressed: () => scrollBy(1),
                ),
              ],
              const SizedBox(width: 16),
            ],
          ),
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (_) {
            rebuild.value++;
            return false;
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: SizedBox(
              height: _cardsHeight,
              child: ListView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                children: [
                  // Named themes first, Custom last (custom sits mid-enum
                  // because values are persisted by index — display order is
                  // independent).
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
        ),
      ],
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
    // Preview the brightness the app is actually in, so light mode does not
    // show a wall of dark cards.
    final brightness = Theme.of(context).brightness;
    // Custom has no fixed tokens; preview with its swatch on a neutral bg.
    final ColorScheme preview = theme == AppTheme.custom
        ? (brightness == Brightness.dark
            ? const ColorScheme.dark()
            : const ColorScheme.light())
        : schemeFromTokens(tokensFor(theme, brightness), brightness);
    final (accent, accent2) = theme == AppTheme.custom
        ? theme.swatch
        : (preview.primary, preview.secondary);
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
