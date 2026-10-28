import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ytb/recommendations.dart';
import 'package:ytb/feed_repository.dart';

void main() {
  test('Feed shows available results while a slow source continues', () async {
    final slow = Completer<Map<String, dynamic>>();
    final feed = FeedRepository(
      RecommendationProfile(),
      'vn',
      request: (method, args) {
        if (method == 'charts') {
          return Future.value({
            'videos': [
              {'id': 'fastvideo01', 'title': 'Fast'},
            ],
          });
        }
        return slow.future;
      },
    );
    final first = await feed.next();
    expect(first.videos.single['id'], 'fastvideo01');
    expect(first.hasMore, true);
    slow.complete({
      'videos': [
        {'id': 'slowvideo01', 'title': 'Slow'},
      ],
    });
    final second = await feed.next();
    expect(second.videos.any((v) => v['id'] == 'slowvideo01'), true);
  });
  const tech = {
    'id': 'tech1234567',
    'title': 'Khám phá chip máy tính',
    'author': 'Chip Lab',
  };
  test('Only videos at 95% or ended are excluded and persisted', () {
    final p = RecommendationProfile()..enabled = false;
    p.completed.add(tech['id']!); // The older 85% learning signal is separate.
    expect(p.excludes(tech['id']), false);
    expect(p.markFinished(tech, 94999, 100000), false);
    expect(p.markFinished(tech, 95000, 100000), true);
    expect(p.rank([tech]), isEmpty);
    final restored = RecommendationProfile.fromJson(p.toJson());
    expect(restored.excludes(tech['id']), true);
    final other = {...tech, 'id': 'other123456'};
    expect(restored.markFinished(other, 0, 0, ended: true), false);
    expect(
      restored.markFinished({...other, 'isLive': true}, 95000, 100000),
      false,
    );
    expect(restored.markFinished(other, 0, 100000, ended: true), true);
  });
  test('Engaged videos seed related discovery and survive reload', () async {
    final p = RecommendationProfile();
    final before = {'id': tech['id'], 'playing': true, 'position': 0};
    for (var i = 0; i < 15; i++) {
      p.observe(
        tech,
        {...before, 'position': i * 1000},
        {...before, 'position': (i + 1) * 1000, 'duration': 60000},
        1000,
      );
    }
    final restored = RecommendationProfile.fromJson(p.toJson());
    expect(restored.discoverySeeds.single['id'], tech['id']);
    final calls = <String>[];
    final feed = FeedRepository(
      restored,
      'forYou',
      request: (method, args) async {
        calls.add('$method:${args['id'] ?? ''}');
        return {
          'videos': method == 'related'
              ? [
                  tech,
                  {
                    'id': 'related1234',
                    'title': 'More chip news',
                    'author': 'Other',
                  },
                ]
              : <Video>[],
        };
      },
    );
    final page = await feed.next();
    expect(calls, contains('related:${tech['id']}'));
    expect(page.videos.map((v) => v['id']), contains('related1234'));
    expect(page.videos.map((v) => v['id']), isNot(contains(tech['id'])));
    restored.dismiss(tech);
    expect(restored.discoverySeeds, isEmpty);
    p.enabled = false;
    expect(p.discoverySeeds, isEmpty);
  });
  test(
    'Actual viewing trains interests; seeking, buffering and opt-out do not',
    () {
      final p = RecommendationProfile();
      final a = {'id': tech['id'], 'playing': true, 'position': 1000};
      final b = {
        'id': tech['id'],
        'playing': true,
        'position': 2000,
        'speed': 1,
        'duration': 60000,
      };
      expect(p.observe(tech, a, b, 1000), 1000);
      final score = p.score(tech, 1);
      expect(p.observe(tech, a, {...b, 'position': 50000}, 1000), 0);
      expect(p.observe(tech, a, {...b, 'buffering': true}, 1000), 0);
      expect(p.observe(tech, a, {...b, 'position': 500}, 1000), 0);
      expect(p.score(tech, 1), score);
      p.enabled = false;
      expect(p.observe(tech, a, b, 1000), 0);
      p.boost(tech, 10);
      expect(p.queries, isEmpty);
      expect(p.watched[tech['id']], 1000);
    },
  );
  test(
    'Preference ranking, hide, persistence and decay remain local and bounded',
    () {
      final p = RecommendationProfile()..boost(tech, 3);
      final other = {
        'id': 'other123456',
        'title': 'Món ngon miền Tây',
        'author': 'Bếp nhà',
      };
      expect(p.rank([other, tech]).first['id'], tech['id']);
      expect(p.queries, contains('Chip Lab'));
      p.dismiss(tech);
      expect(
        p.rank([other, tech]).map((v) => v['id']),
        isNot(contains(tech['id'])),
      );
      final restored = RecommendationProfile.fromJson(p.toJson());
      expect(restored.hidden, contains(tech['id']));
      final old = restored.weights.values.fold(0.0, (a, b) => a + b);
      restored.decay(DateTime.now().add(const Duration(days: 30)));
      expect(restored.weights.values.fold(0.0, (a, b) => a + b), lessThan(old));
    },
  );
  test('Daily feed pages deduplicate, mix regions, diversify and follow continuations', () async {
    var counter = 1000;
    final continuations = <String>[];
    Future<Map<String, dynamic>> source(
      String method,
      Map<String, dynamic> args,
    ) async {
      if (method == 'charts') {
        final prefix = args['region'] == 'VN' ? 'vn' : 'gl';
        return {
          'chartDate': '2026-10-25',
          'videos': List.generate(
            30,
            (i) => {
              'id': '$prefix${i.toString().padLeft(9, '0')}',
              'title': 'Chart $i',
              'author': 'Artist $prefix$i',
              'rank': i + 1,
              'region': args['region'],
            },
          ),
        };
      }
      if (args['continuation'] != null) continuations.add(args['continuation']);
      return {
        'videos': List.generate(
          10,
          (_) => {
            'id': (counter++).toString().padLeft(11, '0'),
            'title': 'New discovery',
            'author': 'Creator $counter',
          },
        ),
        'continuation': args['continuation'] == null
            ? 'next-${args['query']}'
            : null,
      };
    }

    final feed = FeedRepository(
      RecommendationProfile(),
      'forYou',
      request: source,
    );
    final all = <Video>[];
    for (var i = 0; i < 20; i++) {
      final page = await feed.next();
      expect(page.error, isNull);
      all.addAll(page.videos);
    }
    expect(all.length, greaterThan(300));
    expect(all.map((v) => v['id']).toSet().length, all.length);
    expect(all.take(24).any((v) => v['region'] == 'VN'), true);
    expect(all.take(24).any((v) => v['region'] == 'GLOBAL'), true);
    expect(
      all.take(24).where((v) => '${v['reason']}'.startsWith('Khám phá')).length,
      6,
    );
    expect(continuations, isNotEmpty);
  });
  test(
    'Network failure offers retry without pretending the source ended',
    () async {
      var online = false;
      final feed = FeedRepository(
        RecommendationProfile(),
        'vn',
        request: (method, args) async {
          if (!online) throw Exception('offline');
          return {
            'videos': [
              {'id': 'abcdefghijk', 'title': 'Recovered', 'author': 'New'},
            ],
          };
        },
      );
      final failed = await feed.next();
      expect(failed.error, isNotNull);
      expect(failed.hasMore, true);
      online = true;
      final recovered = await feed.next();
      expect(recovered.videos.single['id'], 'abcdefghijk');
    },
  );
}
