import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ytb/main.dart';
import 'package:ytb/search_box.dart';
import 'package:ytb/player_overlay.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Facebook sample highest source, real fullscreen UI and five-minute enhancement',
    (tester) async {
      const player = MethodChannel('ytb/player');
      Future<Map<String, dynamic>> state() async =>
          Map<String, dynamic>.from(await player.invokeMethod('state'));
      Future<Map<String, dynamic>> waitFor(
        bool Function(Map<String, dynamic>) check, [
        int seconds = 30,
      ]) async {
        final end = DateTime.now().add(Duration(seconds: seconds));
        do {
          await tester.pump(const Duration(milliseconds: 200));
          final s = await state();
          expect(s['error'], isNull);
          if (check(s)) return s;
        } while (DateTime.now().isBefore(end));
        fail('Timed out: ${await state()}');
      }

      await tester.pumpWidget(const YtbApp());
      await tester.pump(const Duration(seconds: 2));
      tester
          .widget<VideoSearchBox>(find.byType(VideoSearchBox))
          .onSearch('https://web.facebook.com/reel/28955594210740984');
      final initial = await waitFor(
        (s) =>
            s['id'] == 'https://www.facebook.com/watch/?v=28955594210740984' &&
            s['playing'] == true &&
            (s['height'] as num? ?? 0) > 0,
        120,
      );
      expect(initial['audio'], isNotNull);
      final qualities = List<int>.from(initial['qualities']);
      expect(qualities.length, greaterThan(1));
      expect(initial['networkPolicy'], 'wifi');
      expect(initial['height'], qualities.reduce((a, b) => a > b ? a : b));
      final report = <String, dynamic>{
        'sourceHeight': initial['height'],
        'sourceWidth': initial['width'],
        'qualities': qualities,
        'audio': initial['audio'],
        'uiCycles': 0,
      };
      void save() =>
          File('/data/user/0/com.duchaik.ytb/cache/facebook-quality-ui.json')
              .writeAsStringSync(jsonEncode(report));
      await player.invokeMethod('pause');
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 600));
        final overlay = tester.widget<PlayerOverlay>(
          find.byType(PlayerOverlay),
        );
        if (!overlay.visible) {
          overlay.onToggle();
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.tap(find.byTooltip('Toàn màn hình'));
        await waitFor(
          (s) => s['actualLandscape'] == true && s['fullscreen'] == true,
        );
        await tester.pump(const Duration(milliseconds: 400));
        final viewport =
            tester.view.physicalSize / tester.view.devicePixelRatio;
        final size = tester.getSize(find.byType(PlayerOverlay));
        expect(size.width, closeTo(viewport.width, 2));
        expect(size.height, closeTo(viewport.height, 2));
        if (i % 5 == 0) {
          final o = tester.widget<PlayerOverlay>(find.byType(PlayerOverlay));
          if (!o.visible) {
            o.onToggle();
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.tap(find.byTooltip('Xoay ngang/dọc'));
          await waitFor(
            (s) => s['actualLandscape'] == false && s['fullscreen'] == true,
          );
          await tester.pump(const Duration(milliseconds: 600));
          await tester.tap(find.byTooltip('Xoay ngang/dọc'));
          await waitFor((s) => s['actualLandscape'] == true);
        }
        await tester.binding.handlePopRoute();
        await waitFor(
          (s) => s['actualLandscape'] == false && s['fullscreen'] == false,
        );
        expect(tester.takeException(), isNull);
        report['uiCycles'] = i + 1;
        save();
        if ((i + 1) % 5 == 0) debugPrint('FACEBOOK_UI_QA: ${i + 1}/20 passed');
      }
      await player.invokeMethod('enhancement', {'mode': 'strong'});
      await player.invokeMethod('play');
      await waitFor((s) => s['playing'] == true);
      report['performanceStart'] = await state();
      save();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(seconds: 10));
        final s = await state();
        expect(s['error'], isNull);
        if (i % 6 == 5) {
          debugPrint(
            'FACEBOOK_ENHANCEMENT_QA: ${(i + 1) * 10}s, ${s['enhancementStatus']}, frames=${s['renderedFrames']}, dropped=${s['droppedFrames']}',
          );
        }
      }
      report['performanceEnd'] = await state();
      save();
      expect(
        (report['performanceEnd'] as Map)['position'],
        greaterThan((report['performanceStart'] as Map)['position'] as num),
      );
      await player.invokeMethod('enhancement', {'mode': 'off'});
      await player.invokeMethod('pause');
      await tester.pumpWidget(const SizedBox.shrink());
      debugPrint('FACEBOOK_UI_QA: complete');
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
