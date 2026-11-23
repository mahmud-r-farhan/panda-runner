import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' as fs;

import '../game/game_state.dart';
import '../game/shibuya_scene_controller.dart';
import '../game/sound_fx.dart';
import 'hud_overlay.dart';
import 'loading_screen.dart';
import 'maps_title_card.dart';
import 'shibuya_map_view.dart';
import 'speed_lines.dart';

/// Hosts the Flutter Scene view, the frame ticker, keyboard (A/D, Space,
/// S, P, 1-3, Esc) and touch/swipe input, and the 2D overlays.
///
/// Debug URL parameters (web): `?autoplay=1` starts a run with Auto-Pilot,
/// `&seek=0.5` jumps to that route fraction after landing,
/// `&photo=skyline` opens photo mode with a preset.
class NeonScrambleGameScreen extends StatefulWidget {
  const NeonScrambleGameScreen({super.key});

  @override
  State<NeonScrambleGameScreen> createState() => _NeonScrambleGameScreenState();
}

class _NeonScrambleGameScreenState extends State<NeonScrambleGameScreen>
    with SingleTickerProviderStateMixin {
  late final GameState _state;
  late final SoundFx _soundFx;
  late final ShibuyaSceneController _controller;
  late final Ticker _ticker;
  final FocusNode _focusNode = FocusNode();

  Duration _lastTick = Duration.zero;
  Offset? _dragStart;
  bool _swipeHandled = false;

  // debug params
  final Map<String, String> _q = Uri.base.queryParameters;
  bool _autoStarted = false;
  bool _seekDone = false;
  bool _stopped = false;
  bool _stopAfterNext = false;
  int _runFrames = 0;

  @override
  void initState() {
    super.initState();
    _state = GameState();
    _soundFx = SoundFx();
    _controller = ShibuyaSceneController(state: _state, soundFx: _soundFx);
    _controller.initialize();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }
    var dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05);
    // `&fixdt=1`: step exactly 1/60 s per frame (like the demo's
    // `__advanceFrame`) so debug captures match 60 fps behaviour.
    if (_q['fixdt'] == '1') dt = 1 / 60;
    _lastTick = elapsed;
    _debugHooks();
    // `?sim=N` runs N simulation substeps per frame (debug fast-forward).
    final sub = int.tryParse(_q['sim'] ?? '') ?? 1;
    // `&freeze=1` holds the frame right after a seek (debug captures).
    if (_q['freeze'] == '1' && _seekDone) return;
    if (_stopped) return;
    for (int i = 0; i < sub; i++) {
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
    final stopFrame = int.tryParse(_q['stopframe'] ?? '');
    if (stopFrame != null && _runFrames >= stopFrame) {
      _stopped = true;
      debugPrint('stopped: frame=$_runFrames s=${_controller.sim.s.toStringAsFixed(1)}');
    }
    final stopAt = double.tryParse(_q['stopat'] ?? '');
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
    _ticker.dispose();
    _focusNode.dispose();
    _controller.dispose();
    _soundFx.dispose();
    _state.dispose();
    super.dispose();
  }

  void _play() {
    _soundFx.startMusic();
    _focusNode.requestFocus();
    _controller.startNewRun();
  }

  void _togglePhoto() {
    if (!_state.isGameplay) return;
    _controller.resetPhotoCamera();
    _state.togglePhotoMode();
    if (_state.photoMode) _soundFx.play('photo_shutter');
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      final k = event.logicalKey;
      if (k == LogicalKeyboardKey.keyA || k == LogicalKeyboardKey.arrowLeft) _controller.releaseLane(-1);
      if (k == LogicalKeyboardKey.keyD || k == LogicalKeyboardKey.arrowRight) _controller.releaseLane(1);
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (_state.phase == AppPhase.mapsTitle) {
      if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.enter) {
        _play();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (k == LogicalKeyboardKey.keyP) {
      _togglePhoto();
    } else if (_state.photoMode) {
      if (k == LogicalKeyboardKey.escape) _togglePhoto();
      if (k == LogicalKeyboardKey.digit1) _state.setPhotoPreset(PhotoPreset.hero);
      if (k == LogicalKeyboardKey.digit2) _state.setPhotoPreset(PhotoPreset.scramble);
      if (k == LogicalKeyboardKey.digit3) _state.setPhotoPreset(PhotoPreset.skyline);
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
            child: AnimatedBuilder(
              animation: _state,
              builder: (context, _) {
                final title = _state.phase == AppPhase.mapsTitle;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_controller.initialized && !title)
                      fs.SceneView(
                        _controller.scene,
                        cameraBuilder: _controller.buildCamera,
                      ),
                    if (_controller.initialized && !title) const VignetteOverlay(),
                    if (_controller.initialized && !title)
                      SpeedLinesOverlay(
                        factor: _controller.speedLinesFactor,
                        time: _controller.time,
                      ),
                    if (_controller.initialized && title)
                      ShibuyaMapView(
                        level: _controller.level,
                        time: _state.elapsed,
                      ),
                    if (title)
                      MapsTitleCard(
                        state: _state,
                        onPlay: _play,
                        onSelectLocation: (loc) {
                          _state.selectLocation(loc);
                          _controller.updateLocation(loc);
                        },
                        onSelectHero: (hero) {
                          _state.selectHero(hero);
                        },
                      ),
                    if (_state.isGameplay)
                      HudOverlay(
                        state: _state,
                        level: _controller.level,
                        onToggleAutoPilot: _state.toggleAutoPilot,
                        onToggleMute: () {
                          _state.toggleMute();
                          _soundFx.muted = _state.muted;
                        },
                        onTogglePhoto: _togglePhoto,
                        onPlayAgain: _play,
                        onPhotoPreset: _state.setPhotoPreset,
                      ),
                    if (_state.phase == AppPhase.loading)
                      LoadingScreen(state: _state),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
