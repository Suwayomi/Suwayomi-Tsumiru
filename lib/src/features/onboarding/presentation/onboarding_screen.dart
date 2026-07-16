// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../constants/db_keys.dart';
import '../../../constants/enum.dart';
import '../../../constants/gen/assets.gen.dart';
import '../../../constants/urls.dart';
import '../../../global_providers/global_providers.dart';
import '../../../routes/router_config.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/launch_url_in_web.dart';
import '../../../utils/misc/toast/toast.dart';
import '../../../utils/theme/brand.dart';
import '../../about/data/about_repository.dart';
import '../../auth/presentation/sign_in_action.dart';
import '../../settings/presentation/appearance/widgets/app_theme_selector/app_theme_selector.dart';
import '../../settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../../settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../data/onboarding_complete.dart';
import '../data/server_discovery.dart';
import '../data/server_resolver.dart';

/// First-time onboarding wizard: pick a theme, connect a Suwayomi server, done.
/// Shown by the router until [OnboardingComplete] is set true. Matches the
/// approved Indigo Night mockups.
class OnboardingScreen extends HookConsumerWidget {
  const OnboardingScreen({super.key});

  static const _stepCount = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final step = useState(0);
    final serverVerified = useState(false);

    bool stepComplete(int i) => switch (i) {
          1 => serverVerified.value,
          _ => true,
        };

    final isLast = step.value == _stepCount - 1;

    void finish() {
      ref.read(onboardingCompleteProvider.notifier).update(true);
      const LibraryRoute(categoryId: 0).go(context);
    }

    final cs = context.theme.colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          // Brand backdrop: indigo glow at the top fading into the scaffold.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.center,
                  colors: [
                    cs.primary.withValues(alpha: 0.20),
                    context.theme.scaffoldBackgroundColor.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 12),
                // Brand wordmark, centered, with a top-right "Skip" escape on
                // every step except the final one (nothing left to skip there).
                Stack(
                  alignment: Alignment.center,
                  children: [
                    const _BrandHeader(),
                    if (step.value < _stepCount - 1)
                      Positioned(
                        right: 4,
                        child: TextButton(
                          onPressed: finish,
                          child: Text(context.l10n.onboardingSkip),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _StepDots(count: _stepCount, active: step.value),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: SingleChildScrollView(
                      key: ValueKey(step.value),
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                      child: switch (step.value) {
                        0 => const _ThemeStep(),
                        1 => _ServerStep(
                            onVerifiedChanged: (v) => serverVerified.value = v),
                        _ => const _FinishStep(),
                      },
                    ),
                  ),
                ),
                _NavBar(
                  showBack: step.value > 0,
                  canAdvance: stepComplete(step.value),
                  isLast: isLast,
                  onBack: () => step.value--,
                  onNext: () => isLast ? finish() : step.value++,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The swirl logo + "Tsumiru" wordmark shown at the top of every step.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset(Assets.icons.darkIcon.path, height: 26),
        const SizedBox(width: 8),
        Text(
          'Tsumiru',
          style: context.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.count, required this.active});
  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    final cs = context.theme.colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            width: i == active ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == active
                  ? cs.primary
                  : cs.onSurface.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.showBack,
    required this.canAdvance,
    required this.isLast,
    required this.onBack,
    required this.onNext,
  });
  final bool showBack;
  final bool canAdvance;
  final bool isLast;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final next = BrandButton(
      label: Text(isLast ? context.l10n.finish : context.l10n.next),
      onPressed: canAdvance ? onNext : null,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
      // Back + Next share one row (Next wider) so the nav takes less vertical
      // space; on the first step there's no Back, so Next fills the row.
      child: showBack
          ? Row(
              children: [
                Expanded(
                  child: BrandGlassButton(
                    label: Text(context.l10n.back),
                    onPressed: onBack,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: next),
              ],
            )
          : next,
    );
  }
}

// --- Step 1: theme ----------------------------------------------------------

class _ThemeStep extends StatelessWidget {
  const _ThemeStep();

  @override
  Widget build(BuildContext context) {
    final cs = context.theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        // The big brand mark — the swirl logo above the welcome heading.
        Center(child: Image.asset(Assets.icons.darkIcon.path, height: 160)),
        const SizedBox(height: 24),
        Text(context.l10n.onboardingWelcomeTitle,
            style: context.textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(context.l10n.onboardingWelcomeSubtitle,
            style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 28),
        Text(context.l10n.onboardingChooseTheme,
            style: context.textTheme.titleMedium),
        const ThemeSelector(),
      ],
    );
  }
}

// --- Step 2: server ---------------------------------------------------------

/// Outcome of "Test connection" (and the in-flight states for both actions).
enum _TestState {
  idle,
  searching,
  testing,
  connected,

  /// Reachable Suwayomi whose API is gated — reveal the auth sub-form.
  needsLogin,

  /// Couldn't reach the address at all.
  failed,

  /// Reached something, but it isn't a Suwayomi server.
  notSuwayomi,
}

/// Factory for the throwaway HTTP client the resolver probes use. Overridable
/// in widget tests so the connection flow can be driven against a MockClient.
final onboardingHttpClientProvider =
    Provider<http.Client Function()>((Ref ref) => http.Client.new);

class _ServerStep extends HookConsumerWidget {
  const _ServerStep({required this.onVerifiedChanged});
  final ValueChanged<bool> onVerifiedChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = context.theme.colorScheme;
    final urlController = useTextEditingController(
      text: () {
        final stored = ref.read(serverUrlProvider);
        return (stored == null || stored == DBKeys.serverUrl.initial)
            ? ''
            : stored;
      }(),
    );
    final state = useState(_TestState.idle);
    final version = useState<String?>(null);
    final errorDetail = useState<String?>(null);
    // The base URL we resolved to (after auto-fallback) — shown + persisted.
    final resolvedUrl = useState<String?>(null);
    // Credentials + chosen auth type, revealed when the server needs a login.
    final userController = useTextEditingController();
    final passController = useTextEditingController();
    final authChoice = useState(AuthType.basic);
    final credsRejected = useState(false);

    // The URL field carries the full address (scheme + host + port), so never
    // let the client auto-append a port.
    useEffect(() {
      Future.microtask(
          () => ref.read(serverPortToggleProvider.notifier).update(false));
      return null;
    }, const []);

    void resetToIdle() {
      if (state.value != _TestState.idle) {
        state.value = _TestState.idle;
        onVerifiedChanged(false);
      }
    }

    // Persist a resolved/typed base URL as the active server URL.
    void adopt(String url) {
      resolvedUrl.value = url;
      ref.read(serverPortToggleProvider.notifier).update(false);
      ref.read(serverUrlProvider.notifier).update(url);
      if (urlController.text != url) urlController.text = url;
    }

    // Validate + commit the entered credentials against [base] using
    // [authChoice], via the SAME performSignIn the Connection settings screen
    // uses — the wizard must not run its own login path. Returns true
    // on success; a thrown rejection (bad creds / wrong auth mode) reads as
    // false. [client] is retained for the connection-probe callers above.
    Future<bool> validateCredentials(String base, http.Client client) async {
      final user = userController.text.trim();
      final pass = passController.text;
      if (user.isEmpty || pass.isEmpty) return false;
      if (authChoice.value == AuthType.none) return false;
      // Basic auth has no login round-trip that can fail, so the wizard
      // pre-flights it before committing: confirm it's really Suwayomi over
      // Basic AND that these creds actually authorise the @RequireAuth API —
      // otherwise picking the wrong auth type would "succeed" against a server
      // whose public aboutServer answers regardless of credentials. ui/simple
      // need no pre-flight: performSignIn's login round-trip throws on rejection.
      if (authChoice.value == AuthType.basic) {
        if (!await basicAuthConfirms(base,
            client: client, username: user, password: pass)) {
          return false;
        }
        if (!await authProbeAuthorized(base,
            client: client, basic: '$user:$pass')) {
          return false;
        }
      }
      try {
        await performSignIn(
          ref,
          authType: authChoice.value,
          serverBaseUrl: base,
          username: user,
          password: pass,
        );
      } catch (_) {
        return false;
      }
      ref.read(authTypeKeyProvider.notifier).update(authChoice.value);
      return true;
    }

    // Web can't run the redirect-OFF candidate ladder, so test the typed
    // address (scheme filled in — a scheme-less URL would resolve relative to
    // the page origin) via the about query, then detect auth with the same
    // @RequireAuth probe the native resolver uses.
    Future<void> testWeb() async {
      final typed = urlController.text.trim();
      if (typed.isBlank) return;
      final url = normalisedFallbackUrl(typed);
      state.value = _TestState.testing;
      version.value = null;
      errorDetail.value = null;
      credsRejected.value = false;
      onVerifiedChanged(false);
      ref.read(serverPortToggleProvider.notifier).update(false);
      ref.read(serverUrlProvider.notifier).update(url);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final result = await AsyncValue.guard(
          () => ref.read(aboutRepositoryProvider).getAbout());
      if (result.hasError || result.value == null) {
        errorDetail.value = result.error?.toString();
        state.value = _TestState.failed;
        onVerifiedChanged(false);
        return;
      }
      version.value = result.value?.version;
      resolvedUrl.value = url;
      final client = ref.read(onboardingHttpClientProvider)();
      try {
        if (!await webAuthRequired(url, client: client)) {
          state.value = _TestState.connected;
          onVerifiedChanged(true);
          return;
        }
        final hasCreds = userController.text.trim().isNotEmpty &&
            passController.text.isNotEmpty;
        if (hasCreds && await validateCredentials(url, client)) {
          state.value = _TestState.connected;
          onVerifiedChanged(true);
        } else {
          if (hasCreds) credsRejected.value = true;
          state.value = _TestState.needsLogin;
          onVerifiedChanged(false);
        }
      } finally {
        client.close();
      }
    }

    // "Test connection": validate the address. Auto-fallback (scheme/port) runs
    // under the hood. The first press detects whether a login is needed; once
    // credentials are entered, pressing again validates them.
    Future<void> testConnection() async {
      final input = urlController.text.trim();
      if (input.isBlank) {
        errorDetail.value = context.l10n.onboardingEnterAddress;
        state.value = _TestState.failed;
        onVerifiedChanged(false);
        return;
      }
      if (kIsWeb) return testWeb();

      state.value = _TestState.testing;
      version.value = null;
      errorDetail.value = null;
      credsRejected.value = false;
      onVerifiedChanged(false);

      final client = ref.read(onboardingHttpClientProvider)();
      try {
        final result = await resolveServer(input, client: client);
        switch (result.outcome) {
          case ResolveOutcome.notReached:
            state.value = _TestState.failed;
            onVerifiedChanged(false);
          case ResolveOutcome.reachedUnconfirmed:
            resolvedUrl.value = result.baseUrl;
            state.value = _TestState.notSuwayomi;
            onVerifiedChanged(false);
          case ResolveOutcome.found:
          case ResolveOutcome.basicGated:
            adopt(result.baseUrl);
            version.value = result.serverVersion;
            final needsLogin = result.outcome == ResolveOutcome.basicGated ||
                result.authMode == ProbeAuthMode.authRequired;
            if (!needsLogin) {
              state.value = _TestState.connected;
              onVerifiedChanged(true);
            } else {
              final hasCreds = userController.text.trim().isNotEmpty &&
                  passController.text.isNotEmpty;
              if (hasCreds &&
                  await validateCredentials(result.baseUrl, client)) {
                state.value = _TestState.connected;
                onVerifiedChanged(true);
              } else {
                if (hasCreds) credsRejected.value = true;
                state.value = _TestState.needsLogin;
                onVerifiedChanged(false);
              }
            }
        }
      } catch (e) {
        errorDetail.value = e.toString();
        state.value = _TestState.failed;
        onVerifiedChanged(false);
      } finally {
        client.close();
      }
    }

    // "Search my network": scan the LAN for a Suwayomi server on :4567, fill
    // the field, then test it.
    Future<void> searchNetwork() async {
      if (kIsWeb) return;
      final noServerMsg = context.l10n.onboardingNoServerFound;
      state.value = _TestState.searching;
      errorDetail.value = null;
      onVerifiedChanged(false);
      String? found;
      try {
        found = await discoverServerOnLan();
      } catch (_) {
        found = null;
      }
      if (found == null) {
        errorDetail.value = noServerMsg;
        state.value = _TestState.failed;
        onVerifiedChanged(false);
        return;
      }
      urlController.text = found;
      await testConnection();
    }

    // "Sign in": validate the entered credentials against the resolved server
    // and, on success, unlock Next. Clear, dedicated action that lives right
    // under the credential fields.
    Future<void> signIn() async {
      final base = resolvedUrl.value ?? urlController.text.trim();
      final user = userController.text.trim();
      final pass = passController.text;
      if (base.isEmpty || user.isEmpty || pass.isEmpty) {
        credsRejected.value = true;
        return;
      }
      credsRejected.value = false;
      state.value = _TestState.testing;
      final client = ref.read(onboardingHttpClientProvider)();
      bool ok = false;
      try {
        ok = await validateCredentials(base, client);
      } catch (_) {
        ok = false;
      } finally {
        client.close();
      }
      if (ok) {
        state.value = _TestState.connected;
        onVerifiedChanged(true);
      } else {
        credsRejected.value = true;
        state.value = _TestState.needsLogin;
        onVerifiedChanged(false);
      }
    }

    final busy = state.value == _TestState.testing ||
        state.value == _TestState.searching;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(context.l10n.onboardingServerStepLabel,
            style: TextStyle(
                color: cs.primary, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(context.l10n.onboardingServerTitle,
            style: context.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(context.l10n.onboardingServerSubtitle,
            style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 20),
        TextField(
          controller: urlController,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: context.l10n.serverUrl,
            hintText: 'http://192.168.0.10:4567',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.dns_rounded),
          ),
          onChanged: (_) => resetToIdle(),
        ),
        // Discover: scan the LAN and fill the address.
        if (!kIsWeb)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: busy ? null : searchNetwork,
              icon: state.value == _TestState.searching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search_rounded, size: 18),
              label: Text(state.value == _TestState.searching
                  ? context.l10n.onboardingSearching
                  : context.l10n.onboardingSearchNetwork),
            ),
          ),
        Text(context.l10n.onboardingServerPortHint,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 12),
        // Validate: test the connection.
        FilledButton.tonalIcon(
          onPressed: busy ? null : testConnection,
          icon: state.value == _TestState.testing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.wifi_tethering_rounded),
          label: Text(context.l10n.onboardingTestConnection),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
        ),
        const SizedBox(height: 12),
        ..._buildTestStatus(
            context,
            cs,
            state.value,
            resolvedUrl.value,
            version.value,
            errorDetail.value,
            shouldSuggestHttps(urlController.text.trim())),
        // Auth sub-form, revealed only when the server needs a login.
        if (state.value == _TestState.needsLogin) ...[
          const SizedBox(height: 12),
          // M3 DropdownMenu (not the legacy DropdownButtonFormField, whose menu
          // anchors the selected item over the field and can open upward over
          // other content, wider than the field). This opens below, sized to
          // the field. Keyed by the selection so it re-seeds if changed.
          DropdownMenu<AuthType>(
            key: ValueKey(authChoice.value),
            initialSelection: authChoice.value,
            expandedInsets: EdgeInsets.zero,
            requestFocusOnTap: false,
            label: Text(context.l10n.onboardingAuthMode),
            leadingIcon: const Icon(Icons.shield_rounded),
            inputDecorationTheme:
                const InputDecorationTheme(border: OutlineInputBorder()),
            dropdownMenuEntries: [
              DropdownMenuEntry(
                  value: AuthType.basic,
                  label: context.l10n.onboardingAuthModeBasic),
              DropdownMenuEntry(
                  value: AuthType.simpleLogin,
                  label: context.l10n.onboardingAuthModeSimple),
              DropdownMenuEntry(
                  value: AuthType.uiLogin,
                  label: context.l10n.onboardingAuthModeUi),
            ],
            onSelected: (m) {
              if (m != null) {
                authChoice.value = m;
                credsRejected.value = false;
              }
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: userController,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: context.l10n.userName,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.person_rounded),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: passController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: context.l10n.password,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.lock_rounded),
            ),
            onSubmitted: (_) => signIn(),
          ),
          if (credsRejected.value) ...[
            const SizedBox(height: 8),
            _StatusRow(
              color: cs.error,
              icon: Icons.error_rounded,
              text: context.l10n.onboardingCredsRejected,
            ),
          ],
          const SizedBox(height: 12),
          // The clear, dedicated action right under the credentials.
          FilledButton.icon(
            onPressed: busy ? null : signIn,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.login_rounded),
            label: Text(context.l10n.onboardingSignIn),
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
          ),
        ],
        const SizedBox(height: 8),
        // No server yet? Open the setup docs and let them proceed — Library then
        // shows the friendly "set up a server" empty state.
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              launchUrlInWeb(
                  context, AppUrls.tachideskHelp.url, ref.read(toastProvider));
              onVerifiedChanged(true);
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(context.l10n.onboardingNoServerLink),
          ),
        ),
      ],
    );
  }
}

/// Renders the Test-connection outcome row(s) — always naming the exact
/// address (with explicit port) we reached.
List<Widget> _buildTestStatus(
  BuildContext context,
  ColorScheme cs,
  _TestState state,
  String? url,
  String? version,
  String? errorDetail,
  bool suggestHttps,
) {
  final addr = (url != null && url.isNotEmpty) ? displayAddress(url) : null;
  switch (state) {
    case _TestState.idle:
    case _TestState.testing:
    case _TestState.searching:
      return const [SizedBox.shrink()];

    case _TestState.connected:
      return [
        _StatusRow(
          color: Colors.green,
          icon: Icons.check_circle_rounded,
          text: (version != null && version.isNotEmpty)
              // The server reports "v2.3.x"; the l10n string adds its own "v".
              ? context.l10n.onboardingConnected(
                  version.startsWith('v') ? version.substring(1) : version)
              : context.l10n.onboardingResolvedAddress(addr ?? ''),
        ),
        if (addr != null) ...[
          const SizedBox(height: 6),
          _StatusRow(
            color: cs.onSurfaceVariant,
            icon: Icons.dns_rounded,
            text: context.l10n.onboardingFoundAt(addr),
          ),
        ],
      ];

    case _TestState.needsLogin:
      return [
        _StatusRow(
          color: cs.tertiary,
          icon: Icons.lock_rounded,
          text: context.l10n.onboardingNeedsLogin,
        ),
        if (addr != null) ...[
          const SizedBox(height: 6),
          _StatusRow(
            color: cs.onSurfaceVariant,
            icon: Icons.dns_rounded,
            text: context.l10n.onboardingFoundAt(addr),
          ),
        ],
      ];

    case _TestState.notSuwayomi:
      return [
        _StatusRow(
          color: cs.tertiary,
          icon: Icons.help_outline_rounded,
          text: context.l10n.onboardingResolvedUnconfirmed(addr ?? ''),
        ),
      ];

    case _TestState.failed:
      return [
        _StatusRow(
          color: cs.error,
          icon: Icons.error_rounded,
          text: (errorDetail?.isNotEmpty ?? false)
              ? errorDetail!
              : context.l10n.onboardingNotReached,
        ),
        if (suggestHttps) ...[
          const SizedBox(height: 6),
          _StatusRow(
            color: cs.onSurfaceVariant,
            icon: Icons.lightbulb_outline_rounded,
            text: context.l10n.onboardingNotReachedHttpsHint,
          ),
        ],
      ];
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow(
      {required this.color, required this.icon, required this.text});
  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: color))),
      ],
    );
  }
}

// --- Step 3: finish ---------------------------------------------------------

class _FinishStep extends StatelessWidget {
  const _FinishStep();

  @override
  Widget build(BuildContext context) {
    final cs = context.theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 48),
        Icon(Icons.rocket_launch_rounded, size: 64, color: cs.primary),
        const SizedBox(height: 24),
        Text(context.l10n.onboardingDoneTitle,
            textAlign: TextAlign.center,
            style: context.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(context.l10n.onboardingDoneSubtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant)),
      ],
    );
  }
}
