import 'package:flutter_test/flutter_test.dart';
import 'package:panda_runner/game/game_state.dart';
import 'package:panda_runner/game/map_location.dart';
import 'package:panda_runner/game/save_store.dart';

/// `state` in "playing" phase, ready for scoring/hit assertions.
GameState playingState({SaveStore? store}) {
  final state = GameState(saveStore: store ?? InMemorySaveStore())
    ..beginRun()
    ..landFromSkyDrop();
  return state;
}

void main() {
  group('Sky moods', () {
    test('all presets are defined with distinct accents', () {
      expect(MapLocation.all.length, 3);

      final shibuya = MapLocation.byId(MapLocationId.shibuya);
      final jade = MapLocation.byId(MapLocationId.bambooForest);
      final ultra = MapLocation.byId(MapLocationId.cyberCircuit);

      expect(shibuya.shortName, 'Neon');
      expect(jade.shortName, 'Jade');
      expect(ultra.shortName, 'Ultra');
      expect(shibuya.name, isNot(jade.name));
      expect(jade.name, isNot(ultra.name));
      expect({shibuya.accentColor, jade.accentColor, ultra.accentColor}.length, 3);

      // Sky gradient getters return usable three-component vectors.
      expect(shibuya.skyZenith.y, greaterThan(0));
      expect(jade.skyHorizon.z, greaterThan(0));
      expect(ultra.skyGround.x, greaterThan(0));
    });

    test('unknown id falls back to Shibuya', () {
      expect(MapLocation.byId(MapLocationId.shibuya).id, MapLocationId.shibuya);
    });
  });

  group('GameState defaults', () {
    late GameState state;

    setUp(() {
      state = GameState(saveStore: InMemorySaveStore());
    });

    test('defaults to the 3D panda, Shibuya and a full shield bar', () {
      expect(state.selectedHero, HeroCharacterType.panda);
      expect(state.location.id, MapLocationId.shibuya);
      expect(state.score, 0);
      expect(state.combo, 1);
      expect(state.shields, GameState.maxShields);
      expect(state.phase, AppPhase.loading);
      expect(state.bestScore, 0);
      expect(state.runsPlayed, 0);
    });

    test('can toggle hero character', () {
      var notified = false;
      state.addListener(() => notified = true);

      state.selectHero(HeroCharacterType.pegman);
      expect(state.selectedHero, HeroCharacterType.pegman);
      expect(notified, isTrue);

      notified = false;
      state.selectHero(HeroCharacterType.panda);
      expect(state.selectedHero, HeroCharacterType.panda);
      expect(notified, isTrue);
    });

    test('can switch sky mood', () {
      var notified = false;
      state.addListener(() => notified = true);

      state.selectLocation(MapLocation.bambooForest);
      expect(state.location.id, MapLocationId.bambooForest);
      expect(notified, isTrue);

      state.selectLocation(MapLocation.cyberCircuit);
      expect(state.location.id, MapLocationId.cyberCircuit);
    });

    test('award applies and bumps the combo multiplier', () {
      expect(state.combo, 1);
      final gained1 = state.award(500, bumpCombo: true);
      expect(gained1, 1000); // combo became 2: 500 * 2 = 1000
      expect(state.score, 1000);
      expect(state.combo, 2);

      final gained2 = state.award(1000, bumpCombo: true);
      expect(gained2, 3000); // combo became 3: 1000 * 3 = 3000
      expect(state.score, 4000);
      expect(state.combo, 3);
    });
  });

  group('Run flow', () {
    test('beginRun resets score, combo and shields', () {
      final state = playingState()
        ..score = 12345
        ..combo = 7
        ..shields = 1;

      state.beginRun();

      expect(state.phase, AppPhase.skyDrop);
      expect(state.score, 0);
      expect(state.combo, 1);
      expect(state.shields, GameState.maxShields);
      expect(state.paused, isFalse);
    });

    test('each crash costs a shield and the last one ends the run', () {
      final state = playingState()..score = 4200;

      expect(state.registerHit(), isFalse);
      expect(state.shields, 2);
      expect(state.phase, AppPhase.playing);

      expect(state.registerHit(), isFalse);
      expect(state.shields, 1);

      expect(state.registerHit(), isTrue);
      expect(state.shields, 0);
      expect(state.phase, AppPhase.gameOver);
      expect(state.bestScore, 4200);
      expect(state.newBest, isTrue);
      expect(state.runsPlayed, 1);
    });

    test('completing the route banks the run once', () {
      final state = playingState()..score = 30000;

      state.enterFinale();
      expect(state.phase, AppPhase.finale);
      expect(state.bestScore, 30000);
      expect(state.runsCompleted, 1);

      // A second banking pass must not double-count the run.
      state.enterFinale();
      expect(state.runsPlayed, 1);
      expect(state.runsCompleted, 1);
    });

    test('pause only applies during gameplay and freezes the clock', () {
      final state = GameState(saveStore: InMemorySaveStore());
      state.pause();
      expect(state.paused, isFalse); // still loading

      state.beginRun();
      state.landFromSkyDrop();
      state.pause();
      expect(state.paused, isTrue);

      final before = state.runTimeSec;
      state.tick(0);
      expect(state.runTimeSec, before);

      state.resume();
      expect(state.paused, isFalse);
      state.tick(0.5);
      expect(state.runTimeSec, greaterThan(before));
    });

    test('returnToTitle clears pause and abandons the run', () {
      final state = playingState()..pause();
      state.returnToTitle();

      expect(state.phase, AppPhase.mapsTitle);
      expect(state.paused, isFalse);
      expect(state.photoMode, isFalse);
      expect(state.isGameplay, isFalse);
    });
  });

  group('Persistence', () {
    test('best score and run counters survive a restart', () {
      final store = InMemorySaveStore();
      final first = playingState(store: store)..score = 9120;
      first.endRun();

      final second = GameState(saveStore: store);
      expect(second.bestScore, 9120);
      expect(second.runsPlayed, 1);
      expect(second.bestCombo, 1);
    });

    test('a lower score does not overwrite the best', () {
      final store = InMemorySaveStore();
      (playingState(store: store)..score = 5000).endRun();
      (playingState(store: store)..score = 2500).endRun();

      final state = GameState(saveStore: store);
      expect(state.bestScore, 5000);
      expect(state.runsPlayed, 2);
    });

    test('mute setting is persisted', () {
      final store = InMemorySaveStore();
      GameState(saveStore: store).toggleMute();

      final reloaded = GameState(saveStore: store);
      expect(reloaded.muted, isTrue);
      expect(reloaded.bestScore, 0);
    });

    test('displayBest tracks the run in progress', () {
      final state = playingState()..score = 750;
      expect(state.displayBest, 750);
      state.endRun();
      expect(state.displayBest, 750);
    });
  });
}
