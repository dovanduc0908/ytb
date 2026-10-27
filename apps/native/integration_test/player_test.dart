import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const channel = MethodChannel('ytb/player');
Future<Map<String, dynamic>> state() async =>
    Map<String, dynamic>.from(await channel.invokeMethod('state'));
Future<Map<String, dynamic>> until(
  bool Function(Map<String, dynamic>) condition, [
  int seconds = 30,
]) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    final s = await state();
    if (s['error'] != null) throw StateError(s['error'].toString());
    if (condition(s)) return s;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  throw StateError('Playback condition timed out: ${await state()}');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Real Samsung playback: 17 speeds, supported qualities, sleep timer',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AndroidView(viewType: 'ytb/video')),
        ),
      );
      final report = <String, dynamic>{
        'speeds': <dynamic>[],
        'qualities': <dynamic>[],
      };
      void save() {
        File('/data/user/0/com.duchaik.ytb/cache/player-qa.json')
            .writeAsStringSync(jsonEncode(report));
        debugPrint('YTB_QA_PROGRESS:${jsonEncode(report)}', wrapWidth: 100000);
      }

      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(seconds: 2));
        const provider = MethodChannel('ytb/source');
        final search = Map<String, dynamic>.from(
          await provider.invokeMethod('search', {
            'query': 'Blender open movie',
          }),
        );
        expect((search['videos'] as List).isNotEmpty, true);
        final source = Map<String, dynamic>.from(
          await provider.invokeMethod('resolveFull', {'id': 'aqz-KE-bpKQ'}),
        );
        expect(source['onDevice'], true);
        report['onDevice'] = true;
        report['searchResults'] = (search['videos'] as List).length;
        await channel.invokeMethod('load', {
          'id': source['id'],
          'tracks': source['tracks'],
          'title': source['title'],
          'author': source['author'],
          'position': 0,
        });
        await until((s) => s['playing'] == true);
        await channel.invokeMethod('quality', {'height': 480});
        await until((s) => s['playing'] == true && s['height'] == 480);
        for (var i = 0; i < 17; i++) {
          final rate = 1 + i * .25;
          await channel.invokeMethod('pause');
          await channel.invokeMethod('speed', {'value': rate});
          // Direct CDN throughput can vary. Measure rate only with enough media buffered.
          await until(
            (s) => (s['buffered'] as num) - (s['position'] as num) >= 30000,
            75,
          );
          await channel.invokeMethod('play');
          await until((s) => s['playing'] == true);
          await Future<void>.delayed(const Duration(seconds: 1));
          final start = await state();
          final watch = Stopwatch()..start();
          await Future<void>.delayed(const Duration(seconds: 4));
          final end = await state();
          watch.stop();
          final measured =
              ((end['position'] as num) - (start['position'] as num)) /
              watch.elapsedMilliseconds;
          final passed =
              end['playing'] == true && (measured - rate).abs() < rate * .12;
          (report['speeds'] as List).add({
            'requested': rate,
            'observed': measured,
            'passed': passed,
            'audio': end['audio'],
          });
          save();
          expect(passed, true, reason: 'rate $rate observed $measured');
        }
        await channel.invokeMethod('speed', {'value': 1.0});
        await channel.invokeMethod('seek', {'position': 10000});
        final supported = List<int>.from((await state())['qualities']);
        report['supportedQualities'] = supported;
        save();
        for (final height in supported) {
          await channel.invokeMethod('quality', {'height': height});
          final end = await until(
            (s) => s['playing'] == true && s['height'] == height,
            40,
          );
          final start = end['position'] as num;
          await Future<void>.delayed(const Duration(seconds: 3));
          final after = await state();
          final passed =
              after['playing'] == true &&
              (after['position'] as num) > start + 2000;
          (report['qualities'] as List).add({
            'requested': height,
            'actual': after['height'],
            'passed': passed,
          });
          save();
          expect(passed, true, reason: 'quality $height');
        }
        await channel.invokeMethod('quality', {'height': 480});
        await until((s) => s['playing'] == true && s['height'] == 480);
        await channel.invokeMethod('timer', {'milliseconds': 3000});
        await Future<void>.delayed(const Duration(seconds: 4));
        final end = await state();
        report['timer'] = {
          'passed': end['playing'] == false && end['timerExpired'] == true,
          'state': end,
        };
        save();
        expect(end['playing'], false);
        expect(end['timerExpired'], true);
        final other = Map<String, dynamic>.from(
          await provider.invokeMethod('resolveFull', {'id': 'WhWc3b3KhnY'}),
        );
        expect(other['onDevice'], true);
        await channel.invokeMethod('load', {
          'id': other['id'],
          'title': other['title'],
          'author': other['author'],
          'tracks': other['tracks'],
          'position': 30000,
        });
        final otherStart = await until((s) => s['playing'] == true, 40);
        await Future<void>.delayed(const Duration(seconds: 4));
        final otherEnd = await state();
        expect(
          (otherEnd['position'] as num) >
              (otherStart['position'] as num) + 2500,
          true,
        );
        expect(otherEnd['audio'], isNotNull);
        report['secondVideo'] = {
          'id': other['id'],
          'playing': otherEnd['playing'],
          'audio': otherEnd['audio'],
          'height': otherEnd['height'],
        };
        await channel.invokeMethod('pause');
        save();
        binding.reportData = report;
        debugPrint('YTB_QA_JSON:${jsonEncode(report)}', wrapWidth: 100000);
      });
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
