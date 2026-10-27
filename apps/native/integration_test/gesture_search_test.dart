import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const source = MethodChannel('ytb/source');
  const player = MethodChannel('ytb/player');
  testWidgets(
    'live search pagination, fresh uploads, and native gesture controls',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AndroidView(viewType: 'ytb/video')),
        ),
      );
      await tester.runAsync(() async {
        Future<Map> search(Map<String, dynamic> args) async =>
            Map.from(await source.invokeMethod('search', args));
        final first = await search({'query': 'công nghệ'});
        expect((first['videos'] as List).length, greaterThan(10));
        expect(first['continuation'], isNotNull);
        final second = await search({
          'query': 'công nghệ',
          'continuation': first['continuation'],
        });
        final ids = (first['videos'] as List).map((v) => v['id']).toSet();
        expect(
          (second['videos'] as List)
              .where((v) => !ids.contains(v['id']))
              .length,
          greaterThan(5),
        );
        final recent = await search({'query': 'công nghệ', 'recent': true});
        expect((recent['videos'] as List), isNotEmpty);
        final suggest = Map.from(
          await source.invokeMethod('suggest', {'query': 'nhạc'}),
        );
        expect((suggest['suggestions'] as List).length, greaterThan(8));
        for (final speed in [.25, 1.0, 3.5]) {
          await player.invokeMethod('speed', {'value': speed});
          final state = Map.from(await player.invokeMethod('state'));
          expect(state['speed'], speed);
        }
        final brightness = await player.invokeMethod<num>('adjust', {
          'kind': 'brightness',
          'delta': -.1,
        });
        final volume = await player.invokeMethod<num>('adjust', {
          'kind': 'volume',
          'delta': -.1,
        });
        expect(brightness, inInclusiveRange(.02, 1));
        expect(volume, inInclusiveRange(0, 1));
        await player.invokeMethod('adjust', {'kind': 'volume', 'delta': .1});
        await player.invokeMethod('adjust', {
          'kind': 'brightness',
          'delta': .1,
        });
        await player.invokeMethod('speed', {'value': 1.0});
        debugPrint(
          'GESTURE_SEARCH_QA:${jsonEncode({'first': (first['videos'] as List).length, 'second': (second['videos'] as List).length, 'recent': (recent['videos'] as List).map((v) => v['published']).toList(), 'suggestions': (suggest['suggestions'] as List).length, 'nativeControls': true})}',
        );
      });
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
