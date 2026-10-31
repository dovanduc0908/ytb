import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ytb/feed_repository.dart';
import 'package:ytb/recommendations.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const source = MethodChannel('ytb/source'),
      player = MethodChannel('ytb/player');
  testWidgets(
    'Real regional charts, cursor pagination, personalized feed and seek latency',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AndroidView(viewType: 'ytb/video')),
        ),
      );
      await tester.runAsync(() async {
        final report = <String, dynamic>{'charts': [], 'feed': [], 'seeks': []};
        void save() {
          File('/data/user/0/com.duchaik.ytb/cache/discovery-qa.json')
              .writeAsStringSync(jsonEncode(report));
          debugPrint('DUCHAIK_QA:${jsonEncode(report)}', wrapWidth: 100000);
        }

        await Future.wait(
          ['VN', 'GLOBAL'].map((region) async {
            final timer = Stopwatch()..start();
            final data = Map.from(
              await source.invokeMethod('charts', {'region': region}),
            );
            expect((data['videos'] as List).length, greaterThan(20));
            expect(data['chartDate'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
            (report['charts'] as List).add({
              'region': region,
              'count': (data['videos'] as List).length,
              'date': data['chartDate'],
              'ms': timer.elapsedMilliseconds,
            });
          }),
        );
        final first = Map.from(
          await source.invokeMethod('search', {
            'query': 'công nghệ',
            'popular': true,
          }),
        );
        expect(first['continuation'], isNotNull);
        final next = Map.from(
          await source.invokeMethod('search', {
            'query': 'công nghệ',
            'popular': true,
            'continuation': first['continuation'],
          }),
        );
        final ids = (first['videos'] as List).map((v) => v['id']).toSet();
        expect(
          (next['videos'] as List).where((v) => !ids.contains(v['id'])).length,
          greaterThan(5),
        );
        report['searchPagination'] = true;
        final profile = RecommendationProfile()
          ..boost({
            'id': 'aqz-KE-bpKQ',
            'title': 'Blender animation',
            'author': 'Blender Studio',
          }, 3);
        final feed = FeedRepository(profile, 'forYou');
        final feedIds = <String>{};
        for (var i = 0; i < 3; i++) {
          final timer = Stopwatch()..start();
          final page = await feed.next();
          expect(page.error, isNull);
          expect(page.videos.length, 24);
          for (final v in page.videos) {
            expect(feedIds.add(v['id']), true);
          }
          (report['feed'] as List).add({
            'page': i + 1,
            'ms': timer.elapsedMilliseconds,
            'count': page.videos.length,
          });
        }
        save();
        final startup = Stopwatch()..start();
        final media = Map.from(
          await source.invokeMethod('resolve', {'id': 'aqz-KE-bpKQ'}),
        );
        expect(media['engine'], 'direct-player');
        expect(
          (media['tracks'] as List).first['cacheKey'],
          startsWith('yt:aqz-KE-bpKQ:'),
        );
        await player.invokeMethod('load', {
          'id': media['id'],
          'title': media['title'],
          'author': media['author'],
          'tracks': media['tracks'],
          'position': 0,
        });
        Future<Map> state() async =>
            Map.from(await player.invokeMethod('state'));
        Future<Map> until(bool Function(Map) done) async {
          final timer = Stopwatch()..start();
          while (timer.elapsedMilliseconds < 25000) {
            final s = await state();
            expect(s['error'], isNull);
            if (done(s)) return s;
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          fail('Playback timeout');
        }

        await until(
          (s) => s['playing'] == true && (s['firstFrameMs'] as num) >= 0,
        );
        report['startupWithExistingMediaCacheMs'] = startup.elapsedMilliseconds;
        await Future<void>.delayed(const Duration(seconds: 3));
        for (final position in [10000, 180000, 10000, 180000]) {
          final before = await state();
          final timer = Stopwatch()..start();
          await player.invokeMethod('seek', {'position': position});
          final ready = await until(
            (s) =>
                s['playing'] == true &&
                (s['position'] as num) >= position - 1000 &&
                (s['position'] as num) < position + 5000 &&
                (s['frameSerial'] as num) > (before['frameSerial'] as num),
          );
          (report['seeks'] as List).add({
            'position': position,
            'ms': timer.elapsedMilliseconds,
            'audio': ready['audio'],
          });
          await Future<void>.delayed(const Duration(seconds: 2));
          expect((await state())['error'], isNull);
        }
        await player.invokeMethod('quality', {'height': 2160});
        await until((s) => s['playing'] == true && s['height'] == 2160);
        await Future<void>.delayed(const Duration(seconds: 5));
        expect((await state())['error'], isNull);
        report['direct4K'] = true;
        await source.invokeMethod('prefetch', {
          'ids': ['WhWc3b3KhnY'],
        });
        await Future<void>.delayed(const Duration(seconds: 3));
        final preparedTimer = Stopwatch()..start();
        final prepared = Map.from(
          await source.invokeMethod('resolve', {'id': 'WhWc3b3KhnY'}),
        );
        await player.invokeMethod('load', {
          'id': prepared['id'],
          'title': prepared['title'],
          'author': prepared['author'],
          'tracks': prepared['tracks'],
          'position': 0,
        });
        await until(
          (s) =>
              s['id'] == 'WhWc3b3KhnY' &&
              s['playing'] == true &&
              (s['firstFrameMs'] as num) >= 0,
        );
        report['preparedStartupMs'] = preparedTimer.elapsedMilliseconds;
        await player.invokeMethod('pause');
        save();
      });
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
