{{flutter_js}}
{{flutter_build_config}}

// Release preparation replaces the empty asset base with a content-hashed path.
// Local flutter run still loads assets from the normal root.
const aqdakConfig = {canvasKitBaseUrl: 'canvaskit/', assetBase: ''};
_flutter.loader.load({
  config: aqdakConfig,
  onEntrypointLoaded: async (engineInitializer) => {
    try {
      const runner = await engineInitializer.initializeEngine(aqdakConfig);
      await runner.runApp();
    } catch (error) {
      window.dispatchEvent(new Event('aqdak-load-error'));
      console.error('Aqdak could not start.', error);
    }
  },
}).catch(() => window.dispatchEvent(new Event('aqdak-load-error')));
