import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Prepare the two generated five-second fixtures with scripts/test-orientation.sh.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const player = MethodChannel('ytb/player');
  testWidgets(
    '100 native rotation/surface cycles with delayed portrait and landscape sources',
    (tester) async {
      Future<Map<String, dynamic>> state() async =>
          Map<String, dynamic>.from(await player.invokeMethod('state'));
      Future<Map<String, dynamic>> waitFor(
        bool Function(Map<String, dynamic>) predicate,
      ) async {
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        do {
          await tester.pump(const Duration(milliseconds: 100));
          final s = await state();
          expect(s['error'], isNull);
          if (predicate(s)) return s;
        } while (DateTime.now().isBefore(deadline));
        fail('Timed out: ${await state()}');
      }

      Future<void> surface(int key) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AndroidView(key: ValueKey(key), viewType: 'ytb/video'),
          ),
        ),
      );
      Future<void> load(bool portrait) async {
        final path =
            '/data/user/0/com.duchaik.ytb/cache/qa-${portrait ? 'portrait' : 'landscape'}.mp4';
        expect(
          File(path).existsSync(),
          true,
          reason: 'Run scripts/test-orientation.sh first',
        );
        await player.invokeMethod('load', {
          'id': portrait
              ? 'https://www.facebook.com/watch/?v=10001'
              : 'https://www.facebook.com/watch/?v=10002',
          'title': 'QA generated pattern',
          'position': 0,
          'metadata': {'offline': true},
          'tracks': [
            {
              'height': portrait ? 640 : 360,
              'url': 'file://$path',
              'mime': 'video/mp4',
            },
          ],
        });
      }

      await surface(0);
      await waitFor((s) => s.containsKey('ready'));
      final results = <Map<String, dynamic>>[];
      for (var i = 0; i < 100; i++) {
        // Alternate ordering to exercise dimensions arriving before and after fullscreen.
        if (i.isEven) await load(i % 4 == 0);
        await player.invokeMethod('fullscreen', {'enabled': true});
        await surface(i * 2 + 1);
        if (i.isOdd) await load(i % 4 == 1);
        final landscape = await waitFor(
          (s) =>
              s['actualLandscape'] == true &&
              s['ready'] == true &&
              (s['firstFrameMs'] as num? ?? -1) >= 0 &&
              ((s['videoLayout'] as Map?)?['width'] as num? ?? 0) >
                  ((s['videoLayout'] as Map?)?['height'] as num? ?? 0),
        );
        expect(landscape['orientationMode'], 'landscape');
        await player.invokeMethod('pause');
        final position = landscape['position'] as num;
        if (i % 5 == 0) {
          await player.invokeMethod('lock', {'enabled': true});
          await player.invokeMethod('orientation', {'mode': 'portrait'});
          expect((await state())['orientationMode'], 'landscape');
          await player.invokeMethod('lock', {'enabled': false});
          await player.invokeMethod('orientation', {'mode': 'portrait'});
          await waitFor((s) => s['actualLandscape'] == false);
          await player.invokeMethod('orientation', {'mode': 'landscape'});
          await waitFor((s) => s['actualLandscape'] == true);
        }
        await player.invokeMethod('fullscreen', {'enabled': false});
        await surface(i * 2 + 2);
        final end = await waitFor(
          (s) => s['actualLandscape'] == false && s['fullscreen'] == false,
        );
        expect((end['position'] as num) >= position, true);
        expect(end['orientationLocked'], false);
        expect(tester.takeException(), isNull);
        results.add({
          'cycle': i + 1,
          'position': end['position'],
          'firstFrameMs': landscape['firstFrameMs'],
          'layout': landscape['videoLayout'],
        });
        File('/data/user/0/com.duchaik.ytb/cache/orientation-reliability.json')
            .writeAsStringSync(jsonEncode({'cycles': results}));
        if ((i + 1) % 10 == 0) {
          debugPrint('ORIENTATION_QA: ${i + 1}/100 passed');
        }
      }
      await load(false);
      await waitFor((s) => s['playing'] == true);
      final modes = <Map<String, dynamic>>[];
      for (final mode in ['off', 'auto', 'strong']) {
        await player.invokeMethod('enhancement', {'mode': mode});
        await player.invokeMethod('seek', {'position': 0});
        await player.invokeMethod('play');
        await waitFor((s) => s['playing'] == true);
        await tester.pump(const Duration(seconds: 2));
        final s = await state();
        expect(s['error'], isNull);
        expect(s['playing'], true);
        modes.add({
          'mode': mode,
          'status': s['enhancementStatus'],
          'rendered': s['renderedFrames'],
          'dropped': s['droppedFrames'],
        });
      }
      await player.invokeMethod('enhancement', {'mode': 'off'});
      await player.invokeMethod('pause');
      binding.reportData = {'cycles': results, 'enhancement': modes};
      File('/data/user/0/com.duchaik.ytb/cache/orientation-reliability.json')
          .writeAsStringSync(jsonEncode(binding.reportData));
      debugPrint('ORIENTATION_QA: 100 cycles and enhancement modes passed');
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
