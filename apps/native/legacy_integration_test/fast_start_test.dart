import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const source = MethodChannel('ytb/source'),
      player = MethodChannel('ytb/player');
  testWidgets('Direct startup: cold, prepared and replay; search latency', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AndroidView(viewType: 'ytb/video')),
      ),
    );
    final report = <String, dynamic>{'search': [], 'playback': []};
    await tester.runAsync(() async {
      Future<Map<String, dynamic>> state() async =>
          Map<String, dynamic>.from(await player.invokeMethod('state'));
      void save() {
        File('/data/user/0/com.duchaik.ytb/cache/fast-qa.json')
            .writeAsStringSync(jsonEncode(report));
        debugPrint('YTB_FAST_QA:${jsonEncode(report)}', wrapWidth: 100000);
      }

      for (final query in ['nhạc lofi', 'công nghệ', 'nature documentary 4k']) {
        final timer = Stopwatch()..start();
        final data = Map.from(
          await source.invokeMethod('search', {'query': query}),
        );
        (report['search'] as List).add({
          'kind': 'fresh',
          'ms': timer.elapsedMilliseconds,
          'count': (data['videos'] as List).length,
        });
        expect((data['videos'] as List).length, greaterThan(5));
      }
      await source.invokeMethod('previewSearch', {
        'query': 'Blender open movie',
      });
      await Future<void>.delayed(const Duration(seconds: 2));
      var timer = Stopwatch()..start();
      final cached = Map.from(
        await source.invokeMethod('search', {'query': 'Blender open movie'}),
      );
      (report['search'] as List).add({
        'kind': 'prepared',
        'ms': timer.elapsedMilliseconds,
        'cacheHit': cached['cacheHit'],
      });
      save();
      for (final sample in [
        ['aqz-KE-bpKQ', 'cold'],
        ['jNQXAC9IVRw', 'cold'],
        ['WhWc3b3KhnY', 'prepared'],
        ['WhWc3b3KhnY', 'replay'],
      ]) {
        if (sample[1] == 'prepared') {
          await source.invokeMethod('prefetch', {
            'ids': [sample[0]],
          });
          await Future<void>.delayed(const Duration(seconds: 3));
        }
        await player.invokeMethod('pause');
        timer = Stopwatch()..start();
        final media = Map.from(
          await source.invokeMethod('resolve', {'id': sample[0]}),
        );
        final resolveMs = timer.elapsedMilliseconds;
        expect(media['engine'], 'direct-player');
        await player.invokeMethod('load', {
          'id': media['id'],
          'title': media['title'],
          'author': media['author'],
          'tracks': media['tracks'],
          'position': 0,
        });
        var s = await state();
        while ((s['firstFrameMs'] as num) < 0 &&
            timer.elapsedMilliseconds < 20000) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          s = await state();
          expect(s['error'], isNull);
        }
        expect(s['firstFrameMs'], greaterThanOrEqualTo(0));
        (report['playback'] as List).add({
          'id': sample[0],
          'kind': sample[1],
          'resolveMs': resolveMs,
          'tapToFrameMs': timer.elapsedMilliseconds,
          'loadToFrameMs': s['firstFrameMs'],
          'height': s['height'],
          'audio': s['audio'],
        });
        await Future<void>.delayed(const Duration(seconds: 2));
        s = await state();
        expect(s['playing'], true);
        expect(s['position'], greaterThan(1000));
        expect(s['audio'], isNotNull);
        if (sample[0] != 'jNQXAC9IVRw') {
          await player.invokeMethod('seek', {'position': 180000});
          final seekDeadline = DateTime.now().add(const Duration(seconds: 20));
          do {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            s = await state();
            expect(s['error'], isNull);
          } while ((s['playing'] != true || (s['position'] as num) < 182000) &&
              DateTime.now().isBefore(seekDeadline));
          expect(s['playing'], true);
          expect(s['position'], greaterThan(182000));
          (report['playback'] as List).last['seek180s'] = true;
          if (sample[0] == 'aqz-KE-bpKQ') {
            expect(s['qualities'], contains(2160));
            await player.invokeMethod('quality', {'height': 2160});
            final qualityDeadline = DateTime.now().add(
              const Duration(seconds: 20),
            );
            do {
              await Future<void>.delayed(const Duration(milliseconds: 250));
              s = await state();
              expect(s['error'], isNull);
            } while ((s['playing'] != true || s['height'] != 2160) &&
                DateTime.now().isBefore(qualityDeadline));
            expect(s['height'], 2160);
            expect(s['playing'], true);
            (report['playback'] as List).last['direct4K'] = true;
          }
        }
        await Future<void>.delayed(const Duration(seconds: 8));
        s = await state();
        expect(s['error'], isNull);
        expect(s['playing'], true);
        save();
      }
      await player.invokeMethod('timer', {'milliseconds': 1000});
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect((await state())['timerExpired'], true);
      await player.invokeMethod('pause');
      save();
    });
  }, timeout: const Timeout(Duration(minutes: 4)));
}
