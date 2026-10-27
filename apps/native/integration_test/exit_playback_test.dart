import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const player = MethodChannel('ytb/player'),
      source = MethodChannel('ytb/source');
  testWidgets('leaving the app stops playback and rejects a late start', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AndroidView(viewType: 'ytb/video')),
      ),
    );
    await tester.runAsync(() async {
      final media = Map<String, dynamic>.from(
        await source.invokeMethod('resolve', {'id': 'aqz-KE-bpKQ'}),
      );
      await player.invokeMethod('load', {
        'id': media['id'],
        'title': media['title'],
        'author': media['author'],
        'tracks': media['tracks'],
        'metadata': Map.of(media)..remove('tracks'),
      });
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(deadline)) {
        final state = Map.from(await player.invokeMethod('state'));
        if (state['playing'] == true) break;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      expect(Map.from(await player.invokeMethod('state'))['playing'], true);
      debugPrint('EXIT_QA_READY_FOR_HOME');
      await Future<void>.delayed(const Duration(seconds: 10));
      try {
        await player.invokeMethod('play');
        fail('Playback started when app was not visible');
      } on PlatformException catch (e) {
        expect(e.code, 'NOT_FOREGROUND');
      }
      try {
        await player.invokeMethod('state');
        fail('Playback service still running after exit');
      } on PlatformException catch (e) {
        expect(e.code, 'NOT_READY');
      }
      debugPrint('EXIT_QA_STOPPED_AND_LATE_START_BLOCKED');
    });
  }, timeout: const Timeout(Duration(minutes: 2)));
}
