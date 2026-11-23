// Throwaway visual harness for the 2D overlays (no 3D scene).
// Build: flutter build web -t lib/ui_preview_main.dart -o build/preview
// Views: ?view=loading|title|hud|finale|photo|callout|skydrop|pause|gameover
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'game/game_state.dart';
import 'game/level_data.dart';
import 'game/save_store.dart';
import 'ui/game_over_card.dart';
import 'ui/hud_overlay.dart';
import 'ui/loading_screen.dart';
import 'ui/maps_title_card.dart';
import 'ui/pause_overlay.dart';
import 'ui/shibuya_map_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final level = await ShibuyaLevel.load();
  final view = Uri.base.queryParameters['view'] ?? 'title';
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: _Preview(level: level, view: view),
  ));
}

class _Preview extends StatefulWidget {
  const _Preview({required this.level, required this.view});
  final ShibuyaLevel level;
  final String view;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> with SingleTickerProviderStateMixin {
  final GameState s = GameState(saveStore: InMemorySaveStore());
  late final Ticker _ticker;
  double _t = 0;

  @override
  void initState() {
    super.initState();
    final wp = widget.level.waypoints;
    void at(double routeS) {
      var i = 0;
      while (i < wp.length - 2 && wp[i + 1].s <= routeS) {
        i++;
      }
      s.routeS = routeS;
      s.heroX = wp[i].x;
      s.heroZ = wp[i].z;
      s.heroHeading = math.atan2(wp[i].tx, wp[i].tz);
    }

    switch (widget.view) {
      case 'loading':
        s.setLoading(.52, 'Loading Shibuya skyline...');
      case 'title':
        s.finishLoading();
      case 'skydrop':
        s.finishLoading();
        s.beginRun();
        at(0);
      case 'hud':
      case 'callout':
        s.finishLoading();
        s.beginRun();
        s.landFromSkyDrop();
        at(140);
        s.score = 12840;
        s.speedKmh = 118;
        s.combo = 3;
        s.street = const StreetSegment(
            sStart: 68, sEnd: 228, ja: '神宮通り', miniEn: 'Jingu-dori');
        if (widget.view == 'callout') {
          s.onboardingVisible = false;
          s.move = ParkourMove.railGrind;
          s.combo = 5;
          s.speedKmh = 152;
          s.showCallout('BOOST RING', bonus: '+1,500', accent: CalloutAccent.gold);
        }
      case 'pause':
        s.finishLoading();
        s.beginRun();
        s.landFromSkyDrop();
        at(420);
        s.score = 20450;
        s.speedKmh = 96;
        s.combo = 4;
        s.shields = 2;
        s.pause();
      case 'gameover':
        s.finishLoading();
        s.beginRun();
        s.landFromSkyDrop();
        at(680);
        s.score = 31520;
        s.speedKmh = 0;
        s.maxSpeedKmh = 151;
        s.runTimeSec = 18.4;
        s.combo = 6;
        s.shields = 0;
        s.endRun();
      case 'finale':
      case 'photo':
        s.finishLoading();
        s.beginRun();
        s.landFromSkyDrop();
        at(1040);
        s.score = 48210;
        s.speedKmh = 0;
        s.maxSpeedKmh = 158;
        s.runTimeSec = 41.3;
        s.combo = 7;
        s.enterFinale();
        for (int i = 0; i < 4; i++) {
          s.googleLettersLit[i] = true;
        }
        if (widget.view == 'photo') {
          s.photoMode = true;
          s.photoPreset = PhotoPreset.scramble;
        }
    }
    _ticker = createTicker((e) {
      final t = e.inMicroseconds / 1e6;
      s.tick((t - _t).clamp(0.0, 0.05));
      setState(() => _t = t);
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.view;
    return Scaffold(
      backgroundColor: const Color(0xFF0A1226),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (v == 'title') ShibuyaMapView(level: widget.level, time: _t),
          if (v != 'title' && v != 'loading')
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0B1630), Color(0xFF1A2B4F), Color(0xFF0B1226)],
                ),
              ),
            ),
          if (v == 'loading') LoadingScreen(state: s),
          if (v == 'title')
            MapsTitleCard(
              state: s,
              onPlay: () {},
              onSelectLocation: (loc) => setState(() => s.selectLocation(loc)),
              onSelectHero: (hero) => setState(() => s.selectHero(hero)),
            ),
          HudOverlay(
            state: s,
            level: widget.level,
            onToggleAutoPilot: () => setState(s.toggleAutoPilot),
            onToggleMute: () => setState(s.toggleMute),
            onTogglePhoto: () => setState(s.togglePhotoMode),
            onTogglePause: () => setState(s.togglePause),
            onPlayAgain: () {},
            onPhotoPreset: (p) => setState(() => s.setPhotoPreset(p)),
          ),
          if (v == 'pause')
            PauseOverlay(
              state: s,
              onResume: () {},
              onRestart: () {},
              onQuit: () {},
              onToggleMute: () {},
            ),
          if (v == 'gameover')
            GameOverCard(state: s, onRestart: () {}, onQuit: () {}),
        ],
      ),
    );
  }
}
