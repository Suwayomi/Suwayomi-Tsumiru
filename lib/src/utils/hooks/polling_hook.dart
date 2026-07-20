import 'dart:async';

import 'package:flutter_hooks/flutter_hooks.dart';

T? usePolling<T>({
  required Duration pollingInterval,
  required FutureOr<T> Function() pollFunction,
  bool delayedStart = false,
}) {
  final data = useState<T?>(null);

  useEffect(() {
    bool cancelled = false;

    Future<void> poll() async {
      while (!cancelled) {
        if (delayedStart) {
          await Future.delayed(pollingInterval);
        }
        if (cancelled) return;
        final result = await pollFunction();
        if (cancelled) return;
        data.value = result;
        if (!delayedStart) {
          await Future.delayed(pollingInterval);
        }
      }
    }

    poll();

    return () => cancelled = true;
  }, []);

  return data.value;
}
