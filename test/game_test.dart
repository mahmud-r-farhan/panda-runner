import 'package:flutter_test/flutter_test.dart';
import 'package:neon_scramble/game/game_state.dart';
import 'package:neon_scramble/game/map_location.dart';

void main() {
  group('MapLocation Tests', () {
    test('All presets are properly defined', () {
      expect(MapLocation.all.length, 3);
      final shibuya = MapLocation.byId(MapLocationId.shibuya);
      final bamboo = MapLocation.byId(MapLocationId.bambooForest);
      final cyber = MapLocation.byId(MapLocationId.cyberCircuit);

      expect(shibuya.name, contains('Shibuya'));
      expect(bamboo.name, contains('Bamboo'));
      expect(cyber.name, contains('Cyberway'));

      // Check Vector3 sky getters
      expect(shibuya.skyZenith.y, greaterThan(0));
      expect(bamboo.skyHorizon.z, greaterThan(0));
      expect(cyber.skyGround.x, greaterThan(0));
    });
  });

  group('GameState Character & Map Selection Tests', () {
    late GameState state;

    setUp(() {
      state = GameState();
    });

    test('Defaults to 3D Panda Runner and Shibuya location', () {
      expect(state.selectedHero, HeroCharacterType.panda);
      expect(state.location.id, MapLocationId.shibuya);
      expect(state.score, 0);
      expect(state.combo, 1);
    });

    test('Can toggle hero character', () {
      bool notified = false;
      state.addListener(() => notified = true);

      state.selectHero(HeroCharacterType.pegman);
      expect(state.selectedHero, HeroCharacterType.pegman);
      expect(notified, isTrue);

      notified = false;
      state.selectHero(HeroCharacterType.panda);
      expect(state.selectedHero, HeroCharacterType.panda);
      expect(notified, isTrue);
    });

    test('Can switch map location', () {
      bool notified = false;
      state.addListener(() => notified = true);

      state.selectLocation(MapLocation.bambooForest);
      expect(state.location.id, MapLocationId.bambooForest);
      expect(notified, isTrue);

      state.selectLocation(MapLocation.cyberCircuit);
      expect(state.location.id, MapLocationId.cyberCircuit);
    });

    test('Award calculation and combo multipliers', () {
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
}
