import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../auth/data/auth_credentials_store.dart';

class AccountSessionHost extends StatefulWidget {
  const AccountSessionHost({
    super.key,
    required this.initialContainer,
    required this.restart,
    required this.builder,
    required this.loading,
    required this.errorBuilder,
    this.sessionKey,
    this.onRetained,
  });

  final ProviderContainer initialContainer;
  final Future<ProviderContainer> Function(ProviderContainer) restart;
  final Widget Function(bool changing) builder;
  final Widget loading;
  final Widget Function(Object error) errorBuilder;
  final Object Function(ProviderContainer)? sessionKey;
  final Future<void> Function(ProviderContainer)? onRetained;

  @override
  State<AccountSessionHost> createState() => _AccountSessionHostState();
}

class _AccountSessionHostState extends State<AccountSessionHost> {
  late ProviderContainer _container;
  ProviderSubscription<AsyncValue<AuthCredentialsState>>? _subscription;
  bool _changing = false;
  bool _detached = false;
  bool _restarting = false;
  Object? _error;
  Object? _sessionKey;

  @override
  void initState() {
    super.initState();
    _container = widget.initialContainer;
    _sessionKey = widget.sessionKey?.call(_container);
    _listen();
  }

  void _listen() {
    _subscription = _container.listen(authCredentialsStoreProvider, (
      previous,
      next,
    ) {
      final before = previous?.value;
      final after = next.value;
      if (before == null || after == null) return;
      if (before.sessionEpoch == after.sessionEpoch &&
          before.sessionChanging == after.sessionChanging) {
        if (!_changing) _sessionKey = widget.sessionKey?.call(_container);
        return;
      }
      final nextKey = widget.sessionKey?.call(_container);
      if (!after.sessionChanging && nextKey != null && nextKey == _sessionKey) {
        setState(() => _changing = false);
        unawaited(widget.onRetained?.call(_container));
        return;
      }
      setState(() => _changing = true);
      if (!after.sessionChanging) unawaited(_restart());
    });
  }

  Future<void> _restart() async {
    if (_restarting) return;
    _restarting = true;
    await Future<void>(() {});
    if (!mounted) return;
    setState(() => _detached = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final previous = _container;
    _subscription?.close();
    try {
      final next = await widget.restart(previous);
      if (!mounted) {
        next.dispose();
        return;
      }
      _container = next;
      _sessionKey = widget.sessionKey?.call(next);
      _listen();
      setState(() {
        _changing = false;
        _detached = false;
      });
      previous.dispose();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      _restarting = false;
    }
  }

  @override
  void dispose() {
    _subscription?.close();
    _container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return UncontrolledProviderScope(
      container: _container,
      child: error != null
          ? widget.errorBuilder(error)
          : _detached
          ? widget.loading
          : KeyedSubtree(
              key: ObjectKey(_container),
              child: widget.builder(_changing),
            ),
    );
  }
}
