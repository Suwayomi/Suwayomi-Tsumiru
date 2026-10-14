{{flutter_js}}
{{flutter_build_config}}

(async () => {
  let hosted = false;
  try {
    const response = await fetch(new URL('revision', document.baseURI), {cache: 'no-store'});
    hosted = response.status === 200 && /^v\d+\.\d+\.\d+/.test((await response.text()).trim());
  } catch (_) {}
  if (!hosted) {
    _flutter.loader.load({
      serviceWorkerSettings: {serviceWorkerVersion: {{flutter_service_worker_version}}}
    });
    return;
  }
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
