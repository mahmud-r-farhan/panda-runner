# Changelog

All notable changes to Panda Runner are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/).

## [2.0.0] — 2026-11-23

The "shippable game" release: rebranded from the Neon Scramble port to **Panda
Runner**, given a real fail/retry loop, persistent progress, pause, and an
automated release pipeline.

### Added

- **Shield system**: 3 shields per run; barrier clips and neon-gate crashes burn one,
  the third ends the run. Boost rings restore a shield (risk/reward loop).
- **Game over**: run summary card with score, personal best, NEW BEST badge,
  distance, run time, peak speed, best combo and run count; retry (`R`, `Enter`)
  or return to the map (`Q`).
- **Pause**: pause sheet with resume/restart/map/audio, `Esc` toggle, and
  automatic pause when the app is backgrounded. Pausing freezes the simulation,
  the gameplay clock, cosmetic motion and audio loops, and stops the frame work
  entirely.
- **Persistent progress**: best score, best combo, run counters and mute state
  survive restarts — `localStorage` on web, `~/.panda_runner/save.json` on
  macOS/iOS, memory fallback elsewhere (`lib/game/save_store*.dart`).
- **Best-run summary** on the title card and pause sheet (`displayBest`).
- **Shield pips** in the HUD and a **Pause** action in the top-right pill.
- **Touch-aware onboarding**: swipe hints on narrow screens, key hints on
  desktop.
- **Branded app icon** across macOS, iOS and the web (plus favicon and maskable
  PWA icons) and a custom web boot splash with Open Graph/social metadata.
- **CI, Pages and Release workflows**, `Makefile`, `CONTRIBUTING`, `LICENSE`,
  architecture/releasing/credits docs and this changelog.
- Tests for shields, run banking, pause semantics and persistence.

### Changed

- Renamed the app, package (`panda_runner`), bundle IDs (`dev.pandarunner.game`),
  window/app display names, web manifest, loading/HUD/title branding and the
  in-world billboards from "Neon Scramble" to **Panda Runner**.
- Sky moods are now described honestly as colour grades of the same Shibuya
  route (Neon Night / Jade Dawn / Ultraviolet) instead of separate cities.
- Haptics follow the device: muting audio no longer disables vibration.
- Keyboard: `Esc` is now pause (photo mode exits with `Esc`/`P`), `M` mutes,
  `R` restarts, `Q` returns to the map.

### Performance

- The 3D `SceneView` and its camera builder are no longer rebuilt on every HUD
  frame: the scene lives in its own layer that only rebuilds on phase changes.
- Debug URL parameters are parsed once instead of per frame; debug hooks are
  skipped entirely without a query string.
- `RepaintBoundary` around the scene and the HUD; paused games perform no frame
  work.
- Trains, FX and cosmetic animation freeze with the simulation.

### Fixed

- Frame-length clamp and pause handling could let the run clock drift.
- Haptics were silently disabled by the audio mute switch.
- Web title/manifest/theme colour still said `neon_scramble`.
