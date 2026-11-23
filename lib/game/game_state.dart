import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'map_location.dart';
import 'save_store.dart';

/// Active runner character.
enum HeroCharacterType {
  panda('3D Panda Ninja', '🐼'),
  pegman('Pegman Neon', '📍');

  const HeroCharacterType(this.label, this.emoji);
  final String label;
  final String emoji;
}

/// App phases, mirroring the web demo's `APP_PHASES`
/// (LOADING → MAPS_TITLE → SKY_DROP → PLAYING → FINALE), plus a GAME OVER
/// state for runs that end after the last shield is spent.
enum AppPhase { loading, mapsTitle, skyDrop, playing, finale, gameOver }

/// Parkour move shown in the HUD move badge (`data-move` in the web demo).
enum ParkourMove {
  skyDrop('SKY DROP'),
  sprint('SPRINT'),
  overcharge('OVERCHARGE'),
  jump('JUMP'),
  airFlip('AIR FLIP'),
  slide('SLIDE'),
  railGrind('RAIL GRIND'),
  wallRun('WALL RUN'),
  roofVault('ROOF VAULT'),
  neonSlide('NEON SLIDE'),
  pinBeacon('BOOST'),
  stumble('STUMBLE'),
  carDeflect('DEFLECT'),
  hoodBounce('BOUNCE'),
  sideDeflect('SIDE DEFLECT'),
  finaleOrbit('FINALE');

  const ParkourMove(this.label);
  final String label;
}

/// Accent of the bottom-center action callout (`data-accent`).
enum CalloutAccent { neon, gold, danger, google, vault, neonSlide }

enum PhotoPreset { hero, scramble, skyline }

class ActionCallout {
  ActionCallout({
    required this.id,
    required this.label,
    required this.bonus,
    required this.accent,
    required this.createdAt,
    this.duration = 1.85,
  });

  final int id;
  final String label;

  /// e.g. `+1,500`; empty string hides the `·` separator and bonus.
  final String bonus;
  final CalloutAccent accent;
  final double createdAt;
  final double duration;
}

/// Street-entry pill shown for 1.8 s of sim time when entering a street.
class StreetPill {
  StreetPill(this.id, this.ja, this.en, this.shield, this.isRail, this.createdAt);
  final int id;
  final String ja;
  final String en;
  final String? shield;
  final bool isRail;
  final double createdAt;
}

/// One named street segment of the route (minimap header).
class StreetSegment {
  const StreetSegment({
    required this.sStart,
    required this.sEnd,
    required this.ja,
    required this.miniEn,
    this.shield,
    this.shortEn = '',
    this.isRail = false,
  });

  final String shortEn;
  final bool isRail;

  final double sStart;
  final double sEnd;
  final String ja;
  final String miniEn;
  final String? shield;

  /// Minimap header text, e.g. `渋谷スクランブル · Scramble`.
  String get headerLabel => '$ja · $miniEn';
}

/// Observable game state shared by the 3D controller and the Flutter HUD.
class GameState extends ChangeNotifier {
  static const double overchargeKmh = 130.0;

  /// Shields per run. A crash costs one; the last one ends the run.
  static const int maxShields = 3;

  /// [saveStore] defaults to the platform store (file on desktop/mobile,
  /// `localStorage` on the web, memory elsewhere).
  GameState({SaveStore? saveStore})
      : _saveStore = saveStore ?? SaveStore.create() {
    _restoreProgress();
  }

  final SaveStore _saveStore;

  /// Shields left in the current run.
  int shields = maxShields;

  // Persisted progress & settings.
  int bestScore = 0;
  int bestCombo = 1;
  int runsPlayed = 0;
  int runsCompleted = 0;

  /// True when the run that just ended set a new personal best.
  bool newBest = false;

  /// True while the player has paused an active run.
  bool paused = false;

  /// Guards against banking the same run twice (finale + restart).
  bool _runBanked = false;

  AppPhase phase = AppPhase.loading;
  ParkourMove move = ParkourMove.skyDrop;

  HeroCharacterType selectedHero = HeroCharacterType.panda;
  MapLocation location = MapLocation.shibuya;

  double loadingProgress = 0.0;
  String loadingLabel = 'Loading Shibuya...';

  int score = 0;
  double speedKmh = 0.0;
  double maxSpeedKmh = 0.0;
  int combo = 1;
  double runTimeSec = 0.0;
  double elapsed = 0.0;

  /// 0..1 overcharge meter (speed above the cruise target).
  double overchargeRatio = 0.0;

  /// Distance along the route spline in meters and the route length.
  double routeS = 0.0;
  double routeLength = 1047.1;

  /// Hero world position on the ground plane (meters, three.js frame:
  /// +X east, +Z south) and heading for the minimap.
  double heroX = -48.0;
  double heroZ = -5.2;
  double heroHeading = 1.485;

  StreetSegment? street;

  bool autoPilot = false;
  bool muted = false;
  bool photoMode = false;
  PhotoPreset photoPreset = PhotoPreset.hero;

  /// Onboarding hint pill: shown for the first seconds of the run.
  bool onboardingVisible = false;

  /// Google sign letters (G o o g l e) ignited during the finale.
  final List<bool> googleLettersLit = List<bool>.filled(6, false);

  ActionCallout? callout;
  int _nextCalloutId = 1;
  StreetPill? streetPill;
  double _playTime = 0;

  bool get isGameplay =>
      phase == AppPhase.skyDrop ||
      phase == AppPhase.playing ||
      phase == AppPhase.finale;

  bool get speedOvercharge =>
      phase == AppPhase.playing &&
      (speedKmh >= overchargeKmh || overchargeRatio >= 0.58);

  bool get highChain => combo >= 4;

  /// Best score to show in the UI, including the run in progress.
  int get displayBest => math.max(bestScore, score);

  /// Badge shown in the telemetry pill.
  ParkourMove get displayMove {
    if (phase == AppPhase.skyDrop) return ParkourMove.skyDrop;
    if (speedOvercharge && move == ParkourMove.sprint) {
      return ParkourMove.overcharge;
    }
    return move;
  }

  void setLoading(double value, String label) {
    loadingProgress = value.clamp(0.0, 1.0);
    loadingLabel = label;
    notifyListeners();
  }

  void finishLoading() {
    loadingProgress = 1.0;
    phase = AppPhase.mapsTitle;
    notifyListeners();
  }

  void beginRun() {
    phase = AppPhase.skyDrop;
    move = ParkourMove.skyDrop;
    score = 0;
    speedKmh = 0;
    maxSpeedKmh = 0;
    combo = 1;
    shields = maxShields;
    paused = false;
    newBest = false;
    _runBanked = false;
    runTimeSec = 0;
    overchargeRatio = 0;
    routeS = 0;
    photoMode = false;
    photoPreset = PhotoPreset.hero;
    onboardingVisible = false;
    callout = null;
    streetPill = null;
    for (int i = 0; i < 6; i++) {
      googleLettersLit[i] = false;
    }
    notifyListeners();
  }

  void landFromSkyDrop() {
    phase = AppPhase.playing;
    move = ParkourMove.sprint;
    _playTime = 0;
    onboardingVisible = !autoPilot;
    notifyListeners();
  }

  void enterFinale() {
    _bankRun(completed: true);
    phase = AppPhase.finale;
    autoPilot = false; // the demo drops Auto-Pilot once the run completes
    move = ParkourMove.finaleOrbit;
    onboardingVisible = false;
    streetPill = null;
    notifyListeners();
  }

  void toggleAutoPilot() {
    autoPilot = !autoPilot;
    if (autoPilot) onboardingVisible = false;
    notifyListeners();
  }

  void selectHero(HeroCharacterType hero) {
    if (selectedHero == hero) return;
    selectedHero = hero;
    notifyListeners();
  }

  void selectLocation(MapLocation loc) {
    if (location.id == loc.id) return;
    location = loc;
    notifyListeners();
  }

  void toggleMute() {
    muted = !muted;
    _saveStore.write('muted', muted ? '1' : '0');
    notifyListeners();
  }

  void setMuted(bool value) {
    if (muted == value) return;
    muted = value;
    _saveStore.write('muted', muted ? '1' : '0');
    notifyListeners();
  }

  // ------------------------------------------------------- run progression

  /// Spends one shield after a crash. Returns true when the run is over.
  bool registerHit() {
    if (phase != AppPhase.playing || shields <= 0) return false;
    shields -= 1;
    if (shields <= 0) {
      endRun();
      return true;
    }
    notifyListeners();
    return false;
  }

  /// Restores one shield (boost-ring pickup). Returns true when restored.
  bool restoreShield() {
    if (!isGameplay || shields >= maxShields) return false;
    shields += 1;
    notifyListeners();
    return true;
  }

  /// Ends the run: banks the score and shows the game-over card.
  void endRun() {
    if (phase == AppPhase.gameOver) return;
    _bankRun(completed: false);
    phase = AppPhase.gameOver;
    paused = false;
    photoMode = false;
    onboardingVisible = false;
    callout = null;
    streetPill = null;
    notifyListeners();
  }

  /// Pauses an active run (also used when the app goes to the background).
  void pause() {
    if (!isGameplay || paused || photoMode) return;
    paused = true;
    notifyListeners();
  }

  void resume() {
    if (!paused) return;
    paused = false;
    notifyListeners();
  }

  void togglePause() {
    if (paused) {
      resume();
    } else {
      pause();
    }
  }

  /// Abandons the run and returns to the title / map screen.
  void returnToTitle() {
    paused = false;
    photoMode = false;
    callout = null;
    streetPill = null;
    onboardingVisible = false;
    phase = AppPhase.mapsTitle;
    notifyListeners();
  }

  void _bankRun({required bool completed}) {
    if (_runBanked) return;
    _runBanked = true;
    runsPlayed += 1;
    if (completed) runsCompleted += 1;
    final isRecord = score > bestScore;
    if (isRecord) bestScore = score;
    if (combo > bestCombo) bestCombo = combo;
    newBest = isRecord;
    _persistProgress();
  }

  void _restoreProgress() {
    bestScore = _readInt('best_score');
    bestCombo = _readInt('best_combo', fallback: 1).clamp(1, 12);
    runsPlayed = _readInt('runs_played');
    runsCompleted = _readInt('runs_completed');
    muted = _saveStore.read('muted') == '1';
  }

  int _readInt(String key, {int fallback = 0}) {
    final raw = _saveStore.read(key);
    if (raw == null) return fallback;
    return int.tryParse(raw.trim()) ?? fallback;
  }

  void _persistProgress() {
    _saveStore
      ..write('best_score', '$bestScore')
      ..write('best_combo', '$bestCombo')
      ..write('runs_played', '$runsPlayed')
      ..write('runs_completed', '$runsCompleted')
      ..write('muted', muted ? '1' : '0');
  }

  void togglePhotoMode() {
    if (!isGameplay) return;
    photoMode = !photoMode;
    notifyListeners();
  }

  void setPhotoPreset(PhotoPreset p) {
    photoPreset = p;
    notifyListeners();
  }

  void dismissOnboarding() {
    if (!onboardingVisible) return;
    onboardingVisible = false;
    notifyListeners();
  }

  void showCallout(
    String label, {
    String bonus = '',
    CalloutAccent accent = CalloutAccent.neon,
    double duration = 1.85,
  }) {
    callout = ActionCallout(
      id: _nextCalloutId++,
      label: label,
      bonus: bonus,
      accent: accent,
      createdAt: elapsed,
      duration: duration,
    );
    notifyListeners();
  }

  /// Adds points (multiplied by the current combo) and optionally bumps it.
  int award(int basePoints, {bool bumpCombo = false}) {
    if (bumpCombo) combo = (combo + 1).clamp(1, 12);
    final gained = basePoints * combo;
    score += gained;
    return gained;
  }

  void resetCombo() {
    combo = 1;
  }

  static String formatInt(int v) {
    final s = v.abs().toString();
    final buf = StringBuffer(v < 0 ? '-' : '');
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  /// `mm:ss.t` run timer used by the finale banner.
  static String formatRunTime(double sec) {
    final m = sec ~/ 60;
    final s = sec - m * 60;
    return '${m.toString().padLeft(2, '0')}:${s.toStringAsFixed(1).padLeft(4, '0')}';
  }

  void showStreetPill(StreetSegment seg) {
    if (phase != AppPhase.playing || photoMode) return;
    final en = seg.shortEn
        .replaceAll(RegExp(r'^SCRAMBLE CROSSING$', caseSensitive: false), 'SCRAMBLE')
        .replaceAll(RegExp(r'^TAMAGAWA-DORI R246$', caseSensitive: false), 'TAMAGAWA-DORI')
        .replaceAll(RegExp(r'^MEIJI-DORI AVE$', caseSensitive: false), 'MEIJI-DORI')
        .toUpperCase();
    streetPill = StreetPill(_nextCalloutId++, seg.ja, en, seg.shield,
        seg.isRail || seg.shield == 'LOOP', elapsed);
  }

  /// Per-frame update from the controller; one notify per frame.
  void tick(double dt) {
    elapsed += dt;
    if (phase == AppPhase.playing) {
      runTimeSec += dt;
      _playTime += dt;
      if (onboardingVisible && _playTime >= 4) onboardingVisible = false;
    }
    final sp = streetPill;
    if (sp != null && (elapsed - sp.createdAt >= 1.8 || photoMode)) streetPill = null;
    if (speedKmh > maxSpeedKmh) maxSpeedKmh = speedKmh;
    final c = callout;
    if (c != null && elapsed - c.createdAt > c.duration) callout = null;
    notifyListeners();
  }
}
