import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Audio + haptics.
///
/// * BGM: the demo's own `shibuya_bgm.mp3`, looped (music bus 1.14).
/// * SFX: the demo synthesizes every effect live with Web Audio (`e_`
///   class: playJump, playBoostRing, setRailGrind, ...). Those voices were
///   recorded from the demo's master bus and ship as `assets/sfx/*`, so they
///   sound identical; per-voice retrigger guards mirror `_canTriggerSfx`.
/// * Loops: rail grind (`setRailGrind`), overcharge wind
///   (`updateOverchargeWind`) and the sky-drop wind ramp.
class SoundFx {
  bool _muted = false;
  AudioPlayer? _bgm;
  bool _started = false;
  bool _ready = false;
  final Map<String, AudioPool> _pools = {};
  final Map<String, int> _lastMs = {};
  final Stopwatch _clock = Stopwatch()..start();

  AudioPlayer? _rail, _wind, _skyDrop;
  double _railVol = 0, _windVol = 0;
  bool _skyDropOn = false;

  static const double _bgmVolume = 1.0;

  /// Minimum retrigger interval per voice (ms), from `_canTriggerSfx`.
  static const Map<String, int> _guard = {
    'jump': 65,
    'land_light': 60,
    'land_heavy': 60,
    'slide': 140,
    'lane_left': 55,
    'lane_right': 55,
    'boost_ring': 110,
    'near_miss': 130,
    'drift_whoosh': 125,
    'transfer': 140,
    'pin_ignition': 55,
    'electric_arc': 42,
    'street_chime': 1500,
    'stumble': 180,
    'gas_zap': 110,
    'car_horn': 160,
    'roof_vault': 110,
    'neon_arch': 220,
    'photo_shutter': 150,
    'maps_swell': 600,
    'touchdown': 400,
    'google_tower': 350,
    'finale': 450,
  };

  static const List<String> _oneShots = [
    'jump', 'land_light', 'land_heavy', 'slide', 'lane_left', 'lane_right', //
    'boost_ring', 'near_miss', 'drift_whoosh', 'transfer', 'pin_ignition',
    'electric_arc', 'street_chime', 'stumble', 'gas_zap', 'car_horn',
    'roof_vault', 'neon_arch', 'photo_shutter', 'maps_swell', 'touchdown',
    'google_tower', 'finale', 'letter_0', 'letter_1', 'letter_2', 'letter_3',
    'letter_4', 'letter_5',
  ];

  bool get muted => _muted;
  set muted(bool v) {
    _muted = v;
    _bgm?.setVolume(v ? 0 : _bgmVolume);
    if (v) {
      setRailGrind(false);
      updateOverchargeWind(0);
      skyDropWind(-1);
    }
  }

  /// Starts the BGM and warms the SFX voices (call from the PLAY gesture so
  /// browsers allow playback).
  Future<void> startMusic() async {
    if (_started) return;
    _started = true;
    try {
      final p = AudioPlayer();
      _bgm = p;
      await p.setReleaseMode(ReleaseMode.loop);
      await p.setVolume(_muted ? 0 : _bgmVolume);
      await p.play(AssetSource('audio/shibuya_bgm.mp3'));
    } catch (_) {
      _started = false; // e.g. autoplay blocked; retry on next gesture
      return;
    }
    unawaited(_warm());
  }

  Future<void> _warm() async {
    for (final n in _oneShots) {
      try {
        _pools[n] = await AudioPool.createFromAsset(
            path: 'sfx/$n.mp3', maxPlayers: n.startsWith('lane') || n == 'pin_ignition' ? 4 : 3);
      } catch (_) {}
    }
    Future<AudioPlayer?> loop(String file) async {
      try {
        final p = AudioPlayer();
        await p.setReleaseMode(ReleaseMode.loop);
        await p.setVolume(0);
        await p.setSource(AssetSource(file));
        return p;
      } catch (_) {
        return null;
      }
    }

    _rail = await loop('sfx/rail_loop.wav');
    _wind = await loop('sfx/wind_loop.wav');
    try {
      final s = AudioPlayer();
      await s.setReleaseMode(ReleaseMode.stop);
      await s.setSource(AssetSource('sfx/skydrop_wind.mp3'));
      _skyDrop = s;
    } catch (_) {}
    _ready = true;
  }

  /// Plays a recorded demo voice (see [_oneShots]).
  void play(String name, {double volume = 1}) {
    if (_muted || !_ready) return;
    final now = _clock.elapsedMilliseconds;
    final g = _guard[name] ?? 35;
    if (now - (_lastMs[name] ?? -100000) < g) return;
    _lastMs[name] = now;
    _pools[name]?.start(volume: volume.clamp(0.0, 1.0));
  }

  /// `setRailGrind(active, speedNorm)`: metal screech + crackle loop.
  void setRailGrind(bool active, [double speedNorm = 0.85]) {
    final v = active && !_muted ? (0.55 + 0.45 * speedNorm.clamp(0.0, 1.0)) : 0.0;
    if ((v - _railVol).abs() < 0.02) return;
    final was = _railVol;
    _railVol = v;
    final p = _rail;
    if (p == null) return;
    p.setVolume(v);
    if (v > 0 && was <= 0) {
      p.resume();
    } else if (v <= 0) {
      p.pause();
    }
  }

  /// `updateOverchargeWind(speedMps)`: noise rush above 30 m/s.
  void updateOverchargeWind(double speedMps) {
    final n = _muted ? 0.0 : ((speedMps - 30) / 14).clamp(0.0, 1.0);
    final r = n * n * (3 - 2 * n);
    final v = r <= 0.001 ? 0.0 : r;
    if ((v - _windVol).abs() < 0.03 && !(v == 0 && _windVol > 0)) return;
    final was = _windVol;
    _windVol = v;
    final p = _wind;
    if (p == null) return;
    p.setVolume(v);
    if (v > 0 && was <= 0) {
      p.resume();
    } else if (v <= 0) {
      p.pause();
    }
  }

  /// `playSkyDropWind(progress)`: starts the 3.5 s ramp, `-1` stops it.
  void skyDropWind(double progress) {
    final p = _skyDrop;
    if (p == null) return;
    if (progress < 0) {
      if (_skyDropOn) {
        _skyDropOn = false;
        p.stop();
      }
      return;
    }
    if (!_skyDropOn && !_muted) {
      _skyDropOn = true;
      p.seek(Duration(milliseconds: (progress * 3500).round()));
      p.resume();
    }
  }

  // ---------------------------------------------------------- haptics
  void playLaneSwitch() {
    if (_muted) return;
    HapticFeedback.selectionClick();
  }

  void playJump() {
    if (_muted) return;
    HapticFeedback.lightImpact();
  }

  void playBoostRing() {
    if (_muted) return;
    HapticFeedback.mediumImpact();
  }

  void playCrash() {
    if (_muted) return;
    HapticFeedback.heavyImpact();
  }

  void playVictory() {
    if (_muted) return;
    HapticFeedback.heavyImpact();
  }

  void dispose() {
    _bgm?.dispose();
    for (final p in _pools.values) {
      p.dispose();
    }
    _rail?.dispose();
    _wind?.dispose();
    _skyDrop?.dispose();
  }
}
