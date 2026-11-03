import 'dart:async';

import 'package:graphql/client.dart';

import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import 'graphql/__generated__/web_interface.graphql.dart';
import 'web_interface_repository.dart';

class WebInterfaceInstaller {
  WebInterfaceInstaller(this.repository, this.client, {
    required this.onStatus,
    required this.onError,
  });

  final WebInterfaceRepository repository;
  final GraphQLClient client;
  final void Function(Fragment$WebInterfaceUpdateStatusDto) onStatus;
  final void Function(Object) onError;
  Timer? _timer;
  StreamSubscription? _subscription;
  bool _active = true;
  bool _socketLive = false;

  void dispose() {
    _active = false;
    _timer?.cancel();
    _subscription?.cancel();
  }

  void _accept(Fragment$WebInterfaceUpdateStatusDto? status) {
    if (!_active) return;
    if (status == null) throw StateError('Missing web interface install response');
    if (status.state == Enum$UpdateState.FINISHED ||
        status.state == Enum$UpdateState.ERROR) {
      dispose();
    }
    onStatus(status);
  }

  void _schedule() {
    if (_active && !_socketLive) {
      _timer?.cancel();
      _timer = Timer(const Duration(seconds: 2), _poll);
    }
  }

  Future<void> _poll() async {
    try {
      _accept(await repository.status());
    } catch (error) {
      if (_active) onError(error);
    }
    _schedule();
  }

  Future<void> install() async {
    _accept(await repository.install());
    if (!_active) return;
    try {
      _subscription = client.subscribe$WebInterfaceUpdateStatusChange(
        Options$Subscription$WebInterfaceUpdateStatusChange(),
      ).getData((data) => data.webUIUpdateStatusChange).listen((status) {
        if (!_active) return;
        _socketLive = true;
        _timer?.cancel();
        try {
          _accept(status);
        } catch (error) {
          onError(error);
        }
      }, onError: (_) {
        _socketLive = false;
        _schedule();
      }, onDone: () {
        _socketLive = false;
        _schedule();
      });
    } catch (_) {
      _socketLive = false;
    }
    _schedule();
  }
}
