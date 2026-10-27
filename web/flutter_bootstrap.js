{{flutter_js}}
{{flutter_build_config}}

// Characters that none of the app's fonts has would be fetched from fonts.gstatic.com, which tells Google who is
// using the IDE. The app's own fonts cover what it shows (pubspec.yaml); anything else is looked for on this site,
// where there is nothing, and shows as a box.
_flutter.loader.load({
  config: {
    fontFallbackBaseUrl: 'assets/fallback-fonts/',
  },
});
