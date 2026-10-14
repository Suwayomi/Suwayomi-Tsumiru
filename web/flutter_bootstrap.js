{{flutter_js}}
{{flutter_build_config}}

(async () => {
  try {
    if ('serviceWorker' in navigator) {
      const scope = new URL('.', document.baseURI).href;
      const registrations = await navigator.serviceWorker.getRegistrations();
      const flutterRegistrations = registrations.filter(registration =>
        registration.scope === scope &&
        [registration.active, registration.waiting, registration.installing]
          .some(worker => worker && new URL(worker.scriptURL).pathname.endsWith('/flutter_service_worker.js'))
      );
      const controlledByFlutter = navigator.serviceWorker.controller &&
        new URL(navigator.serviceWorker.controller.scriptURL).pathname.endsWith('/flutter_service_worker.js');
      await Promise.all(flutterRegistrations.map(registration => registration.unregister()));
      if (flutterRegistrations.length && controlledByFlutter) {
        window.location.reload();
        return;
      }
    }
  } catch (error) {
    console.warn("Could not retire the Flutter service worker:", error);
  }
  _flutter.loader.load();
})();
