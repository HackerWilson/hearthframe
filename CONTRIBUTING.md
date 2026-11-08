# Contributing to HearthFrame

Thanks for taking the time to contribute.

## Ways to help

- Bug reports with device model, Android version, source type and steps.
- Fixes and features that keep the frame simple and reliable.
- Documentation, test fixtures and translations.

## Development setup

- Flutter 3.x stable, JDK 17 and the Android SDK.
- `flutter pub get`
- `flutter run` or `flutter build apk --release`
- `flutter analyze` must be clean.
- `flutter test` must pass.

See [docs/TESTING.md](docs/TESTING.md) for the verification checklist and
fixture recipes.

## Code style

- Run `dart format` for Dart changes and keep the Kotlin files in the style
  of the existing code.
- Do not add analyzer warnings. `vendor/` is excluded from analysis because
  it is third-party code.
- Prefer small, focused changes. Update the specification or decision records
  when behavior changes.

## Commits and pull requests

- Use [Conventional Commits](https://www.conventionalcommits.org/), for
  example `fix: skip undecodable cache entries` or
  `feat: add sleep schedule`.
- Describe the user-visible effect and how you verified it (device, source).
- Do not commit credentials: use placeholders such as `192.168.1.20` and
  `/photo/family`. Never commit NAS hostnames, passwords, tokens, keystores,
  `local.properties` or personal photos.
- By contributing you agree that your contribution is licensed under the
  project's MIT license.

## Reporting security issues

Please follow [SECURITY.md](SECURITY.md) instead of opening a public issue.
