import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const source = MethodChannel('ytb/source');
  const player = MethodChannel('ytb/player');
  testWidgets('real playback starts, saves only long video and loops', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AndroidView(viewType: 'ytb/video')),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 2));
      Future<Map<String, dynamic>> state() async =>
          Map<String, dynamic>.from(await player.invokeMethod('state'));
      Future<Map<String, dynamic>> resolve(String id) async =>
          Map<String, dynamic>.from(
            await source.invokeMethod('resolve', {'id': id}),
          );
      Future<Map<String, dynamic>> waitFor(
        bool Function(Map<String, dynamic>) condition,
      ) async {
        final end = DateTime.now().add(const Duration(seconds: 35));
        while (DateTime.now().isBefore(end)) {
          final s = await state();
          if (s['error'] != null) throw StateError('${s['error']}');
          if (condition(s)) return s;
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        throw StateError('Playback timed out: ${await state()}');
      }

      Future<void> load(Map<String, dynamic> media) async {
        await player.invokeMethod('load', {
          'id': media['id'],
          'title': media['title'],
          'author': media['author'],
          'tracks': media['tracks'],
          'position': 0,
          'metadata': media,
        });
        await waitFor(
          (s) => s['playing'] == true && (s['firstFrameMs'] as num) >= 0,
        );
      }

      final search = Map<String, dynamic>.from(
        await source.invokeMethod('search', {
          'query': 'classical music 1 hour no ads',
        }),
      );
      Map<String, dynamic>? long;
      for (final raw in (search['videos'] as List).take(20)) {
        final candidate = Map<String, dynamic>.from(raw as Map);
        final parts = '${candidate['duration']}'.split(':');
        if (parts.length < 3) continue;
        try {
          final m = await resolve('${candidate['id']}');
          if ((m['duration'] as num? ?? 0) > 1800 && m['isLive'] != true) {
            long = m;
            break;
          }
        } catch (_) {}
      }
      expect(
        long,
        isNotNull,
        reason: 'Need a public long video for resume test',
      );
      long = {...long!, 'id': 'QAresume001'};
      await load(long);
      await player.invokeMethod('seek', {'position': 60000});
      await waitFor(
        (s) => s['playing'] == true && (s['position'] as num) > 58000,
      );
      await player.invokeMethod('pause');
      final longPosition = await player.invokeMethod<int>('savedProgress', {
        'id': long['id'],
      });
      expect(longPosition, greaterThan(58000));
      debugPrint('YTB_LONG_RESUME:$longPosition');
      final actualShort = await resolve('jNQXAC9IVRw');
      await load(actualShort);
      await waitFor(
        (s) =>
            (s['metadata'] as Map?)?['category']?.toString().isNotEmpty == true,
      );
      debugPrint('YTB_ASYNC_CATEGORY_OK');
      final short = {...actualShort, 'id': 'QAresume002'};
      await load(short);
      await player.invokeMethod('seek', {'position': 5000});
      await waitFor(
        (s) => s['playing'] == true && (s['position'] as num) > 4000,
      );
      await player.invokeMethod('pause');
      expect(
        await player.invokeMethod<int>('savedProgress', {'id': short['id']}),
        0,
      );
      final saved = await player.invokeMethod<int>('savedProgress', {
        'id': long['id'],
      });
      await player.invokeMethod('load', {
        'id': long['id'],
        'title': long['title'],
        'author': long['author'],
        'tracks': long['tracks'],
        'position': saved,
        'metadata': long,
      });
      await waitFor(
        (s) => s['playing'] == true && (s['position'] as num) >= 58000,
      );
      debugPrint('YTB_REOPEN_OK:$saved');
      await load(short);
      await player.invokeMethod('repeat', {'mode': 1});
      final queue = Map<String, dynamic>.from(
        await player.invokeMethod('queue'),
      );
      expect(queue['repeat'], 1);
      final duration = ((await state())['duration'] as num).toInt();
      await player.invokeMethod('seek', {'position': duration - 1500});
      await player.invokeMethod('play');
      await waitFor(
        (s) =>
            s['playing'] == true &&
            (s['position'] as num) < 4000 &&
            s['id'] == short['id'],
      );
      debugPrint('YTB_REPEAT_OK');
      await player.invokeMethod('repeat', {'mode': 0});
      await player.invokeMethod('pause');
    });
  }, timeout: const Timeout(Duration(minutes: 4)));
}
