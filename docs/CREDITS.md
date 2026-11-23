# Credits & third-party notices

## Original demo

Panda Runner is a re-themed, gameplay-hardened **Flutter Scene** port of the
*Gemini Neon Scramble* web demo by **Lucas Goldner**:

- Demo: <https://neon-scramble.ai.studio/>
- Preview: <https://x.com/LucasGoldner/status/2124441656867082289>

The Dart/Flutter source in this repository is MIT licensed (see `LICENSE`).
The bundled art, audio, GLB models and exported level data originate from that
demo and remain subject to their upstream terms. If you intend to sell or
redistribute the assets themselves, verify the upstream rights first.

## Map & street data

- Map data © **OpenStreetMap** contributors, licensed under the
  [Open Database License (ODbL) 1.0](https://www.openstreetmap.org/copyright).
- The route spline, building footprints/heights, roads, rails and street names
  used by `assets/data/shibuya_level.json` are derived from OSM data via the
  original demo's export.

## Fonts

| Font | Licence |
| --- | --- |
| Inter | SIL Open Font License 1.1 |
| JetBrains Mono | SIL Open Font License 1.1 |
| Noto Sans JP (subset) | SIL Open Font License 1.1 |

## Packages

- [`flutter_scene`](https://pub.dev/packages/flutter_scene) — Flutter GPU / WebGL2
  scene renderer (BSD-3-Clause).
- [`audioplayers`](https://pub.dev/packages/audioplayers) — audio playback
  (MIT).
- [`vector_math`](https://pub.dev/packages/vector_math) — math types used by the
  simulation and camera rigs (BSD-3-Clause).
- Flutter, Impeller and the Dart SDK — BSD-3-Clause, © Google.

## Panda Runner changes

Rebranding (name, icons, docs, platform metadata), the shield/game-over loop,
pause + lifecycle handling, persistent best scores, touch onboarding, the HUD
pause/shield widgets, layered-render performance work, CI and the release
pipeline are original work for this repository, MIT licensed.
