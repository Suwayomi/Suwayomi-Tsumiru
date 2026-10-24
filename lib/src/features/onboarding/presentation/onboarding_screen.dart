// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:graphql/client.dart';
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
import '../../../utils/motion/reduce_motion.dart';
import '../../../utils/network/graphql_errors.dart';
import '../../../utils/platform/web_auth_mode.dart';
import '../../../utils/theme/brand.dart';
import '../../account/data/account_actions.dart';
import '../../account/data/account_providers.dart';
import '../../account/data/server_account_capability.dart';
import '../../account/domain/account_access.dart';
import '../../account/presentation/account_code_dialog.dart';
import '../../auth/data/auth_coordinator.dart';
import '../../auth/data/auth_credentials_store.dart';
import '../../auth/data/custom_headers_store.dart';
import '../../auth/data/ui_login_token_rejected.dart';
import '../../auth/presentation/sign_in_action.dart';
import '../../settings/presentation/appearance/widgets/app_theme_selector/app_theme_selector.dart';
import '../../settings/presentation/connection/custom_headers_section.dart';
import '../../settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../../settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../../settings/widgets/app_theme_mode_tile/app_theme_mode_tile.dart';
import '../data/onboarding_complete.dart';
import '../data/server_discovery.dart';
import '../data/server_resolver.dart';
import 'onboarding_sign_in.dart';

class OnboardingScreen extends HookConsumerWidget {
  const OnboardingScreen({super.key});

  static const _stepCount = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(sharedPreferencesProvider);
    final resume =
        ref.watch(onboardingCompleteProvider) != true &&
        preferences.getInt('onboarding.step') == 2;
    final step = useState(
      resume ? 2 : (preferences.getInt('onboarding.step') ?? 0).clamp(0, 1),
    );
    final serverVerified = useState(resume);
    final nextRequest = useState(0);
    final activity = useState<String?>(null);
    useEffect(() {
      if (resume) {
        Future.microtask(() {
          if (!context.mounted) return;
          step.value = 2;
          serverVerified.value = true;
        });
      }
      return null;
    }, [resume]);

    Future<void> moveTo(int next) async {
      nextRequest.value = 0;
      await preferences.setInt('onboarding.step', next.clamp(0, 1));
      if (context.mounted) step.value = next;
    }

    final isLast = step.value == _stepCount - 1;

    void finish() {
      preferences.setInt('onboarding.step', 0);
      ref.read(onboardingCompleteProvider.notifier).update(true);
      const LibraryRoute(categoryId: 0).go(context);
    }

    final cs = context.theme.colorScheme;

    return Scaffold(
      body: Stack(
        children: [
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
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        const _BrandHeader(),
                        if (step.value < _stepCount - 1)
                          Positioned(
                            right: 4,
                            child: TextButton(
                              onPressed: activity.value == null ? finish : null,
                              child: Text(context.l10n.onboardingSkip),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _StepDots(count: _stepCount, active: step.value),
                    Expanded(
                      child: _StepSwitcher(
                        child: SingleChildScrollView(
                          key: ValueKey(step.value),
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                          child: switch (step.value) {
                            0 => const _ThemeStep(),
                            1 => _ServerStep(
                              nextRequest: nextRequest.value,
                              onActivityChanged: (value) {
                                if (context.mounted && step.value == 1) {
                                  activity.value = value;
                                }
                              },
                              onVerifiedChanged: (v) =>
                                  serverVerified.value = v,
                              onSignedIn: () {
                                activity.value = null;
                                serverVerified.value = true;
                                step.value = 2;
                              },
                            ),
                            _ => const _FinishStep(),
                          },
                        ),
                      ),
                    ),
                    _NavBar(
                      activity: step.value == 1 ? activity.value : null,
                      showBack: step.value > 0,
                      isLast: isLast,
                      onBack: () => moveTo(step.value - 1),
                      onNext: () {
                        if (step.value == 1) {
                          nextRequest.value++;
                        } else if (isLast) {
                          finish();
                        } else {
                          moveTo(step.value + 1);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

AssetGenImage _brandLogo(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light
    ? Assets.icons.logoOnLight
    : Assets.icons.darkIcon;

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset(_brandLogo(context).path, height: 26),
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

class _StepSwitcher extends StatelessWidget {
  const _StepSwitcher({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => context.reduceMotion
      ? child
      : AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: child,
        );
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
          _StepDot(
            width: i == active ? 22 : 8,
            color: i == active
                ? cs.primary
                : cs.onSurface.withValues(alpha: 0.22),
          ),
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.width, required this.color});
  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const margin = EdgeInsets.symmetric(horizontal: 4, vertical: 12);
    final decoration = BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(4),
    );
    return context.reduceMotion
        ? Container(
            margin: margin,
            width: width,
            height: 8,
            decoration: decoration,
          )
        : AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: margin,
            width: width,
            height: 8,
            decoration: decoration,
          );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.showBack,
    required this.activity,
    required this.isLast,
    required this.onBack,
    required this.onNext,
  });
  final String? activity;
  final bool showBack;
  final bool isLast;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final next = BrandButton(
      label: Text(isLast ? context.l10n.finish : context.l10n.next),
      onPressed: activity == null ? onNext : null,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (activity != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Semantics(liveRegion: true, child: Text(activity!)),
                  ),
                ],
              ),
            ),
          showBack
              ? Row(
                  children: [
                    Expanded(
                      child: BrandGlassButton(
                        label: Text(context.l10n.back),
                        onPressed: activity == null ? onBack : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: next),
                  ],
                )
              : next,
        ],
      ),
    );
  }
}


class _ThemeStep extends ConsumerWidget {
  const _ThemeStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = context.theme.colorScheme;
    final mode = ref.watch(appThemeModeProvider) ?? ThemeMode.system;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Center(
          child: Image.asset(
            _brandLogo(context).path,
            height: _compactLogo(MediaQuery.sizeOf(context)) ? 96 : 160,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          context.l10n.onboardingWelcomeTitle,
          style: context.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.onboardingWelcomeSubtitle,
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 28),
        Text(context.l10n.appearance, style: context.textTheme.titleMedium),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(
                value: ThemeMode.system,
                icon: const Icon(FluentIcons.dark_theme_24_regular),
                label: Text(context.l10n.themeModeSystem),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: const Icon(FluentIcons.weather_sunny_24_regular),
                label: Text(context.l10n.themeModeLight),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: const Icon(FluentIcons.weather_moon_24_regular),
                label: Text(context.l10n.themeModeDark),
              ),
            ],
            selected: {mode},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                ref.read(appThemeModeProvider.notifier).update(selection.first),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? cs.secondaryContainer
                    : null,
              ),
              foregroundColor: WidgetStatePropertyAll(cs.onSurface),
              side: WidgetStatePropertyAll(
                BorderSide(color: cs.outlineVariant),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        ThemeSelector(
          title: Text(
            context.l10n.onboardingChooseTheme,
            style: context.textTheme.titleMedium,
          ),
        ),
      ],
    );
  }
}


enum _TestState {
  idle,
  searching,
  testing,
  signingIn,
  connected,

  needsLogin,

  failed,

  /// Web cannot use this server mode across origins.
  unsupportedAuth,

  notSuwayomi,
}

final onboardingHttpClientProvider = Provider<http.Client Function()>(
  (Ref ref) => http.Client.new,
);

/// Accepts confirmed Suwayomi or Basic-gated hosts; closes [client].
@visibleForTesting
Future<DiscoveredServer?> confirmLanServer(
  String url, {
  required http.Client client,
  Map<String, String>? extraHeaders,
}) async {
  try {
    final result = await probeServer(
      url,
      client: client,
      extraHeaders: extraHeaders,
    );
    if (!result.confirmed && !result.basicGated) return null;
    return DiscoveredServer(
      url: url,
      name: result.serverName,
      version: result.serverVersion,
    );
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

final lanServerScanProvider =
    Provider<Future<List<DiscoveredServer>> Function()>(
      (ref) =>
          () => discoverServersOnLan(
            confirm: (url) => confirmLanServer(
              url,
              client: ref.read(onboardingHttpClientProvider)(),
              extraHeaders: ref.read(customHttpHeadersProvider).value,
            ),
          ),
    );

String _serverLabel(DiscoveredServer server) {
  final name = server.name?.trim();
  final version = server.version?.trim().replaceFirst(RegExp(r'^[vV]'), '');
  if (name == null || name.isEmpty) return server.address;
  final titled = (version == null || version.isEmpty)
      ? name
      : '$name v$version';
  return '$titled · ${server.address}';
}

class _ServerPickerSheet extends StatelessWidget {
  const _ServerPickerSheet({required this.servers});

  final List<DiscoveredServer> servers;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Text(
                context.l10n.onboardingChooseServer,
                style: context.theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Divider(height: 1),
            for (final server in servers)
              ListTile(
                leading: const Icon(FluentIcons.server_24_regular),
                title: Text(_serverLabel(server)),
                onTap: () => Navigator.pop(context, server),
              ),
          ],
        ),
      ),
    );
  }
}

class _ServerStep extends HookConsumerWidget {
  const _ServerStep({
    required this.nextRequest,
    required this.onActivityChanged,
    required this.onVerifiedChanged,
    required this.onSignedIn,
  });
  final ValueChanged<String?> onActivityChanged;
  final int nextRequest;
  final ValueChanged<bool> onVerifiedChanged;
  final VoidCallback onSignedIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = context.theme.colorScheme;
    final isWeb = ref.watch(isWebProvider);
    final urlController = useTextEditingController(
      text: () {
        final stored = ref.read(serverExternalUrlProvider);
        return (stored == null || stored == DBKeys.serverUrl.initial)
            ? ''
            : stored;
      }(),
    );
    final preferences = ref.watch(sharedPreferencesProvider);
    final pendingProbe = useMemoized(
      () => preferences.getString('onboarding.pendingProbe'),
    );
    final state = useState(_TestState.idle);
    final version = useState<String?>(null);
    final errorDetail = useState<String?>(null);
    final resolvedUrl = useState<String?>(null);
    final userController = useTextEditingController();
    final passController = useTextEditingController();
    final authChoice = useState(onboardingAuthChoices(isWeb: isWeb).first);
    // A manual auth choice must take precedence over detection.
    final userChangedAuth = useState(false);
    final credsRejected = useState(false);
    final unsupportedAfterLogin = useState(false);
    final unsupportedFromNotFound = useState(false);
    final serverAccountCapability = useState(AccountCapability.unknown);
    final capabilityGeneration = useRef(0);
    final showAccountCodes =
        authChoice.value == AuthType.uiLogin &&
        (ref.watch(authTypeKeyProvider) != AuthType.uiLogin ||
            ref.watch(settledAccountAccessProvider).capability !=
                AccountCapability.unsupported) &&
        serverAccountCapability.value != AccountCapability.unsupported;

    void applyDetectedAuth(AuthType? detected) {
      if (!userChangedAuth.value) {
        authChoice.value =
            detected ?? (isWeb ? AuthType.uiLogin : AuthType.basic);
      }
    }

    void resetToIdle() {
      if (state.value != _TestState.idle) {
        state.value = _TestState.idle;
        onVerifiedChanged(false);
      }
    }

    Future<void> refreshServerAccountCapability(
      String base,
      http.Client client,
    ) async {
      if (authChoice.value != AuthType.uiLogin) return;
      final generation = ++capabilityGeneration.value;
      final capability = await probeServerAccountCapability(
        base,
        client: client,
        headers: ref.read(customHttpHeadersProvider).value,
      );
      if (!context.mounted) return;
      if (generation != capabilityGeneration.value) return;
      if (base != resolvedUrl.value) return;
      serverAccountCapability.value = capability;
    }

    Future<void> adopt(String url) async {
      resolvedUrl.value = url;
      final ports = ref.read(serverPortToggleProvider.notifier);
      await ports.update(false);
      if (!context.mounted) return;
      await ref.read(serverExternalUrlProvider.notifier).update(url);
      if (!context.mounted) return;
      if (urlController.text != url) urlController.text = url;
    }

    Future<void> openCodeDialog(AccountCodeMode mode) async {
      final base = resolvedUrl.value;
      if (base == null || base.isEmpty) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AccountCodeDialog(
          mode: mode,
          onSubmit: ({required code, username, required password}) async {
            await finishOnboardingSignIn(ref, () async {
              await adopt(base);
              await ref
                  .read(accountActionsProvider)
                  .redeemCode(
                    code: code,
                    username: username,
                    password: password,
                  );
            });
          },
        ),
        animationStyle: context.motionStyle,
      );
      if (context.mounted && preferences.getInt('onboarding.step') == 2) {
        onSignedIn();
      }
    }

    Future<bool> validateCredentials(String base, http.Client client) async {
      final user = userController.text.trim();
      final pass = passController.text;
      if (user.isEmpty || pass.isEmpty) return false;
      if (authChoice.value == AuthType.none) return false;
      // Basic auth must confirm Suwayomi and authorize a protected query; public aboutServer is insufficient.
      if (authChoice.value == AuthType.basic) {
        final extra = ref.read(customHttpHeadersProvider).value;
        if (!await basicAuthConfirms(
          base,
          client: client,
          username: user,
          password: pass,
          extraHeaders: extra,
        )) {
          return false;
        }
        if (!await authProbeAuthorized(
          base,
          client: client,
          basic: '$user:$pass',
          extraHeaders: extra,
        )) {
          return false;
        }
      }
      try {
        final coordinator = ref.read(authCoordinatorProvider.notifier);
        if (authChoice.value == AuthType.uiLogin) {
          await coordinator.verifyUiCredentials(
            gqlClient: GraphQLClient(
              link: HttpLink(
                graphqlUriFor(base).toString(),
                httpClient: client,
                httpResponseDecoder: tsumiruHttpResponseDecoder,
                defaultHeaders:
                    ref.read(customHttpHeadersProvider).value ?? const {},
              ),
              cache: GraphQLCache(store: InMemoryStore()),
            ),
            username: user,
            password: pass,
          );
        } else if (authChoice.value == AuthType.simpleLogin) {
          await coordinator.verifySimpleCredentials(
            serverBaseUrl: base,
            username: user,
            password: pass,
          );
        }
        await finishOnboardingSignIn(ref, () async {
          await adopt(base);
          await performSignIn(
            ref,
            authType: authChoice.value,
            serverBaseUrl: base,
            username: user,
            password: pass,
          );
        });
      } catch (e) {
        if (e is UiLoginTokenRejected) unsupportedAfterLogin.value = true;
        return false;
      }
      if (context.mounted) onSignedIn();
      return true;
    }

    Future<void> completeConnection() async {
      final base = resolvedUrl.value;
      if (base == null) return;
      await finishOnboardingSignIn(ref, () => adopt(base));
      if (context.mounted) onSignedIn();
    }

    Future<void> markConnected() async {
      state.value = _TestState.connected;
      onVerifiedChanged(true);
      if (preferences.getBool('onboarding.advanceAfterProbe') == true) {
        await completeConnection();
      }
    }

    Future<void> testWeb() async {
      final typed = urlController.text.trim();
      if (typed.isBlank) return;
      final url = validServerBaseUrl(typed);
      if (url == null) {
        errorDetail.value = context.l10n.invalidProp(context.l10n.serverUrl);
        state.value = _TestState.failed;
        onVerifiedChanged(false);
        return;
      }
      state.value = _TestState.testing;
      version.value = null;
      errorDetail.value = null;
      credsRejected.value = false;
      unsupportedAfterLogin.value = false;
      unsupportedFromNotFound.value = false;
      capabilityGeneration.value++;
      serverAccountCapability.value = AccountCapability.unknown;
      onVerifiedChanged(false);
      final client = ref.read(onboardingHttpClientProvider)();
      try {
        final graphQl = GraphQLClient(
          link: HttpLink(
            graphqlUriFor(url).toString(),
            httpClient: client,
            httpResponseDecoder: tsumiruHttpResponseDecoder,
            defaultHeaders:
                ref.read(customHttpHeadersProvider).value ?? const {},
          ),
          cache: GraphQLCache(store: InMemoryStore()),
        );
        final result = await graphQl.query(
          QueryOptions(
            document: gql(kAboutProbeQuery),
            fetchPolicy: FetchPolicy.noCache,
          ),
        );
        if (!context.mounted) return;
        final about = result.data?['aboutServer'];
        if (result.hasException || about == null) {
          final failure = result.exception;
          if (webServerAuthUnsupported(
            aboutError: failure,
            detectedAuthType: null,
          )) {
            unsupportedFromNotFound.value =
                failure != null && isBasicGatedNotFound(failure);
            state.value = _TestState.unsupportedAuth;
            onVerifiedChanged(false);
            return;
          }
          errorDetail.value = failure?.toString();
          state.value = _TestState.failed;
          onVerifiedChanged(false);
          return;
        }
        version.value = about['version'] as String?;
        resolvedUrl.value = url;
        final probe = await webAuthProbe(
          url,
          client: client,
          extraHeaders: ref.read(customHttpHeadersProvider).value,
        );
        if (!probe.required) {
          await markConnected();
          return;
        }
        if (webServerAuthUnsupported(
          aboutError: null,
          detectedAuthType: probe.detected,
        )) {
          state.value = _TestState.unsupportedAuth;
          onVerifiedChanged(false);
          return;
        }
        applyDetectedAuth(probe.detected);
        final hasCreds =
            userController.text.trim().isNotEmpty &&
            passController.text.isNotEmpty;
        if (hasCreds && await validateCredentials(url, client)) return;
        if (!context.mounted) return;
        if (unsupportedAfterLogin.value) {
          state.value = _TestState.unsupportedAuth;
          onVerifiedChanged(false);
          return;
        }
        if (hasCreds) credsRejected.value = true;
        state.value = _TestState.needsLogin;
        onVerifiedChanged(false);
        await refreshServerAccountCapability(url, client);
      } catch (e) {
        if (!context.mounted) return;
        errorDetail.value = e.toString();
        state.value = _TestState.failed;
        onVerifiedChanged(false);
      } finally {
        client.close();
      }
    }

    Future<void> testConnection() async {
      final input = urlController.text.trim();
      if (input.isBlank) {
        errorDetail.value = context.l10n.onboardingEnterAddress;
        state.value = _TestState.failed;
        onVerifiedChanged(false);
        return;
      }
      if (validServerBaseUrl(input) == null) {
        errorDetail.value = context.l10n.invalidProp(context.l10n.serverUrl);
        state.value = _TestState.failed;
        onVerifiedChanged(false);
        if (context.mounted) {
          await preferences.setString('onboarding.pendingProbe', '');
          await preferences.setBool('onboarding.advanceAfterProbe', false);
        }
        return;
      }
      state.value = _TestState.testing;
      version.value = null;
      errorDetail.value = null;
      credsRejected.value = false;
      unsupportedAfterLogin.value = false;
      unsupportedFromNotFound.value = false;
      capabilityGeneration.value++;
      serverAccountCapability.value = AccountCapability.unknown;
      onVerifiedChanged(false);
      final sessionIsCurrent = ref
          .read(authCredentialsStoreProvider.notifier)
          .captureSession();
      await preferences.setString('onboarding.pendingProbe', input);
      if (!context.mounted) return;
      if (isWeb) {
        try {
          await testWeb();
        } finally {
          if (context.mounted && sessionIsCurrent()) {
            await preferences.setString('onboarding.pendingProbe', '');
            await preferences.setBool('onboarding.advanceAfterProbe', false);
          }
        }
        return;
      }

      final client = ref.read(onboardingHttpClientProvider)();
      try {
        final result = await resolveServer(
          input,
          client: client,
          extraHeaders: ref.read(customHttpHeadersProvider).value,
        );
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
            resolvedUrl.value = result.baseUrl;
            if (urlController.text != result.baseUrl) {
              urlController.text = result.baseUrl;
            }
            version.value = result.serverVersion;
            final needsLogin =
                result.outcome == ResolveOutcome.basicGated ||
                result.authMode == ProbeAuthMode.authRequired;
            if (!needsLogin) {
              await markConnected();
            } else {
              applyDetectedAuth(result.detectedAuthType);
              final hasCreds =
                  userController.text.trim().isNotEmpty &&
                  passController.text.isNotEmpty;
              if (hasCreds &&
                  await validateCredentials(result.baseUrl, client)) {
                return;
              }
              if (!context.mounted) return;
              if (hasCreds) credsRejected.value = true;
              state.value = _TestState.needsLogin;
              onVerifiedChanged(false);
              await refreshServerAccountCapability(result.baseUrl, client);
            }
        }
      } catch (e) {
        if (!context.mounted) return;
        errorDetail.value = e.toString();
        state.value = _TestState.failed;
        onVerifiedChanged(false);
      } finally {
        client.close();
        if (context.mounted && sessionIsCurrent()) {
          await preferences.setString('onboarding.pendingProbe', '');
          await preferences.setBool('onboarding.advanceAfterProbe', false);
        }
      }
    }

    useEffect(() {
      if (pendingProbe?.isNotEmpty == true) {
        Future.microtask(() async {
          if (!context.mounted) return;
          urlController.text = pendingProbe!;
          await testConnection();
        });
      }
      return null;
    }, const []);

    Future<void> searchNetwork() async {
      if (isWeb) return;
      final noServerMsg = context.l10n.onboardingNoServerFound;
      state.value = _TestState.searching;
      errorDetail.value = null;
      onVerifiedChanged(false);
      List<DiscoveredServer> found;
      try {
        found = await ref.read(lanServerScanProvider)();
      } catch (_) {
        found = const [];
      }
      if (!context.mounted) return;
      if (found.isEmpty) {
        errorDetail.value = noServerMsg;
        state.value = _TestState.failed;
        onVerifiedChanged(false);
        return;
      }
      var chosen = found.first;
      if (found.length > 1) {
        resetToIdle();
        final picked = await showModalBottomSheet<DiscoveredServer>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (_) => _ServerPickerSheet(servers: found),
          sheetAnimationStyle: context.motionStyle,
        );
        if (!context.mounted) return;
        if (picked == null) return;
        chosen = picked;
      }
      urlController.text = chosen.url;
      await testConnection();
    }

    Future<void> signIn() async {
      final base = resolvedUrl.value ?? urlController.text.trim();
      final user = userController.text.trim();
      final pass = passController.text;
      if (base.isEmpty || user.isEmpty || pass.isEmpty) {
        credsRejected.value = true;
        return;
      }
      credsRejected.value = false;
      unsupportedAfterLogin.value = false;
      unsupportedFromNotFound.value = false;
      state.value = _TestState.signingIn;
      final client = ref.read(onboardingHttpClientProvider)();
      bool ok = false;
      try {
        ok = await validateCredentials(base, client);
      } catch (_) {
        ok = false;
      } finally {
        client.close();
      }
      if (ok || !context.mounted) return;
      if (unsupportedAfterLogin.value) {
        state.value = _TestState.unsupportedAuth;
        onVerifiedChanged(false);
        return;
      }
      credsRejected.value = true;
      state.value = _TestState.needsLogin;
      onVerifiedChanged(false);
    }

    useEffect(() {
      if (nextRequest == 0) return null;
      Future.microtask(() async {
        if (!context.mounted ||
            state.value == _TestState.testing ||
            state.value == _TestState.signingIn ||
            state.value == _TestState.searching) {
          return;
        }
        if (state.value == _TestState.connected) {
          await completeConnection();
        } else if (state.value == _TestState.needsLogin) {
          await signIn();
        } else {
          if (urlController.text.trim().isNotEmpty) {
            await preferences.setBool('onboarding.advanceAfterProbe', true);
          }
          if (context.mounted) await testConnection();
        }
      });
      return null;
    }, [nextRequest]);

    final busy =
        state.value == _TestState.testing ||
        state.value == _TestState.signingIn ||
        state.value == _TestState.searching;
    final activity = switch (state.value) {
      _TestState.testing => context.l10n.onboardingCheckingConnection,
      _TestState.signingIn => context.l10n.onboardingSigningIn,
      _TestState.searching => context.l10n.onboardingSearching,
      _ => null,
    };
    useEffect(() {
      Future.microtask(() {
        if (context.mounted) onActivityChanged(activity);
      });
      return null;
    }, [activity]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          context.l10n.onboardingServerStepLabel,
          style: TextStyle(
            color: cs.primary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          context.l10n.onboardingServerTitle,
          style: context.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: urlController,
          enabled: !busy,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: context.l10n.serverUrl,
            hintText: 'http://192.168.0.10:4567',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(FluentIcons.server_24_regular),
          ),
          onChanged: (_) {
            capabilityGeneration.value++;
            serverAccountCapability.value = AccountCapability.unknown;
            resetToIdle();
          },
        ),
        if (!isWeb)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: busy ? null : searchNetwork,
              icon: state.value == _TestState.searching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(FluentIcons.search_24_regular, size: 18),
              label: Text(
                state.value == _TestState.searching
                    ? context.l10n.onboardingSearching
                    : context.l10n.onboardingSearchNetwork,
              ),
            ),
          ),
        Text(
          context.l10n.onboardingServerPortHint,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
        ),
        const SizedBox(height: 8),
        // Proxy access headers must be set before probing.
        const CustomHeadersSection(compact: true),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: busy ? null : testConnection,
          icon: state.value == _TestState.testing
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.onPrimary,
                  ),
                )
              : const Icon(FluentIcons.wifi_1_24_regular),
          label: Text(
            state.value == _TestState.testing
                ? context.l10n.onboardingCheckingConnection
                : context.l10n.onboardingTestConnection,
          ),
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
          validServerBaseUrl(urlController.text.trim()) != null &&
              shouldSuggestHttps(urlController.text.trim()),
          unsupportedFromNotFound.value,
        ),
        if (state.value == _TestState.needsLogin ||
            state.value == _TestState.signingIn) ...[
          const SizedBox(height: 12),
          // Key by selection so DropdownMenu reseeds after auth detection.
          DropdownMenu<AuthType>(
            key: ValueKey(authChoice.value),
            initialSelection: authChoice.value,
            expandedInsets: EdgeInsets.zero,
            requestFocusOnTap: false,
            label: Text(context.l10n.onboardingAuthMode),
            leadingIcon: const Icon(FluentIcons.shield_24_regular),
            trailingIcon: const Icon(
              FluentIcons.caret_down_24_filled,
            ),
            inputDecorationTheme: const InputDecorationTheme(
              border: OutlineInputBorder(),
            ),
            dropdownMenuEntries: [
              for (final mode in onboardingAuthChoices(isWeb: isWeb))
                DropdownMenuEntry(
                  value: mode,
                  label: switch (mode) {
                    AuthType.basic => context.l10n.onboardingAuthModeBasic,
                    AuthType.simpleLogin =>
                      context.l10n.onboardingAuthModeSimple,
                    AuthType.uiLogin => context.l10n.onboardingAuthModeUi,
                    AuthType.none => context.l10n.authTypeNone,
                  },
                ),
            ],
            onSelected: (m) {
              if (m != null) {
                userChangedAuth.value = true;
                authChoice.value = m;
                credsRejected.value = false;
                unsupportedAfterLogin.value = false;
                unsupportedFromNotFound.value = false;
                capabilityGeneration.value++;
                serverAccountCapability.value = AccountCapability.unknown;
                final base = resolvedUrl.value;
                if (m == AuthType.uiLogin &&
                    (state.value == _TestState.needsLogin ||
                        state.value == _TestState.signingIn) &&
                    base != null &&
                    base.isNotEmpty) {
                  final probeClient = ref.read(onboardingHttpClientProvider)();
                  refreshServerAccountCapability(
                    base,
                    probeClient,
                  ).whenComplete(probeClient.close);
                }
              }
            },
          ),
          if (isWeb &&
              !isSameOriginServer(
                pageOrigin: pageOriginOrNull(),
                serverAddress:
                    (resolvedUrl.value != null &&
                        resolvedUrl.value!.isNotEmpty)
                    ? resolvedUrl.value!
                    : urlController.text.trim(),
              ))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                context.l10n.webUiLoginOnlyHint,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: userController,
            enabled: !busy,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: context.l10n.userName,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(FluentIcons.person_24_regular),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: passController,
            enabled: !busy,
            obscureText: true,
            decoration: InputDecoration(
              labelText: context.l10n.password,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(FluentIcons.lock_closed_24_regular),
            ),
            onSubmitted: (_) => signIn(),
          ),
          if (showAccountCodes)
            Wrap(
              children: [
                TextButton(
                  onPressed: busy
                      ? null
                      : () => openCodeDialog(AccountCodeMode.registration),
                  child: Text(context.l10n.accountRegistrationTitle),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => openCodeDialog(AccountCodeMode.recovery),
                  child: Text(context.l10n.accountRecoveryTitle),
                ),
              ],
            ),
          if (credsRejected.value) ...[
            const SizedBox(height: 8),
            _StatusRow(
              color: cs.error,
              icon: FluentIcons.error_circle_24_regular,
              text: context.l10n.onboardingCredsRejected,
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: busy ? null : signIn,
            icon: busy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.onPrimary,
                    ),
                  )
                : const Icon(FluentIcons.arrow_enter_20_regular),
            label: Text(
              state.value == _TestState.signingIn
                  ? context.l10n.onboardingSigningIn
                  : context.l10n.onboardingSignIn,
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              launchUrlInWeb(
                context,
                AppUrls.tachideskHelp.url,
                ref.read(toastProvider),
              );
              onVerifiedChanged(true);
            },
            icon: const Icon(FluentIcons.open_24_regular, size: 18),
            label: Text(context.l10n.onboardingNoServerLink),
          ),
        ),
      ],
    );
  }
}

List<Widget> _buildTestStatus(
  BuildContext context,
  ColorScheme cs,
  _TestState state,
  String? url,
  String? version,
  String? errorDetail,
  bool suggestHttps,
  bool unsupportedFromNotFound,
) {
  final addr = (url != null && url.isNotEmpty) ? displayAddress(url) : null;
  switch (state) {
    case _TestState.idle:
    case _TestState.testing:
    case _TestState.signingIn:
    case _TestState.searching:
      return const [SizedBox.shrink()];

    case _TestState.connected:
      return [
        _StatusRow(
          color: BrandColors.of(context).success,
          icon: FluentIcons.checkmark_circle_24_regular,
          text: (version != null && version.isNotEmpty)
              // The server version includes "v"; localization supplies its own prefix.
              ? context.l10n.onboardingConnected(
                  version.startsWith('v') ? version.substring(1) : version,
                )
              : context.l10n.onboardingResolvedAddress(addr ?? ''),
        ),
        if (addr != null) ...[
          const SizedBox(height: 6),
          _StatusRow(
            color: cs.onSurfaceVariant,
            icon: FluentIcons.server_24_regular,
            text: context.l10n.onboardingFoundAt(addr),
          ),
        ],
      ];

    case _TestState.needsLogin:
      return [
        _StatusRow(
          color: cs.tertiary,
          icon: FluentIcons.lock_closed_24_regular,
          text: context.l10n.onboardingNeedsLogin,
        ),
        if (addr != null) ...[
          const SizedBox(height: 6),
          _StatusRow(
            color: cs.onSurfaceVariant,
            icon: FluentIcons.server_24_regular,
            text: context.l10n.onboardingFoundAt(addr),
          ),
        ],
      ];

    case _TestState.unsupportedAuth:
      return [
        _StatusRow(
          color: cs.tertiary,
          icon: FluentIcons.lock_closed_24_regular,
          text: unsupportedFromNotFound
              ? context.l10n.webServerAuthUnconfirmed
              : context.l10n.webUnsupportedAuthMode,
        ),
      ];

    case _TestState.notSuwayomi:
      return [
        _StatusRow(
          color: cs.tertiary,
          icon: FluentIcons.question_circle_24_regular,
          text: context.l10n.onboardingResolvedUnconfirmed(addr ?? ''),
        ),
      ];

    case _TestState.failed:
      return [
        _StatusRow(
          color: cs.error,
          icon: FluentIcons.error_circle_24_regular,
          text: (errorDetail?.isNotEmpty ?? false)
              ? errorDetail!
              : context.l10n.onboardingNotReached,
        ),
        if (suggestHttps) ...[
          const SizedBox(height: 6),
          _StatusRow(
            color: cs.onSurfaceVariant,
            icon: FluentIcons.lightbulb_24_regular,
            text: context.l10n.onboardingNotReachedHttpsHint,
          ),
        ],
      ];
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.color,
    required this.icon,
    required this.text,
  });
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
        Expanded(
          child: Text(text, style: TextStyle(color: color)),
        ),
      ],
    );
  }
}


class _FinishStep extends StatelessWidget {
  const _FinishStep();

  @override
  Widget build(BuildContext context) {
    final cs = context.theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 48),
        Icon(FluentIcons.rocket_24_regular, size: 64, color: cs.primary),
        const SizedBox(height: 24),
        Text(
          context.l10n.onboardingDoneTitle,
          textAlign: TextAlign.center,
          style: context.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.onboardingDoneSubtitle,
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

bool _compactLogo(Size screen) =>
    screen.height < 1000 && screen.width > screen.height;
