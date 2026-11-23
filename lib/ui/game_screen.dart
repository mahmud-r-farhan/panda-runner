import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' as fs;

import '../game/game_state.dart';
import '../game/shibuya_scene_controller.dart';
import '../game/sound_fx.dart';
import 'game_over_card.dart';
import 'hud_overlay.dart';
import 'loading_screen.dart';
import 'maps_title_card.dart';
import 'pause_overlay.dart';
import 'shibuya_map_view.dart';
import 'speed_lines.dart';

/// Hosts the Flutter Scene view, the frame ticker, keyboard and touch input,
/// and the 2D overlays.
///
/// Controls: `A`/`D` or `←`/`→` lanes · `Space`/`W`/`↑` jump & roof vault ·
/// `S`/`↓` slide · `P` photo mode · `Esc` pause · `R` restart · `Q` map ·
/// `M` mute. Touch: swipe left/right/up/down.
///
/// Debug URL parameters (web): `?autoplay=1` starts a run with Auto-Pilot,
/// `&seek=0.5` jumps to that route fraction after landing,
/// `&photo=skyline` opens photo mode with a preset.
class PandaRunnerGameScreen extends StatefulWidget {
  const PandaRunnerGameScreen({super.key});

  @override
  State<PandaRunnerGameScreen> createState() => _PandaRunnerGameScreenState();
}

class _PandaRunnerGameScreenState extends State<PandaRunnerGameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final GameState _state;
  late final SoundFx _soundFx;
  late final ShibuyaSceneController _controller;
  late final Ticker _ticker;
  final FocusNode _focusNode = FocusNode();

  Duration _lastTick = Duration.zero;
  Offset? _dragStart;
  bool _swipeHandled = false;

  // Debug params, parsed once. Real players have an empty query string, so
  // the per-frame path below stays allocation- and parse-free.
  final Map<String, String> _q = Uri.base.queryParameters;
  late final bool _fixDt = _q['fixdt'] == '1';
  late final bool _freeze = _q['freeze'] == '1';
  late final int _simSteps = (int.tryParse(_q['sim'] ?? '') ?? 1).clamp(1, 32);
  late final int? _stopFrame = int.tryParse(_q['stopframe'] ?? '');
  late final double? _stopAt = double.tryParse(_q['stopat'] ?? '');
  bool _autoStarted = false;
  bool _seekDone = false;
  bool _stopped = false;
  bool _stopAfterNext = false;
  int _runFrames = 0;

  // Coarse render tracking: the 3D layer is only rebuilt when the phase or
  // scene readiness changes, never on a simulation frame.
  AppPhase? _builtPhase;
  bool? _builtInitialized;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _state = GameState();
    _soundFx = SoundFx()..muted = _state.muted;
    _controller = ShibuyaSceneController(state: _state, soundFx: _soundFx);
    _controller.initialize();
    // Listen after the first frame: `initialize()` reports loading progress
    // synchronously, which must not call setState during initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _state.addListener(_onCoarseStateChanged);
    });
    _ticker = createTicker(_onTick)..start();
  }

  /// Rebuilds the screen (and therefore the 3D layer) only when the app phase
  /// or scene readiness changes. The HUD listens to [GameState] separately and
  /// still updates every frame.
  void _onCoarseStateChanged() {
    if (!mounted) return;
    if (_state.phase == _builtPhase &&
        _controller.initialized == _builtInitialized) {
      return;
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) return;
    // Backgrounding the app pauses the run, so nobody returns to a crash.
    if (_state.isGameplay && !_state.paused && !_state.photoMode) {
      _state.pause();
      _soundFx.setPaused(true);
    }
  }

  void _onTick(Duration elapsed) {
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }
    var dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastTick = elapsed;
    // Paused: the frame stays frozen, no simulation and no repaint cost.
    if (_state.paused) return;
    // `&fixdt=1`: step exactly 1/60 s per frame (like the demo's
    // `__advanceFrame`) so debug captures match 60 fps behaviour.
    if (_fixDt) dt = 1 / 60;
    if (_q.isNotEmpty) _debugHooks();
    // `&freeze=1` holds the frame right after a seek (debug captures).
    if (_freeze && _seekDone) return;
    if (_stopped) return;
    for (int i = 0; i < _simSteps; i++) {
      _controller.tick(dt);
    }
    if (_stopAfterNext) {
      _stopped = true;
      final h = _controller.sim;
      debugPrint('stopped: ffframes ${_state.phase.name} ${h.move.name} s=${h.s.toStringAsFixed(2)} '
          'lat=${h.lateral.toStringAsFixed(2)} y=${h.y.toStringAsFixed(2)} lane=${h.laneIndex} '
          'v=${h.speed.toStringAsFixed(2)} flip=${h.flipStyle} ${h.flipPhase.toStringAsFixed(2)} '
          'hero=(${h.x.toStringAsFixed(2)},${h.y.toStringAsFixed(2)},${h.z.toStringAsFixed(2)}) '
          'cam=(${_controller.camPos.x.toStringAsFixed(2)},${_controller.camPos.y.toStringAsFixed(2)},${_controller.camPos.z.toStringAsFixed(2)}) '
          'tgt=(${_controller.camTarget.x.toStringAsFixed(2)},${_controller.camTarget.y.toStringAsFixed(2)},${_controller.camTarget.z.toStringAsFixed(2)}) fov=${_controller.camFov.toStringAsFixed(1)} '
          'kv=${h.voltage.toStringAsFixed(2)} combo=${_state.combo} boost=${h.boostBonus.toStringAsFixed(2)} '
          'score=${_state.score} ${h.ledger.join(' ; ')}');
    }
    // `&stopat=<meters>`: run live, then hold the frame once the hero
    // reaches that route distance (debug captures of in-motion FX).
    // `&stopframe=N`: hold after N ticks of the run (sky-drop captures).
    if (_state.phase != AppPhase.mapsTitle && _state.phase != AppPhase.loading) _runFrames++;
    final stopFrame = _stopFrame;
    if (stopFrame != null && _runFrames >= stopFrame) {
      _stopped = true;
      debugPrint('stopped: frame=$_runFrames s=${_controller.sim.s.toStringAsFixed(1)}');
    }
    final stopAt = _stopAt;
    if (stopAt != null && _seekDone && _controller.sim.s >= stopAt) {
      _stopped = true;
      final c = _controller;
      debugPrint('stopped: s=${c.sim.s.toStringAsFixed(1)} move=${c.sim.move.name} '
          'hero=(${c.sim.x.toStringAsFixed(2)},${c.sim.y.toStringAsFixed(2)},${c.sim.z.toStringAsFixed(2)}) lat=${c.sim.lateral.toStringAsFixed(2)} '
          'cam=(${c.camPos.x.toStringAsFixed(2)},${c.camPos.y.toStringAsFixed(2)},${c.camPos.z.toStringAsFixed(2)}) '
          'tgt=(${c.camTarget.x.toStringAsFixed(2)},${c.camTarget.y.toStringAsFixed(2)},${c.camTarget.z.toStringAsFixed(2)}) fov=${c.camFov.toStringAsFixed(1)}');
    }
  }

  void _debugHooks() {
    if (!_controller.initialized) return;
    if (!_autoStarted && (_q['autoplay'] == '1' || _q['manual'] == '1') && _state.phase == AppPhase.mapsTitle) {
      _autoStarted = true;
      if (_q['manual'] != '1' && !_state.autoPilot) _state.toggleAutoPilot();
      _controller.startNewRun();
    }
    final seek = double.tryParse(_q['seek'] ?? '');
    if (seek != null && !_seekDone && _state.phase == AppPhase.playing) {
      _seekDone = true;
      _controller.sim.seek(seek);
    }
    // `?seekm=<meters>`: like the demo's __seekRouteProgress — fast-forward
    // the real simulation on Auto-Pilot at 60 Hz until the hero reaches s.
    // `?ffframes=N`: simulate the first N ticks (1/60 s) of the run
    // synchronously, then hold (frame-exact sky-drop captures).
    final ff = int.tryParse(_q['ffframes'] ?? '');
    if (ff != null && !_seekDone && _state.phase == AppPhase.skyDrop) {
      _seekDone = true;
      // `&script=240:R,270:J,...`: frame-exact taps (L/R lane, J jump,
      // S slide) for side-by-side movement tests against the demo.
      final script = <int, List<String>>{};
      for (final part in (_q['script'] ?? '').split(',')) {
        final kv = part.split(':');
        if (kv.length == 2) (script[int.tryParse(kv[0]) ?? -1] ??= []).add(kv[1]);
      }
      for (int i = 1; i < ff; i++) {
        for (final a in script[i] ?? const <String>[]) {
          switch (a) {
            case 'L':
              _controller.moveLane(-1);
              _controller.releaseLane(-1);
            case 'R':
              _controller.moveLane(1);
              _controller.releaseLane(1);
            case 'l': // hold A
              _controller.moveLane(-1);
            case 'r': // hold D
              _controller.moveLane(1);
            case 'U': // release both
              _controller.releaseLane(-1);
              _controller.releaseLane(1);
            case 'J':
              _controller.jump();
            case 'S':
              _controller.slide();
          }
        }
        _controller.tick(1 / 60);
      }
      _stopAfterNext = true;
      debugPrint('ffframes: $ff s=${_controller.sim.s.toStringAsFixed(1)} phase=${_state.phase.name}');
    }
    final seekm = double.tryParse(_q['seekm'] ?? '');
    if (seekm != null && !_seekDone && _state.phase == AppPhase.skyDrop) {
      for (int i = 0; i < 600 && _state.phase == AppPhase.skyDrop; i++) {
        _controller.tick(1 / 60);
      }
    }
    if (seekm != null && !_seekDone && _state.phase == AppPhase.playing) {
      _seekDone = true;
      if (!_state.autoPilot) _state.toggleAutoPilot();
      try {
        int i = 0;
        for (; i < 5400 && _controller.sim.s < seekm && _state.phase == AppPhase.playing; i++) {
          _controller.tick(1 / 60);
        }
        final c = _controller;
        if (_q['ledger'] == '1') {
          for (final l in c.sim.ledger) {
            debugPrint('ledger|$l');
          }
          debugPrint('ledger|score|${_state.score}|nm=${c.sim.nearMisses} st=${c.sim.stumbles}');
        }
        debugPrint('seekm: $i steps -> s=${c.sim.s.toStringAsFixed(1)} '
            'hero=(${c.sim.x.toStringAsFixed(2)},${c.sim.y.toStringAsFixed(2)},${c.sim.z.toStringAsFixed(2)}) '
            'cam=(${c.camPos.x.toStringAsFixed(2)},${c.camPos.y.toStringAsFixed(2)},${c.camPos.z.toStringAsFixed(2)}) fov=${c.camFov.toStringAsFixed(1)}');
      } catch (e, st) {
        debugPrint('seekm failed: $e\n$st');
      }
    }
    final photo = _q['photo'];
    if (photo != null && !_state.photoMode && _seekDone && _state.isGameplay &&
        (_state.phase == AppPhase.finale || _q['photoNow'] == '1')) {
      _state.setPhotoPreset(PhotoPreset.values.firstWhere((p) => p.name == photo,
          orElse: () => PhotoPreset.hero));
      _state.togglePhotoMode();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _state.removeListener(_onCoarseStateChanged);
    _ticker.dispose();
    _focusNode.dispose();
    _controller.dispose();
    _soundFx.dispose();
    _state.dispose();
    super.dispose();
  }

  void _play() {
    _state.resume();
    _soundFx
      ..setPaused(false)
      ..startMusic();
    _focusNode.requestFocus();
    _controller.startNewRun();
  }

  void _togglePause() {
    if (!_state.isGameplay || _state.photoMode) return;
    _state.togglePause();
    _soundFx.setPaused(_state.paused);
    _focusNode.requestFocus();
  }

  void _resume() {
    if (!_state.paused) return;
    _state.resume();
    _soundFx.setPaused(false);
    _focusNode.requestFocus();
  }

  void _toggleMute() {
    _state.toggleMute();
    _soundFx.muted = _state.muted;
  }

  void _quitToTitle() {
    _soundFx.setPaused(false);
    _controller.quitToTitle();
    _focusNode.requestFocus();
  }

  void _togglePhoto() {
    if (!_state.isGameplay || _state.paused) return;
    _controller.resetPhotoCamera();
    _state.togglePhotoMode();
    if (_state.photoMode) _soundFx.play('photo_shutter');
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      final k = event.logicalKey;
      if (k == LogicalKeyboardKey.keyA || k == LogicalKeyboardKey.arrowLeft) {
        _controller.releaseLane(-1);
      }
      if (k == LogicalKeyboardKey.keyD || k == LogicalKeyboardKey.arrowRight) {
        _controller.releaseLane(1);
      }
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;

    // Title / map screen: start a run.
    if (_state.phase == AppPhase.mapsTitle) {
      if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.enter) {
        _play();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Game over: retry or go back to the map.
    if (_state.phase == AppPhase.gameOver) {
      if (k == LogicalKeyboardKey.keyR ||
          k == LogicalKeyboardKey.enter ||
          k == LogicalKeyboardKey.space) {
        _play();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyQ || k == LogicalKeyboardKey.escape) {
        _quitToTitle();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Escape always means "back out of the current modal state".
    if (k == LogicalKeyboardKey.escape) {
      if (_state.photoMode) {
        _togglePhoto();
      } else {
        _togglePause();
      }
      return KeyEventResult.handled;
    }

    if (_state.paused) {
      if (k == LogicalKeyboardKey.enter ||
          k == LogicalKeyboardKey.space ||
          k == LogicalKeyboardKey.keyP) {
        _resume();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyR) {
        _play();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyQ) {
        _quitToTitle();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyM) {
        _toggleMute();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (k == LogicalKeyboardKey.keyP) {
      _togglePhoto();
    } else if (_state.photoMode) {
      if (k == LogicalKeyboardKey.digit1) _state.setPhotoPreset(PhotoPreset.hero);
      if (k == LogicalKeyboardKey.digit2) {
        _state.setPhotoPreset(PhotoPreset.scramble);
      }
      if (k == LogicalKeyboardKey.digit3) _state.setPhotoPreset(PhotoPreset.skyline);
    } else if (k == LogicalKeyboardKey.keyM) {
      _toggleMute();
    } else if (k == LogicalKeyboardKey.keyA || k == LogicalKeyboardKey.arrowLeft) {
      _controller.moveLane(-1);
    } else if (k == LogicalKeyboardKey.keyD || k == LogicalKeyboardKey.arrowRight) {
      _controller.moveLane(1);
    } else if (k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.keyW ||
        k == LogicalKeyboardKey.arrowUp) {
      _controller.jump();
    } else if (k == LogicalKeyboardKey.keyS || k == LogicalKeyboardKey.arrowDown) {
      _controller.slide();
    } else if (k == LogicalKeyboardKey.enter && _state.phase == AppPhase.finale) {
      _play();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _onPanStart(DragStartDetails d) {
    _dragStart = d.localPosition;
    _swipeHandled = false;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_state.photoMode) {
      _controller.orbitPhotoCamera(d.delta.dx, d.delta.dy);
      return;
    }
    if (_swipeHandled || _dragStart == null) return;
    final delta = d.localPosition - _dragStart!;
    if (delta.distance < 26) return;
    _swipeHandled = true;
    if (delta.dx.abs() > delta.dy.abs()) {
      final dir = delta.dx > 0 ? 1 : -1;
      _controller.moveLane(dir);
      _controller.releaseLane(dir);
    } else if (delta.dy < 0) {
      _controller.jump();
    } else {
      _controller.slide();
    }
  }

  @override
  Widget build(BuildContext context) {
    final showScene =
        _controller.initialized && _state.phase != AppPhase.mapsTitle;
    // Remember what this build was based on: `_onCoarseStateChanged` only
    // asks for another one when the phase or scene readiness changes.
    _builtPhase = _state.phase;
    _builtInitialized = _controller.initialized;

    return Scaffold(
      backgroundColor: const Color(0xFF07090E),
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent && _state.photoMode) {
              _controller.zoomPhotoCamera(e.scrollDelta.dy);
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _focusNode.requestFocus(),
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 3D scene + static post FX: rebuilt on phase changes only.
                if (showScene) _SceneLayer(controller: _controller),
                // 2D overlays: this layer re-renders every simulation frame,
                // the 3D scene above does not.
                AnimatedBuilder(
                  animation: _state,
                  builder: (context, _) => _buildOverlays(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlays() {
    final title = _state.phase == AppPhase.mapsTitle;
    final ready = _controller.initialized;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (ready && !title)
          IgnorePointer(
            child: SpeedLinesOverlay(
              factor: _controller.speedLinesFactor,
              time: _controller.time,
            ),
          ),
        if (ready && title)
          ShibuyaMapView(level: _controller.level, time: _state.elapsed),
        if (title)
          MapsTitleCard(
            state: _state,
            onPlay: _play,
            onSelectLocation: (loc) {
              _state.selectLocation(loc);
              _controller.updateLocation(loc);
            },
            onSelectHero: (hero) => _state.selectHero(hero),
          ),
        if (_state.isGameplay)
          HudOverlay(
            state: _state,
            level: _controller.level,
            onToggleAutoPilot: _state.toggleAutoPilot,
            onToggleMute: _toggleMute,
            onTogglePhoto: _togglePhoto,
            onTogglePause: _togglePause,
            onPlayAgain: _play,
            onPhotoPreset: _state.setPhotoPreset,
          ),
        if (_state.phase == AppPhase.gameOver)
          GameOverCard(
            state: _state,
            onRestart: _play,
            onQuit: _quitToTitle,
          ),
        if (_state.paused)
          PauseOverlay(
            state: _state,
            onResume: _resume,
            onRestart: _play,
            onQuit: _quitToTitle,
            onToggleMute: _toggleMute,
          ),
        if (_state.phase == AppPhase.loading) LoadingScreen(state: _state),
      ],
    );
  }
}

/// The 3D scene plus its static full-screen post effects.
///
/// Living in its own widget keeps [fs.SceneView] out of the per-frame HUD
/// rebuild, so the scene widget, its camera-builder closure and its layer are
/// only re-created when the app phase changes.
class _SceneLayer extends StatelessWidget {
  const _SceneLayer({required this.controller});

  final ShibuyaSceneController controller;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          fs.SceneView(
            controller.scene,
            cameraBuilder: controller.buildCamera,
          ),
          const VignetteOverlay(),
        ],
      ),
    );
  }
}
