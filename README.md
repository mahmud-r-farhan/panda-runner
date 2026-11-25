# 🐼 Panda Runner

**A 3D neon parkour runner built with [Flutter Scene](https://pub.dev/packages/flutter_scene) (Flutter GPU + WebGL2).**
Sprint the Shibuya Scramble Crossing as a neon panda, vault taxis, grind the Yamanote Line, ignite the city and
finish on the Shibuya Stream rooftop.

[![CI](https://github.com/mahmud-r-farhan/panda-runner/actions/workflows/ci.yml/badge.svg)](https://github.com/mahmud-r-farhan/panda-runner/actions/workflows/ci.yml)
[![Release](https://github.com/mahmud-r-farhan/panda-runner/actions/workflows/release.yml/badge.svg)](https://github.com/mahmud-r-farhan/panda-runner/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-FF6B1A.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.47.1%2B-02569B.svg)](https://flutter.dev)

<p align="center">
  <img src="assets/branding/icon_square.png" width="160" alt="Panda Runner app icon">
</p>

## Play now

| Platform | How |
| --- | --- |
| **Browser** (Windows, macOS, Linux, Chromebook, Android, iOS) | **[mahmud-r-farhan.github.io/panda-runner](https://mahmud-r-farhan.github.io/panda-runner/)** — no install, fullscreen, offline after the first load (live once Pages is enabled, see below) |
| **Android** | Download the matching ABI APK (`arm64-v8a`, `armeabi-v7a` or `x86_64`) from [Releases](https://github.com/mahmud-r-farhan/panda-runner/releases) |
| **Windows x64** | Download `PandaRunner-*-Windows-x64.zip` from [Releases](https://github.com/mahmud-r-farhan/panda-runner/releases), extract and run `panda_runner.exe` |
| **macOS 12+** (Apple silicon) | Download `PandaRunner-*-macOS-arm64.dmg` from [Releases](https://github.com/mahmud-r-farhan/panda-runner/releases) |
| **Self-hosted web** | Download `panda-runner-web.zip`, unzip, serve the folder with any static server |
| **iOS 15+** | Build from source (`flutter run -d ios --enable-flutter-gpu`); store build needs your own signing |

> The browser build is served by GitHub Pages; maintainers enable it once under **Settings → Pages → Source: GitHub Actions**
> (the deploy workflow skips cleanly until then).
>
> The macOS app is unsigned. If Gatekeeper blocks the first launch, right-click the app → **Open**, or run
> `xattr -dr com.apple.quarantine /Applications/PandaRunner.app`.
>
> Android APKs are for sideloading. Unless maintainers configure the optional Android signing secrets, CI uses a
> disposable debug key; those APKs are not Play Store uploads and may require uninstalling before installing a later
> CI build. See [`docs/RELEASING.md`](docs/RELEASING.md) for signing setup.

## What you actually do

A single 1,047 m route through Shibuya in four phases:

1. **SKY DROP** — the panda falls through the skyline while the camera swoops from the city map to street level.
2. **SCRAMBLE CROSSING** — three lanes of traffic, drifting cars, zebra crossings, neon slide gates and boost rings.
3. **YAMANOTE GRIND** — rail grind up onto the elevated Yamanote Line, with wall-run → rail transfer arcs.
4. **GOOGLE TOKYO** — front-flip onto the Shibuya Stream rooftop, light all six Google letters and orbit the pin.

**Survive.** You start with **3 shields**. Clipping a street barrier or hitting a neon slide gate burns one, and the
third ends the run. Taxis don't kill you — they launch you into a hood bounce and cost speed. **Boost rings restore a
shield**, so risky lines keep you alive.

**Score.** Base points are multiplied by your combo (1×–12×). Combos climb with near misses, ring hits, gate ignites
and roof vaults; a crash halves the combo and kills your speed.

| Event | Base points |
| --- | --- |
| Boost ring | 400 × combo |
| Pin gate / building sign | 250 × combo / 150 × combo |
| Near miss (taxi / drift car) | 500–600 × combo |
| Roof vault | 750 |
| Neon slide | 1,500 |
| Google letter ignition | 1,500 × combo (final letter) |
| Rooftop pin | 1,000 × combo |

Your best score, run count and best combo persist locally (`localStorage` on web, `~/.panda_runner/save.json` on
Android/iOS/desktop, under your user profile on Windows) and are shown on the title card, pause sheet and game-over card.

## Controls

| Action | Keyboard | Touch |
| --- | --- | --- |
| Lane left / right | `A` / `D` or `←` / `→` | swipe left / right |
| Jump, rail vault, roof vault | `Space` / `W` / `↑` | swipe up |
| Slide under neon gates | `S` / `↓` | swipe down |
| Pause / resume | `Esc` | **Pause** button |
| Restart (pause & game over) | `R` | sheet button |
| Back to the map | `Q` | sheet button |
| Photo mode | `P` (then `1` `2` `3`) | **Photo** button |
| Mute | `M` | speaker button |
| Start run (title card) | `Enter` / `Space` | **Play** button |

Photo mode: drag to orbit, scroll/pinch to zoom, three presets (Hero, Scramble, Skyline).

## Features

- **Real runner gameplay** instead of an endless demo: shields, failure, retry, persistent personal bests.
- **Frame-rate independent** simulation with a clamped delta, pause that truly freezes the gameplay clock, and
  automatic pause when the app is backgrounded.
- **Performance-first rendering**: the 3D `SceneView` lives outside the per-frame HUD rebuild, so scoring, combos and
  callouts no longer re-create the scene, camera builder and layer 60 times a second. Debug URL parsing is done once.
- **Two runners** (procedural 3D panda + Pegman) and **three sky moods** (Neon Night, Jade Dawn, Ultraviolet).
- **Auto-Pilot** demo mode for screenshots and letting the game play itself.
- **Audio**: licensed-in-repo BGM plus 30 recorded SFX voices, retrigger guards, looped rail/wind beds, mute that
  persists; haptics that follow the device rather than the mute switch.
- **Juice**: bloom, AgX-toned HDR neon, sparks, camera trauma, speed lines, minimap, street pills, callouts.
- **Web app**: installable PWA with manifest, theme colour, boot splash, Open Graph tags and landscape orientation.

## Build from source

Requirements: **Flutter 3.47.1 stable or newer** (Dart 3.10+). Native targets also need their usual toolchains:
Android SDK/JDK for Android, Visual Studio with the Desktop development with C++ workload for Windows, and Xcode
for iOS/macOS.

```bash
git clone https://github.com/mahmud-r-farhan/panda-runner.git
cd panda-runner
bash setup.sh  # generates any missing native runners, configures GPU/branding, fetches packages and runs tests
```

```bash
# Web (WebGL2; no extra flags)
flutter run -d chrome

# Android (Flutter GPU is enabled in the generated Android manifest)
flutter run -d android

# Windows (Flutter GPU is enabled in the generated C++ runner; build on Windows)
flutter run -d windows

# macOS (Impeller + Flutter GPU / Metal)
flutter run -d macos --enable-flutter-gpu

# iOS (Impeller + Flutter GPU / Metal)
flutter run -d ios --enable-flutter-gpu

# Production web build
flutter build web --release --base-href /

# Production Android APKs (armv7, arm64 and x64)
flutter build apk --release --split-per-abi

# Production Windows build (run on Windows)
flutter build windows --release

# Production macOS build
flutter build macos --release
```

`setup.sh` regenerates missing iOS/macOS/web/Android/Windows platform runners, preserves existing Apple project
customizations, and calls [`scripts/configure_native_platforms.py`](scripts/configure_native_platforms.py) to set
Android's `EnableFlutterGPU` manifest flag, Windows' `DartProject` GPU flag, the app IDs and native icons. Flutter Scene
uses Flutter GPU on native platforms and its WebGL2 backend on web. Everything else (3D geometry, textures, animation)
is code.

### Tests & analysis

```bash
flutter analyze
flutter test
python3 -m unittest discover -s scripts -p 'test_*.py' -v
make check     # analyze + test + web build
make android   # Android SDK/JDK required
make windows   # Windows + Visual Studio C++ required
```

## Project layout

```text
assets/
├── branding/                  # Icon sources + native Android/Windows sizes (not bundled)
├── data/shibuya_level.json    # OSM-derived route spline, buildings, roads, rails, hazards
├── fonts/                     # Inter, JetBrains Mono, Noto Sans JP
├── models/                    # GLB props (tower, fleet, arch, props, Pegman rig)
├── audio/                     # BGM
└── sfx/                       # 30 recorded one-shot + loop voices
lib/
├── main.dart                  # PandaRunnerApp
├── game/
│   ├── game_state.dart        # Phases, shields, score/combo, pause, persistence
│   ├── save_store.dart        # Conditional-import save store (file / localStorage / memory)
│   ├── hero_sim.dart          # Sky drop, parkour physics, collisions, scoring, autopilot
│   ├── shibuya_scene_controller.dart # Scene graph, traffic, camera rigs, FX wiring
│   ├── world_builder.dart     # Extruded OSM city, viaduct, rails, props, Google tower
│   ├── panda_rig.dart         # Procedural 3D panda
│   ├── pegman_builder.dart    # Procedural Pegman
│   ├── fx.dart                # Sparks, arcs, rain, shockwaves
│   ├── sound_fx.dart          # Audio buses, haptics, pause
│   └── ...
└── ui/
    ├── game_screen.dart       # Ticker, input, lifecycle, layered compositing
    ├── hud_overlay.dart       # Telemetry, shields, actions, callouts, finale banner
    ├── pause_overlay.dart     # Pause sheet
    ├── game_over_card.dart    # Run summary / retry
    ├── maps_title_card.dart   # Hero + sky mood picker, best-run summary
    └── ...
scripts/                        # Generated Android/Windows runner configuration + tests
test/game_test.dart             # State, scoring, shields, pause, persistence
docs/                           # Architecture, releasing, credits
```

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — frame loop, layer split, simulation and save-store design.
- [`docs/RELEASING.md`](docs/RELEASING.md) — how GitHub Releases, web, Android, Windows and macOS artifacts are produced.
- [`docs/CREDITS.md`](docs/CREDITS.md) — original demo, OSM data and third-party licences.
- [`CHANGELOG.md`](CHANGELOG.md) — release history.

## Debug URL parameters (web)

`?autoplay=1` starts a run with Auto-Pilot · `&seek=0.5` jumps to that route fraction after landing ·
`&sim=4` runs 4 simulation steps per frame · `&photo=skyline` opens photo mode at the finale ·
`&photoNow=1` allows photo mode mid-run · `&fixdt=1` steps exactly 1/60 s · `&freeze=1` holds after a seek.

`lib/ui_preview_main.dart` is a 2D-only harness for the overlays:
`flutter build web -t lib/ui_preview_main.dart -o build/preview` then
`?view=loading|title|hud|callout|skydrop|pause|gameover|finale|photo`.

## Credits & licence

Panda Runner is a re-themed, gameplay-hardened Flutter Scene port of the **Gemini Neon Scramble** demo by
**Lucas Goldner** ([original](https://neon-scramble.ai.studio/), [video](https://x.com/LucasGoldner/status/2124441656867082289)).
Map data © OpenStreetMap contributors (ODbL). Code is MIT licensed — see [`LICENSE`](LICENSE) and
[`docs/CREDITS.md`](docs/CREDITS.md).
