# Architecture

Panda Runner is a single Flutter application that renders a 3D scene with
[`flutter_scene`](https://pub.dev/packages/flutter_scene) and composites a 2D
game HUD on top of it. The same Dart code runs on Android/iOS/macOS/Windows
(Impeller + Flutter GPU) and on the web (WebGL2). Android and Windows runner
projects are generated from the installed Flutter SDK by `setup.sh` and configured
with `scripts/configure_native_platforms.py`.

```
lib/main.dart                  PandaRunnerApp → PandaRunnerGameScreen
lib/ui/game_screen.dart        Ticker, input, lifecycle, layer split
lib/game/shibuya_scene_controller.dart   Scene graph, cameras, traffic, FX
lib/game/hero_sim.dart         Deterministic-ish parkour simulation
lib/game/game_state.dart       Observable app/game state (+ChangeNotifier)
```

## Frame loop

`PandaRunnerGameScreen` owns a single `Ticker`:

```
Ticker → dt = clamp(elapsed - last, 0, 50 ms)   // frame-rate independent
       → if paused: return                       // no sim, no repaint
       → controller.tick(dt)
           ├─ sim.step(dt)        physics, collisions, scoring, traffic
           ├─ _handleEvents()     SFX + FX + shield damage for this frame
           ├─ _syncAudio()        loop buses (rail, wind, sky-drop)
           ├─ _syncProps()        sign/rail/gate materials, media screens
           ├─ _syncTrains()       Yamanote trains (cosmetic)
           ├─ _syncHero()         panda/Pegman rig + IK pose
           ├─ _computeCamera()    chase / sky-drop / finale / photo rigs
           ├─ _syncFx()           sparks, rain, speed lines
           └─ state.tick(dt)      one ChangeNotifier notification per frame
```

`dt` is clamped so a slow frame (or a stalled tab) can never teleport the hero
through traffic. The simulation is therefore frame-rate independent, but it is
*not* bit-exact deterministic across frame rates — the debug hooks
(`&fixdt=1`) exist for reproducible captures.

### Pausing and backgrounding

* `GameState.paused` freezes `sim.step`, the gameplay clock (`state.tick(0)`),
  cosmetic train motion and the audio loops; the ticker short-circuits before
  any work, so a paused game costs no CPU.
* `AppLifecycleState.paused/hidden/inactive` automatically pauses an active
  run. Resuming is always an explicit player action.
* Photo mode is a separate freeze: the sim stops but the photo camera rigs and
  overlay UI keep animating.

## Layer split (why it is fast)

The screen is a `Stack` of exactly two children:

1. **`_SceneLayer`** — `fs.SceneView` plus the static vignette shader.
   Rebuilt only when the app phase or scene readiness changes.
2. **`AnimatedBuilder(GameState)`** — the 2D HUD, map view, title card, pause
   sheet, game-over card and loading screen. This layer re-renders every frame.

Before this split the `SceneView`, its `cameraBuilder` closure and the scene
layer were rebuilt with every `notifyListeners()` (i.e. 60×/second). Keeping the
3D layer outside the animation builder removes a full widget + layer rebuild per
frame at zero visual cost.

Other per-frame rules:

* Debug query parameters are parsed once (`_fixDt`, `_freeze`, `_simSteps`,
  `_stopFrame`, `_stopAt`) instead of on every tick; `_debugHooks()` is skipped
  entirely when the URL has no query string.
* `SceneView` and the HUD are wrapped in `RepaintBoundary`s so HUD repaints do
  not invalidate the 3D layer.
* Materials and meshes are created once at load time; per-frame work only
  mutates transforms, emissive factors and light values.

## App phases

```
loading ──► mapsTitle ──► skyDrop ──► playing ──► finale ──► (map / retry)
                                        │
                                        └──► gameOver ──► (retry / map)
```

`AppPhase` lives in `game_state.dart`. `isGameplay` covers sky drop, playing and
finale; `gameOver` deliberately ends gameplay so the HUD hides and the run
summary takes over.

## Shields & scoring

* `GameState.maxShields = 3`; `beginRun()` refills them.
* `HeroSim._stumble()` emits a `stumble` event. `ShibuyaSceneController`
  translates that into `state.registerHit()`, which burns a shield and calls
  `endRun()` on the last one.
* Boost rings call `state.restoreShield()` (capped at the maximum), which is the
  risk/reward loop that keeps long runs alive.
* `GameState.award()` multiplies by the combo (clamped 1–12). Moves that must
  not scale pass `scaled: false` in `HeroSim._award`.
* `_bankRun()` is idempotent per run (`_runBanked`), so reaching the finale and
  then restarting can never double-count a run.

## Persistence

`lib/game/save_store.dart` selects an implementation at compile time:

| Target | Implementation | Backing store |
| --- | --- | --- |
| Android, iOS, macOS, Windows | `save_store_io.dart` | `.panda_runner/save.json` under the user home (`USERPROFILE` on Windows) |
| Web (JS) | `save_store_web.dart` | `window.localStorage` |
| Web (Wasm) / anything else | `save_store_stub.dart` | memory only |

Reads are synchronous and defensive: a missing, corrupt or read-only save file
falls back to defaults instead of throwing. Tests and the UI preview harness
inject `InMemorySaveStore`.

Persisted keys: `best_score`, `best_combo`, `runs_played`, `runs_completed`,
`muted`.

## 3D content pipeline

* `assets/data/shibuya_level.json` (≈1 MB) is exported from the original demo's
  bundle: OSM route spline, 167 buildings with heights, roads, rails, boost
  rings, barriers, slide portals, pin gates, taxis, street segments and the
  Google tower metadata.
* `world_builder.dart` extrudes the OSM footprints, `world_glb.dart` places the
  GLB props, `world_textures.dart` paints procedural window/brick/storefront
  textures, and `fx.dart` adds sparks, arcs and rain.
* `panda_rig.dart` builds the panda procedurally (no GLB needed), while
  `pegman_glb.dart`/`pegman_pose.dart` drive the original jointed Pegman.
* HDR emissive materials, AgX tone mapping and bloom come from `flutter_scene`.

## Tests

`test/game_test.dart` covers state defaults, combo scoring, shield depletion,
run banking, pause semantics, title reset and the persistence round-trip. The
3D layer is intentionally not widget-tested (it needs a GPU-backed scene), but
`flutter analyze` and the CI web, Android and Windows builds compile the whole
Dart/native integration on every PR. The native runner configurator has a
separate standard-library Python test suite.
