import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const player = MethodChannel('ytb/player'),
      source = MethodChannel('ytb/source');
  testWidgets(
    'qualified music queue starts immediately, auto advances, excludes films',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AndroidView(viewType: 'ytb/video')),
        ),
      );
      await tester.runAsync(() async {
        Future<dynamic> call(String name, [Map<String, dynamic>? args]) =>
            player
                .invokeMethod(name, args)
                .timeout(const Duration(seconds: 10));
        Future<Map> state() async => Map.from(await call('state'));
        Future<Map> until(bool Function(Map) done) async {
          for (var i = 0; i < 120; i++) {
            final s = await state();
            if (done(s)) return s;
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
          fail('Timeout waiting for playback');
        }

        expect((await state())['musicLearning'], greaterThanOrEqualTo(6));
        await call('queue', {'items': [], 'repeat': 0});
        await call('musicAuto', {'enabled': true});
        Future<void> load(String id) async {
          final media = Map<String, dynamic>.from(
            await source.invokeMethod('resolve', {'id': id}),
          );
          await call('load', {
            'id': id,
            'tracks': media['tracks'],
            'title': media['title'],
            'author': media['author'],
            'metadata': Map.of(media)..remove('tracks'),
          });
          await until((s) => s['id'] == id && s['playing'] == true);
        }

        try {
          await load('FN7ALfpGxiI');
          Map queue = {};
          for (var i = 0; i < 30; i++) {
            queue = Map.from(await call('queue'));
            if ((queue['items'] as List).length >= 3) break;
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
          expect((queue['items'] as List).length, greaterThanOrEqualTo(3));
          final nextId = queue['items'][0]['id'];
          debugPrint(
            'QUEUE_READY:${(queue['items'] as List).length} next=$nextId',
          );
          final s = await state();
          await call('seek', {
            'position': (s['duration'] as num).toInt() - 500,
          });
          debugPrint('SEEK_SENT');
          await until((s) => s['id'] == nextId && s['playing'] == true);
          debugPrint('AUTO_NEXT_PASS');
          await load('aqz-KE-bpKQ');
          expect((await state())['isMusic'], false);
          expect(
            (Map.from(await call('queue'))['items'] as List).where(
              (v) => v['autoMusic'] == true,
            ),
            isEmpty,
          );
          debugPrint('MOVIE_EXCLUSION_PASS');
        } finally {
          await call('pause');
          await call('musicAuto', {'clear': true});
          await call('queue', {'items': [], 'repeat': 0});
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
