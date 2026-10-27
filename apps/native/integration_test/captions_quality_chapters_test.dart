import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const player = MethodChannel('ytb/player');
  const source = MethodChannel('ytb/source');
  testWidgets('public metadata, caption playback and adaptive quality', (
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
      final filtered = Map<String, dynamic>.from(
        await source.invokeMethod('search', {
          'query': 'nature documentary',
          'durationFilter': 1,
        }),
      );
      final videos = (filtered['videos'] as List).cast<Map>();
      expect(videos, isNotEmpty);
      final times = videos
          .map((v) => '${v['duration']}')
          .where((s) => RegExp(r'^\d+:\d\d(?::\d\d)?$').hasMatch(s))
          .toList();
      expect(times, isNotEmpty);
      final durations = times.map(
        (s) => s
            .split(':')
            .map(int.parse)
            .fold<int>(0, (value, part) => value * 60 + part),
      );
      expect(durations.every((seconds) => seconds < 240), isTrue);
      debugPrint(
        'SEARCH_FILTER_QA count=${videos.length} timed=${times.length}',
      );
      for (final id in [
        'aqz-KE-bpKQ',
        'jNQXAC9IVRw',
        'dQw4w9WgXcQ',
        'K5KVEU3aaeQ',
      ]) {
        final media = Map<String, dynamic>.from(
          await source.invokeMethod('resolve', {'id': id}),
        );
        await player.invokeMethod('load', {
          'id': id,
          'title': media['title'],
          'author': media['author'],
          'tracks': media['tracks'],
          'metadata': media,
        });
        var s = await state();
        for (
          var i = 0;
          i < 90 && (s['captionStatus'] == 'loading' || s['playing'] != true);
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          s = await state();
        }
        debugPrint(
          'EXTRAS_QA id=$id playing=${s['playing']} status=${s['captionStatus']} tracks=${s['captionTracks']} chapters=${(s['chapters'] as List).length} quality=${s['qualityMode']}',
        );
        expect(s['playing'], true);
        expect(s['qualityMode'], 0);
        if (id == 'K5KVEU3aaeQ') expect(s['bandwidthSamples'], greaterThan(0));
        final tracks = s['captionTracks'] as List;
        if (id == 'jNQXAC9IVRw') expect(tracks, isNotEmpty);
        if (tracks.isNotEmpty) {
          await player.invokeMethod('caption', {
            'id': (tracks.first as Map)['id'],
          });
          for (var i = 0; i < 60; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            s = await state();
            if (s['captionStatus'] != 'loading') break;
          }
          expect(s['captionStatus'], 'ready');
          expect(s['captionSelected'], (tracks.first as Map)['id']);
          if (id == 'jNQXAC9IVRw') {
            await player.invokeMethod('seek', {'position': 2000});
            for (var i = 0; i < 30; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 100));
              s = await state();
              if ((s['captionText'] as String).isNotEmpty) break;
            }
            expect((s['captionText'] as String), isNotEmpty);
          }
          debugPrint(
            'CAPTION_QA id=$id status=${s['captionStatus']} selected=${s['captionSelected']} visible=${(s['captionText'] as String).isNotEmpty}',
          );
        }
        if (id == 'K5KVEU3aaeQ') {
          for (var i = 0; i < 60; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            s = await state();
            if ((s['chapters'] as List).isNotEmpty) break;
          }
          final chapters = s['chapters'] as List;
          expect(chapters.length, greaterThanOrEqualTo(3));
          final start = ((chapters[1] as Map)['startMs'] as num).toInt();
          await player.invokeMethod('seek', {'position': start});
          for (var i = 0; i < 50; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            s = await state();
            if (((s['position'] as num) - start).abs() < 2000 &&
                s['playing'] == true) {
              break;
            }
          }
          expect(((s['position'] as num) - start).abs(), lessThan(2000));
          debugPrint('CHAPTER_QA count=${chapters.length} seek=$start');
        }
        final heights = List<num>.from(s['qualities'] as List);
        if (heights.length > 1) {
          await player.invokeMethod('quality', {'height': heights.first});
          await Future<void>.delayed(const Duration(seconds: 2));
          s = await state();
          expect(s['qualityMode'], heights.first);
          await player.invokeMethod('quality', {'height': 0});
        }
      }
      await player.invokeMethod('pause');
    });
  }, timeout: const Timeout(Duration(minutes: 3)));
}
