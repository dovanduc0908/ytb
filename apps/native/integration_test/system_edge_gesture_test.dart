import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ytb/player_overlay.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const player = MethodChannel('ytb/player');
  testWidgets('system shade swipes do not adjust the fullscreen player', (
    tester,
  ) async {
    final adjustments = <String>[];
    final seeks = <int>[];
    final speeds = <double>[];
    await player.invokeMethod('fullscreen', {'enabled': true});
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerOverlay(
              video: const AndroidView(viewType: 'ytb/video'),
              visible: false,
              fullscreen: true,
              loading: false,
              state: const {
                'playing': true,
                'position': 30000,
                'duration': 180000,
              },
              onToggle: () {},
              onPlay: () {},
              onSeek: seeks.add,
              onFullscreen: () {},
              onSettings: () {},
              formatTime: (n) => '$n',
              onSpeed: speeds.add,
              onAdjust: (kind, delta) async {
                adjustments.add(kind);
                return (await player.invokeMethod<num>('adjust', {
                  'kind': kind,
                  'delta': delta,
                }))!.toDouble();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      debugPrint('SYSTEM_EDGE_READY');
      // Host swipes the actual Android status/shade edge during this window.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 30)),
      );
      await tester.pump();
      expect(adjustments, isEmpty);
      expect(seeks, isEmpty);
      expect(speeds, isEmpty);
      final bounds = tester.getRect(find.byType(PlayerOverlay));
      for (final fraction in [.2, .8]) {
        await tester.dragFrom(
          Offset(bounds.left + bounds.width * fraction, bounds.center.dy),
          const Offset(0, -100),
        );
        await tester.pump();
      }
      expect(adjustments, containsAll(['brightness', 'volume']));
      debugPrint(
        'SYSTEM_EDGE_PASS: shade unchanged; interior controls preserved',
      );
    } finally {
      await player.invokeMethod('fullscreen', {'enabled': false});
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
