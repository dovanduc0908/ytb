import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ytb/related_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const source = MethodChannel('ytb/source'),
      player = MethodChannel('ytb/player');
  testWidgets(
    'Related/Shorts live sources and background service queue/timer',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AndroidView(viewType: 'ytb/video')),
        ),
      );
      await tester.runAsync(() async {
        final report = <String, dynamic>{};
        Future<Map> state() async =>
            Map.from(await player.invokeMethod('state'));
        Future<Map> until(bool Function(Map) done) async {
          final timer = Stopwatch()..start();
          while (timer.elapsedMilliseconds < 40000) {
            final s = await state();
            expect(s['error'], isNull);
            if (done(s)) return s;
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          fail('Timeout');
        }

        final watch = Stopwatch()..start();
        final related = Map.from(
          await source.invokeMethod('related', {'id': 'aqz-KE-bpKQ'}),
        );
        expect((related['videos'] as List).length, greaterThan(6));
        expect(related['continuation'], isNotNull);
        final second = Map.from(
          await source.invokeMethod('related', {
            'id': 'aqz-KE-bpKQ',
            'continuation': related['continuation'],
          }),
        );
        final ids = (related['videos'] as List).map((v) => v['id']).toSet();
        expect(
          (second['videos'] as List)
              .where((v) => !ids.contains(v['id']))
              .length,
          greaterThan(5),
        );
        report['related'] = {
          'first': (related['videos'] as List).length,
          'second': (second['videos'] as List).length,
          'twoPagesMs': watch.elapsedMilliseconds,
        };
        final repo = RelatedRepository({
          'id': 'aqz-KE-bpKQ',
          'title': 'karaoke Việt Nam',
        }, query: 'karaoke Việt Nam');
        final all = <String>{};
        for (var page = 0; page < 30 && all.length < 400; page++) {
          final result = await repo.next();
          expect(result.error, isNull);
          for (final video in result.videos) {
            expect(all.add(video['id']), true);
          }
          if (!result.hasMore) break;
        }
        expect(all.length, greaterThanOrEqualTo(400));
        report['karaokeUnique'] = all.length;
        final short = Map.from(
          await source.invokeMethod('shorts', {'query': 'Việt Nam'}),
        );
        expect((short['videos'] as List).length, greaterThan(2));
        expect(
          (short['videos'] as List).every((v) => v['isShort'] == true),
          true,
        );
        report['verifiedShorts'] = (short['videos'] as List).length;
        Future<Map> load(String id) async {
          final media = Map.from(
            await source.invokeMethod('resolve', {'id': id}),
          );
          await player.invokeMethod('load', {
            'id': id,
            'title': media['title'],
            'author': media['author'],
            'tracks': media['tracks'],
            'position': 0,
          });
          return until(
            (s) =>
                s['id'] == id &&
                s['playing'] == true &&
                (s['firstFrameMs'] as num) >= 0,
          );
        }

        await source.invokeMethod('prefetch', {
          'ids': ['WhWc3b3KhnY'],
        });
        final first = await load('aqz-KE-bpKQ');
        await player.invokeMethod('queue', {
          'items': [
            {
              'id': 'WhWc3b3KhnY',
              'title': 'Spring',
              'author': 'Blender Studio',
            },
          ],
          'repeat': 0,
        });
        final nextTimer = Stopwatch()..start();
        await player.invokeMethod('seek', {
          'position': (first['duration'] as num).toInt() - 350,
        });
        final next = await until(
          (s) =>
              s['id'] == 'WhWc3b3KhnY' &&
              s['playing'] == true &&
              (s['firstFrameMs'] as num) >= 0,
        );
        expect(
          (Map.from(await player.invokeMethod('queue'))['items'] as List),
          isEmpty,
        );
        report['autoNext'] = {
          'elapsedWithEndSeekMs': nextTimer.elapsedMilliseconds,
          'firstFrameMs': next['firstFrameMs'],
        };
        final start = await load('aqz-KE-bpKQ');
        await player.invokeMethod('queue', {
          'items': [
            {'id': 'WhWc3b3KhnY', 'title': 'Spring'},
          ],
          'repeat': 0,
        });
        await player.invokeMethod('timer', {'milliseconds': 300});
        await until((s) => s['timerExpired'] == true);
        await player.invokeMethod('seek', {
          'position': (start['duration'] as num).toInt(),
        });
        await Future<void>.delayed(const Duration(seconds: 2));
        final sleeping = await state();
        expect(sleeping['id'], 'aqz-KE-bpKQ');
        expect(sleeping['playing'], false);
        expect(
          (Map.from(await player.invokeMethod('queue'))['items'] as List)
              .length,
          1,
        );
        report['sleepPreventsAutoNext'] = true;
        await player.invokeMethod('queue', {'items': [], 'repeat': 0});
        await player.invokeMethod('timer', {'milliseconds': 0});
        await player.invokeMethod('pause');
        File('/data/user/0/com.duchaik.ytb/cache/features-06.json')
            .writeAsStringSync(jsonEncode(report));
        debugPrint('DUCHAIK_06:${jsonEncode(report)}', wrapWidth: 100000);
      });
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
