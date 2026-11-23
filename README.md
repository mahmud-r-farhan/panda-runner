

# NEON SCRAMBLE — Flutter Scene Edition

A cross-platform 3D Flutter port of the **Gemini Neon Scramble** demo ([neon-scramble.ai.studio](https://neon-scramble.ai.studio/)), built with [`flutter_scene`](https://pub.dev/packages/flutter_scene) so the exact same Dart 3D codebase runs on **iOS**, **macOS**, and **Web**.

- Map data © OpenStreetMap contributors (ODbL).
- **iOS & macOS**: Renders natively through **Impeller + Flutter GPU** (Metal).
- **Web**: Renders automatically through `flutter_scene`'s built-in **WebGL2** backend (works under both CanvasKit and Skwasm, with no extra flags).

Preview video here:
https://x.com/LucasGoldner/status/2124441656867082289

## Gameplay & Features

1. **Loading & Shibuya Map Overview**
   - Dark navy loading screen with warm orange radial glow and `Loading Shibuya...` progress bar synced to `Scene.initializeStaticResources()`.
   - Stylized dark Shibuya map with glowing cyan, purple, emerald (Yamanote), and orange/yellow transit lines and markers for **Shibuya Scramble Crossing**, **Shibuya Station**, and **Shibuya Stream - Google Tokyo**.
2. **4-Phase 3D Neon Runner (`flutter_scene`)**
   - **SKY DROP**: Yellow 3D Pegman drops from above the Shibuya skyline with a glowing HDR pink/magenta trail as the camera swoops from an aerial city view into street level.
   - **SCRAMBLE CROSSING**: 3-lane neon runner across the diagonal zebra crosswalk and Center-Gai — weave around glowing Tokyo taxis & buses, jump (`Space` / swipe up) to vault roofs and roadblocks, slide (`S` / swipe down) under neon gates, and ignite roadside neon signs for combo multipliers.
   - **YAMANOTE GRIND**: Elevated neon-green Yamanote Line rails above Shibuya Station with rail-spark trails and overhead gantries.
   - **GOOGLE TOKYO**: Final sprint into **Shibuya Stream – Google Tokyo** with a celebratory four-color neon light cascade.
3. **HUD & Controls**
   - Top-left HUD: **NEON SCRAMBLE**, **SCORE**, **SPEED (`km/h`)**, **COMBO (`1x`–`12x`)**, route progress, and phase badge.
   - Top-right controls: `AUDIO ON/OFF` toggle and pause/menu button.
   - **Desktop / Web**: `A` / `D` (or `←` / `→`) Lanes · `Space` / `W` / `↑` Jump & Roof Vault · `S` / `↓` Slide · `Esc` Pause.
   - **iOS / Touch**: Swipe left/right to switch lanes, swipe up to jump/vault, swipe down to slide.

## Requirements

- **Flutter 3.47 (stable) or newer** ([Flutter Scene installation guide](https://fscene.dev/getting-started/installation/)).
- No external `.glb` models or build hooks are required — all 3D geometry (Pegman, Shibuya skyscrapers, glowing billboards, scramble crosswalk, Tokyo vehicles, Yamanote rails, and Shibuya Stream) is procedurally constructed with `flutter_scene`'s built-in `CuboidGeometry`, `SphereGeometry`, `PhysicallyBasedMaterial` (HDR `emissiveFactor` + AgX tone mapping + Bloom), and `UnlitMaterial`.

## Quick Start

From inside the `neon_scramble_flutter` directory:

```bash
chmod +x setup.sh
./setup.sh
```

`setup.sh` runs `flutter create . --platforms=ios,macos,web`, adds `<key>FLTEnableFlutterGPU</key><true/>` to both `ios/Runner/Info.plist` and `macos/Runner/Info.plist`, and runs `flutter pub get`.

### Run on Each Platform

```bash
# Web (WebGL2 — no extra flags needed)
flutter run -d chrome

# Web with WebAssembly (Skwasm)
flutter run -d chrome --wasm

# macOS (Impeller + Flutter GPU / Metal)
flutter run -d macos --enable-flutter-gpu

# iOS (Impeller + Flutter GPU / Metal)
flutter run -d ios --enable-flutter-gpu
```

## Project Layout

```text
assets/
├── data/shibuya_level.json   # Level data exported from the web demo's bundle:
│                             # OSM route spline, 167 buildings w/ heights, roads,
│                             # rails, rings, barriers, taxis, signs, Google tower
└── fonts/                    # Inter + JetBrains Mono (the demo's CSS fonts)
lib/
├── main.dart
├── game/
│   ├── game_state.dart               # Phases (loading → title → sky drop → playing → finale), HUD state
│   ├── level_data.dart               # Loads shibuya_level.json
│   ├── route_spline.dart             # Route sampling + three.js → Flutter Scene (Z-mirror) helpers
│   ├── hero_sim.dart                 # Port of the demo's sky drop, parkour physics, scoring, autopilot
│   ├── world_builder.dart            # Extruded OSM city, viaduct, rails, props, Google tower
│   ├── world_textures.dart           # Procedural window/brick/storefront/ground/glyph textures
│   ├── mesh_buf.dart                 # Mesh batching + polygon triangulation
│   ├── pegman_builder.dart           # Jointed procedural Pegman
│   ├── shibuya_scene_controller.dart # Scene, traffic, rain, camera rigs (chase/sky-drop/finale/photo)
│   └── sound_fx.dart
└── ui/                               # Loading, title map, title card, HUD, minimap, callouts, finale, photo bar
```

## Debug URL parameters (web)

`?autoplay=1` starts a run with Auto-Pilot, `&seek=0.5` jumps to that route fraction after
landing, `&sim=4` runs 4 simulation steps per frame, `&photo=skyline` opens photo mode at the
finale. `lib/ui_preview_main.dart` is a UI-only preview harness (`?view=loading|title|hud|finale|photo`).
