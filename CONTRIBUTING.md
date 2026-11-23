# Contributing

Thanks for helping Panda Runner. Keep changes focused, explained and tested.

## Setup

```bash
flutter --version        # 3.47 stable or newer
flutter pub get
flutter analyze
flutter test
flutter run -d chrome    # fastest iteration loop
```

`make check` runs analyse, tests and a production web build.

## Pull requests

- One logical change per PR, with a short "why" in the description.
- `flutter analyze` must be clean (no new warnings) and `flutter test` green.
- Add or update tests for gameplay/state changes in `test/game_test.dart`.
- If you touch the frame loop, quantify the change (frame time, rebuild counts)
  and keep per-frame allocations out of `ShibuyaSceneController.tick`.
- Update `CHANGELOG.md` under an `Unreleased` heading for user-visible changes.

## Code style

- Standard `dart format` (80 columns), trailing commas where the formatter puts
  them.
- Prefer immutable data and private helpers; keep new public API documented with
  `///` comments.
- Never block the UI isolate in the frame loop. Persistence is the only
  synchronous I/O and happens once per run.
- Throw nothing from platform integration: storage, audio and haptics all fail
  soft.

## Assets

- Keep generated art in `assets/branding/` (source) and regenerate the platform
  icon sets from `assets/branding/icon_square.png`.
- Large binaries belong in `assets/` with the existing naming; do not add build
  output, `build/`, `.dart_tool/` or screenshots outside `docs/`.

## Releasing

See [`docs/RELEASING.md`](docs/RELEASING.md). Maintainers tag `vX.Y.Z` on `main`
and the release workflow does the rest.
