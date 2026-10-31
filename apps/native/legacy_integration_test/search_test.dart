import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const source = MethodChannel('ytb/source');
  const player = MethodChannel('ytb/player');
  testWidgets(
    'Samsung direct search, autocomplete, cache, and playback smoke',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AndroidView(viewType: 'ytb/video')),
        ),
      );
      final report = <String, dynamic>{'search': [], 'suggest': []};
      await tester.runAsync(() async {
        Future<Map<String, dynamic>> measure(
          String method,
          String query,
        ) async {
          final watch = Stopwatch()..start();
          final result = Map<String, dynamic>.from(
            await source.invokeMethod(method, {'query': query}),
          );
          final count =
              (result[method == 'search' ? 'videos' : 'suggestions'] as List)
                  .length;
          final row = {
            'query': query,
            'ms': watch.elapsedMilliseconds,
            'count': count,
            'cacheHit': result['cacheHit'],
          };
          (report[method] as List).add(row);
          debugPrint('YTB_SEARCH_SAMPLE:${jsonEncode(row)}');
          expect(count, greaterThan(0));
          if (method == 'search') {
            expect(result['engine'], 'direct');
            for (final video in result['videos']) {
              expect(
                RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(video['id']),
                true,
              );
              expect(video['title'], isNotEmpty);
            }
          }
          return result;
        }

        // First search is deliberately before any media-engine initialization.
        for (final query in [
          'Blender open movie',
          'nhạc không lời',
          'nhạc lofi',
          'công nghệ',
          'nature documentary 4k',
        ]) {
          expect((await measure('search', query))['cacheHit'], false);
        }
        expect((await measure('search', 'nhạc lofi'))['cacheHit'], true);
        for (final query in ['nhac', 'nhạc', 'lofi', 'son tung', 'công nghệ']) {
          await measure('suggest', query);
        }
        expect((await measure('suggest', 'nhac'))['cacheHit'], true);
        final media = Map<String, dynamic>.from(
          await source.invokeMethod('resolve', {'id': 'jNQXAC9IVRw'}),
        );
        await player.invokeMethod('load', {
          'id': media['id'],
          'title': media['title'],
          'author': media['author'],
          'tracks': media['tracks'],
          'position': 0,
        });
        Map<String, dynamic> state = {};
        final deadline = DateTime.now().add(const Duration(seconds: 40));
        do {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          state = Map<String, dynamic>.from(await player.invokeMethod('state'));
          expect(state['error'], isNull);
        } while ((state['playing'] != true ||
                (state['position'] as num? ?? 0) < 2000) &&
            DateTime.now().isBefore(deadline));
        expect(state['playing'], true);
        expect(state['audio'], isNotNull);
        expect(state['position'], greaterThan(2000));
        report['playback'] = {
          'position': state['position'],
          'audio': state['audio'],
          'playing': state['playing'],
        };
        await player.invokeMethod('pause');
        File('/data/user/0/com.duchaik.ytb/cache/search-qa.json')
            .writeAsStringSync(jsonEncode(report));
        debugPrint('YTB_SEARCH_QA:${jsonEncode(report)}', wrapWidth: 100000);
      });
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
