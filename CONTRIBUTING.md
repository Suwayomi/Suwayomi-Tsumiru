# Contributing to Tsumiru

Pull requests are welcome. For larger changes, open an issue first so we can talk it through.

## Building

The Flutter version is pinned in `.fvmrc`.

```bash
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter build apk            # or: ios / linux / windows / macos / web
```

Generated files (`*.g.dart`, `*.graphql.dart`, generated localisations) are not committed. Run the generation steps above before analysing, testing or building.

## Before opening a pull request

```bash
flutter analyze
flutter test
```

Fill in the pull request template.
